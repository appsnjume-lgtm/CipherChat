create table if not exists public.grid_breach_scoreboards (
  left_player_id uuid not null references public.profiles (id) on delete cascade,
  right_player_id uuid not null references public.profiles (id) on delete cascade,
  left_wins integer not null default 0,
  right_wins integer not null default 0,
  draws integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grid_breach_scoreboards_pk primary key (left_player_id, right_player_id),
  constraint grid_breach_scoreboards_players_distinct check (left_player_id <> right_player_id),
  constraint grid_breach_scoreboards_count_nonnegative check (
    left_wins >= 0 and right_wins >= 0 and draws >= 0
  )
);

alter table public.grid_breach_matches
  add column if not exists move_time_limit_seconds integer not null default 45;

alter table public.grid_breach_matches
  add column if not exists move_deadline_at timestamptz;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_move_time_limit_check
    check (move_time_limit_seconds between 15 and 120);
exception
  when duplicate_object then null;
end $$;

alter table public.grid_breach_scoreboards enable row level security;

drop policy if exists "grid_breach_scoreboards_select_participants" on public.grid_breach_scoreboards;
create policy "grid_breach_scoreboards_select_participants"
  on public.grid_breach_scoreboards
  for select
  to authenticated
  using (auth.uid() in (left_player_id, right_player_id));

grant select on public.grid_breach_scoreboards to authenticated;

create index if not exists idx_grid_breach_matches_deadline
  on public.grid_breach_matches (move_deadline_at)
  where status = 'active';

drop trigger if exists trg_grid_breach_scoreboards_set_updated_at on public.grid_breach_scoreboards;
create trigger trg_grid_breach_scoreboards_set_updated_at
before update on public.grid_breach_scoreboards
for each row execute function public.set_updated_at();

