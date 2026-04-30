import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/realtime_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/call_models.dart';

final callRepositoryProvider = Provider<CallRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final realtime = ref.watch(realtimeServiceProvider);
  return CallRepository(client, realtime);
});

class CallRepository {
  CallRepository(this._client, this._realtimeService);

  final SupabaseClient _client;
  final RealtimeService _realtimeService;

  Future<CallSessionModel> createCallSession({
    required String chatId,
    required String callerId,
    required String calleeId,
    required AppCallType type,
  }) async {
    final row = await _client
        .from('call_sessions')
        .insert({
          'chat_id': chatId,
          'caller_id': callerId,
          'callee_id': calleeId,
          'call_type': type.name,
          'status': 'ringing',
        })
        .select()
        .single();
    return CallSessionModel.fromMap(row);
  }

  Future<CallSessionModel> fetchCallSession(String callId) async {
    final row = await _client
        .from('call_sessions')
        .select()
        .eq('id', callId)
        .single();
    return CallSessionModel.fromMap(row);
  }

  Future<void> updateCallStatus({
    required String callId,
    required AppCallStatus status,
  }) async {
    await _client
        .from('call_sessions')
        .update({'status': status.name})
        .eq('id', callId);
  }

  Future<void> sendSignal({
    required String callId,
    required String senderId,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    await _client.from('call_signals').insert({
      'call_id': callId,
      'sender_id': senderId,
      'event_type': eventType,
      'payload': payload,
    });
  }

  RealtimeChannel subscribeToIncomingCalls({
    required String userId,
    required void Function(CallSessionModel session) onUpsert,
  }) {
    return _realtimeService.subscribeToIncomingCalls(
      userId: userId,
      onUpsert: (payload) => onUpsert(CallSessionModel.fromMap(payload)),
    );
  }

  RealtimeChannel subscribeToCallSession({
    required String callId,
    required void Function(CallSessionModel session) onUpsert,
  }) {
    return _realtimeService.subscribeToCallSession(
      callId: callId,
      onUpsert: (payload) => onUpsert(CallSessionModel.fromMap(payload)),
    );
  }

  RealtimeChannel subscribeToSignals({
    required String callId,
    required void Function(CallSignalModel signal) onInsert,
  }) {
    return _realtimeService.subscribeToCallSignals(
      callId: callId,
      onInsert: (payload) => onInsert(CallSignalModel.fromMap(payload)),
    );
  }

  Future<void> disposeChannel(RealtimeChannel channel) {
    return _realtimeService.disposeChannel(channel);
  }
}
