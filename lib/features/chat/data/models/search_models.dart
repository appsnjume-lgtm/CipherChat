class ChatMessageSearchMatch {
  const ChatMessageSearchMatch({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.messageType,
    required this.createdAt,
    required this.searchText,
    required this.snippet,
    required this.matchPosition,
    required this.totalMatches,
  });

  final String messageId;
  final String chatId;
  final String senderId;
  final String messageType;
  final DateTime createdAt;
  final String searchText;
  final String snippet;
  final int matchPosition;
  final int totalMatches;

  factory ChatMessageSearchMatch.fromMap(Map<String, dynamic> map) {
    return ChatMessageSearchMatch(
      messageId: map['message_id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      messageType: map['message_type'] as String? ?? 'text',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      searchText: map['search_text'] as String? ?? '',
      snippet: map['snippet'] as String? ?? '',
      matchPosition: map['match_position'] as int? ?? 0,
      totalMatches: (map['total_matches'] as num?)?.toInt() ?? 0,
    );
  }
}

class GlobalMessageSearchResult {
  const GlobalMessageSearchResult({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.messageType,
    required this.createdAt,
    required this.searchText,
    required this.snippet,
    required this.chatLabel,
    required this.isGroup,
    required this.senderUsername,
    required this.matchPosition,
    required this.relevance,
    required this.totalMatches,
  });

  final String messageId;
  final String chatId;
  final String senderId;
  final String messageType;
  final DateTime createdAt;
  final String searchText;
  final String snippet;
  final String chatLabel;
  final bool isGroup;
  final String senderUsername;
  final int matchPosition;
  final double relevance;
  final int totalMatches;

  factory GlobalMessageSearchResult.fromMap(Map<String, dynamic> map) {
    return GlobalMessageSearchResult(
      messageId: map['message_id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      messageType: map['message_type'] as String? ?? 'text',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      searchText: map['search_text'] as String? ?? '',
      snippet: map['snippet'] as String? ?? '',
      chatLabel: map['chat_label'] as String? ?? 'Chat',
      isGroup: map['is_group'] as bool? ?? false,
      senderUsername: map['sender_username'] as String? ?? 'Unknown',
      matchPosition: map['match_position'] as int? ?? 0,
      relevance: (map['relevance'] as num?)?.toDouble() ?? 0,
      totalMatches: (map['total_matches'] as num?)?.toInt() ?? 0,
    );
  }
}

class GlobalContactSearchResult {
  const GlobalContactSearchResult({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarId,
    required this.directChatId,
    required this.sharedChatCount,
    required this.relevance,
  });

  final String userId;
  final String username;
  final String displayName;
  final String avatarId;
  final String? directChatId;
  final int sharedChatCount;
  final double relevance;

  factory GlobalContactSearchResult.fromMap(Map<String, dynamic> map) {
    return GlobalContactSearchResult(
      userId: map['user_id'] as String,
      username: map['username'] as String? ?? 'Unknown',
      displayName: map['display_name'] as String? ?? map['username'] as String? ?? 'Unknown',
      avatarId: map['avatar_id'] as String? ?? 'avatar_1',
      directChatId: map['direct_chat_id'] as String?,
      sharedChatCount: (map['shared_chat_count'] as num?)?.toInt() ?? 0,
      relevance: (map['relevance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class GlobalSearchResults {
  const GlobalSearchResults({
    this.messages = const [],
    this.contacts = const [],
  });

  final List<GlobalMessageSearchResult> messages;
  final List<GlobalContactSearchResult> contacts;

  bool get isEmpty => messages.isEmpty && contacts.isEmpty;
}
