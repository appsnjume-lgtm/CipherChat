import '../../../../core/security/cipher_envelope.dart';
import '../../domain/entities/message.dart';
import 'message_receipt_model.dart';

class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.chatId,
    required super.senderId,
    required super.kind,
    required super.payloadEnvelope,
    required super.keyEnvelopes,
    required super.senderKeyPublic,
    required super.createdAt,
    required super.receipts,
    super.stickerId,
    super.replyToMessageId,
    super.deletedForEveryoneAt,
    super.deletedForEveryoneBy,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    final receiptRows = (map['message_receipts'] as List<dynamic>? ?? const []);
    final rawKeyEnvelopes =
        map['key_envelopes'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final payloadEncrypted =
        map['payload_encrypted'] as Map<String, dynamic>? ??
        const <String, dynamic>{'nonce': '', 'cipher_text': '', 'mac': ''};

    return MessageModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      kind: _kindFromRaw(map['message_type'] as String? ?? 'text'),
      stickerId: map['sticker_id'] as String?,
      payloadEnvelope: CipherEnvelope.fromMap(
        Map<String, dynamic>.from(payloadEncrypted),
      ),
      keyEnvelopes: {
        for (final entry in rawKeyEnvelopes.entries)
          entry.key: CipherEnvelope.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      senderKeyPublic: map['sender_key_public'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      replyToMessageId: map['reply_to_message_id'] as String?,
      deletedForEveryoneAt: _tryParse(
        map['deleted_for_everyone_at'] as String?,
      ),
      deletedForEveryoneBy: map['deleted_for_everyone_by'] as String?,
      receipts: receiptRows
          .map(
            (item) => MessageReceiptModel.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  static MessageKind _kindFromRaw(String value) {
    switch (value) {
      case 'image':
        return MessageKind.image;
      case 'video':
        return MessageKind.video;
      case 'file':
        return MessageKind.file;
      case 'audio':
        return MessageKind.audio;
      case 'sticker':
        return MessageKind.sticker;
      case 'grid_breach':
        return MessageKind.grid_breach;
      case 'text':
      default:
        return MessageKind.text;
    }
  }

  static DateTime? _tryParse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value).toLocal();
  }
}
