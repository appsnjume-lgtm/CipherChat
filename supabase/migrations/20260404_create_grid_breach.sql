-- Grid Breach (GX Mode) - Connect Four multiplayer game
-- 7x6 grid, realtime via Supabase

-- ============================================================================
-- Tables
-- ============================================================================

create table public.grid_breach_matches (
  id uuid primary key default gen_random_uuid(),
  player_1_id uuid not null references public.profiles (id) on delete cascade,
  player_2_id uuid not null references public.profiles (id) on delete cascade,
  current_turn uuid not null, -- player_1_id or player_2_id
  status text not null default 'waiting', -- waiting, active, finished
  winner_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grid_breach_matches_status_check
    check (status in ('waiting', 'active', 'finished')),
  constraint grid_breach_matches_turn_check
    check (current_turn = player_1_id or current_turn = player_2_id),
  constraint grid_breach_matches_winner_check
    check (winner_id is null or winner_id in (player_1_id, player_2_id)),
  constraint grid_breach_matches_players_distinct
    check (player_1_id != player_2_id),
  constraint grid_breach_matches_status_coherent
    check (
      (status = 'finished' and winner_id is not null)
      or (status = 'active' and winner_id is null)
      or status = 'waiting'
    )
);

create table public.grid_breach_moves (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.grid_breach_matches (id) on delete cascade,
  player_id uuid not null references public.profiles (id) on delete cascade,
  column_index integer not null check (column_index between 0 and 6),
  row_index integer not null check (row_index between 0 and 5),
  created_at timestamptz not null default now(),
  constraint grid_breach_moves_unique_position
    unique (match_id, column_index, row_index)
);

