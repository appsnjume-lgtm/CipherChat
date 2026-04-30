import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/local_chat_cache_service.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/message.dart';
import '../models/pending_outgoing_message_record.dart';
import 'secure_chat_service.dart';

final pendingOutgoingMessageSyncServiceProvider =
    Provider<PendingOutgoingMessageSyncService>((ref) {
      return PendingOutgoingMessageSyncService(ref);
    });

class PendingMessageSyncResult {
  const PendingMessageSyncResult({
    this.sentMessageIds = const [],
    this.droppedMessageIds = const [],
  });

  final List<String> sentMessageIds;
  final List<String> droppedMessageIds;

  PendingMessageSyncResult merge(PendingMessageSyncResult other) {
    return PendingMessageSyncResult(
      sentMessageIds: [...sentMessageIds, ...other.sentMessageIds],
      droppedMessageIds: [...droppedMessageIds, ...other.droppedMessageIds],
    );
  }
}

class PendingOutgoingMessageSyncService {
  PendingOutgoingMessageSyncService(this._ref);

  final Ref _ref;

  bool _isSyncing = false;
  bool _needsResync = false;

  LocalChatCacheService get _chatCache =>
      _ref.read(localChatCacheServiceProvider);

  Future<List<PendingOutgoingMessageRecord>> readPendingMessages({
    required String userId,
    String? chatId,
  }) {
    return _chatCache.readPendingOutgoingMessages(
      userId: userId,
      chatId: chatId,
    );
  }

  Future<PendingMessageSyncResult> enqueueAndAttemptSend({
    required String userId,
    required PendingOutgoingMessageRecord record,
  }) async {
    await _chatCache.upsertPendingOutgoingMessage(
      userId: userId,
      message: record,
    );
    return syncAllPendingMessages();
  }

  Future<PendingMessageSyncResult> syncAllPendingMessages() async {
    final currentUserId = _ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return const PendingMessageSyncResult();
    }

    if (_isSyncing) {
      _needsResync = true;
      return const PendingMessageSyncResult();
    }

    _isSyncing = true;
    var aggregate = const PendingMessageSyncResult();

    try {
      do {
        _needsResync = false;
        final isOnline = await _ref
            .read(connectivityServiceProvider)
            .currentStatus();
        if (!isOnline) {
          return aggregate;
        }

        final pending = await _chatCache.readPendingOutgoingMessages(
          userId: currentUserId,
        );
        if (pending.isEmpty) {
          return aggregate;
        }

        for (final record in pending) {
          final result = await _sendPendingRecord(
            userId: currentUserId,
            record: record,
          );
          aggregate = aggregate.merge(result);
          if (result.sentMessageIds.isEmpty &&
              result.droppedMessageIds.isEmpty) {
            return aggregate;
          }
        }
      } while (_needsResync);
    } finally {
      _isSyncing = false;
    }

    return aggregate;
  }

  Future<PendingMessageSyncResult> _sendPendingRecord({
    required String userId,
    required PendingOutgoingMessageRecord record,
  }) async {
    try {
      switch (record.kind) {
        case MessageKind.text:
          final text = record.text?.trim();
          if (text == null || text.isEmpty) {
            throw StateError('Pending text message is empty.');
          }
          await _ref
              .read(secureChatServiceProvider)
              .sendTextMessage(
                messageId: record.messageId,
                chatId: record.chatId,
                currentUserId: userId,
                text: text,
                replyToMessageId: record.replyToMessageId,
              );
          break;
        case MessageKind.sticker:
          final stickerId = record.stickerId?.trim();
          if (stickerId == null || stickerId.isEmpty) {
            throw StateError('Pending sticker reference is missing.');
          }
          await _ref
              .read(secureChatServiceProvider)
              .sendStickerMessage(
                messageId: record.messageId,
                chatId: record.chatId,
                currentUserId: userId,
                stickerId: stickerId,
                replyToMessageId: record.replyToMessageId,
              );
          break;
        case MessageKind.image:
        case MessageKind.video:
        case MessageKind.file:
        case MessageKind.audio:
          final path = record.localPath?.trim();
          if (path == null || path.isEmpty) {
            throw StateError('Pending attachment path is missing.');
          }
          await _ref
              .read(secureChatServiceProvider)
              .sendAttachmentMessage(
                messageId: record.messageId,
                chatId: record.chatId,
                currentUserId: userId,
                sourcePath: path,
                kind: record.kind,
                viewOnce: record.viewOnce,
                compressVideo: record.compressVideo,
                durationMs: record.durationMs,
                fileNameOverride: record.fileNameOverride,
                replyToMessageId: record.replyToMessageId,
              );
          break;
        case MessageKind.grid_breach:
          debugPrint(
            'Dropping unsupported pending GRID BREACH message '
            '${record.messageId}.',
          );
          await _chatCache.removePendingOutgoingMessage(
            userId: userId,
            messageId: record.messageId,
          );
          return PendingMessageSyncResult(
            droppedMessageIds: [record.messageId],
          );
      }

      await _chatCache.removePendingOutgoingMessage(
        userId: userId,
        messageId: record.messageId,
      );
      return PendingMessageSyncResult(sentMessageIds: [record.messageId]);
    } catch (error) {
      if (AppErrorHelper.isNetworkRelated(error)) {
        return const PendingMessageSyncResult();
      }

      if (!AppErrorHelper.isPermanentOutgoingMessageFailure(error)) {
        return const PendingMessageSyncResult();
      }

      await _chatCache.removePendingOutgoingMessage(
        userId: userId,
        messageId: record.messageId,
      );
      return PendingMessageSyncResult(droppedMessageIds: [record.messageId]);
    }
  }
}
