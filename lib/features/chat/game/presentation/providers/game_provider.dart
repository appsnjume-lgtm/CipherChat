import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/services/realtime_service.dart';
import '../../../../../core/services/supabase_service.dart';
import '../../../../../core/utils/app_error_helper.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/game_models.dart';
import '../../data/repositories/game_repository.dart';
import '../../domain/game_utils.dart';

class GameState {
  const GameState({
    this.match,
    this.scoreboard,
    this.serverNow,
    required this.board,
    required this.moves,
    required this.winningCells,
    this.status = GameStatus.waiting,
    this.isLoading = false,
    this.isSubmitting = false,
    this.isSubmittingMove = false,
    this.error,
    this.myPlayerNumber = 0,
    this.isMyTurn = false,
  });

  final GridBreachMatch? match;
  final GridBreachScoreboard? scoreboard;
  final DateTime? serverNow;
  final BoardState board;
  final List<GridBreachMove> moves;
  final List<BoardPosition> winningCells;
  final GameStatus status;
  final bool isLoading;
  final bool isSubmitting;
  final bool isSubmittingMove;
  final String? error;
  final int myPlayerNumber;
  final bool isMyTurn;

  GameState copyWith({
    GridBreachMatch? match,
    GridBreachScoreboard? scoreboard,
    DateTime? serverNow,
    BoardState? board,
    List<GridBreachMove>? moves,
    List<BoardPosition>? winningCells,
    GameStatus? status,
    bool? isLoading,
    bool? isSubmitting,
    bool? isSubmittingMove,
    Object? error = _noChange,
    int? myPlayerNumber,
    bool? isMyTurn,
  }) {
    return GameState(
      match: match ?? this.match,
      scoreboard: scoreboard ?? this.scoreboard,
      serverNow: serverNow ?? this.serverNow,
      board: board ?? this.board,
      moves: moves ?? this.moves,
      winningCells: winningCells ?? this.winningCells,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSubmittingMove: isSubmittingMove ?? this.isSubmittingMove,
      error: error == _noChange ? this.error : error as String?,
      myPlayerNumber: myPlayerNumber ?? this.myPlayerNumber,
      isMyTurn: isMyTurn ?? this.isMyTurn,
    );
  }

  factory GameState.initial() {
    return GameState(
      board: BoardState.empty(),
      moves: const <GridBreachMove>[],
      winningCells: const <BoardPosition>[],
    );
  }

  bool get isPlayer1 => myPlayerNumber == 1;
  bool get isPlayer2 => myPlayerNumber == 2;

  String? get myUserId {
    final currentMatch = match;
    if (currentMatch == null) {
      return null;
    }
    if (isPlayer1) {
      return currentMatch.player1Id;
    }
    if (isPlayer2) {
      return currentMatch.player2Id;
    }
    return null;
  }

  String? get opponentUserId {
    final currentMatch = match;
    if (currentMatch == null) {
      return null;
    }
    if (isPlayer1) {
      return currentMatch.player2Id;
    }
    if (isPlayer2) {
      return currentMatch.player1Id;
    }
    return null;
  }

  int get myWins {
    final board = scoreboard;
    final userId = myUserId;
    if (board == null || userId == null) {
      return 0;
    }
    return board.winsFor(userId);
  }

  int get opponentWins {
    final board = scoreboard;
    final userId = myUserId;
    if (board == null || userId == null) {
      return 0;
    }
    return board.lossesFor(userId);
  }

  int get drawCount => scoreboard?.draws ?? 0;

  bool get canAcceptMatch =>
      match?.isWaiting == true && isPlayer2 && !isLoading && !isSubmitting;
  bool get canPlay =>
      match?.isActive == true &&
      isMyTurn &&
      !hasQuitSignal &&
      !isLoading &&
      !isSubmitting &&
      !isSubmittingMove;
  bool get canClaimTimeout =>
      match?.isActive == true &&
      !isMyTurn &&
      !hasQuitSignal &&
      myPlayerNumber != 0 &&
      !isLoading &&
      !isSubmitting &&
      !isSubmittingMove;
  bool get canQuitMatch =>
      match?.isActive == true &&
      myPlayerNumber != 0 &&
      !hasQuitSignal &&
      !isLoading &&
      !isSubmitting &&
      !isSubmittingMove;
  bool get hasRematchRequest => match?.hasRematchRequest == true;
  bool get hasQuitSignal => match?.hasQuitSignal == true;

