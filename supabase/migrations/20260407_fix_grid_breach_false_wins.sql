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
as 
$$
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

with recalculated as (
  select
    m.id,
    m.player_1_id,
    m.player_2_id,
    coalesce(b.moves_count, 0) as moves_count,
    public.grid_breach_board_winner(
      coalesce(b.board, public.grid_breach_empty_board())
    ) as board_winner
  from public.grid_breach_matches m
  left join public.grid_breach_board_state b
    on b.match_id = m.id
), normalized as (
  select
    id,
    case
      when moves_count = 0 then 'waiting'
      when board_winner is not null or moves_count >= 42 then 'finished'
      else 'active'
    end as normalized_status,
    case board_winner
      when 1 then player_1_id
      when 2 then player_2_id
      else null
    end as normalized_winner_id,
    case
      when moves_count % 2 = 0 then player_1_id
      else player_2_id
    end as normalized_turn,
    player_1_id
  from recalculated
)
update public.grid_breach_matches m
set status = n.normalized_status,
    winner_id = case
      when n.normalized_status = 'finished' then n.normalized_winner_id
      else null
    end,
    current_turn = case
      when n.normalized_status = 'active' then n.normalized_turn
      else n.player_1_id
    end,
    updated_at = now()
from normalized n
where m.id = n.id;

