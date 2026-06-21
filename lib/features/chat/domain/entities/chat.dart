import 'chat_member.dart';
import 'message.dart';

class Chat {
  const Chat({
    required this.id,
    required this.isGroup,
    required this.createdBy,
    required this.createdAt,
    this.title,
    this.groupImageUrl,
    this.members = const [],
    this.latestMessage,
    this.latestMessagePreviewText,
    this.unreadCount = 0,
    this.isCurrentUserMember = false,
    this.isCurrentUserAdmin = false,
  });

  final String id;
  final bool isGroup;
  final String? createdBy;
  final DateTime createdAt;
  final String? title;
  final String? groupImageUrl;
  final List<ChatMember> members;
  final Message? latestMessage;
  final String? latestMessagePreviewText;
  final int unreadCount;
  final bool isCurrentUserMember;
  final bool isCurrentUserAdmin;

  String titleFor(String currentUserId) {
    if (isGroup) {
      final trimmedTitle = title?.trim();
      if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
        return trimmedTitle;
      }
      return 'Group ${_shortId(id)}';
    }

    final participant = otherMemberFor(currentUserId);
    return participant?.displayNameOrUsername ?? 'Direct chat';
  }

  String subtitleFor(String currentUserId) {
    if (isGroup) {
      if (members.isEmpty) {
        return 'No members yet';
      }

      final names = members
          .map((member) => member.displayNameOrUsername)
          .whereType<String>()
          .take(3)
          .join(', ');
      return names.isEmpty ? '${members.length} members' : names;
    }

    final participant = otherMemberFor(currentUserId);
    return participant?.usernameHandle ??
        participant?.bioPreview ??
        participant?.displayNameOrUsername ??
        'Unknown user';
  }

  String? avatarIdFor(String currentUserId) {
    return otherMemberFor(currentUserId)?.avatarId;
  }

  String? profileImageUrlFor(String currentUserId) {
    return otherMemberFor(currentUserId)?.profileImageUrl;
  }

  ChatMember? otherMemberFor(String currentUserId) {
    if (isGroup) {
      return null;
    }

    for (final member in members) {
      if (member.userId != currentUserId) {
        return member;
      }
    }

    return null;
  }

  static String _shortId(String value) {
    final compact = value.replaceAll('-', '');
    return compact.length <= 6 ? compact : compact.substring(0, 6);
  }
}
