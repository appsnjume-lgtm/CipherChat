import '../../domain/entities/message_receipt.dart';

class MessageReceiptModel extends MessageReceipt {
  const MessageReceiptModel({
    required super.messageId,
    required super.chatId,
    required super.userId,
    super.deliveredAt,
    super.readAt,
    super.consumedAt,
  });

  factory MessageReceiptModel.fromMap(Map<String, dynamic> map) {
    return MessageReceiptModel(
      messageId: map['message_id'] as String,
      chatId: map['chat_id'] as String,
      userId: map['user_id'] as String,
      deliveredAt: _tryParse(map['delivered_at'] as String?),
      readAt: _tryParse(map['read_at'] as String?),
      consumedAt: _tryParse(map['consumed_at'] as String?),
    );
  }

  static DateTime? _tryParse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value).toLocal();
  }
}
