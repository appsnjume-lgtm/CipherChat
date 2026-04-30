class ChatMember {
  const ChatMember({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
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
  final String? avatarId;
  final String? profileImageUrl;
  final String? genderLabel;
  final String? bioPreview;
  final bool isOnline;
  final DateTime? lastSeenAt;

  bool get isAdmin => role == 'admin';

  ChatMember copyWith({
    String? username,
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
      avatarId: avatarId ?? this.avatarId,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      genderLabel: genderLabel ?? this.genderLabel,
      bioPreview: bioPreview ?? this.bioPreview,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
