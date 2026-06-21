import '../../domain/entities/chat_member.dart';

class ChatMemberModel extends ChatMember {
  const ChatMemberModel({
    required super.id,
    required super.chatId,
    required super.userId,
    required super.role,
    required super.joinedAt,
    super.username,
    super.displayName,
    super.avatarId,
    super.profileImageUrl,
    super.genderLabel,
    super.bioPreview,
    super.isOnline,
    super.lastSeenAt,
  });

  factory ChatMemberModel.fromMap(Map<String, dynamic> map) {
    return ChatMemberModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      userId: map['user_id'] as String,
      role: (map['role'] as String?) ?? 'member',
      joinedAt: DateTime.parse(map['joined_at'] as String).toLocal(),
    );
  }

  ChatMemberModel withProfile({
    String? username,
    String? displayName,
    String? avatarId,
    String? profileImageUrl,
    String? genderLabel,
    String? bioPreview,
    bool? isOnline,
    DateTime? lastSeenAt,
  }) {
    return ChatMemberModel(
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
