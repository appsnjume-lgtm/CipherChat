class MessageReceipt {
  const MessageReceipt({
    required this.messageId,
    required this.chatId,
    required this.userId,
    this.deliveredAt,
    this.readAt,
    this.consumedAt,
  });

  final String messageId;
  final String chatId;
  final String userId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? consumedAt;

  bool get isDelivered => deliveredAt != null;
  bool get isRead => readAt != null;
  bool get isConsumed => consumedAt != null;
}