create table public.grid_breach_board_state (
  match_id uuid primary key references public.grid_breach_matches (id) on delete cascade,
  board jsonb not null default '[[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null]]'::jsonb,
  moves_count integer not null default 0 check (moves_count >= 0),
  last_move_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ============================================================================
-- Indexes
-- ============================================================================

create index idx_grid_breach_matches_player1 on public.grid_breach_matches (player_1_id);
create index idx_grid_breach_matches_player2 on public.grid_breach_matches (player_2_id);
create index idx_grid_breach_matches_current_turn on public.grid_breach_matches (current_turn);
create index idx_grid_breach_matches_status on public.grid_breach_matches (status);
create index idx_grid_breach_matches_players_status
  on public.grid_breach_matches (player_1_id, player_2_id, status);

create index idx_grid_breach_moves_match on public.grid_breach_moves (match_id);
create index idx_grid_breach_moves_match_created on public.grid_breach_moves (match_id, created_at desc);
create index idx_grid_breach_moves_column on public.grid_breach_moves (match_id, column_index);

-- ============================================================================
-- Functions
-- ============================================================================

create function public.is_grid_breach_player(
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

create function public.is_grid_breach_current_turn(
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

create function public.grid_breach_can_make_move(
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
  match_status text;
  board jsonb;
  col_count integer;
begin
  select m.status, b.board
  into match_status, board
  from public.grid_breach_matches m
  left join public.grid_breach_board_state b on b.match_id = m.id
  where m.id = p_match_id;

  if match_status != 'active' then
    return false;
  end if;

  if p_column_index < 0 or p_column_index > 6 then
    return false;
  end if;

  -- Count non-null in column
  select count(*)
  into col_count
  from jsonb_array_elements(board[0:p_column_index]) as cell
  where cell.value is not null;

  return col_count < 6;
end;
$$;

-- Trigger: Update board_state and check win on move insert
create function public.update_grid_breach_board_and_check_win()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  board jsonb;
  new_board jsonb;
  moves_count integer;
  winner boolean;
  player_num integer;
begin
  -- Get current board
  select b.board, b.moves_count
  into board, moves_count
  from public.grid_breach_board_state b
  where b.match_id = new.match_id;

  if board is null then
    board := '[[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null],[null,null,null,null,null,null,null]]'::jsonb;
    moves_count := 0;
  end if;

  player_num := case
    when new.player_id = (
      select player_1_id
      from public.grid_breach_matches
      where id = new.match_id
    ) then 1
    else 2
  end;

  -- Place piece (player_id determines 1 or 2)

  new_board := board;
  new_board := jsonb_set(
    new_board,
    array[(5 - new.row_index)::text, new.column_index::text],
    to_jsonb(player_num),
    true
  );

  -- Switch turn
  update public.grid_breach_matches
  set current_turn = case 
    when current_turn = (select player_1_id from public.grid_breach_matches where id = new.match_id)
    then (select player_2_id from public.grid_breach_matches where id = new.match_id)
    else (select player_1_id from public.grid_breach_matches where id = new.match_id)
  end
  where id = new.match_id;

  -- Update board state
  insert into public.grid_breach_board_state (match_id, board, moves_count, last_move_at)
  values (new.match_id, new_board, moves_count + 1, now())
  on conflict (match_id) do update set
    board = new_board,
    moves_count = moves_count + 1,
    last_move_at = now(),
    updated_at = now();

  -- Simple win check (client should verify too)
  -- For full win detect, would need more complex function
  -- Here just check if board full for draw

  if moves_count + 1 = 42 then
    update public.grid_breach_matches set status = 'finished' where id = new.match_id;
  end if;

  return new;
end;
$$;

-- ============================================================================
-- Triggers
-- ============================================================================

create trigger trg_grid_breach_matches_set_updated_at
  before update on public.grid_breach_matches
  for each row execute function public.set_updated_at();

create trigger trg_grid_breach_board_state_set_updated_at
  before update on public.grid_breach_board_state
  for each row execute function public.set_updated_at();

create trigger trg_grid_breach_moves_update_board
  after insert on public.grid_breach_moves
  for each row execute function public.update_grid_breach_board_and_check_win();

-- ============================================================================
-- Row Level Security
-- ============================================================================

alter table public.grid_breach_matches enable row level security;
alter table public.grid_breach_moves enable row level security;
alter table public.grid_breach_board_state enable row level security;

-- Matches: players can read own matches
create policy "grid_breach_matches_select_own"
  on public.grid_breach_matches for select
  to authenticated
  using (auth.uid() in (player_1_id, player_2_id));

create policy "grid_breach_matches_insert_player1"
  on public.grid_breach_matches for insert
  to authenticated
  with check (auth.uid() = player_1_id);

-- Moves: players can insert if their turn + valid column
create policy "grid_breach_moves_select_own_match"
  on public.grid_breach_moves for select
  to authenticated
  using (public.is_grid_breach_player(match_id, auth.uid()));

create policy "grid_breach_moves_insert_current_turn"
  on public.grid_breach_moves for insert
  to authenticated
  with check (
    public.is_grid_breach_player(match_id, auth.uid())
    and public.is_grid_breach_current_turn(match_id, auth.uid())
    and public.grid_breach_can_make_move(match_id, column_index)
  );

create policy "grid_breach_board_state_select_own_match"
  on public.grid_breach_board_state for select
  to authenticated
  using (public.is_grid_breach_player(match_id, auth.uid()));

-- ============================================================================
-- Realtime
-- ============================================================================

alter publication supabase_realtime add table public.grid_breach_moves;
alter publication supabase_realtime add table public.grid_breach_board_state;
alter publication supabase_realtime add table public.grid_breach_matches;

-- ============================================================================
-- Grants
-- ============================================================================

grant select, insert, update on public.grid_breach_matches to authenticated;
grant select, insert on public.grid_breach_moves to authenticated;
grant select on public.grid_breach_board_state to authenticated;

grant execute on function public.is_grid_breach_player(uuid, uuid) to authenticated;
grant execute on function public.is_grid_breach_current_turn(uuid, uuid) to authenticated;
grant execute on function public.grid_breach_can_make_move(uuid, integer) to authenticated;

