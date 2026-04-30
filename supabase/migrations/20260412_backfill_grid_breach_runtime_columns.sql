alter table public.grid_breach_matches
  add column if not exists move_time_limit_seconds integer not null default 45;

alter table public.grid_breach_matches
  add column if not exists move_deadline_at timestamptz;

alter table public.grid_breach_matches
  add column if not exists rematch_requested_by uuid references public.profiles (id) on delete set null;

alter table public.grid_breach_matches
  add column if not exists rematch_requested_at timestamptz;

alter table public.grid_breach_matches
  add column if not exists quit_by uuid references public.profiles (id) on delete set null;

alter table public.grid_breach_matches
  add column if not exists quit_at timestamptz;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_rematch_request_check
    check (
      rematch_requested_by is null
      or rematch_requested_by in (player_1_id, player_2_id)
    );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_quit_by_check
    check (
      quit_by is null
      or quit_by in (player_1_id, player_2_id)
    );
exception
  when duplicate_object then null;
end $$;

create or replace function public.grid_breach_request_rematch(
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

  if v_match.quit_by is not null then
    raise exception 'Quit matches expire and cannot be rematched';
  end if;

  if v_match.rematch_requested_by is null or v_match.rematch_requested_by = v_user_id then
    update public.grid_breach_matches
    set rematch_requested_by = v_user_id,
        rematch_requested_at = now(),
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
      winner_id = null,
      move_deadline_at = now() + make_interval(secs => move_time_limit_seconds),
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
      winner_id = v_winner_id,
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
    raise exception 'You cannot advance your own expired turn';
  end if;

  if v_match.move_deadline_at is null or v_match.move_deadline_at > now() then
    raise exception 'Turn timer has not expired yet';
  end if;

  update public.grid_breach_matches
  set current_turn = v_user_id,
      move_deadline_at = now() + make_interval(secs => move_time_limit_seconds),
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

grant execute on function public.grid_breach_request_rematch(uuid) to authenticated;
grant execute on function public.grid_breach_accept_rematch(uuid) to authenticated;
grant execute on function public.grid_breach_quit_match(uuid) to authenticated;
grant execute on function public.grid_breach_claim_timeout(uuid) to authenticated;
