import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_member.dart';
import '../../domain/entities/message.dart';

class ChatModel extends Chat {
  const ChatModel({
    required super.id,
    required super.isGroup,
    required super.createdBy,
    required super.createdAt,
    super.title,
    super.groupImageUrl,
    super.members,
    super.latestMessage,
    super.latestMessagePreviewText,
    super.unreadCount,
    super.isCurrentUserMember,
    super.isCurrentUserAdmin,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map) {
    return ChatModel(
      id: map['id'] as String,
      isGroup: map['is_group'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
      title: (map['title'] as String?)?.trim(),
      groupImageUrl: (map['group_image_url'] as String?)?.trim(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  ChatModel copyWith({
    String? title,
    String? groupImageUrl,
    List<ChatMember>? members,
    Message? latestMessage,
    String? latestMessagePreviewText,
    int? unreadCount,
    bool? isCurrentUserMember,
    bool? isCurrentUserAdmin,
  }) {
    return ChatModel(
      id: id,
      isGroup: isGroup,
      createdBy: createdBy,
      createdAt: createdAt,
      title: title ?? this.title,
      groupImageUrl: groupImageUrl ?? this.groupImageUrl,
      members: members ?? this.members,
      latestMessage: latestMessage ?? this.latestMessage,
      latestMessagePreviewText:
          latestMessagePreviewText ?? this.latestMessagePreviewText,
      unreadCount: unreadCount ?? this.unreadCount,
      isCurrentUserMember: isCurrentUserMember ?? this.isCurrentUserMember,
      isCurrentUserAdmin: isCurrentUserAdmin ?? this.isCurrentUserAdmin,
    );
  }
}
