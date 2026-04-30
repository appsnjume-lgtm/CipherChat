import '../../domain/entities/message.dart';

class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
  };

  factory LinkPreviewData.fromJson(Map<String, dynamic> json) =>
      LinkPreviewData(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );
}

class ResolvedAttachment {
  const ResolvedAttachment({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.storagePath,
    required this.blobNonceBase64,
    required this.blobMacBase64,
    required this.isViewOnce,
    this.durationMs,
    this.localPath,
    this.thumbnailPath,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String storagePath;
  final String blobNonceBase64;
  final String blobMacBase64;
  final bool isViewOnce;
  final int? durationMs;
  final String? localPath;
  final String? thumbnailPath;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
}

class ResolvedChatMessage {
  const ResolvedChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.kind,
    required this.createdAt,
    required this.isMine,
    required this.deliveryState,
    this.stickerId,
    this.text,
    this.attachment,
    this.replyToMessageId,
    this.senderLabel,
    this.isViewOnce = false,
    this.isConsumed = false,
    this.isDeletedForEveryone = false,
    this.isPendingLocal = false,
    this.errorLabel,
    this.linkPreview,
    this.gameMatchId,
    this.isExpiredGridBreachSession = false,
  });

  final String id;
  final String chatId;
  final String senderId;
  final MessageKind kind;
  final DateTime createdAt;
  final bool isMine;
  final MessageDeliveryState deliveryState;
  final String? stickerId;
  final String? text;
  final ResolvedAttachment? attachment;
  final String? replyToMessageId;
  final String? senderLabel;
  final bool isViewOnce;
  final bool isConsumed;
  final bool isDeletedForEveryone;
  final bool isPendingLocal;
  final String? errorLabel;
  final LinkPreviewData? linkPreview;
  final String? gameMatchId;
  final bool isExpiredGridBreachSession;

  bool get canBeCopied => kind == MessageKind.text && !isDeletedForEveryone;

  ResolvedChatMessage copyWith({
    MessageDeliveryState? deliveryState,
    bool? isPendingLocal,
    ResolvedAttachment? attachment,
    bool setAttachment = false,
    String? text,
    bool setText = false,
    String? gameMatchId,
    bool? isExpiredGridBreachSession,
  }) {
    return ResolvedChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      kind: kind,
      createdAt: createdAt,
      isMine: isMine,
      deliveryState: deliveryState ?? this.deliveryState,
      stickerId: stickerId,
      text: setText ? text : this.text,
      attachment: setAttachment ? attachment : this.attachment,
      replyToMessageId: replyToMessageId,
      senderLabel: senderLabel,
      isViewOnce: isViewOnce,
      isConsumed: isConsumed,
      isDeletedForEveryone: isDeletedForEveryone,
      isPendingLocal: isPendingLocal ?? this.isPendingLocal,
      errorLabel: errorLabel,
      linkPreview: linkPreview,
      gameMatchId: gameMatchId ?? this.gameMatchId,
      isExpiredGridBreachSession:
          isExpiredGridBreachSession ?? this.isExpiredGridBreachSession,
    );
  }

  String get previewText {
    if (isDeletedForEveryone) {
      return isMine ? 'You deleted this message' : 'This message was deleted';
    }
    if (errorLabel != null) {
      return errorLabel!;
    }
    switch (kind) {
      case MessageKind.text:
        return text ?? '';
      case MessageKind.image:
        return isConsumed ? 'Photo expired' : 'Photo';
      case MessageKind.video:
        return isConsumed ? 'Video expired' : 'Video';
      case MessageKind.file:
        return attachment?.fileName ?? 'File';
      case MessageKind.audio:
        return 'Audio message';
      case MessageKind.sticker:
        return 'Sticker';
      case MessageKind.grid_breach:
        return 'GRID BREACH INVITE';
    }
  }
}
