class ChatMember {
  const ChatMember({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
    this.displayName,
    this.avatarId,
    this.profileImageUrl,
    this.genderLabel,
    this.bioPreview,
    this.isOnline = false,
    this.lastSeenAt,
  });

  final String id;
  final String chatId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final String? username;
  final String? displayName;
  final String? avatarId;
  final String? profileImageUrl;
  final String? genderLabel;
  final String? bioPreview;
  final bool isOnline;
  final DateTime? lastSeenAt;

  bool get isAdmin => role == 'admin';

  String get displayNameOrUsername {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final handle = username?.trim();
    return handle == null || handle.isEmpty ? userId : handle;
  }

  String? get usernameHandle {
    final handle = username?.trim();
    if (handle == null || handle.isEmpty) {
      return null;
    }
    return '@$handle';
  }

  ChatMember copyWith({
    String? username,
    String? displayName,
    String? avatarId,
    String? profileImageUrl,
    String? genderLabel,
    String? bioPreview,
    bool? isOnline,
    DateTime? lastSeenAt,
  }) {
    return ChatMember(
      id: id,
      chatId: chatId,
      userId: userId,
      role: role,
      joinedAt: joinedAt,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarId: avatarId ?? this.avatarId,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      genderLabel: genderLabel ?? this.genderLabel,
      bioPreview: bioPreview ?? this.bioPreview,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
