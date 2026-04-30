import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../startup/app_startup.dart';
import 'supabase_service.dart';

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return RealtimeService(client);
});

class RealtimeService {
  RealtimeService(this._client);

  final SupabaseClient _client;

  RealtimeChannel subscribeToChatMessages({
    required String chatId,
    required void Function(Map<String, dynamic> payload) onInsert,
    required void Function(Map<String, dynamic> payload) onUpdate,
  }) {
    final channel = _client.channel('chat-messages-$chatId');

    void handleInsert(PostgresChangePayload payload) {
      if (payload.newRecord.isNotEmpty) {
        onInsert(Map<String, dynamic>.from(payload.newRecord));
      }
    }

    void handleUpdate(PostgresChangePayload payload) {
      if (payload.newRecord.isNotEmpty) {
        onUpdate(Map<String, dynamic>.from(payload.newRecord));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: handleInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: handleUpdate,
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToMessageReceipts({
    required String chatId,
    required void Function(Map<String, dynamic> payload) onUpsert,
  }) {
    final channel = _client.channel('chat-receipts-$chatId');

    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      if (row.isNotEmpty) {
        onUpsert(Map<String, dynamic>.from(row));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'message_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: handle,
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToInboxChanges({
    required String userId,
    required void Function(Map<String, dynamic> payload) onChange,
  }) {
    final channel = _client.channel('chat-inbox-$userId');

    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      if (row.isNotEmpty) {
        onChange(Map<String, dynamic>.from(row));
      }
    }

    StartupTrace.sync(
      'Inbox realtime setup',
      () => channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'message_receipts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: handle,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'message_receipts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: handle,
          )
          .subscribe(),
    );

    return channel;
  }

  RealtimeChannel subscribeToIncomingCalls({
    required String userId,
    required void Function(Map<String, dynamic> payload) onUpsert,
  }) {
    final channel = _client.channel('incoming-calls-$userId');

    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      if (row.isNotEmpty) {
        onUpsert(Map<String, dynamic>.from(row));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee_id',
            value: userId,
          ),
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee_id',
            value: userId,
          ),
          callback: handle,
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToCallSession({
    required String callId,
    required void Function(Map<String, dynamic> payload) onUpsert,
  }) {
    final channel = _client.channel('call-session-$callId');

    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      if (row.isNotEmpty) {
        onUpsert(Map<String, dynamic>.from(row));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: callId,
          ),
          callback: handle,
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToCallSignals({
    required String callId,
    required void Function(Map<String, dynamic> payload) onInsert,
  }) {
    final channel = _client.channel('call-signals-$callId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: callId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onInsert(Map<String, dynamic>.from(payload.newRecord));
            }
          },
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToProfiles({
    required String channelName,
    required void Function(Map<String, dynamic> payload) onUpsert,
  }) {
    final channel = _client.channel(channelName);

    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      if (row.isNotEmpty) {
        onUpsert(Map<String, dynamic>.from(row));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'profiles',
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: handle,
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToChatRequests({
    required String channelName,
    required void Function(
      PostgresChangeEvent event,
      Map<String, dynamic> payload,
    )
    onChange,
  }) {
    final channel = _client.channel(channelName);

    void handle(PostgresChangeEvent event, PostgresChangePayload payload) {
      final row = payload.newRecord.isNotEmpty
          ? payload.newRecord
          : payload.oldRecord;
      if (row.isNotEmpty) {
        onChange(event, Map<String, dynamic>.from(row));
      }
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_requests',
          callback: (payload) => handle(PostgresChangeEvent.insert, payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_requests',
          callback: (payload) => handle(PostgresChangeEvent.update, payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'chat_requests',
          callback: (payload) => handle(PostgresChangeEvent.delete, payload),
        )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToGameMoves({
    required String matchId,
    required void Function(Map<String, dynamic> payload) onMove,
    Function()? onBoardUpdate,
  }) {
    final channel = _client.channel('game-moves-$matchId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'grid_breach_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onMove(Map<String, dynamic>.from(payload.newRecord));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'grid_breach_board_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (_) => onBoardUpdate?.call(),
        )
        .subscribe();

    return channel;
  }

  Future<void> disposeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
