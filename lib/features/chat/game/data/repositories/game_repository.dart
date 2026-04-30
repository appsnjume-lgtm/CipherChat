import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/services/realtime_service.dart';
import '../models/game_models.dart';

class GameSnapshot {
  const GameSnapshot({
    required this.match,
    required this.board,
    required this.moves,
    required this.scoreboard,
    required this.serverNow,
  });

  final GridBreachMatch match;
  final BoardState board;
  final List<GridBreachMove> moves;
  final GridBreachScoreboard scoreboard;
  final DateTime serverNow;
}

class GameRepository {
  GameRepository({
    required SupabaseClient client,
    required RealtimeService realtime,
  }) : _client = client,
       _realtime = realtime;

  final SupabaseClient _client;
  final RealtimeService _realtime;

  Future<GridBreachMatch> createMatch({
    required String player1Id,
    required String player2Id,
    required String chatId,
  }) async {
    if (chatId.trim().isEmpty) {
      throw ArgumentError.value(chatId, 'chatId', 'chatId must not be empty');
    }

    final response = await _client
        .from('grid_breach_matches')
        .insert({
          'player_1_id': player1Id,
          'player_2_id': player2Id,
          'current_turn': player1Id,
          'current_turn_user_id': player1Id,
          'status': 'waiting',
        })
        .select()
        .single();

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response));
  }

  Future<GridBreachMatch> acceptMatch(String matchId) async {
    final response = await _client.rpc(
      'grid_breach_accept_match',
      params: {'p_match_id': matchId},
    );

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMatch> requestRematch(String matchId) async {
    final response = await _client.rpc(
      'grid_breach_request_rematch',
      params: {'p_match_id': matchId},
    );

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMatch> acceptRematch(String matchId) async {
    final response = await _client.rpc(
      'grid_breach_accept_rematch',
      params: {'p_match_id': matchId},
    );

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMatch> quitMatch(String matchId) async {
    final response = await _client.rpc(
      'grid_breach_quit_match',
      params: {'p_match_id': matchId},
    );

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMatch> claimTimeout(String matchId) async {
    final response = await _client.rpc(
      'claim_timeout',
      params: {'p_match_id': matchId},
    );

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMove> makeMove({
    required String matchId,
    required int columnIndex,
  }) async {
    if (columnIndex < 0 || columnIndex >= BoardState.columnCount) {
      throw ArgumentError.value(
        columnIndex,
        'columnIndex',
        'Column index must be between 0 and 6',
      );
    }

    final response = await _client.rpc(
      'make_move',
      params: {'p_match_id': matchId, 'p_column_index': columnIndex},
    );

    return GridBreachMove.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GridBreachMatch?> getMatch(String matchId) async {
    final response = await _client
        .from('grid_breach_matches')
        .select()
        .eq('id', matchId)
        .maybeSingle();
    if (response == null) {
      return null;
    }

    return GridBreachMatch.fromJson(Map<String, dynamic>.from(response));
  }

  Future<Map<String, GridBreachMatch?>> getMatchesByIds(
    Iterable<String> matchIds,
  ) async {
    final uniqueIds = matchIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueIds.isEmpty) {
      return const <String, GridBreachMatch?>{};
    }

    final matches = await Future.wait(
      uniqueIds.map(
        (matchId) async => MapEntry(matchId, await getMatch(matchId)),
      ),
    );
    return {for (final entry in matches) entry.key: entry.value};
  }

  Future<List<GridBreachMove>> getMoves(String matchId) async {
    final response = await _client
        .from('grid_breach_moves')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: true);

    return (response as List<dynamic>)
        .map(
          (item) =>
              GridBreachMove.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<BoardState> getBoardState(String matchId) async {
    final response = await _client
        .from('grid_breach_board_state')
        .select()
        .eq('match_id', matchId)
        .maybeSingle();

    if (response == null) {
      return BoardState.empty();
    }

    final row = Map<String, dynamic>.from(response);
    return BoardState(
      grid: BoardState.parseGrid(row['board']),
      movesCount: row['moves_count'] as int? ?? 0,
      lastMoveAt: row['last_move_at'] == null
          ? null
          : DateTime.parse(row['last_move_at'] as String).toLocal(),
    );
  }

  Future<GridBreachScoreboard> getScoreboard({
    required String player1Id,
    required String player2Id,
  }) async {
    final ordered = _orderedPair(player1Id, player2Id);
    final response = await _client
        .from('grid_breach_scoreboards')
        .select()
        .eq('left_player_id', ordered.$1)
        .eq('right_player_id', ordered.$2)
        .maybeSingle();

    if (response == null) {
      return GridBreachScoreboard.empty(playerA: player1Id, playerB: player2Id);
    }

    return GridBreachScoreboard.fromJson(Map<String, dynamic>.from(response));
  }

  Future<DateTime> getServerNow() async {
    final response = await _client.rpc('grid_breach_server_now');
    if (response is String) {
      return DateTime.parse(response).toLocal();
    }
    if (response is DateTime) {
      return response.toLocal();
    }
    throw StateError('Unexpected server timestamp response for Grid Breach');
  }

  Future<GameSnapshot> loadSnapshot(String matchId) async {
    final match = await getMatch(matchId);
    if (match == null) {
      throw StateError('Match not found');
    }

    final results = await Future.wait<Object?>([
      getBoardState(matchId),
      getMoves(matchId),
      getScoreboard(player1Id: match.player1Id, player2Id: match.player2Id),
      getServerNow(),
    ]);

    return GameSnapshot(
      match: match,
      board: results[0] as BoardState,
      moves: results[1] as List<GridBreachMove>,
      scoreboard: results[2] as GridBreachScoreboard,
      serverNow: results[3] as DateTime,
    );
  }

  RealtimeChannel subscribeToMatch({
    required String matchId,
    required VoidCallback onChange,
  }) {
    final channel = _client.channel('grid-breach-$matchId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'grid_breach_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'grid_breach_board_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'grid_breach_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();

    return channel;
  }

  Future<void> disposeChannel(RealtimeChannel? channel) async {
    if (channel == null) {
      return;
    }
    await _realtime.disposeChannel(channel);
  }

  (String, String) _orderedPair(String playerA, String playerB) {
    if (playerA.compareTo(playerB) <= 0) {
      return (playerA, playerB);
    }
    return (playerB, playerA);
  }
}