  bool get rematchRequestedByMe {
    final requester = match?.rematchRequestedBy;
    final userId = myUserId;
    return requester != null && userId != null && requester == userId;
  }

  bool get rematchRequestedByOpponent {
    final requester = match?.rematchRequestedBy;
    final userId = myUserId;
    return requester != null && userId != null && requester != userId;
  }

  bool get quitRequestedByMe {
    final quitter = match?.quitBy;
    final userId = myUserId;
    return quitter != null && userId != null && quitter == userId;
  }

  bool get quitRequestedByOpponent {
    final quitter = match?.quitBy;
    final userId = myUserId;
    return quitter != null && userId != null && quitter != userId;
  }

  bool get canRequestRematch =>
      match?.isFinished == true &&
      !hasQuitSignal &&
      myPlayerNumber != 0 &&
      !hasRematchRequest &&
      !isLoading &&
      !isSubmitting;
  bool get canAcceptRematch =>
      match?.isFinished == true &&
      !hasQuitSignal &&
      rematchRequestedByOpponent &&
      !isLoading &&
      !isSubmitting;
  bool get isWaitingForRematch =>
      match?.isFinished == true && !hasQuitSignal && rematchRequestedByMe;
}

const _noChange = Object();

final gameProvider = StateNotifierProvider.autoDispose
    .family<GameController, GameState, String>((ref, matchId) {
      final repo = ref.watch(gameRepositoryProvider);
      return GameController(ref, matchId, repo);
    });

class GameController extends StateNotifier<GameState> {
  GameController(this._ref, this._matchId, this._repo)
    : super(GameState.initial()) {
    _subscribe();
    unawaited(refresh());
  }

  final Ref _ref;
  final String _matchId;
  final GameRepository _repo;
  RealtimeChannel? _channel;
  Future<void>? _refreshFuture;
  bool _refreshQueued = false;

