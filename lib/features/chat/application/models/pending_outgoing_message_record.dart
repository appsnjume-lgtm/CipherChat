import '../../domain/entities/message.dart';

class PendingOutgoingMessageRecord {
  const PendingOutgoingMessageRecord({
    required this.messageId,
    required this.chatId,
    required this.kind,
    required this.createdAt,
    this.stickerId,
    this.text,
    this.localPath,
    this.replyToMessageId,
    this.viewOnce = false,
    this.compressVideo = false,
    this.durationMs,
    this.fileNameOverride,
  });

  final String messageId;
  final String chatId;
  final MessageKind kind;
  final DateTime createdAt;
  final String? stickerId;
  final String? text;
  final String? localPath;
  final String? replyToMessageId;
  final bool viewOnce;
  final bool compressVideo;
  final int? durationMs;
  final String? fileNameOverride;

  factory PendingOutgoingMessageRecord.fromMap(Map<String, dynamic> map) {
    return PendingOutgoingMessageRecord(
      messageId: map['message_id'] as String,
      chatId: map['chat_id'] as String,
      kind: _kindFromValue(map['kind'] as String? ?? 'text'),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      stickerId: map['sticker_id'] as String?,
      text: map['text'] as String?,
      localPath: map['local_path'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      viewOnce: map['view_once'] as bool? ?? false,
      compressVideo: map['compress_video'] as bool? ?? false,
      durationMs: map['duration_ms'] as int?,
      fileNameOverride: map['file_name_override'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'chat_id': chatId,
      'kind': kind.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sticker_id': stickerId,
      'text': text,
      'local_path': localPath,
      'reply_to_message_id': replyToMessageId,
      'view_once': viewOnce,
      'compress_video': compressVideo,
      'duration_ms': durationMs,
      'file_name_override': fileNameOverride,
    };
  }

  static MessageKind _kindFromValue(String value) {
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
      case 'text':
      default:
        return MessageKind.text;
    }
  }
}
