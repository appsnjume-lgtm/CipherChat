import '../../domain/entities/chat_request.dart';
import '../../domain/entities/chat.dart';
import '../../../auth/domain/entities/app_user.dart';

class ChatRequestModel extends ChatRequest {
  const ChatRequestModel({
    required super.id,
    required super.userId,
    required super.requestedBy,
    required super.type,
    required super.status,
    required super.createdAt,
    super.chatId,
    super.chat,
    super.user,
    super.requestedByUser,
  });

  factory ChatRequestModel.fromMap(Map<String, dynamic> map) {
    return ChatRequestModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String?,
      userId: map['user_id'] as String,
      requestedBy: map['requested_by'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  ChatRequestModel enrich({
    String? chatId,
    Chat? chat,
    AppUser? user,
    AppUser? requestedByUser,
    String? status,
  }) {
    return ChatRequestModel(
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