  Future<void> refresh({bool showLoader = true}) {
    final existing = _refreshFuture;
    if (existing != null) {
      _refreshQueued = true;
      return existing;
    }

    final future = _refresh(showLoader: showLoader);
    _refreshFuture = future;
    future.whenComplete(() {
      if (_refreshFuture == future) {
        _refreshFuture = null;
      }
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refresh(showLoader: false));
      }
    });
    return future;
  }

  Future<void> _refresh({required bool showLoader}) async {
    if (showLoader) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final snapshot = await _repo.loadSnapshot(_matchId);
      final currentUserId = _ref.read(currentUserIdProvider);
      if (currentUserId == null) {
        throw StateError('No authenticated user found.');
      }

      final myPlayerNumber = snapshot.match.playerNumberFor(currentUserId);
      final isMyTurn = _isMyTurn(snapshot.match, myPlayerNumber);
      final winningCells = GameUtils.findWinningLine(snapshot.board.grid);
      final status = _statusFromSnapshot(
        match: snapshot.match,
        board: snapshot.board,
      );

      if (!mounted) {
        return;
      }

      state = state.copyWith(
        match: snapshot.match,
        scoreboard: snapshot.scoreboard,
        serverNow: snapshot.serverNow,
        board: snapshot.board,
        moves: snapshot.moves,
        winningCells: winningCells,
        myPlayerNumber: myPlayerNumber,
        isMyTurn: snapshot.match.isActive ? isMyTurn : false,
        status: status,
        isLoading: false,
        isSubmittingMove: false,
        error: null,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        isSubmitting: false,
        isSubmittingMove: false,
        error: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> acceptMatch() async {
    if (!state.canAcceptMatch) {
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final match = await _repo.acceptMatch(_matchId);
      _applyMatch(match);
      unawaited(refresh(showLoader: false));
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  Future<void> requestRematch() async {
    if (!state.canRequestRematch) {
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final match = await _repo.requestRematch(_matchId);
      _applyMatch(match);
      unawaited(refresh(showLoader: false));
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  Future<void> acceptRematch() async {
    if (!state.canAcceptRematch) {
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final match = await _repo.acceptRematch(_matchId);
      _applyMatch(
        match,
        board: BoardState.empty(),
        moves: const <GridBreachMove>[],
        winningCells: const <BoardPosition>[],
      );
      unawaited(refresh(showLoader: false));
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  Future<bool> quitMatch() async {
    if (!state.canQuitMatch) {
      return false;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final match = await _repo.quitMatch(_matchId);
      _applyMatch(match);
      unawaited(refresh(showLoader: false));
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
      return false;
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  Future<void> claimTimeout() async {
    if (!state.canClaimTimeout) {
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final match = await _repo.claimTimeout(_matchId);
      _applyMatch(match);
      unawaited(refresh(showLoader: false));
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  Future<void> makeMove(int columnIndex) async {
    if (state.isSubmittingMove ||
        !state.canPlay ||
        !GameUtils.isValidColumn(state.board.grid, columnIndex)) {
      return;
    }

    state = state.copyWith(isSubmittingMove: true, error: null);
    try {
      await _repo.makeMove(matchId: _matchId, columnIndex: columnIndex);
      await refresh(showLoader: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(error: AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        state = state.copyWith(isSubmittingMove: false);
      }
    }
  }

  void _applyMatch(
    GridBreachMatch match, {
    BoardState? board,
    List<GridBreachMove>? moves,
    List<BoardPosition>? winningCells,
    GridBreachScoreboard? scoreboard,
  }) {
    final currentUserId = _ref.read(currentUserIdProvider);
    if (!mounted || currentUserId == null) {
      return;
    }

    final nextBoard = board ?? state.board;
    final nextMoves = moves ?? state.moves;
    final nextWinningCells =
        winningCells ?? GameUtils.findWinningLine(nextBoard.grid);
    final nextScoreboard = scoreboard ?? state.scoreboard;
    final myPlayerNumber = match.playerNumberFor(currentUserId);

    state = state.copyWith(
      match: match,
      scoreboard: nextScoreboard,
      board: nextBoard,
      moves: nextMoves,
      winningCells: nextWinningCells,
      myPlayerNumber: myPlayerNumber,
      isMyTurn: match.isActive ? _isMyTurn(match, myPlayerNumber) : false,
      status: _statusFromSnapshot(match: match, board: nextBoard),
      isLoading: false,
      error: null,
    );
  }

  void _subscribe() {
    _channel = _repo.subscribeToMatch(
      matchId: _matchId,
      onChange: () {
        unawaited(refresh(showLoader: false));
      },
    );
  }

  GameStatus _statusFromSnapshot({
    required GridBreachMatch match,
    required BoardState board,
  }) {
    if (match.isWaiting && board.movesCount == 0) {
      return GameStatus.waiting;
    }
    if (match.isFinished) {
      if (match.winnerId == match.player1Id) {
        return GameStatus.winPlayer1;
      }
      if (match.winnerId == match.player2Id) {
        return GameStatus.winPlayer2;
      }
      if (match.isDraw || board.isFull) {
        return GameStatus.draw;
      }
      return GameStatus.finished;
    }
    return GameStatus.active;
  }

  bool _isMyTurn(GridBreachMatch match, int myPlayerNumber) {
    if (myPlayerNumber == 1) {
      return match.isPlayer1Turn;
    }
    if (myPlayerNumber == 2) {
      return match.isPlayer2Turn;
    }
    return false;
  }

  @override
  void dispose() {
    unawaited(_repo.disposeChannel(_channel));
    super.dispose();
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final realtime = ref.watch(realtimeServiceProvider);
  return GameRepository(client: client, realtime: realtime);
});
