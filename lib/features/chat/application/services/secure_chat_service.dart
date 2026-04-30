import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/cipher_envelope.dart';
import '../../../../core/security/identity_key_service.dart';
import '../../../../core/security/secure_message_crypto.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/services/link_preview_service.dart';
import '../../data/repositories/chat_repository.dart';
import '../../presentation/providers/chat_provider.dart';
import '../../domain/entities/message.dart';
import '../models/resolved_chat_message.dart';

final linkPreviewServiceProvider = Provider<LinkPreviewService>(
  (ref) => LinkPreviewService(),
);

final secureChatServiceProvider = Provider<SecureChatService>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  final crypto = ref.watch(secureMessageCryptoProvider);
  final identity = ref.watch(identityKeyServiceProvider);
  final linkPreview = ref.watch(linkPreviewServiceProvider);
  return SecureChatService(repository, crypto, identity, linkPreview);
});

class SecureChatService {
  SecureChatService(
    this._repository,
    this._crypto,
    this._identity,
    this._linkPreview,
  );

  final ChatRepository _repository;
  final SecureMessageCrypto _crypto;
  final IdentityKeyService _identity;
  final LinkPreviewService _linkPreview;
  final Uuid _uuid = const Uuid();

  Future<List<ResolvedChatMessage>> fetchResolvedMessages({
    required String chatId,
    required String currentUserId,
    DateTime? before,
    int limit = AppConstants.messagePageSize,
  }) async {
    await _identity.ensurePublishedIdentity(currentUserId);
    final messages = await _repository.fetchMessages(
      chatId: chatId,
      before: before,
      limit: limit,
    );
    final resolved = await Future.wait(
      messages.map(
        (message) =>
            resolveMessage(message: message, currentUserId: currentUserId),
      ),
    );

    final incomingIds = messages
        .where((message) => message.senderId != currentUserId)
        .map((message) => message.id)
        .toList();
    if (incomingIds.isNotEmpty) {
      await _repository.markMessagesDelivered(
        chatId: chatId,
        userId: currentUserId,
        messageIds: incomingIds,
      );
      await _repository.markMessagesRead(
        chatId: chatId,
        userId: currentUserId,
        messageIds: incomingIds,
      );
    }

    return resolved;
  }

