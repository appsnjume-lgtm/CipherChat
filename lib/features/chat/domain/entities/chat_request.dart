import 'chat.dart';
import '../../../auth/domain/entities/app_user.dart';

class ChatRequest {
  const ChatRequest({
    required this.id,
    required this.userId,
    required this.requestedBy,
    required this.type,
    required this.status,
    required this.createdAt,
    this.chatId,
    this.chat,
    this.user,
    this.requestedByUser,
  });

  final String id;
  final String? chatId;
  final String userId;
  final String requestedBy;
  final String type;
  final String status;
  final DateTime createdAt;
  final Chat? chat;
  final AppUser? user;
  final AppUser? requestedByUser;

  bool get isInvite => type == 'invite';

  bool get isJoinRequest => type == 'join_request';

  bool get isDirectRequest => type == 'direct_request';

  ChatRequest copyWith({
    String? chatId,
    Chat? chat,
    AppUser? user,
    AppUser? requestedByUser,
    String? status,
  }) {
    return ChatRequest(
      id: id,
      chatId: chatId ?? this.chatId,
      userId: userId,
      requestedBy: requestedBy,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      chat: chat ?? this.chat,
      user: user ?? this.user,
      requestedByUser: requestedByUser ?? this.requestedByUser,
    );
  }
}
