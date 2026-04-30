class GridBreachMatch {
  const GridBreachMatch({
    required this.id,
    required this.player1Id,
    required this.player2Id,
    required this.currentTurnUserId,
    required this.status,
    required this.winnerId,
    required this.createdAt,
    required this.updatedAt,
    required this.moveTimeLimitSeconds,
    this.turnStartedAt,
    this.moveDeadlineAt,
    this.rematchRequestedBy,
    this.rematchRequestedAt,
    this.quitBy,
    this.quitAt,
  });

  final String id;
  final String player1Id;
  final String player2Id;
  final String currentTurnUserId;
  final String status;
  final String? winnerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int moveTimeLimitSeconds;
  final DateTime? turnStartedAt;
  final DateTime? moveDeadlineAt;
  final String? rematchRequestedBy;
  final DateTime? rematchRequestedAt;
  final String? quitBy;
  final DateTime? quitAt;

  factory GridBreachMatch.fromJson(Map<String, dynamic> json) {
    return GridBreachMatch(
      id: json['id'] as String,
      player1Id: json['player_1_id'] as String,
      player2Id: json['player_2_id'] as String,
      currentTurnUserId:
          (json['current_turn_user_id'] ?? json['current_turn']) as String,
      status: json['status'] as String,
      winnerId: json['winner_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      moveTimeLimitSeconds: json['move_time_limit_seconds'] as int? ?? 45,
      turnStartedAt: json['turn_started_at'] == null
          ? null
          : DateTime.parse(json['turn_started_at'] as String).toLocal(),
      moveDeadlineAt: json['move_deadline_at'] == null
          ? null
          : DateTime.parse(json['move_deadline_at'] as String).toLocal(),
      rematchRequestedBy: json['rematch_requested_by'] as String?,
      rematchRequestedAt: json['rematch_requested_at'] == null
          ? null
          : DateTime.parse(json['rematch_requested_at'] as String).toLocal(),
      quitBy: json['quit_by'] as String?,
      quitAt: json['quit_at'] == null
          ? null
          : DateTime.parse(json['quit_at'] as String).toLocal(),
    );
  }

  String get currentTurn => currentTurnUserId;
  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';
  bool get isDraw => isFinished && winnerId == null;
  bool get isPlayer1Turn => currentTurnUserId == player1Id;
  bool get isPlayer2Turn => currentTurnUserId == player2Id;
  bool get hasRematchRequest => rematchRequestedBy != null;
  bool get hasQuitSignal => quitBy != null;
  bool get isExpiredSession => isFinished && quitBy != null;

  DateTime? get turnDeadlineAt {
    final startedAt = turnStartedAt;
    if (startedAt == null) {
      return moveDeadlineAt;
    }
    return startedAt.add(Duration(seconds: moveTimeLimitSeconds));
  }

  int playerNumberFor(String userId) {
    if (userId == player1Id) {
      return 1;
    }
    if (userId == player2Id) {
      return 2;
    }
    return 0;
  }
}

class GridBreachMove {
  const GridBreachMove({
    required this.id,
    required this.matchId,
    required this.playerId,
    required this.columnIndex,
    required this.rowIndex,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final String playerId;
  final int columnIndex;
  final int rowIndex;
  final DateTime createdAt;

  BoardPosition get position => BoardPosition(rowIndex, columnIndex);

  factory GridBreachMove.fromJson(Map<String, dynamic> json) {
    return GridBreachMove(
      id: json['id'] as String,
      matchId: json['match_id'] as String,
      playerId: json['player_id'] as String,
      columnIndex: json['column_index'] as int,
      rowIndex: json['row_index'] as int,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

class GridBreachScoreboard {
  const GridBreachScoreboard({
    required this.leftPlayerId,
    required this.rightPlayerId,
    required this.leftWins,
    required this.rightWins,
    required this.draws,
    required this.updatedAt,
  });

  final String leftPlayerId;
  final String rightPlayerId;
  final int leftWins;
  final int rightWins;
  final int draws;
  final DateTime updatedAt;

  factory GridBreachScoreboard.fromJson(Map<String, dynamic> json) {
    return GridBreachScoreboard(
      leftPlayerId: json['left_player_id'] as String,
      rightPlayerId: json['right_player_id'] as String,
      leftWins: json['left_wins'] as int? ?? 0,
      rightWins: json['right_wins'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
      updatedAt: json['updated_at'] == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal()
          : DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  factory GridBreachScoreboard.empty({
    required String playerA,
    required String playerB,
  }) {
    final ordered = _orderedPair(playerA, playerB);
    return GridBreachScoreboard(
      leftPlayerId: ordered.$1,
      rightPlayerId: ordered.$2,
      leftWins: 0,
      rightWins: 0,
      draws: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal(),
    );
  }

  int winsFor(String userId) => userId == leftPlayerId ? leftWins : rightWins;

  int lossesFor(String userId) => userId == leftPlayerId ? rightWins : leftWins;

  static (String, String) _orderedPair(String playerA, String playerB) {
    if (playerA.compareTo(playerB) <= 0) {
      return (playerA, playerB);
    }
    return (playerB, playerA);
  }
}

class BoardPosition {
  const BoardPosition(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) {
    return other is BoardPosition && other.row == row && other.column == column;
  }

  @override
  int get hashCode => Object.hash(row, column);
}

class BoardState {
  const BoardState({
    required this.grid,
    required this.movesCount,
    this.lastMoveAt,
  });

  static const int rowCount = 6;
  static const int columnCount = 7;

  final List<List<int?>> grid;
  final int movesCount;
  final DateTime? lastMoveAt;

  factory BoardState.empty() {
    return BoardState(
      grid: List<List<int?>>.generate(
        rowCount,
        (_) => List<int?>.filled(columnCount, null),
      ),
      movesCount: 0,
    );
  }

  static List<List<int?>> parseGrid(dynamic raw) {
    final fallback = BoardState.empty().grid;
    if (raw is! List) {
      return fallback;
    }

    final parsed = <List<int?>>[];
    for (var row = 0; row < rowCount; row++) {
      final rawRow = row < raw.length ? raw[row] : null;
      if (rawRow is! List) {
        parsed.add(List<int?>.filled(columnCount, null));
        continue;
      }

      final parsedRow = <int?>[];
      for (var column = 0; column < columnCount; column++) {
        final cell = column < rawRow.length ? rawRow[column] : null;
        if (cell is num) {
          parsedRow.add(cell.toInt());
        } else {
          parsedRow.add(null);
        }
      }
      parsed.add(parsedRow);
    }

    return parsed;
  }

  bool get isFull => movesCount >= rowCount * columnCount;
}

enum GameStatus { waiting, active, finished, winPlayer1, winPlayer2, draw }
