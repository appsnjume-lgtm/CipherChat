drop trigger if exists trg_grid_breach_moves_update_board on public.grid_breach_moves;

drop function if exists public.update_grid_breach_board_and_check_win();

alter table public.grid_breach_matches
  drop constraint if exists grid_breach_matches_status_coherent;

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

grant execute on function public.grid_breach_board_winner(jsonb) to authenticated;

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
where m.id = n.id
  and (
    m.status is distinct from n.normalized_status
    or m.winner_id is distinct from case
      when n.normalized_status = 'finished' then n.normalized_winner_id
      else null
    end
    or m.current_turn is distinct from case
      when n.normalized_status = 'active' then n.normalized_turn
      else n.player_1_id
    end
  );

