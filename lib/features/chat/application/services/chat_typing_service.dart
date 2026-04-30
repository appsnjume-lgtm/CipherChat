import 'package:supabase_flutter/supabase_flutter.dart';

class ChatTypingSignal {
  const ChatTypingSignal({
    required this.chatId,
    required this.userId,
    required this.username,
    required this.isTyping,
    required this.sentAt,
  });

  final String chatId;
  final String userId;
  final String? username;
  final bool isTyping;
  final DateTime sentAt;

  factory ChatTypingSignal.fromPayload(
    Map<String, dynamic> payload, {
    required String fallbackChatId,
  }) {
    final raw = payload['payload'];
    final data = raw is Map<String, dynamic>
        ? raw
        : raw is Map
        ? Map<String, dynamic>.from(raw)
        : payload;

    final sentAtRaw = data['sent_at'] as String?;
    return ChatTypingSignal(
      chatId: (data['chat_id'] as String?) ?? fallbackChatId,
      userId: data['user_id'] as String? ?? '',
      username: data['username'] as String?,
      isTyping: data['is_typing'] as bool? ?? false,
      sentAt: sentAtRaw == null
          ? DateTime.now().toUtc()
          : DateTime.tryParse(sentAtRaw)?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

class ChatTypingService {
  ChatTypingService(this._client);

  final SupabaseClient _client;
  final Map<String, _TypingChannelEntry> _entries =
      <String, _TypingChannelEntry>{};

  static const String _eventName = 'typing';
  static const String _channelPrefix = 'chat-typing-';

  RealtimeChannel joinChannel({
    required String chatId,
    void Function(ChatTypingSignal signal)? onSignal,
    bool includeSelf = false,
  }) {
    final existing = _entries[chatId];
    if (existing != null) {
      existing.refCount += 1;
      if (onSignal != null) {
        existing.listeners.add(onSignal);
      }
      return existing.channel;
    }

    final listeners = <void Function(ChatTypingSignal signal)>{};
    if (onSignal != null) {
      listeners.add(onSignal);
    }
    final channel = _client.channel(
      '$_channelPrefix$chatId',
      opts: RealtimeChannelConfig(self: includeSelf),
    );

    channel.onBroadcast(
      event: _eventName,
      callback: (payload) {
        final signal = ChatTypingSignal.fromPayload(
          payload,
          fallbackChatId: chatId,
        );
        if (signal.userId.isEmpty) {
          return;
        }

        final snapshot = List<void Function(ChatTypingSignal signal)>.from(
          listeners,
        );
        for (final listener in snapshot) {
          listener(signal);
        }
      },
    );

    channel.subscribe();
    _entries[chatId] = _TypingChannelEntry(
      channel: channel,
      listeners: listeners,
      refCount: 1,
    );
    return channel;
  }

  Future<void> sendTypingState({
    required RealtimeChannel channel,
    required String chatId,
    required String userId,
    required String username,
    required bool isTyping,
  }) async {
    await channel.sendBroadcastMessage(
      event: _eventName,
      payload: {
        'chat_id': chatId,
        'user_id': userId,
        'username': username,
        'is_typing': isTyping,
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> disposeChannel(
    RealtimeChannel channel, {
    void Function(ChatTypingSignal signal)? onSignal,
  }) {
    String? chatId;
    _TypingChannelEntry? entry;

    for (final mapEntry in _entries.entries) {
      if (identical(mapEntry.value.channel, channel)) {
        chatId = mapEntry.key;
        entry = mapEntry.value;
        break;
      }
    }

    if (chatId == null || entry == null) {
      return _client.removeChannel(channel);
    }

    if (onSignal != null) {
      entry.listeners.remove(onSignal);
    }

    entry.refCount -= 1;
    if (entry.refCount > 0) {
      return Future<void>.value();
    }

    _entries.remove(chatId);
    return _client.removeChannel(channel);
  }
}

class _TypingChannelEntry {
  _TypingChannelEntry({
    required this.channel,
    required this.listeners,
    required this.refCount,
  });

  final RealtimeChannel channel;
  final Set<void Function(ChatTypingSignal signal)> listeners;
  int refCount;
}
