-- GRID BREACH (GX MODE) - Production schema
-- 6 x 7 realtime match state with authoritative server-side move validation.

create table if not exists public.grid_breach_matches (
  id uuid primary key default gen_random_uuid(),
  player_1_id uuid not null references public.profiles (id) on delete cascade,
  player_2_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'waiting',
  current_turn uuid not null references public.profiles (id) on delete cascade,
  winner_id uuid references public.profiles (id) on delete set null,
  rematch_requested_by uuid references public.profiles (id) on delete set null,
  rematch_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.grid_breach_moves (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.grid_breach_matches (id) on delete cascade,
  player_id uuid not null references public.profiles (id) on delete cascade,
  column_index integer not null,
  row_index integer not null,
  created_at timestamptz not null default now()
);

create table if not exists public.grid_breach_board_state (
  match_id uuid primary key references public.grid_breach_matches (id) on delete cascade,
  board jsonb not null default '[[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null]]'::jsonb,
  moves_count integer not null default 0,
  last_move_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.grid_breach_matches
  alter column status set default 'waiting';
alter table public.grid_breach_board_state
  alter column board set default '[[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null]]'::jsonb;
alter table public.grid_breach_board_state
  alter column moves_count set default 0;

alter table public.grid_breach_board_state
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_status_check
    check (status in ('waiting', 'active', 'finished'));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_players_distinct
    check (player_1_id <> player_2_id);
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_turn_check
    check (current_turn in (player_1_id, player_2_id));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_matches
    add constraint grid_breach_matches_winner_check
    check (winner_id is null or winner_id in (player_1_id, player_2_id));
exception
  when duplicate_object then null;
end $$;

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
  alter table public.grid_breach_moves
    add constraint grid_breach_moves_column_check
    check (column_index between 0 and 6);
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_moves
    add constraint grid_breach_moves_row_check
    check (row_index between 0 and 5);
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_moves
    add constraint grid_breach_moves_unique_position
    unique (match_id, column_index, row_index);
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.grid_breach_board_state
    add constraint grid_breach_board_state_moves_nonnegative
    check (moves_count >= 0 and moves_count <= 42);
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_grid_breach_matches_player_1
  on public.grid_breach_matches (player_1_id);
create index if not exists idx_grid_breach_matches_player_2
  on public.grid_breach_matches (player_2_id);
create index if not exists idx_grid_breach_matches_status
  on public.grid_breach_matches (status);
create index if not exists idx_grid_breach_matches_turn
  on public.grid_breach_matches (current_turn);
create index if not exists idx_grid_breach_moves_match_created
  on public.grid_breach_moves (match_id, created_at desc);
create index if not exists idx_grid_breach_moves_match_column
  on public.grid_breach_moves (match_id, column_index);

create or replace function public.grid_breach_empty_board()
returns jsonb
language sql
immutable
set search_path = public
as $$
  select '[[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null]]'::jsonb;
$$;

create or replace function public.grid_breach_board_cell(
  p_board jsonb,
  p_row integer,
  p_column integer
)
returns integer
language sql
immutable
set search_path = public
as $$
  select nullif(p_board -> p_row ->> p_column, 'null')::integer;
$$;

create or replace function public.grid_breach_find_drop_row(
  p_board jsonb,
  p_column_index integer
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_row integer;
begin
  if p_column_index < 0 or p_column_index > 6 then
    return -1;
  end if;

  for v_row in reverse 5..0 loop
    if public.grid_breach_board_cell(p_board, v_row, p_column_index) is null then
      return v_row;
    end if;
  end loop;

  return -1;
end;
$$;

create or replace function public.grid_breach_count_direction(
  p_board jsonb,
  p_row integer,
  p_column integer,
  p_row_delta integer,
  p_column_delta integer,
  p_player integer
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_row integer := p_row + p_row_delta;
  v_column integer := p_column + p_column_delta;
  v_cell integer;
  v_count integer := 0;
begin
  while v_row between 0 and 5 and v_column between 0 and 6 loop
    v_cell := public.grid_breach_board_cell(p_board, v_row, v_column);
    if v_cell is null or v_cell <> p_player then
      exit;
    end if;

    v_count := v_count + 1;
    v_row := v_row + p_row_delta;
    v_column := v_column + p_column_delta;
  end loop;

  return v_count;
end;
$$;

create or replace function public.grid_breach_has_winner(
  p_board jsonb,
  p_row integer,
  p_column integer,
  p_player integer
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select greatest(
    1 + public.grid_breach_count_direction(p_board, p_row, p_column, 0, 1, p_player)
      + public.grid_breach_count_direction(p_board, p_row, p_column, 0, -1, p_player),
    1 + public.grid_breach_count_direction(p_board, p_row, p_column, 1, 0, p_player)
      + public.grid_breach_count_direction(p_board, p_row, p_column, -1, 0, p_player),
    1 + public.grid_breach_count_direction(p_board, p_row, p_column, 1, 1, p_player)
      + public.grid_breach_count_direction(p_board, p_row, p_column, -1, -1, p_player),
    1 + public.grid_breach_count_direction(p_board, p_row, p_column, 1, -1, p_player)
      + public.grid_breach_count_direction(p_board, p_row, p_column, -1, 1, p_player)
  ) >= 4;
$$;

create or replace function public.grid_breach_board_winner(
  p_board jsonb
)
returns integer
language plpgsql
immutable
set search_path = public
as 
$$
declare
  v_row integer;
  v_column integer;
  v_player integer;
begin
  for v_row in 0..5 loop
    for v_column in 0..6 loop
      v_player := public.grid_breach_board_cell(p_board, v_row, v_column);
      if v_player is not null
         and public.grid_breach_has_winner(p_board, v_row, v_column, v_player) then
        return v_player;
      end if;
    end loop;
  end loop;

  return null;
end;
$$;
create or replace function public.is_grid_breach_player(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.grid_breach_matches m
    where m.id = p_match_id
      and p_user_id in (m.player_1_id, m.player_2_id)
  );
$$;

create or replace function public.is_grid_breach_current_turn(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.grid_breach_matches m
    where m.id = p_match_id
      and m.current_turn = p_user_id
      and m.status = 'active'
  );
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
     or v_match.current_turn <> auth.uid() then
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

create or replace function public.init_grid_breach_board()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.grid_breach_board_state (match_id)
  values (new.id)
  on conflict (match_id) do nothing;
  return new;
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
        updated_at = now()
    where id = p_match_id
    returning * into v_match;
  end if;

  return v_match;
end;
$$;

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
        updated_at = now()
    where id = p_match_id;
  elsif v_next_moves_count >= 42 then
    update public.grid_breach_matches
    set status = 'finished',
        winner_id = null,
        updated_at = now()
    where id = p_match_id;
  else
    update public.grid_breach_matches
    set current_turn = v_next_turn,
        updated_at = now()
    where id = p_match_id;
  end if;

  return v_move;
end;
$$;

drop trigger if exists trg_grid_breach_matches_set_updated_at on public.grid_breach_matches;
create trigger trg_grid_breach_matches_set_updated_at
before update on public.grid_breach_matches
for each row execute function public.set_updated_at();

drop trigger if exists trg_grid_breach_board_state_set_updated_at on public.grid_breach_board_state;
create trigger trg_grid_breach_board_state_set_updated_at
before update on public.grid_breach_board_state
for each row execute function public.set_updated_at();

drop trigger if exists trg_grid_breach_init_board on public.grid_breach_matches;
create trigger trg_grid_breach_init_board
after insert on public.grid_breach_matches
for each row execute function public.init_grid_breach_board();

alter table public.grid_breach_matches enable row level security;
alter table public.grid_breach_moves enable row level security;
alter table public.grid_breach_board_state enable row level security;

drop policy if exists "Participants can view matches" on public.grid_breach_matches;
drop policy if exists "Participants can update their matches" on public.grid_breach_matches;
drop policy if exists "grid_breach_matches_select_own" on public.grid_breach_matches;
drop policy if exists "grid_breach_matches_insert_player1" on public.grid_breach_matches;
drop policy if exists "grid_breach_matches_select_participants" on public.grid_breach_matches;
drop policy if exists "grid_breach_matches_insert_owner" on public.grid_breach_matches;

drop policy if exists "Participants can view moves" on public.grid_breach_moves;
drop policy if exists "Participants can insert moves" on public.grid_breach_moves;
drop policy if exists "grid_breach_moves_select_own_match" on public.grid_breach_moves;
drop policy if exists "grid_breach_moves_insert_current_turn" on public.grid_breach_moves;
drop policy if exists "grid_breach_moves_select_participants" on public.grid_breach_moves;

drop policy if exists "Participants can view board state" on public.grid_breach_board_state;
drop policy if exists "grid_breach_board_state_select_own_match" on public.grid_breach_board_state;
drop policy if exists "grid_breach_board_state_select_participants" on public.grid_breach_board_state;

create policy "grid_breach_matches_select_participants"
  on public.grid_breach_matches
  for select
  to authenticated
  using (auth.uid() in (player_1_id, player_2_id));

create policy "grid_breach_matches_insert_owner"
  on public.grid_breach_matches
  for insert
  to authenticated
  with check (
    auth.uid() = player_1_id
    and player_1_id <> player_2_id
    and current_turn = player_1_id
    and status = 'waiting'
    and winner_id is null
  );

create policy "grid_breach_moves_select_participants"
  on public.grid_breach_moves
  for select
  to authenticated
  using (public.is_grid_breach_player(match_id, auth.uid()));

create policy "grid_breach_board_state_select_participants"
  on public.grid_breach_board_state
  for select
  to authenticated
  using (public.is_grid_breach_player(match_id, auth.uid()));

grant select, insert on public.grid_breach_matches to authenticated;
grant select on public.grid_breach_moves to authenticated;
grant select on public.grid_breach_board_state to authenticated;

grant execute on function public.grid_breach_empty_board() to authenticated;
grant execute on function public.grid_breach_board_cell(jsonb, integer, integer) to authenticated;
grant execute on function public.grid_breach_find_drop_row(jsonb, integer) to authenticated;
grant execute on function public.grid_breach_count_direction(jsonb, integer, integer, integer, integer, integer) to authenticated;
grant execute on function public.grid_breach_has_winner(jsonb, integer, integer, integer) to authenticated;
grant execute on function public.grid_breach_board_winner(jsonb) to authenticated;
grant execute on function public.is_grid_breach_player(uuid, uuid) to authenticated;
grant execute on function public.is_grid_breach_current_turn(uuid, uuid) to authenticated;
grant execute on function public.grid_breach_can_make_move(uuid, integer) to authenticated;
grant execute on function public.grid_breach_accept_match(uuid) to authenticated;
grant execute on function public.grid_breach_request_rematch(uuid) to authenticated;
grant execute on function public.grid_breach_accept_rematch(uuid) to authenticated;
grant execute on function public.grid_breach_quit_match(uuid) to authenticated;
grant execute on function public.grid_breach_claim_timeout(uuid) to authenticated;
grant execute on function public.grid_breach_make_move(uuid, integer) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'grid_breach_matches'
  ) then
    alter publication supabase_realtime add table public.grid_breach_matches;
  end if;
exception
  when undefined_object then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'grid_breach_moves'
  ) then
    alter publication supabase_realtime add table public.grid_breach_moves;
  end if;
exception
  when undefined_object then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'grid_breach_board_state'
  ) then
    alter publication supabase_realtime add table public.grid_breach_board_state;
  end if;
exception
  when undefined_object then null;
end $$;








