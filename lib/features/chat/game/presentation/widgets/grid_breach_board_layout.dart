import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/models/game_models.dart';

/// Shared board geometry so hit testing, grid layout, and the animated disc
/// all use the same coordinate system in every orientation.
class GridBreachBoardLayout {
  const GridBreachBoardLayout(this.boardSize);

  static const EdgeInsets padding = EdgeInsets.all(10);
  static const double crossAxisSpacing = 8;
  static const double mainAxisSpacing = 8;

  final Size boardSize;

  double get usableWidth {
    final spacing = (BoardState.columnCount - 1) * crossAxisSpacing;
    return math.max(0, boardSize.width - padding.horizontal - spacing);
  }

  double get usableHeight {
    final spacing = (BoardState.rowCount - 1) * mainAxisSpacing;
    return math.max(0, boardSize.height - padding.vertical - spacing);
  }

  double get cellWidth => usableWidth / BoardState.columnCount;

  double get cellHeight => usableHeight / BoardState.rowCount;

  Rect cellRect(int row, int column) {
    final left = padding.left + (column * (cellWidth + crossAxisSpacing));
    final top = padding.top + (row * (cellHeight + mainAxisSpacing));
    return Rect.fromLTWH(left, top, cellWidth, cellHeight);
  }

  double discTopForProgress(int row, double progress) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final startTop = padding.top - cellHeight;
    final targetTop = cellRect(row, 0).top;
    return startTop + ((targetTop - startTop) * clampedProgress);
  }

  int? columnForOffset(Offset offset) {
    final localX = offset.dx - padding.left;
    final stride = cellWidth + crossAxisSpacing;
    final gridWidth =
        usableWidth + ((BoardState.columnCount - 1) * crossAxisSpacing);

    if (localX < -(crossAxisSpacing / 2) ||
        localX > gridWidth + (crossAxisSpacing / 2)) {
      return null;
    }

    final column = ((localX + (crossAxisSpacing / 2)) / stride).floor();
    return column.clamp(0, BoardState.columnCount - 1);
  }
}