create or replace function public.grid_breach_record_result(
  p_player_1_id uuid,
  p_player_2_id uuid,
  p_winner_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_left_player_id uuid;
  v_right_player_id uuid;
begin
  if p_player_1_id is null or p_player_2_id is null or p_player_1_id = p_player_2_id then
    return;
  end if;

  if p_player_1_id::text <= p_player_2_id::text then
    v_left_player_id := p_player_1_id;
    v_right_player_id := p_player_2_id;
  else
    v_left_player_id := p_player_2_id;
    v_right_player_id := p_player_1_id;
  end if;

  insert into public.grid_breach_scoreboards (
    left_player_id,
    right_player_id,
    left_wins,
    right_wins,
    draws
  )
  values (
    v_left_player_id,
    v_right_player_id,
    case when p_winner_id = v_left_player_id then 1 else 0 end,
    case when p_winner_id = v_right_player_id then 1 else 0 end,
    case when p_winner_id is null then 1 else 0 end
  )
  on conflict (left_player_id, right_player_id) do update set
    left_wins = public.grid_breach_scoreboards.left_wins + excluded.left_wins,
    right_wins = public.grid_breach_scoreboards.right_wins + excluded.right_wins,
    draws = public.grid_breach_scoreboards.draws + excluded.draws,
    updated_at = now();
end;
$$;

create or replace function public.grid_breach_can_make_move(
  p_match_id uuid,
  p_column_index integer
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_match public.grid_breach_matches;
  v_board jsonb;
begin
  if auth.uid() is null or p_column_index < 0 or p_column_index > 6 then
    return false;
  end if;

  select *
  into v_match
  from public.grid_breach_matches
  where id = p_match_id;

  if not found then
    return false;
  end if;

  if auth.uid() not in (v_match.player_1_id, v_match.player_2_id)
     or v_match.status <> 'active'
     or v_match.current_turn <> auth.uid()
     or (
       v_match.move_deadline_at is not null
       and v_match.move_deadline_at <= now()
     ) then
    return false;
  end if;

  select board
  into v_board
  from public.grid_breach_board_state
  where match_id = p_match_id;

  return public.grid_breach_find_drop_row(
    coalesce(v_board, public.grid_breach_empty_board()),
    p_column_index
  ) <> -1;
end;
$$;

create or replace function public.grid_breach_accept_match(
  p_match_id uuid
)
returns public.grid_breach_matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.grid_breach_matches;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_match
  from public.grid_breach_matches
  where id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found';
  end if;

  if auth.uid() not in (v_match.player_1_id, v_match.player_2_id) then
    raise exception 'You are not a participant in this match';
  end if;

  if v_match.status = 'waiting' then
    if auth.uid() <> v_match.player_2_id then
      raise exception 'Only the invited player can accept this match';
    end if;

    update public.grid_breach_matches
    set status = 'active',
        current_turn = player_1_id,
        move_deadline_at = now() + make_interval(secs => move_time_limit_seconds),
        updated_at = now()
    where id = p_match_id
    returning * into v_match;
  end if;

  return v_match;
end;
$$;

create or replace function public.grid_breach_make_move(
  p_match_id uuid,
  p_column_index integer
)
returns public.grid_breach_moves
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_match public.grid_breach_matches;
  v_board_state public.grid_breach_board_state;
  v_board jsonb;
  v_player integer;
  v_row integer;
  v_next_turn uuid;
  v_new_board jsonb;
  v_move public.grid_breach_moves;
  v_next_moves_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_column_index < 0 or p_column_index > 6 then
    raise exception 'Column index out of range';
  end if;

  select *
  into v_match
  from public.grid_breach_matches
  where id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found';
  end if;

  if v_user_id not in (v_match.player_1_id, v_match.player_2_id) then
    raise exception 'You are not a participant in this match';
  end if;

  if v_match.status = 'waiting' then
    raise exception 'Match has not been accepted yet';
  end if;

  if v_match.status <> 'active' then
    raise exception 'Match is already finished';
  end if;

  if v_match.current_turn <> v_user_id then
    raise exception 'It is not your turn';
  end if;

  if v_match.move_deadline_at is not null and v_match.move_deadline_at <= now() then
    raise exception 'Turn timer expired';
  end if;

  select *
  into v_board_state
  from public.grid_breach_board_state
  where match_id = p_match_id
  for update;

  if not found then
    insert into public.grid_breach_board_state (match_id)
    values (p_match_id)
    returning * into v_board_state;
  end if;

  v_board := coalesce(v_board_state.board, public.grid_breach_empty_board());
  v_row := public.grid_breach_find_drop_row(v_board, p_column_index);

  if v_row = -1 then
    raise exception 'Column is full';
  end if;

  v_player := case when v_user_id = v_match.player_1_id then 1 else 2 end;
  v_next_turn := case
    when v_user_id = v_match.player_1_id then v_match.player_2_id
    else v_match.player_1_id
  end;
  v_new_board := jsonb_set(
    v_board,
    array[v_row::text, p_column_index::text],
    to_jsonb(v_player),
    false
  );
  v_next_moves_count := coalesce(v_board_state.moves_count, 0) + 1;

  insert into public.grid_breach_moves (
    match_id,
    player_id,
    column_index,
    row_index
  )
  values (
    p_match_id,
    v_user_id,
    p_column_index,
    v_row
  )
  returning * into v_move;

  update public.grid_breach_board_state
  set board = v_new_board,
      moves_count = v_next_moves_count,
      last_move_at = now(),
      updated_at = now()
  where match_id = p_match_id;

  if public.grid_breach_has_winner(v_new_board, v_row, p_column_index, v_player) then
    update public.grid_breach_matches
    set status = 'finished',
        winner_id = v_user_id,
        move_deadline_at = null,
        updated_at = now()
    where id = p_match_id;

    perform public.grid_breach_record_result(
      v_match.player_1_id,
      v_match.player_2_id,
      v_user_id
    );
  elsif v_next_moves_count >= 42 then
    update public.grid_breach_matches
    set status = 'finished',
        winner_id = null,
        move_deadline_at = null,
        updated_at = now()
    where id = p_match_id;

    perform public.grid_breach_record_result(
      v_match.player_1_id,
      v_match.player_2_id,
      null
    );
  else
    update public.grid_breach_matches
    set current_turn = v_next_turn,
        move_deadline_at = now() + make_interval(secs => v_match.move_time_limit_seconds),
        updated_at = now()
    where id = p_match_id;
  end if;

  return v_move;
end;
$$;

create or replace function public.grid_breach_accept_rematch(
  p_match_id uuid
)
returns public.grid_breach_matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_match public.grid_breach_matches;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_match
  from public.grid_breach_matches
  where id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found';
  end if;

  if v_user_id not in (v_match.player_1_id, v_match.player_2_id) then
    raise exception 'You are not a participant in this match';
  end if;

  if v_match.status <> 'finished' then
    raise exception 'Rematch is only available after the match is finished';
  end if;

  if v_match.rematch_requested_by is null then
    raise exception 'No rematch request is pending';
  end if;

  if v_match.rematch_requested_by = v_user_id then
    raise exception 'Waiting for the opponent to accept the rematch';
  end if;

  delete from public.grid_breach_moves
  where match_id = p_match_id;

  insert into public.grid_breach_board_state (
    match_id,
    board,
    moves_count,
    last_move_at,
    updated_at
  )
  values (
    p_match_id,
    public.grid_breach_empty_board(),
    0,
    null,
    now()
  )
  on conflict (match_id) do update set
    board = excluded.board,
    moves_count = excluded.moves_count,
    last_move_at = excluded.last_move_at,
    updated_at = excluded.updated_at;

  update public.grid_breach_matches
  set status = 'active',
      current_turn = player_1_id,
      winner_id = null,
      move_deadline_at = now() + make_interval(secs => move_time_limit_seconds),
      rematch_requested_by = null,
      rematch_requested_at = null,
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

create or replace function public.grid_breach_claim_timeout(
  p_match_id uuid
)
returns public.grid_breach_matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_match public.grid_breach_matches;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_match
  from public.grid_breach_matches
  where id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found';
  end if;

  if v_user_id not in (v_match.player_1_id, v_match.player_2_id) then
    raise exception 'You are not a participant in this match';
  end if;

  if v_match.status <> 'active' then
    raise exception 'Match is not active';
  end if;

  if v_match.current_turn = v_user_id then
    raise exception 'You cannot claim timeout on your own turn';
  end if;

  if v_match.move_deadline_at is null or v_match.move_deadline_at > now() then
    raise exception 'Turn timer has not expired yet';
  end if;

  update public.grid_breach_matches
  set status = 'finished',
      winner_id = v_user_id,
      move_deadline_at = null,
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  perform public.grid_breach_record_result(
    v_match.player_1_id,
    v_match.player_2_id,
    v_user_id
  );

  return v_match;
end;
$$;

grant execute on function public.grid_breach_record_result(uuid, uuid, uuid) to authenticated;
grant execute on function public.grid_breach_claim_timeout(uuid) to authenticated;

update public.grid_breach_matches
set move_deadline_at = now() + make_interval(secs => move_time_limit_seconds)
where status = 'active'
  and move_deadline_at is null;

update public.grid_breach_matches
set move_deadline_at = null
where status <> 'active'
  and move_deadline_at is not null;

insert into public.grid_breach_scoreboards (
  left_player_id,
  right_player_id,
  left_wins,
  right_wins,
  draws
)
select
  ordered.left_player_id,
  ordered.right_player_id,
  count(*) filter (where ordered.winner_id = ordered.left_player_id) as left_wins,
  count(*) filter (where ordered.winner_id = ordered.right_player_id) as right_wins,
  count(*) filter (where ordered.winner_id is null) as draws
from (
  select
    case
      when m.player_1_id::text <= m.player_2_id::text then m.player_1_id
      else m.player_2_id
    end as left_player_id,
    case
      when m.player_1_id::text <= m.player_2_id::text then m.player_2_id
      else m.player_1_id
    end as right_player_id,
    m.winner_id
  from public.grid_breach_matches m
  where m.status = 'finished'
) ordered
where not exists (
  select 1
  from public.grid_breach_scoreboards existing
)
group by ordered.left_player_id, ordered.right_player_id
on conflict (left_player_id, right_player_id) do nothing;


