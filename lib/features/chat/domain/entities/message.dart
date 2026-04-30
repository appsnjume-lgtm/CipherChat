import '../../../../core/security/cipher_envelope.dart';
import 'message_receipt.dart';

enum MessageKind { text, image, video, file, audio, sticker, grid_breach }

enum MessageDeliveryState { sending, sent, delivered, read, consumed, failed }

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.kind,
    required this.payloadEnvelope,
    required this.keyEnvelopes,
    required this.senderKeyPublic,
    required this.createdAt,
    required this.receipts,
    this.stickerId,
    this.replyToMessageId,
    this.deletedForEveryoneAt,
    this.deletedForEveryoneBy,
    this.gameMatchId,
  });

  final String id;
  final String chatId;
  final String senderId;
  final MessageKind kind;
  final CipherEnvelope payloadEnvelope;
  final Map<String, CipherEnvelope> keyEnvelopes;
  final String senderKeyPublic;
  final DateTime createdAt;
  final String? stickerId;
  final String? replyToMessageId;
  final List<MessageReceipt> receipts;
  final DateTime? deletedForEveryoneAt;
  final String? deletedForEveryoneBy;
  final String? gameMatchId;

  bool get isDeletedForEveryone => deletedForEveryoneAt != null;

  CipherEnvelope? envelopeForUser(String userId) {
    return keyEnvelopes[userId];
  }

  Message copyWith({
    List<MessageReceipt>? receipts,
    DateTime? deletedForEveryoneAt,
    String? deletedForEveryoneBy,
    bool keepDeletedFields = true,
    String? gameMatchId,
  }) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      kind: kind,
      payloadEnvelope: payloadEnvelope,
      keyEnvelopes: keyEnvelopes,
      senderKeyPublic: senderKeyPublic,
      createdAt: createdAt,
      stickerId: stickerId,
      replyToMessageId: replyToMessageId,
      receipts: receipts ?? this.receipts,
      deletedForEveryoneAt: keepDeletedFields
          ? deletedForEveryoneAt ?? this.deletedForEveryoneAt
          : deletedForEveryoneAt,
      deletedForEveryoneBy: keepDeletedFields
          ? deletedForEveryoneBy ?? this.deletedForEveryoneBy
          : deletedForEveryoneBy,
      gameMatchId: gameMatchId ?? this.gameMatchId,
    );
  }

  MessageReceipt? receiptForUser(String userId) {
    for (final receipt in receipts) {
      if (receipt.userId == userId) {
        return receipt;
      }
    }
    return null;
  }

  String get previewLabel {
    if (isDeletedForEveryone) {
      return 'Deleted message';
    }

    switch (kind) {
      case MessageKind.text:
        return 'Encrypted message';
      case MessageKind.image:
        return 'Encrypted photo';
      case MessageKind.video:
        return 'Encrypted video';
      case MessageKind.file:
        return 'Encrypted file';
      case MessageKind.audio:
        return 'Encrypted audio';
      case MessageKind.sticker:
        return 'Sticker';
      case MessageKind.grid_breach:
        return 'GRID BREACH INVITE';
    }
  }

  MessageDeliveryState deliveryStateFor(String currentUserId) {
    if (senderId != currentUserId) {
      return MessageDeliveryState.read;
    }

    if (receipts.any((receipt) => receipt.isConsumed)) {
      return MessageDeliveryState.consumed;
    }
    if (receipts.any((receipt) => receipt.isRead)) {
      return MessageDeliveryState.read;
    }
    if (receipts.any((receipt) => receipt.isDelivered)) {
      return MessageDeliveryState.delivered;
    }
    return MessageDeliveryState.sent;
  }
}
