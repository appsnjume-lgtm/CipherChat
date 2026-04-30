import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../data/models/game_models.dart';
import '../../domain/game_utils.dart';
import '../providers/game_provider.dart';
import '../widgets/grid_breach_board_layout.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin {
  late final AnimationController _dropController;
  late final AnimationController _pulseController;
  Timer? _clockTimer;
  final Queue<GridBreachMove> _moveQueue = Queue<GridBreachMove>();
  final Stopwatch _serverClock = Stopwatch();
  GridBreachMove? _animatingMove;
  DateTime? _serverNowAnchor;
  String? _lastAppliedMoveId;
  bool _isAnimatingMove = false;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _startClock();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GameState>(gameProvider(widget.matchId), (previous, next) {
      _syncServerClock(next.serverNow);
      _enqueueIncomingMoves(previous, next);

      final nextError = next.error;
      if (nextError != null && nextError != previous?.error) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger
          ?..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(nextError)));
      }
    });

    final state = ref.watch(gameProvider(widget.matchId));
    final theme = Theme.of(context);
    final gx = GXThemeExtension.of(context);

    if (!gx.isGX) {
      return Scaffold(
        appBar: AppBar(title: const Text('GRID BREACH')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.grid_on_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'GRID BREACH is only available while GX theme is active.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Switch back to GX theme, then reopen this match from chat.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: () => context.pop(),
                  child: const Text('Return to chat'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.error != null && state.match == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('GRID BREACH GX')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 16),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(gameProvider(widget.matchId).notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final accent = theme.colorScheme.primary;
    final rivalColor = theme.colorScheme.tertiary;
    final surface = theme.colorScheme.surface;
    final countdown = _remainingFor(state.match);
    final matchTurnSeconds = state.match?.moveTimeLimitSeconds;
    final isTimerUrgent =
        state.match?.isActive == true &&
        countdown != null &&
        countdown > Duration.zero &&
        countdown.inSeconds <= 5;
    final isTimerWarning =
        state.match?.isActive == true &&
        countdown != null &&
        countdown > Duration.zero &&
        countdown.inSeconds <= 20 &&
        countdown.inSeconds > 5;
    final myTurnExpired = _isMyTurnExpired(state, countdown);
    final opponentTurnExpired = _isOpponentTurnExpired(state, countdown);
    final quitRequestedByMe = state.quitRequestedByMe;
    final quitRequestedByOpponent = state.quitRequestedByOpponent;
    final canTapBoard = state.canPlay && !myTurnExpired;

    final statusLabel = _statusLabel(
      state,
      myTurnExpired: myTurnExpired,
      opponentTurnExpired: opponentTurnExpired,
      quitRequestedByMe: quitRequestedByMe,
      quitRequestedByOpponent: quitRequestedByOpponent,
    );
    final helperLabel = _helperLabel(
      state,
      countdown: countdown,
      myTurnExpired: myTurnExpired,
      opponentTurnExpired: opponentTurnExpired,
      quitRequestedByMe: quitRequestedByMe,
      quitRequestedByOpponent: quitRequestedByOpponent,
    );

    final double timerProgress = _timerProgress(
      state,
      countdown: countdown,
      totalSeconds: matchTurnSeconds,
      myTurnExpired: myTurnExpired,
      opponentTurnExpired: opponentTurnExpired,
    );

    final Color timerBorderColor = isTimerUrgent
        ? Colors.deepOrange
        : isTimerWarning
        ? Colors.orangeAccent
        : accent;

    final Color timerValueColor = quitRequestedByOpponent
        ? accent
        : quitRequestedByMe || myTurnExpired
        ? Colors.redAccent
        : isTimerUrgent
        ? Colors.deepOrange
        : isTimerWarning
        ? Colors.orangeAccent
        : Colors.white;

    _syncPulse(isTimerUrgent);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('GRID BREACH GX'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (state.canQuitMatch)
            IconButton(
              tooltip: 'Quit breach',
              onPressed: state.isSubmitting
                  ? null
                  : () => _handleQuitPressed(context),
              icon: const Icon(Icons.power_settings_new_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildResponsiveLayout(
          context,
          state: state,
          accent: accent,
          rivalColor: rivalColor,
          surface: surface,
          countdown: countdown,
          canTapBoard: canTapBoard,
          statusLabel: statusLabel,
          helperLabel: helperLabel,
          timerProgress: timerProgress,
          timerValueColor: timerValueColor,
          timerBorderColor: timerBorderColor,
          myTurnExpired: myTurnExpired,
          opponentTurnExpired: opponentTurnExpired,
          quitRequestedByMe: quitRequestedByMe,
          quitRequestedByOpponent: quitRequestedByOpponent,
        ),
      ),
    );
  }

  Widget _buildResponsiveLayout(
    BuildContext context, {
    required GameState state,
    required Color accent,
    required Color rivalColor,
    required Color surface,
    required Duration? countdown,
    required bool canTapBoard,
    required String statusLabel,
    required String helperLabel,
    required double timerProgress,
    required Color timerValueColor,
    required Color timerBorderColor,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: isLandscape
          ? LayoutBuilder(
              builder: (context, constraints) {
                final sidebarWidth = math.min(
                  360.0,
                  math.max(280.0, constraints.maxWidth * 0.34),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHudCard(
                                context,
                                state: state,
                                accent: accent,
                                rivalColor: rivalColor,
                                surface: surface,
                                countdown: countdown,
                                statusLabel: statusLabel,
                                helperLabel: helperLabel,
                                timerProgress: timerProgress,
                                timerValueColor: timerValueColor,
                                timerBorderColor: timerBorderColor,
                                myTurnExpired: myTurnExpired,
                                opponentTurnExpired: opponentTurnExpired,
                                quitRequestedByMe: quitRequestedByMe,
                                quitRequestedByOpponent:
                                    quitRequestedByOpponent,
                              ),
                              const SizedBox(height: 12),
                              _buildBottomPanel(
                                context,
                                state: state,
                                accent: accent,
                                surface: surface,
                                helperLabel: helperLabel,
                                myTurnExpired: myTurnExpired,
                                opponentTurnExpired: opponentTurnExpired,
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBoardSection(
                        context,
                        state: state,
                        accent: accent,
                        rivalColor: rivalColor,
                        canTapBoard: canTapBoard,
                        maxWidth: 760,
                      ),
                    ),
                  ],
                );
              },
            )
          : Column(
              children: [
                _buildHudCard(
                  context,
                  state: state,
                  accent: accent,
                  rivalColor: rivalColor,
                  surface: surface,
                  countdown: countdown,
                  statusLabel: statusLabel,
                  helperLabel: helperLabel,
                  timerProgress: timerProgress,
                  timerValueColor: timerValueColor,
                  timerBorderColor: timerBorderColor,
                  myTurnExpired: myTurnExpired,
                  opponentTurnExpired: opponentTurnExpired,
                  quitRequestedByMe: quitRequestedByMe,
                  quitRequestedByOpponent: quitRequestedByOpponent,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildBoardSection(
                    context,
                    state: state,
                    accent: accent,
                    rivalColor: rivalColor,
                    canTapBoard: canTapBoard,
                    maxWidth: 620,
                  ),
                ),
                const SizedBox(height: 12),
                _buildBottomPanel(
                  context,
                  state: state,
                  accent: accent,
                  surface: surface,
                  helperLabel: helperLabel,
                  myTurnExpired: myTurnExpired,
                  opponentTurnExpired: opponentTurnExpired,
                ),
              ],
            ),
    );
  }

  Widget _buildHudCard(
    BuildContext context, {
    required GameState state,
    required Color accent,
    required Color rivalColor,
    required Color surface,
    required Duration? countdown,
    required String statusLabel,
    required String helperLabel,
    required double timerProgress,
    required Color timerValueColor,
    required Color timerBorderColor,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              _HudChip(label: statusLabel, color: accent),
              _HudChip(
                label: state.isPlayer1 ? 'NODE 1' : 'NODE 2',
                color: rivalColor,
              ),
              _HudChip(
                label: _turnChipLabel(
                  state,
                  myTurnExpired: myTurnExpired,
                  opponentTurnExpired: opponentTurnExpired,
                  quitRequestedByMe: quitRequestedByMe,
                  quitRequestedByOpponent: quitRequestedByOpponent,
                ),
                color: _turnChipColor(
                  state,
                  accent,
                  myTurnExpired: myTurnExpired,
                  opponentTurnExpired: opponentTurnExpired,
                  quitRequestedByMe: quitRequestedByMe,
                  quitRequestedByOpponent: quitRequestedByOpponent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _MetricPanel(
                    label: 'SCORE',
                    value: '${state.myWins} : ${state.opponentWins}',
                    color: accent,
                    footer: state.drawCount > 0
                        ? 'DRAWS ${state.drawCount}'
                        : '1V1 RECORD',
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1, end: 1.04).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: _TimerPanel(
                      label: 'CLOCK',
                      value: _timerLabel(
                        state,
                        countdown: countdown,
                        myTurnExpired: myTurnExpired,
                        opponentTurnExpired: opponentTurnExpired,
                        quitRequestedByMe: quitRequestedByMe,
                        quitRequestedByOpponent: quitRequestedByOpponent,
                      ),
                      footer: _timerFooter(
                        state,
                        countdown: countdown,
                        myTurnExpired: myTurnExpired,
                        opponentTurnExpired: opponentTurnExpired,
                        quitRequestedByMe: quitRequestedByMe,
                        quitRequestedByOpponent: quitRequestedByOpponent,
                      ),
                      valueColor: timerValueColor,
                      borderColor: timerBorderColor,
                      progress: timerProgress,
                      accentColor: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            helperLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                (state.isLoading || state.isSubmitting)
                    ? accent
                    : Colors.transparent,
              ),
              value: (state.isLoading || state.isSubmitting) ? null : 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardSection(
    BuildContext context, {
    required GameState state,
    required Color accent,
    required Color rivalColor,
    required bool canTapBoard,
    required double maxWidth,
  }) {
    final theme = Theme.of(context);
    const boardAspectRatio = BoardState.columnCount / BoardState.rowCount;
    const boardTopSpacing = 8.0;
    const boardLabelHeight = 18.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.min(constraints.maxWidth, maxWidth);
        final availableBoardHeight = math.max(
          constraints.maxHeight - boardLabelHeight - boardTopSpacing,
          0.0,
        );
        final boardWidth = math.min(
          availableWidth,
          availableBoardHeight * boardAspectRatio,
        );
        final boardHeight = boardWidth / boardAspectRatio;
        final boardLayout = GridBreachBoardLayout(
          Size(boardWidth, boardHeight),
        );
        final hiddenCells = _hiddenAnimatedCells;
        final renderedMove = _animatingMove;

        return Center(
          child: SizedBox(
            width: boardWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: boardLabelHeight,
                  child: Stack(
                    children: List<Widget>.generate(BoardState.columnCount, (
                      column,
                    ) {
                      final columnRect = boardLayout.cellRect(0, column);
                      return Positioned(
                        left: columnRect.left,
                        width: columnRect.width,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Text(
                            '${column + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color:
                                  GameUtils.isValidColumn(
                                    state.board.grid,
                                    column,
                                  )
                                  ? accent
                                  : Colors.white24,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: boardTopSpacing),
                SizedBox(
                  width: boardWidth,
                  height: boardHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: canTapBoard
                        ? (details) {
                            final column = boardLayout.columnForOffset(
                              details.localPosition,
                            );
                            if (column == null ||
                                !GameUtils.isValidColumn(
                                  state.board.grid,
                                  column,
                                )) {
                              return;
                            }
                            ref
                                .read(gameProvider(widget.matchId).notifier)
                                .makeMove(column);
                          }
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                              accent.withValues(alpha: 0.16),
                              const Color(0xFF101726),
                            ),
                            const Color(0xFF11131E),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.5),
                          width: 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: GridBreachBoardLayout.padding,
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount:
                                  BoardState.rowCount * BoardState.columnCount,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: BoardState.columnCount,
                                    crossAxisSpacing:
                                        GridBreachBoardLayout.crossAxisSpacing,
                                    mainAxisSpacing:
                                        GridBreachBoardLayout.mainAxisSpacing,
                                  ),
                              itemBuilder: (context, index) {
                                final row = index ~/ BoardState.columnCount;
                                final column = index % BoardState.columnCount;
                                final isHiddenCell = hiddenCells.contains(
                                  BoardPosition(row, column),
                                );
                                final cellValue = isHiddenCell
                                    ? null
                                    : state.board.grid[row][column];
                                final isWinning = state.winningCells.any(
                                  (cell) =>
                                      cell.row == row && cell.column == column,
                                );
                                return _BoardCell(
                                  value: cellValue,
                                  player1Color: accent,
                                  player2Color: rivalColor,
                                  isWinning: isWinning,
                                );
                              },
                            ),
                          ),
                          if (renderedMove != null)
                            AnimatedBuilder(
                              animation: _dropController,
                              builder: (context, child) {
                                final progress = Curves.easeInCubic.transform(
                                  _dropController.value,
                                );
                                final cellRect = boardLayout.cellRect(
                                  renderedMove.rowIndex,
                                  renderedMove.columnIndex,
                                );
                                return Positioned(
                                  top: boardLayout.discTopForProgress(
                                    renderedMove.rowIndex,
                                    progress,
                                  ),
                                  left: cellRect.left,
                                  width: cellRect.width,
                                  height: cellRect.height,
                                  child: _AnimatedDisc(
                                    color:
                                        renderedMove.playerId ==
                                            state.match?.player1Id
                                        ? accent
                                        : rivalColor,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _serverNowAnchor == null) return;
      setState(() {});
    });
  }

  void _syncServerClock(DateTime? serverNow) {
    if (serverNow == null || _serverNowAnchor == serverNow) {
      return;
    }
    _serverNowAnchor = serverNow;
    _serverClock
      ..reset()
      ..start();
  }

  DateTime? _serverNow() {
    final anchor = _serverNowAnchor;
    if (anchor == null) {
      return null;
    }
    return anchor.add(_serverClock.elapsed);
  }

  Duration? _remainingFor(GridBreachMatch? match) {
    final deadline = match?.turnDeadlineAt;
    final serverNow = _serverNow();
    if (match?.isActive != true || deadline == null || serverNow == null) {
      return null;
    }
    final remaining = deadline.difference(serverNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _isMyTurnExpired(GameState state, Duration? countdown) =>
      state.match?.isActive == true &&
      state.isMyTurn &&
      countdown != null &&
      countdown == Duration.zero;

  bool _isOpponentTurnExpired(GameState state, Duration? countdown) =>
      state.canClaimTimeout && countdown != null && countdown == Duration.zero;

  double _timerProgress(
    GameState state, {
    required Duration? countdown,
    required int? totalSeconds,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
  }) {
    if (state.match?.isActive != true) return 1.0;
    if (myTurnExpired || opponentTurnExpired) return 0.0;
    if (countdown == null || totalSeconds == null || totalSeconds == 0) {
      return 1.0;
    }
    return (countdown.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0);
  }

  void _syncPulse(bool shouldPulse) {
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      return;
    }
    if (_pulseController.isAnimating || _pulseController.value != 0) {
      _pulseController
        ..stop()
        ..value = 0;
    }
  }

  Set<BoardPosition> get _hiddenAnimatedCells {
    final hidden = <BoardPosition>{};
    final animatingMove = _animatingMove;
    if (animatingMove != null) {
      hidden.add(animatingMove.position);
    }
    for (final move in _moveQueue) {
      hidden.add(move.position);
    }
    return hidden;
  }

  void _enqueueIncomingMoves(GameState? previous, GameState next) {
    final latestMoveId = next.moves.isEmpty ? null : next.moves.last.id;
    if (previous == null || previous.match == null) {
      _moveQueue.clear();
      _lastAppliedMoveId = latestMoveId;
      return;
    }

    final previousMoveIds = previous.moves.map((move) => move.id).toSet();
    for (final move in next.moves) {
      if (previousMoveIds.contains(move.id) || _isKnownMove(move.id)) {
        continue;
      }
      _moveQueue.add(move);
    }

    _processNextMoveAnimation();
  }

  bool _isKnownMove(String moveId) {
    if (moveId == _lastAppliedMoveId || moveId == _animatingMove?.id) {
      return true;
    }
    for (final queuedMove in _moveQueue) {
      if (queuedMove.id == moveId) {
        return true;
      }
    }
    return false;
  }

  void _processNextMoveAnimation() {
    if (_isAnimatingMove || _moveQueue.isEmpty || !mounted) {
      return;
    }

    final move = _moveQueue.removeFirst();
    _dropController.duration = Duration(
      milliseconds: 220 + (move.rowIndex * 45),
    );
    _dropController.stop();
    _isAnimatingMove = true;
    setState(() => _animatingMove = move);
    _dropController.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) {
        return;
      }
      setState(() => _animatingMove = null);
      _isAnimatingMove = false;
      _lastAppliedMoveId = move.id;
      _processNextMoveAnimation();
    });
  }

  String _statusLabel(
    GameState state, {
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    final sessionExpired = state.match?.quitBy != null;
    switch (state.status) {
      case GameStatus.waiting:
        return 'STANDBY';
      case GameStatus.active:
        if (opponentTurnExpired) return 'CLAIM WIN';
        if (myTurnExpired) return 'EXPIRED';
        return state.isMyTurn ? 'YOUR MOVE' : 'LIVE';
      case GameStatus.winPlayer1:
        return state.isPlayer1 ? 'BREACH' : 'HELD';
      case GameStatus.winPlayer2:
        return state.isPlayer2 ? 'BREACH' : 'HELD';
      case GameStatus.draw:
        return 'DRAW';
      case GameStatus.finished:
        if (sessionExpired) return quitRequestedByMe ? 'EXPIRED' : 'OPP QUIT';
        return 'CLOSED';
    }
  }

  String _helperLabel(
    GameState state, {
    required Duration? countdown,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    if (state.status == GameStatus.waiting) {
      return state.isPlayer2
          ? 'Accept the breach to activate the grid.'
          : 'Invite sent. Opponent needs to accept from chat.';
    }
    if (state.status == GameStatus.active) {
      if (opponentTurnExpired) {
        return 'Opponent timed out. Claim the match on the server.';
      }
      if (myTurnExpired) {
        return 'Your clock expired. Waiting for opponent to claim the win.';
      }
      if (state.isMyTurn) {
        return countdown == null
            ? 'Tap a column to deploy your node.'
            : 'Tap a column before ${_formatCountdown(countdown)}.';
      }
      return countdown == null
          ? 'Hold position. Board updates when opponent moves.'
          : 'Opponent has ${_formatCountdown(countdown)} left.';
    }
    if (state.status == GameStatus.finished && state.match?.quitBy != null) {
      return quitRequestedByMe
          ? 'You quit. Win awarded to opponent.'
          : 'Opponent quit. Win awarded to you.';
    }
    switch (state.status) {
      case GameStatus.winPlayer1:
        return state.isPlayer1
            ? 'Four linked nodes established the breach path.'
            : 'The opponent completed a four-node breach chain.';
      case GameStatus.winPlayer2:
        return state.isPlayer2
            ? 'Four linked nodes established the breach path.'
            : 'The opponent completed a four-node breach chain.';
      case GameStatus.draw:
        return 'All 42 cells occupied. No breach path completed.';
      case GameStatus.finished:
      case GameStatus.waiting:
      case GameStatus.active:
        return '';
    }
  }

  String _turnChipLabel(
    GameState state, {
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    if (state.canAcceptRematch) return 'REMATCH: READY';
    if (state.isWaitingForRematch) return 'REMATCH: SENT';
    if (state.canRequestRematch) return 'MATCH: CLOSED';
    if (state.match?.quitBy != null) return 'MATCH: EXPIRED';
    if (opponentTurnExpired) return 'TIMEOUT: CLAIM';
    if (myTurnExpired) return 'TIMEOUT: WAIT';
    return state.isMyTurn ? 'TURN: YOURS' : 'TURN: OPP';
  }

  Color _turnChipColor(
    GameState state,
    Color accent, {
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    if (state.canAcceptRematch) return accent;
    if (state.isWaitingForRematch || state.canRequestRematch) {
      return Colors.white70;
    }
    if (state.match?.quitBy != null) {
      return quitRequestedByMe ? Colors.redAccent : accent;
    }
    if (opponentTurnExpired) return accent;
    if (myTurnExpired) return Colors.redAccent;
    return state.isMyTurn ? accent : Colors.white70;
  }

  String _timerLabel(
    GameState state, {
    required Duration? countdown,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    if (state.match?.quitBy != null) return 'EXPIRED';
    if (state.match?.isActive != true) return 'STANDBY';
    if (opponentTurnExpired) return 'CLAIM';
    if (myTurnExpired) return 'WAIT';
    if (countdown == null) return 'SYNC';
    return _formatCountdown(countdown);
  }

  String _timerFooter(
    GameState state, {
    required Duration? countdown,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    required bool quitRequestedByMe,
    required bool quitRequestedByOpponent,
  }) {
    if (state.match?.quitBy != null) {
      return quitRequestedByMe ? 'YOU FORFEITED' : 'OPP FORFEITED';
    }
    if (state.match?.isActive != true) return 'CLOCK ON MATCH START';
    if (opponentTurnExpired) return 'OPP TIMED OUT';
    if (myTurnExpired) return 'WAITING FOR OPP';
    if (countdown != null && countdown.inSeconds <= 10) {
      return state.isMyTurn ? 'LAST SECONDS' : 'OPP LAST SECONDS';
    }
    return state.isMyTurn ? 'YOUR WINDOW' : 'OPP WINDOW';
  }

  String _formatCountdown(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 5999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildBottomPanel(
    BuildContext context, {
    required GameState state,
    required Color accent,
    required Color surface,
    required String helperLabel,
    required bool myTurnExpired,
    required bool opponentTurnExpired,
    bool compact = false,
  }) {
    final theme = Theme.of(context);

    if (state.canAcceptMatch) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: state.isSubmitting
              ? null
              : () => ref
                    .read(gameProvider(widget.matchId).notifier)
                    .acceptMatch(),
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('Accept Breach'),
        ),
      );
    }

    if (opponentTurnExpired) {
      return _buildActionPanel(
        context,
        accent: accent,
        surface: surface,
        icon: Icons.timer_off_rounded,
        title: 'Opponent timed out',
        subtitle: 'Their window expired. Claim the win from the server.',
        actionLabel: 'Claim Win',
        actionIcon: Icons.verified_rounded,
        compact: compact,
        onPressed: state.isSubmitting
            ? null
            : () => ref
                  .read(gameProvider(widget.matchId).notifier)
                  .claimTimeout(),
      );
    }

    if (state.canAcceptRematch) {
      return _buildActionPanel(
        context,
        accent: accent,
        surface: surface,
        icon: Icons.refresh_rounded,
        title: 'Rematch ready?',
        subtitle: 'Reset board, keep score.',
        actionLabel: 'Accept',
        actionIcon: Icons.restart_alt_rounded,
        compact: compact,
        onPressed: state.isSubmitting
            ? null
            : () => ref
                  .read(gameProvider(widget.matchId).notifier)
                  .acceptRematch(),
      );
    }

    if (state.isWaitingForRematch) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, color: accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Rematch sent. Waiting for opponent.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.canRequestRematch) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: state.isSubmitting
              ? null
              : () => ref
                    .read(gameProvider(widget.matchId).notifier)
                    .requestRematch(),
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Request Rematch'),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(
            myTurnExpired
                ? Icons.hourglass_disabled_rounded
                : state.status == GameStatus.active
                ? Icons.touch_app_rounded
                : Icons.hub_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              helperLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel(
    BuildContext context, {
    required Color accent,
    required Color surface,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required IconData actionIcon,
    required bool compact,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);

    final description = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.labelMedium),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actionButton = FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(actionIcon, size: 16),
      label: Text(actionLabel),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [description, const SizedBox(height: 12), actionButton],
            )
          : Row(
              children: [
                Expanded(child: description),
                const SizedBox(width: 10),
                actionButton,
              ],
            ),
    );
  }

  Future<void> _handleQuitPressed(BuildContext context) async {
    final navigator = Navigator.of(context);
    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quit breach?'),
        content: const Text(
          'This ends the session immediately, awards the win to your opponent, and marks the match as expired.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (shouldQuit != true || !mounted) return;
    final didQuit = await ref
        .read(gameProvider(widget.matchId).notifier)
        .quitMatch();
    if (didQuit && mounted && navigator.mounted) navigator.pop();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pulseController.dispose();
    _dropController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD chip — slightly tighter than original
// ─────────────────────────────────────────────────────────────────────────────

class _HudChip extends StatelessWidget {
  const _HudChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score metric panel
// ─────────────────────────────────────────────────────────────────────────────

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    required this.label,
    required this.value,
    required this.color,
    required this.footer,
  });

  final String label;
  final String value;
  final Color color;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.85),
              letterSpacing: 1.1,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: color,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            footer,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white60,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer panel with rounded-rect progress border
// ─────────────────────────────────────────────────────────────────────────────

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.label,
    required this.value,
    required this.footer,
    required this.valueColor,
    required this.borderColor,
    required this.progress,
    required this.accentColor,
  });

  final String label;
  final String value;
  final String footer;
  final Color valueColor;
  final Color borderColor;
  final double progress; // 0.0–1.0
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _TimerProgressPainter(
        progress: progress,
        progressColor: borderColor,
        trackColor: borderColor.withValues(alpha: 0.2),
        strokeWidth: 2.0,
        borderRadius: 12,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // Background only — no border (the CustomPaint draws it)
        decoration: BoxDecoration(
          color: const Color(0x14000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: valueColor.withValues(alpha: 0.85),
                letterSpacing: 1.1,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: valueColor,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              footer,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white60,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a rounded-rect progress border that drains clockwise from top-left.
/// At progress=1.0 the full border is drawn; at 0.0 nothing is drawn.
class _TimerProgressPainter extends CustomPainter {
  const _TimerProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.borderRadius,
  });

  final double progress;
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Always draw dim track
    canvas.drawRRect(rrect, trackPaint);

    if (progress <= 0) return;

    // Compute perimeter segments
    final w = rect.width;
    final h = rect.height;
    final r = borderRadius.clamp(0.0, math.min(w, h) / 2);
    final straightW = w - 2 * r;
    final straightH = h - 2 * r;
    final cornerArcLen = (math.pi / 2) * r;
    final totalPerim = 2 * straightW + 2 * straightH + 4 * cornerArcLen;
    final drawn = (progress * totalPerim).clamp(0.0, totalPerim);

    final path = _buildArcPath(
      rect,
      drawn,
      r,
      straightW,
      straightH,
      cornerArcLen,
    );

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, progressPaint);
  }

  /// Builds a partial path clockwise starting from top-left corner end
  /// (i.e. the midpoint of the top edge start).
  Path _buildArcPath(
    Rect rect,
    double drawn,
    double r,
    double sw, // straight width
    double sh, // straight height
    double ca, // corner arc length
  ) {
    final path = Path();
    final ox = rect.left;
    final oy = rect.top;
    final ow = rect.width;
    final oh = rect.height;

    // Start at top-left corner exit = (ox + r, oy)
    path.moveTo(ox + r, oy);

    double rem = drawn;

    // Helper: draw segment up to `len` pixels; return how much was used
    double take(double len) {
      final t = math.min(rem, len);
      rem -= t;
      return t / len; // fraction 0..1
    }

    // 1. Top edge →
    {
      final f = take(sw);
      path.lineTo(ox + r + sw * f, oy);
    }

    // 2. Top-right corner (−π/2 → 0)
    if (rem > 0) {
      final f = take(ca);
      path.arcTo(
        Rect.fromLTWH(ox + ow - 2 * r, oy, 2 * r, 2 * r),
        -math.pi / 2,
        (math.pi / 2) * f,
        false,
      );
    }

    // 3. Right edge ↓
    if (rem > 0) {
      final f = take(sh);
      path.lineTo(ox + ow, oy + r + sh * f);
    }

    // 4. Bottom-right corner (0 → π/2)
    if (rem > 0) {
      final f = take(ca);
      path.arcTo(
        Rect.fromLTWH(ox + ow - 2 * r, oy + oh - 2 * r, 2 * r, 2 * r),
        0,
        (math.pi / 2) * f,
        false,
      );
    }

    // 5. Bottom edge ←
    if (rem > 0) {
      final f = take(sw);
      path.lineTo(ox + ow - r - sw * f, oy + oh);
    }

    // 6. Bottom-left corner (π/2 → π)
    if (rem > 0) {
      final f = take(ca);
      path.arcTo(
        Rect.fromLTWH(ox, oy + oh - 2 * r, 2 * r, 2 * r),
        math.pi / 2,
        (math.pi / 2) * f,
        false,
      );
    }

    // 7. Left edge ↑
    if (rem > 0) {
      final f = take(sh);
      path.lineTo(ox, oy + oh - r - sh * f);
    }

    // 8. Top-left corner (π → 3π/2)
    if (rem > 0) {
      final f = take(ca);
      path.arcTo(
        Rect.fromLTWH(ox, oy, 2 * r, 2 * r),
        math.pi,
        (math.pi / 2) * f,
        false,
      );
    }

    return path;
  }

  @override
  bool shouldRepaint(_TimerProgressPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Board cell & animated disc — unchanged
// ─────────────────────────────────────────────────────────────────────────────

class _BoardCell extends StatelessWidget {
  const _BoardCell({
    required this.value,
    required this.player1Color,
    required this.player2Color,
    required this.isWinning,
  });

  final int? value;
  final Color player1Color;
  final Color player2Color;
  final bool isWinning;

  @override
  Widget build(BuildContext context) {
    final discColor = switch (value) {
      1 => player1Color,
      2 => player2Color,
      _ => null,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF080B13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isWinning ? Colors.white : Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: discColor ?? const Color(0xFF141A2A),
            border: Border.all(
              color: discColor?.withValues(alpha: 0.9) ?? Colors.white10,
              width: discColor == null ? 1 : 1.6,
            ),
            boxShadow: discColor == null
                ? null
                : [
                    BoxShadow(
                      color: discColor.withValues(
                        alpha: isWinning ? 0.7 : 0.42,
                      ),
                      blurRadius: isWinning ? 20 : 12,
                      spreadRadius: isWinning ? 2 : 0,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedDisc extends StatelessWidget {
  const _AnimatedDisc({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.7),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