  Future<ResolvedChatMessage> resolveMessage({
    required Message message,
    required String currentUserId,
  }) async {
    if (message.isDeletedForEveryone) {
      return ResolvedChatMessage(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        kind: message.kind,
        createdAt: message.createdAt,
        isMine: message.senderId == currentUserId,
        deliveryState: message.deliveryStateFor(currentUserId),
        stickerId: message.stickerId,
        replyToMessageId: message.replyToMessageId,
        isDeletedForEveryone: true,
      );
    }

    try {
      final wrappedKey = message.envelopeForUser(currentUserId);
      if (wrappedKey == null) {
        throw StateError('No wrapped key was found for the active user.');
      }

      final payloadKey = await _crypto.unwrapPayloadKey(
        currentUserId: currentUserId,
        chatId: message.chatId,
        senderPublicKeyBase64: message.senderKeyPublic,
        wrappedKey: wrappedKey,
      );

      final payload = await _crypto.decryptJson(
        envelope: message.payloadEnvelope,
        secretKey: payloadKey,
        aad: _payloadAad(message.id, message.kind),
      );

      final linkPreview = payload['link_preview'] != null
          ? LinkPreviewData.fromJson(
              payload['link_preview'] as Map<String, dynamic>,
            )
          : null;

      switch (message.kind) {
        case MessageKind.text:
          return ResolvedChatMessage(
            id: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            kind: message.kind,
            createdAt: message.createdAt,
            isMine: message.senderId == currentUserId,
            deliveryState: message.deliveryStateFor(currentUserId),
            text: payload['text'] as String?,
            replyToMessageId: message.replyToMessageId,
            linkPreview: linkPreview,
          );
        case MessageKind.sticker:
          return ResolvedChatMessage(
            id: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            kind: message.kind,
            createdAt: message.createdAt,
            isMine: message.senderId == currentUserId,
            deliveryState: message.deliveryStateFor(currentUserId),
            stickerId: payload['sticker_id'] as String? ?? message.stickerId,
            replyToMessageId: message.replyToMessageId,
          );
        case MessageKind.grid_breach:
          return ResolvedChatMessage(
            id: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            kind: message.kind,
            createdAt: message.createdAt,
            isMine: message.senderId == currentUserId,
            deliveryState: message.deliveryStateFor(currentUserId),
            text: 'GRID BREACH INVITE',
            replyToMessageId: message.replyToMessageId,
            gameMatchId: payload['match_id'] as String?,
          );
        case MessageKind.image:
        case MessageKind.video:
        case MessageKind.file:
        case MessageKind.audio:
          final viewOnce = payload['view_once'] as bool? ?? false;
          final receipt = message.receiptForUser(currentUserId);
          final isConsumed =
              message.senderId != currentUserId &&
              viewOnce &&
              (receipt?.isConsumed ?? false);
          return ResolvedChatMessage(
            id: message.id,
            chatId: message.chatId,
            senderId: message.senderId,
            kind: message.kind,
            createdAt: message.createdAt,
            isMine: message.senderId == currentUserId,
            deliveryState: message.deliveryStateFor(currentUserId),
            replyToMessageId: message.replyToMessageId,
            isViewOnce: viewOnce,
            isConsumed: isConsumed,
            linkPreview: linkPreview,
            attachment: ResolvedAttachment(
              fileName: payload['file_name'] as String? ?? 'attachment.bin',
              mimeType:
                  payload['mime_type'] as String? ??
                  _fallbackMimeType(message.kind),
              sizeBytes: payload['size_bytes'] as int? ?? 0,
              storagePath: payload['storage_path'] as String? ?? '',
              blobNonceBase64: payload['blob_nonce'] as String? ?? '',
              blobMacBase64: payload['blob_mac'] as String? ?? '',
              isViewOnce: viewOnce,
              durationMs: payload['duration_ms'] as int?,
            ),
          );
      }
    } catch (_) {
      return ResolvedChatMessage(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        kind: message.kind,
        createdAt: message.createdAt,
        isMine: message.senderId == currentUserId,
        deliveryState: message.deliveryStateFor(currentUserId),
        stickerId: message.stickerId,
        errorLabel: '[Unable to decrypt]',
      );
    }
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String currentUserId,
    required String text,
    String? replyToMessageId,
    String? messageId,
  }) async {
    final resolvedMessageId = messageId ?? _uuid.v4();
    final participants = await _participantKeysForChat(chatId, currentUserId);
    final bundle = await _crypto.createPayloadKeyBundle(
      currentUserId: currentUserId,
      chatId: chatId,
      participantPublicKeys: participants,
    );

    final linkPreview = await _linkPreview.fetchPreview(text);

    final payload = await _crypto.encryptJson(
      payload: {
        'text': text,
        if (linkPreview != null) 'link_preview': linkPreview.toJson(),
      },
      secretKey: bundle.payloadKey,
      aad: _payloadAad(resolvedMessageId, MessageKind.text),
    );

    await _repository.createEncryptedMessage(
      messageId: resolvedMessageId,
      chatId: chatId,
      senderId: currentUserId,
      kind: MessageKind.text,
      payloadEnvelope: payload.toMap(),
      keyEnvelopes: bundle.toMap(),
      senderKeyPublic: bundle.senderPublicKeyBase64,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendStickerMessage({
    required String chatId,
    required String currentUserId,
    required String stickerId,
    String? replyToMessageId,
    String? messageId,
  }) async {
    final resolvedMessageId = messageId ?? _uuid.v4();
    final participants = await _participantKeysForChat(chatId, currentUserId);
    final bundle = await _crypto.createPayloadKeyBundle(
      currentUserId: currentUserId,
      chatId: chatId,
      participantPublicKeys: participants,
    );

    final payload = await _crypto.encryptJson(
      payload: {'sticker_id': stickerId},
      secretKey: bundle.payloadKey,
      aad: _payloadAad(resolvedMessageId, MessageKind.sticker),
    );

    await _repository.createEncryptedMessage(
      messageId: resolvedMessageId,
      chatId: chatId,
      senderId: currentUserId,
      kind: MessageKind.sticker,
      stickerId: stickerId,
      payloadEnvelope: payload.toMap(),
      keyEnvelopes: bundle.toMap(),
      senderKeyPublic: bundle.senderPublicKeyBase64,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendGridBreachInvite({
    required String chatId,
    required String currentUserId,
    required String matchId,
    String? messageId,
  }) async {
    final resolvedMessageId = messageId ?? _uuid.v4();
    final participants = await _participantKeysForChat(chatId, currentUserId);
    final bundle = await _crypto.createPayloadKeyBundle(
      currentUserId: currentUserId,
      chatId: chatId,
      participantPublicKeys: participants,
    );

    final payload = await _crypto.encryptJson(
      payload: {'match_id': matchId},
      secretKey: bundle.payloadKey,
      aad: _payloadAad(resolvedMessageId, MessageKind.grid_breach),
    );

    await _repository.createEncryptedMessage(
      messageId: resolvedMessageId,
      chatId: chatId,
      senderId: currentUserId,
      kind: MessageKind.grid_breach,
      payloadEnvelope: payload.toMap(),
      keyEnvelopes: bundle.toMap(),
      senderKeyPublic: bundle.senderPublicKeyBase64,
    );
  }

  Future<void> sendAttachmentMessage({
    required String chatId,
    required String currentUserId,
    required String sourcePath,
    required MessageKind kind,
    bool viewOnce = false,
    bool compressVideo = false,
    int? durationMs,
    String? fileNameOverride,
    String? replyToMessageId,
    String? caption,
    String? messageId,
  }) async {
    final resolvedMessageId = messageId ?? _uuid.v4();
    final participants = await _participantKeysForChat(chatId, currentUserId);
    final bundle = await _crypto.createPayloadKeyBundle(
      currentUserId: currentUserId,
      chatId: chatId,
      participantPublicKeys: participants,
    );

    final prepared = await _prepareAttachment(
      sourcePath: sourcePath,
      kind: kind,
      compressVideo: compressVideo,
      fileNameOverride: fileNameOverride,
    );
    final blobEnvelope = await _crypto.encryptBytes(
      prepared.bytes,
      secretKey: bundle.payloadKey,
      aad: _blobAad(resolvedMessageId),
    );

    final objectPath = _buildObjectPath(
      chatId: chatId,
      messageId: resolvedMessageId,
      fileName: prepared.fileName,
    );

    await _repository.uploadEncryptedMedia(
      objectPath: objectPath,
      bytes: Uint8List.fromList(blobEnvelope.cipherTextBytes),
      contentType: 'application/octet-stream',
    );

    final normalizedCaption = caption?.trim();
    final linkPreview = normalizedCaption == null || normalizedCaption.isEmpty
        ? null
        : await _linkPreview.fetchPreview(normalizedCaption);

    final payload = await _crypto.encryptJson(
      payload: {
        'file_name': prepared.fileName,
        'mime_type': prepared.mimeType,
        'size_bytes': prepared.bytes.length,
        'storage_path': objectPath,
        'blob_nonce': blobEnvelope.nonceBase64,
        'blob_mac': blobEnvelope.macBase64,
        'view_once': viewOnce,
        'duration_ms': durationMs,
        if (normalizedCaption != null && normalizedCaption.isNotEmpty)
          'text': normalizedCaption,
        if (linkPreview != null) 'link_preview': linkPreview.toJson(),
      },
      secretKey: bundle.payloadKey,
      aad: _payloadAad(resolvedMessageId, kind),
    );

    await _repository.createEncryptedMessage(
      messageId: resolvedMessageId,
      chatId: chatId,
      senderId: currentUserId,
      kind: kind,
      payloadEnvelope: payload.toMap(),
      keyEnvelopes: bundle.toMap(),
      senderKeyPublic: bundle.senderPublicKeyBase64,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<Message> deleteMessageForEveryone({
    required Message sourceMessage,
    required String currentUserId,
  }) async {
    if (sourceMessage.senderId != currentUserId) {
      throw StateError('Only the sender can delete this message for everyone.');
    }

    if (!sourceMessage.isDeletedForEveryone &&
        sourceMessage.kind != MessageKind.text) {
      try {
        final resolved = await resolveMessage(
          message: sourceMessage,
          currentUserId: currentUserId,
        );
        final storagePath = resolved.attachment?.storagePath;
        if (storagePath != null && storagePath.isNotEmpty) {
          await _repository.deleteEncryptedMedia(storagePath);
        }
      } catch (_) {
        // If media cleanup fails, we still proceed with the tombstone update.
      }
    }

    return _repository.markMessageDeletedForEveryone(
      messageId: sourceMessage.id,
    );
  }

  Future<File> materializeAttachment({
    required Message sourceMessage,
    required ResolvedChatMessage resolvedMessage,
    required String currentUserId,
  }) async {
    final attachment = resolvedMessage.attachment;
    if (attachment == null || resolvedMessage.isDeletedForEveryone) {
      throw StateError(
        'This message does not contain a downloadable attachment.',
      );
    }
    if (resolvedMessage.isConsumed && !resolvedMessage.isMine) {
      throw StateError('This attachment has already been consumed.');
    }

    final cacheFile = await _cachedFileFor(
      messageId: sourceMessage.id,
      fileName: attachment.fileName,
    );
    if (await cacheFile.exists()) {
      return cacheFile;
    }

    final wrappedKey = sourceMessage.envelopeForUser(currentUserId);
    if (wrappedKey == null) {
      throw StateError('No wrapped key was found for the active user.');
    }

    final payloadKey = await _crypto.unwrapPayloadKey(
      currentUserId: currentUserId,
      chatId: sourceMessage.chatId,
      senderPublicKeyBase64: sourceMessage.senderKeyPublic,
      wrappedKey: wrappedKey,
    );

    final encryptedBytes = await _repository.downloadEncryptedMedia(
      attachment.storagePath,
    );
    final blobEnvelope = CipherEnvelope(
      nonceBase64: attachment.blobNonceBase64,
      cipherTextBase64: base64Encode(encryptedBytes),
      macBase64: attachment.blobMacBase64,
    );
    final plainBytes = await _crypto.decryptBytes(
      blobEnvelope,
      secretKey: payloadKey,
      aad: _blobAad(sourceMessage.id),
    );

    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(plainBytes, flush: true);
    return cacheFile;
  }

  Future<void> consumeViewOnceMessage({
    required Message sourceMessage,
    required ResolvedChatMessage resolvedMessage,
    required String currentUserId,
  }) async {
    if (!resolvedMessage.isViewOnce || resolvedMessage.isMine) {
      return;
    }

    final cacheFile = await _cachedFileFor(
      messageId: sourceMessage.id,
      fileName: resolvedMessage.attachment?.fileName ?? 'attachment.bin',
    );
    if (await cacheFile.exists()) {
      await cacheFile.delete();
    }

    await _repository.markMessageConsumed(
      chatId: sourceMessage.chatId,
      userId: currentUserId,
      messageId: sourceMessage.id,
    );
  }

  Future<Map<String, String>> _participantKeysForChat(
    String chatId,
    String currentUserId,
  ) async {
    final keys = await _repository.fetchParticipantPublicKeys(chatId);
    final ownPublicKey = await _identity.ensurePublishedIdentity(currentUserId);
    final merged = <String, String>{...keys, currentUserId: ownPublicKey};
    if (merged.length < 2) {
      throw StateError('A chat needs at least two published identity keys.');
    }
    return merged;
  }

  Future<_PreparedAttachment> _prepareAttachment({
    required String sourcePath,
    required MessageKind kind,
    required bool compressVideo,
    String? fileNameOverride,
  }) async {
    var file = File(sourcePath);
    if (!await file.exists()) {
      throw StateError('Selected file no longer exists on disk.');
    }

    if (kind == MessageKind.image) {
      final compressed = await FlutterImageCompress.compressWithFile(
        sourcePath,
        quality: 82,
        minWidth: 1600,
        minHeight: 1600,
      );
      if (compressed != null) {
        return _PreparedAttachment(
          bytes: Uint8List.fromList(compressed),
          fileName:
              fileNameOverride ??
              _normalizedFileName(file.path, fallback: 'image.jpg'),
          mimeType: 'image/jpeg',
        );
      }
    }

    if (kind == MessageKind.video && compressVideo) {
      try {
        final mediaInfo = await VideoCompress.compressVideo(
          sourcePath,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        final compressedFile = mediaInfo?.file;
        if (compressedFile != null && await compressedFile.exists()) {
          file = compressedFile;
        }
      } catch (_) {
        // We deliberately fall back to the original video bytes if compression fails.
      }
    }

    return _PreparedAttachment(
      bytes: await file.readAsBytes(),
      fileName: fileNameOverride ?? _normalizedFileName(file.path),
      mimeType: lookupMimeType(file.path) ?? _fallbackMimeType(kind),
    );
  }

  String _buildObjectPath({
    required String chatId,
    required String messageId,
    required String fileName,
  }) {
    final extension = p.extension(fileName);
    final safeExtension = extension.isEmpty ? '.bin' : extension;
    return '$chatId/$messageId$safeExtension.enc';
  }

  Future<File> _cachedFileFor({
    required String messageId,
    required String fileName,
  }) async {
    final directory = await getTemporaryDirectory();
    final cacheDir = Directory(
      p.join(directory.path, AppConstants.encryptedMediaCacheFolder),
    );
    return File(
      p.join(
        cacheDir.path,
        '$messageId${p.extension(fileName).isEmpty ? '.bin' : p.extension(fileName)}',
      ),
    );
  }

  String _normalizedFileName(String path, {String? fallback}) {
    final name = p.basename(path).trim();
    if (name.isNotEmpty) {
      return name;
    }
    return fallback ?? 'attachment.bin';
  }

  String _payloadAad(String messageId, MessageKind kind) {
    return 'cipherchat:payload:$messageId:${kind.name}';
  }

  String _blobAad(String messageId) {
    return 'cipherchat:blob:$messageId';
  }

  String _fallbackMimeType(MessageKind kind) {
    switch (kind) {
      case MessageKind.image:
        return 'image/jpeg';
      case MessageKind.video:
        return 'video/mp4';
      case MessageKind.file:
        return 'application/octet-stream';
      case MessageKind.audio:
        return 'audio/mpeg';
      case MessageKind.sticker:
        return 'image/png';
      case MessageKind.grid_breach:
        return 'application/octet-stream';
      case MessageKind.text:
        return 'application/octet-stream';
    }
  }
}

class _PreparedAttachment {
  const _PreparedAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}
