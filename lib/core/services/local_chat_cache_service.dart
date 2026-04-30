import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/chat/application/models/pending_outgoing_message_record.dart';
import '../../features/chat/application/models/resolved_chat_message.dart';
import '../../features/chat/domain/entities/chat.dart';
import '../../features/chat/domain/entities/chat_member.dart';
import '../../features/chat/domain/entities/message.dart';
import '../../features/chat/domain/entities/message_receipt.dart';
import '../security/cipher_envelope.dart';

final localChatCacheServiceProvider = Provider<LocalChatCacheService>((ref) {
  return LocalChatCacheService.instance;
});

class LocalChatCacheService {
  LocalChatCacheService._();

  static final LocalChatCacheService instance = LocalChatCacheService._();

  static const _emptyEnvelope = CipherEnvelope(
    nonceBase64: '',
    cipherTextBase64: '',
    macBase64: '',
  );

  Future<List<Chat>> readChatSnapshots(String userId) async {
    final file = await _chatListFile(userId);
    if (!await file.exists()) {
      return const [];
    }

    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        return const [];
      }

      return raw
          .whereType<Map>()
          .map((item) => _chatFromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Chat?> readChatSnapshot({
    required String userId,
    required String chatId,
  }) async {
    final chats = await readChatSnapshots(userId);
    for (final chat in chats) {
      if (chat.id == chatId) {
        return chat;
      }
    }
    return null;
  }

  Future<void> writeChatSnapshots({
    required String userId,
    required List<Chat> chats,
  }) async {
    final file = await _chatListFile(userId);
    final payload = chats.map(_chatToMap).toList(growable: false);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> updateChatPreviewText({
    required String userId,
    required String chatId,
    required String? previewText,
  }) async {
    final chats = await readChatSnapshots(userId);
    if (chats.isEmpty) {
      return;
    }

    final nextChats = chats
        .map(
          (chat) => chat.id == chatId
              ? _copyChatWithPreview(chat, previewText)
              : chat,
        )
        .toList(growable: false);
    await writeChatSnapshots(userId: userId, chats: nextChats);
  }

  Future<List<ResolvedChatMessage>> readMessageHeaders({
    required String userId,
    required String chatId,
  }) async {
    final file = await _messageHeadersFile(userId: userId, chatId: chatId);
    if (!await file.exists()) {
      return const [];
    }

    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        return const [];
      }

      return raw
          .whereType<Map>()
          .map(
            (item) => _resolvedMessageFromMap(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeMessageHeaders({
    required String userId,
    required String chatId,
    required List<ResolvedChatMessage> messages,
    int maxItems = 60,
  }) async {
    final trimmed = [...messages]
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    final selected = trimmed.length <= maxItems
        ? trimmed
        : trimmed.sublist(trimmed.length - maxItems);

    final file = await _messageHeadersFile(userId: userId, chatId: chatId);
    final payload = selected.map(_resolvedMessageToMap).toList(growable: false);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<List<PendingOutgoingMessageRecord>> readPendingOutgoingMessages({
    required String userId,
    String? chatId,
  }) async {
    final file = await _pendingOutgoingMessagesFile(userId);
    if (!await file.exists()) {
      return const [];
    }

    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        return const [];
      }

      final pending =
          raw
              .whereType<Map>()
              .map(
                (item) => PendingOutgoingMessageRecord.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => chatId == null || item.chatId == chatId)
              .toList(growable: false)
            ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

      return pending;
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertPendingOutgoingMessage({
    required String userId,
    required PendingOutgoingMessageRecord message,
  }) async {
    final existing = await readPendingOutgoingMessages(userId: userId);
    final next = [
      ...existing.where((item) => item.messageId != message.messageId),
      message,
    ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    final file = await _pendingOutgoingMessagesFile(userId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(next.map((item) => item.toMap()).toList(growable: false)),
      flush: true,
    );
  }

  Future<void> removePendingOutgoingMessage({
    required String userId,
    required String messageId,
  }) async {
    final existing = await readPendingOutgoingMessages(userId: userId);
    final next = existing
        .where((item) => item.messageId != messageId)
        .toList(growable: false);

    final file = await _pendingOutgoingMessagesFile(userId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(next.map((item) => item.toMap()).toList(growable: false)),
      flush: true,
    );
  }

  Chat _copyChatWithPreview(Chat chat, String? previewText) {
    return Chat(
      id: chat.id,
      isGroup: chat.isGroup,
      createdBy: chat.createdBy,
      createdAt: chat.createdAt,
      title: chat.title,
      groupImageUrl: chat.groupImageUrl,
      members: chat.members,
      latestMessage: chat.latestMessage,
      latestMessagePreviewText: previewText,
      unreadCount: chat.unreadCount,
      isCurrentUserMember: chat.isCurrentUserMember,
      isCurrentUserAdmin: chat.isCurrentUserAdmin,
    );
  }

  Future<Directory> _baseDirectory() async {
    final directory = await getApplicationSupportDirectory();
    final base = Directory(p.join(directory.path, 'cipherchat_local_cache'));
    await base.create(recursive: true);
    return base;
  }

  Future<File> _chatListFile(String userId) async {
    final base = await _baseDirectory();
    return File(p.join(base.path, 'chat_cache', userId, 'chat_list.json'));
  }

  Future<File> _messageHeadersFile({
    required String userId,
    required String chatId,
  }) async {
    final base = await _baseDirectory();
    return File(
      p.join(base.path, 'chat_cache', userId, 'headers', '$chatId.json'),
    );
  }

  Future<File> _pendingOutgoingMessagesFile(String userId) async {
    final base = await _baseDirectory();
    return File(p.join(base.path, 'chat_cache', userId, 'pending_outbox.json'));
  }

  Map<String, dynamic> _chatToMap(Chat chat) {
    return {
      'id': chat.id,
      'is_group': chat.isGroup,
      'created_by': chat.createdBy,
      'created_at': chat.createdAt.toUtc().toIso8601String(),
      'title': chat.title,
      'group_image_url': chat.groupImageUrl,
      'unread_count': chat.unreadCount,
      'is_current_user_member': chat.isCurrentUserMember,
      'is_current_user_admin': chat.isCurrentUserAdmin,
      'latest_message_preview_text': chat.latestMessage?.previewLabel,
      'members': chat.members.map(_chatMemberToMap).toList(growable: false),
      'latest_message': chat.latestMessage == null
          ? null
          : _messageToMap(chat.latestMessage!),
    };
  }

  Chat _chatFromMap(Map<String, dynamic> map) {
    final rawMembers = map['members'] as List<dynamic>? ?? const [];
    return Chat(
      id: map['id'] as String,
      isGroup: map['is_group'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
      createdAt: _parseDate(map['created_at'] as String) ?? DateTime.now(),
      title: (map['title'] as String?)?.trim(),
      groupImageUrl: (map['group_image_url'] as String?)?.trim(),
      members: rawMembers
          .whereType<Map>()
          .map((item) => _chatMemberFromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      latestMessage: map['latest_message'] is Map<String, dynamic>
          ? _messageFromMap(map['latest_message'] as Map<String, dynamic>)
          : map['latest_message'] is Map
          ? _messageFromMap(
              Map<String, dynamic>.from(map['latest_message'] as Map),
            )
          : null,
      latestMessagePreviewText: (map['latest_message_preview_text'] as String?)
          ?.trim(),
      unreadCount: map['unread_count'] as int? ?? 0,
      isCurrentUserMember: map['is_current_user_member'] as bool? ?? false,
      isCurrentUserAdmin: map['is_current_user_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _chatMemberToMap(ChatMember member) {
    return {
      'id': member.id,
      'chat_id': member.chatId,
      'user_id': member.userId,
      'role': member.role,
      'joined_at': member.joinedAt.toUtc().toIso8601String(),
      'username': member.username,
      'avatar_id': member.avatarId,
      'profile_image_url': member.profileImageUrl,
      'gender_label': member.genderLabel,
      'bio_preview': member.bioPreview,
      'is_online': member.isOnline,
      'last_seen_at': member.lastSeenAt?.toUtc().toIso8601String(),
    };
  }

  ChatMember _chatMemberFromMap(Map<String, dynamic> map) {
    return ChatMember(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String? ?? 'member',
      joinedAt: _parseDate(map['joined_at'] as String) ?? DateTime.now(),
      username: (map['username'] as String?)?.trim(),
      avatarId: (map['avatar_id'] as String?)?.trim(),
      profileImageUrl: (map['profile_image_url'] as String?)?.trim(),
      genderLabel: (map['gender_label'] as String?)?.trim(),
      bioPreview: (map['bio_preview'] as String?)?.trim(),
      isOnline: map['is_online'] as bool? ?? false,
      lastSeenAt: _parseDate(map['last_seen_at'] as String?),
    );
  }

  Map<String, dynamic> _messageToMap(Message message) {
    return {
      'id': message.id,
      'chat_id': message.chatId,
      'sender_id': message.senderId,
      'message_type': message.kind.name,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'sticker_id': message.stickerId,
      'reply_to_message_id': message.replyToMessageId,
      'deleted_for_everyone_at': message.deletedForEveryoneAt
          ?.toUtc()
          .toIso8601String(),
      'deleted_for_everyone_by': message.deletedForEveryoneBy,
      'receipts': message.receipts.map(_messageReceiptToMap).toList(),
    };
  }

  Message _messageFromMap(Map<String, dynamic> map) {
    final receiptRows = map['receipts'] as List<dynamic>? ?? const [];
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      kind: _messageKindFromValue(map['message_type'] as String? ?? 'text'),
      payloadEnvelope: _emptyEnvelope,
      keyEnvelopes: const {},
      stickerId: map['sticker_id'] as String?,
      senderKeyPublic: '',
      createdAt: _parseDate(map['created_at'] as String) ?? DateTime.now(),
      replyToMessageId: map['reply_to_message_id'] as String?,
      deletedForEveryoneAt: _parseDate(
        map['deleted_for_everyone_at'] as String?,
      ),
      deletedForEveryoneBy: map['deleted_for_everyone_by'] as String?,
      receipts: receiptRows
          .whereType<Map>()
          .map(
            (item) => _messageReceiptFromMap(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> _messageReceiptToMap(MessageReceipt receipt) {
    return {
      'message_id': receipt.messageId,
      'chat_id': receipt.chatId,
      'user_id': receipt.userId,
      'delivered_at': receipt.deliveredAt?.toUtc().toIso8601String(),
      'read_at': receipt.readAt?.toUtc().toIso8601String(),
      'consumed_at': receipt.consumedAt?.toUtc().toIso8601String(),
    };
  }

  MessageReceipt _messageReceiptFromMap(Map<String, dynamic> map) {
    return MessageReceipt(
      messageId: map['message_id'] as String,
      chatId: map['chat_id'] as String,
      userId: map['user_id'] as String,
      deliveredAt: _parseDate(map['delivered_at'] as String?),
      readAt: _parseDate(map['read_at'] as String?),
      consumedAt: _parseDate(map['consumed_at'] as String?),
    );
  }

  Map<String, dynamic> _resolvedMessageToMap(ResolvedChatMessage message) {
    return {
      'id': message.id,
      'chat_id': message.chatId,
      'sender_id': message.senderId,
      'kind': message.kind.name,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'is_mine': message.isMine,
      'delivery_state': message.deliveryState.name,
      'sticker_id': message.stickerId,
      'text': null,
      'reply_to_message_id': message.replyToMessageId,
      'sender_label': null,
      'is_view_once': message.isViewOnce,
      'is_consumed': message.isConsumed,
      'is_deleted_for_everyone': message.isDeletedForEveryone,
      'error_label': message.errorLabel,
      // Keep cached headers free of decrypted content and attachment metadata.
      'attachment': null,
      'link_preview': null,
      'game_match_id': message.gameMatchId,
      'is_expired_grid_breach_session': message.isExpiredGridBreachSession,
    };
  }

  ResolvedChatMessage _resolvedMessageFromMap(Map<String, dynamic> map) {
    final rawAttachment = map['attachment'];
    final rawLinkPreview = map['link_preview'];
    return ResolvedChatMessage(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      kind: _messageKindFromValue(map['kind'] as String? ?? 'text'),
      createdAt: _parseDate(map['created_at'] as String) ?? DateTime.now(),
      isMine: map['is_mine'] as bool? ?? false,
      deliveryState: _deliveryStateFromValue(
        map['delivery_state'] as String? ?? 'sent',
      ),
      stickerId: map['sticker_id'] as String?,
      text: map['text'] as String?,
      attachment: rawAttachment is Map
          ? ResolvedAttachment(
              fileName: rawAttachment['file_name'] as String? ?? 'attachment',
              mimeType:
                  rawAttachment['mime_type'] as String? ??
                  'application/octet-stream',
              sizeBytes: rawAttachment['size_bytes'] as int? ?? 0,
              storagePath: rawAttachment['storage_path'] as String? ?? '',
              blobNonceBase64: rawAttachment['blob_nonce'] as String? ?? '',
              blobMacBase64: rawAttachment['blob_mac'] as String? ?? '',
              isViewOnce: rawAttachment['is_view_once'] as bool? ?? false,
              durationMs: rawAttachment['duration_ms'] as int?,
              localPath: rawAttachment['local_path'] as String?,
              thumbnailPath: rawAttachment['thumbnail_path'] as String?,
            )
          : null,
      replyToMessageId: map['reply_to_message_id'] as String?,
      senderLabel: map['sender_label'] as String?,
      isViewOnce: map['is_view_once'] as bool? ?? false,
      isConsumed: map['is_consumed'] as bool? ?? false,
      isDeletedForEveryone: map['is_deleted_for_everyone'] as bool? ?? false,
      errorLabel: map['error_label'] as String?,
      linkPreview: rawLinkPreview is Map
          ? LinkPreviewData.fromJson(Map<String, dynamic>.from(rawLinkPreview))
          : null,
      gameMatchId: map['game_match_id'] as String?,
      isExpiredGridBreachSession:
          map['is_expired_grid_breach_session'] as bool? ?? false,
    );
  }

  MessageKind _messageKindFromValue(String value) {
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

  MessageDeliveryState _deliveryStateFromValue(String value) {
    switch (value) {
      case 'sending':
        return MessageDeliveryState.sending;
      case 'delivered':
        return MessageDeliveryState.delivered;
      case 'read':
        return MessageDeliveryState.read;
      case 'consumed':
        return MessageDeliveryState.consumed;
      case 'failed':
        return MessageDeliveryState.failed;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value)?.toLocal();
  }
}
