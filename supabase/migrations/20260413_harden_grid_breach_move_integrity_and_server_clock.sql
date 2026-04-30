-- Server-authoritative Grid Breach turn ownership and timeout handling.
-- The client may render animations locally, but move legality and timer expiry
-- are validated only from server state.

alter table public.grid_breach_matches
  add column if not exists current_turn_user_id uuid references public.profiles (id) on delete cascade;

alter table public.grid_breach_matches
  add column if not exists turn_started_at timestamptz;

update public.grid_breach_matches
set current_turn_user_id = coalesce(current_turn_user_id, current_turn),
    turn_started_at = case
      when status = 'active' then coalesce(
        turn_started_at,
        move_deadline_at - make_interval(secs => move_time_limit_seconds),
        updated_at
      )
      else turn_started_at
    end
where current_turn_user_id is null
   or (status = 'active' and turn_started_at is null);

do $$
begin
  alter table public.grid_breach_matches
    alter column current_turn_user_id set not null;
exception
  when others then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_current_turn_user_check
    check (current_turn_user_id in (player_1_id, player_2_id));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_active_turn_started_check
    check (status <> 'active' or turn_started_at is not null);
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_grid_breach_matches_current_turn_user
  on public.grid_breach_matches (current_turn_user_id);

create or replace function public.grid_breach_server_now()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select now();
$$;

create or replace function public.grid_breach_turn_deadline(
  p_turn_started_at timestamptz,
  p_move_time_limit_seconds integer
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select p_turn_started_at + make_interval(secs => p_move_time_limit_seconds);
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
     or v_match.current_turn_user_id <> auth.uid()
     or v_match.turn_started_at is null
     or public.grid_breach_turn_deadline(
       v_match.turn_started_at,
       v_match.move_time_limit_seconds
     ) <= now() then
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
  v_turn_started_at timestamptz := now();
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
        current_turn_user_id = player_1_id,
        turn_started_at = v_turn_started_at,
        move_deadline_at = public.grid_breach_turn_deadline(
          v_turn_started_at,
          move_time_limit_seconds
        ),
        updated_at = now()
    where id = p_match_id
    returning * into v_match;
  end if;

  return v_match;
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
  v_turn_started_at timestamptz := now();
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

  if v_match.quit_by is not null then
    raise exception 'Quit matches expire and cannot be rematched';
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
      current_turn_user_id = player_1_id,
      winner_id = null,
      turn_started_at = v_turn_started_at,
      move_deadline_at = public.grid_breach_turn_deadline(
        v_turn_started_at,
        move_time_limit_seconds
      ),
      rematch_requested_by = null,
      rematch_requested_at = null,
      quit_by = null,
      quit_at = null,
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

create or replace function public.grid_breach_quit_match(
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
  v_winner_id uuid;
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
    raise exception 'Only active matches can be quit';
  end if;

  v_winner_id := case
    when v_user_id = v_match.player_1_id then v_match.player_2_id
    else v_match.player_1_id
  end;

  update public.grid_breach_matches
  set status = 'finished',
      current_turn = v_winner_id,
      current_turn_user_id = v_winner_id,
      winner_id = v_winner_id,
      turn_started_at = null,
      move_deadline_at = null,
      quit_by = v_user_id,
      quit_at = now(),
      rematch_requested_by = null,
      rematch_requested_at = null,
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  perform public.grid_breach_record_result(
    v_match.player_1_id,
    v_match.player_2_id,
    v_winner_id
  );

  return v_match;
end;
$$;

create or replace function public.make_move(
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
  v_turn_started_at timestamptz := now();
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

  if v_match.current_turn_user_id <> v_user_id then
    raise exception 'It is not your turn';
  end if;

  if v_match.turn_started_at is null or public.grid_breach_turn_deadline(
    v_match.turn_started_at,
    v_match.move_time_limit_seconds
  ) <= v_turn_started_at then
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
      last_move_at = v_turn_started_at,
      updated_at = v_turn_started_at
  where match_id = p_match_id;

  if public.grid_breach_has_winner(v_new_board, v_row, p_column_index, v_player) then
    update public.grid_breach_matches
    set status = 'finished',
        current_turn = v_user_id,
        current_turn_user_id = v_user_id,
        winner_id = v_user_id,
        turn_started_at = null,
        move_deadline_at = null,
        updated_at = v_turn_started_at
    where id = p_match_id;

    perform public.grid_breach_record_result(
      v_match.player_1_id,
      v_match.player_2_id,
      v_user_id
    );
  elsif v_next_moves_count >= 42 then
    update public.grid_breach_matches
    set status = 'finished',
        current_turn = v_next_turn,
        current_turn_user_id = v_next_turn,
        winner_id = null,
        turn_started_at = null,
        move_deadline_at = null,
        updated_at = v_turn_started_at
    where id = p_match_id;

    perform public.grid_breach_record_result(
      v_match.player_1_id,
      v_match.player_2_id,
      null
    );
  else
    update public.grid_breach_matches
    set current_turn = v_next_turn,
        current_turn_user_id = v_next_turn,
        turn_started_at = v_turn_started_at,
        move_deadline_at = public.grid_breach_turn_deadline(
          v_turn_started_at,
          move_time_limit_seconds
        ),
        updated_at = v_turn_started_at
    where id = p_match_id;
  end if;

  return v_move;
end;
$$;

create or replace function public.claim_timeout(
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
  v_now timestamptz := now();
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

  if v_match.current_turn_user_id = v_user_id then
    raise exception 'You cannot claim your own expired turn';
  end if;

  if v_match.turn_started_at is null or public.grid_breach_turn_deadline(
    v_match.turn_started_at,
    v_match.move_time_limit_seconds
  ) > v_now then
    raise exception 'Turn timer has not expired yet';
  end if;

  update public.grid_breach_matches
  set status = 'finished',
      current_turn = v_user_id,
      current_turn_user_id = v_user_id,
      winner_id = v_user_id,
      turn_started_at = null,
      move_deadline_at = null,
      rematch_requested_by = null,
      rematch_requested_at = null,
      updated_at = v_now
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

create or replace function public.grid_breach_make_move(
  p_match_id uuid,
  p_column_index integer
)
returns public.grid_breach_moves
language sql
security definer
set search_path = public
as $$
  select public.make_move(p_match_id, p_column_index);
$$;

create or replace function public.grid_breach_claim_timeout(
  p_match_id uuid
)
returns public.grid_breach_matches
language sql
security definer
set search_path = public
as $$
  select public.claim_timeout(p_match_id);
$$;

grant execute on function public.grid_breach_server_now() to authenticated;
grant execute on function public.grid_breach_turn_deadline(timestamptz, integer) to authenticated;
grant execute on function public.make_move(uuid, integer) to authenticated;
grant execute on function public.claim_timeout(uuid) to authenticated;
