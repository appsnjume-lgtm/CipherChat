import '../data/models/game_models.dart';

class GameUtils {
  static List<BoardPosition> findWinningLine(List<List<int?>> grid) {
    for (var row = 0; row < BoardState.rowCount; row++) {
      for (var column = 0; column < BoardState.columnCount; column++) {
        final player = grid[row][column];
        if (player == null) {
          continue;
        }

        for (final direction in const <BoardPosition>[
          BoardPosition(0, 1),
          BoardPosition(1, 0),
          BoardPosition(1, 1),
          BoardPosition(-1, 1),
        ]) {
          final line = <BoardPosition>[];
          for (var step = 0; step < 4; step++) {
            final nextRow = row + (direction.row * step);
            final nextColumn = column + (direction.column * step);
            if (nextRow < 0 ||
                nextRow >= BoardState.rowCount ||
                nextColumn < 0 ||
                nextColumn >= BoardState.columnCount ||
                grid[nextRow][nextColumn] != player) {
              line.clear();
              break;
            }
            line.add(BoardPosition(nextRow, nextColumn));
          }

          if (line.length == 4) {
            return line;
          }
        }
      }
    }

    return const <BoardPosition>[];
  }

  static int? winnerForGrid(List<List<int?>> grid) {
    final line = findWinningLine(grid);
    if (line.isEmpty) {
      return null;
    }
    final first = line.first;
    return grid[first.row][first.column];
  }

  static int getNextRow(List<List<int?>> grid, int column) {
    if (column < 0 || column >= BoardState.columnCount) {
      return -1;
    }

    for (var row = BoardState.rowCount - 1; row >= 0; row--) {
      if (grid[row][column] == null) {
        return row;
      }
    }
    return -1;
  }

  static bool isValidColumn(List<List<int?>> grid, int column) {
    return getNextRow(grid, column) != -1;
  }
}
