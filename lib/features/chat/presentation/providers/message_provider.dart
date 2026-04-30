import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/local_chat_cache_service.dart';
import '../../../../core/services/realtime_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../application/models/pending_outgoing_message_record.dart';
import '../../application/models/resolved_chat_message.dart';
import '../../application/services/local_message_visibility_service.dart';
import '../../application/services/pending_outgoing_message_sync_service.dart';
import '../../application/services/secure_chat_service.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/message_receipt.dart';
import '../../game/data/repositories/game_repository.dart';
import 'chat_provider.dart';

final messageProvider = StateNotifierProvider.autoDispose
    .family<MessageController, MessageState, String>((ref, chatId) {
      return MessageController(ref, chatId);
    });

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final realtime = ref.watch(realtimeServiceProvider);
  return GameRepository(client: client, realtime: realtime);
});

const _unset = Object();

class MessageState {
  const MessageState({
    required this.messages,
    required this.rawMessagesById,
    required this.hiddenMessageIds,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.isSending,
    required this.hasMore,
    required this.errorMessage,
  });

  factory MessageState.initial() {
    return const MessageState(
      messages: [],
      rawMessagesById: {},
      hiddenMessageIds: <String>{},
      isLoadingInitial: true,
      isLoadingMore: false,
      isSending: false,
      hasMore: true,
      errorMessage: null,
    );
  }

  final List<ResolvedChatMessage> messages;
  final Map<String, Message> rawMessagesById;
  final Set<String> hiddenMessageIds;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool isSending;
  final bool hasMore;
  final String? errorMessage;

  MessageState copyWith({
    List<ResolvedChatMessage>? messages,
    Map<String, Message>? rawMessagesById,
    Set<String>? hiddenMessageIds,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? isSending,
    bool? hasMore,
    Object? errorMessage = _unset,
  }) {
    return MessageState(
      messages: messages ?? this.messages,
      rawMessagesById: rawMessagesById ?? this.rawMessagesById,
      hiddenMessageIds: hiddenMessageIds ?? this.hiddenMessageIds,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class MessageController extends StateNotifier<MessageState> {
  MessageController(this._ref, this._chatId) : super(MessageState.initial()) {
    _connectivitySubscription = _ref
        .read(connectivityServiceProvider)
        .watchConnection()
        .listen((isOnline) {
          if (isOnline) {
            unawaited(_syncPendingMessages());
            unawaited(refresh(reconnectRealtime: true));
          }
        });
    _bootstrap();
  }

  final Ref _ref;
  final String _chatId;
  final Uuid _uuid = const Uuid();
  RealtimeChannel? _messageChannel;
  RealtimeChannel? _receiptChannel;
  RealtimeChannel? _gridBreachMatchChannel;
  StreamSubscription<bool>? _connectivitySubscription;
  final Map<String, Future<File>> _attachmentOpenFutures =
      <String, Future<File>>{};
  int _sendOperations = 0;
  bool _isDisposing = false;

  LocalChatCacheService get _chatCache =>
      _ref.read(localChatCacheServiceProvider);

  bool get _isActive => mounted && !_isDisposing;

  String get _currentUserId {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    return userId;
  }

  Future<void> _bootstrap() async {
    await _loadHiddenMessageIds();
    await _hydrateCachedHeaders();
    await _reconcilePendingOutgoingMessages();
    _subscribe();
    await _loadPage(initial: true);
    if (!mounted) {
      return;
    }
    unawaited(_syncPendingMessages());
  }

  Future<void> refresh({bool reconnectRealtime = false}) async {
    if (reconnectRealtime) {
      await _resubscribe();
    }

    await _loadPage(initial: true);
    if (!mounted) {
      return;
    }

    _ref.invalidate(chatDetailsProvider(_chatId));
    _ref.invalidate(chatListProvider);
  }

  Future<void> _loadHiddenMessageIds() async {
    try {
      final hiddenIds = await _ref
          .read(localMessageVisibilityServiceProvider)
          .readHiddenMessageIds(userId: _currentUserId, chatId: _chatId);
      if (!mounted) {
        return;
      }
      state = state.copyWith(hiddenMessageIds: hiddenIds);
    } catch (_) {
      // Local visibility state should not block chat loading.
    }
  }

  Future<void> _hydrateCachedHeaders() async {
    try {
      final cachedHeaders = await _chatCache.readMessageHeaders(
        userId: _currentUserId,
        chatId: _chatId,
      );
      if (!mounted || cachedHeaders.isEmpty) {
        return;
      }

      final cachedMessages = await _enrichGridBreachMessages(cachedHeaders);
      state = state.copyWith(
        messages: _visibleMessagesFrom(cachedMessages),
        isLoadingInitial: false,
        errorMessage: null,
      );
    } catch (_) {
      // Header hydration is best-effort and should never block the live fetch.
    }
  }

  Future<void> _loadPage({required bool initial}) async {
    if (initial) {
      state = state.copyWith(
        isLoadingInitial: state.messages.isEmpty,
        errorMessage: null,
      );
    } else {
      if (state.isLoadingMore ||
          !state.hasMore ||
          state.rawMessagesById.isEmpty) {
        return;
      }
      state = state.copyWith(isLoadingMore: true, errorMessage: null);
    }

    try {
      final repository = _ref.read(chatRepositoryProvider);
      final service = _ref.read(secureChatServiceProvider);
      final currentUserId = _currentUserId;
      final before = initial ? null : _oldestLoadedCreatedAt();
      final rawMessages = await repository.fetchMessages(
        chatId: _chatId,
        before: before,
        limit: AppConstants.messagePageSize,
      );
      final resolved = await Future.wait(
        rawMessages.map(
          (message) => service.resolveMessage(
            message: message,
            currentUserId: currentUserId,
          ),
        ),
      );

      final mergedRaw = <String, Message>{
        ...state.rawMessagesById,
        for (final message in rawMessages) message.id: message,
      };
      final mergedMessages = _visibleMessagesFrom(
        await _enrichGridBreachMessages([...state.messages, ...resolved]),
      );
      final incomingIds = rawMessages
          .where((message) => message.senderId != currentUserId)
          .map((message) => message.id)
          .toList(growable: false);
      final shouldMarkRead =
          _ref.read(currentUserProfileProvider)?.readReceiptsEnabled ?? true;

      if (!mounted) {
        return;
      }

      state = state.copyWith(
        messages: mergedMessages,
        rawMessagesById: mergedRaw,
        isLoadingInitial: false,
        isLoadingMore: false,
        hasMore: rawMessages.length == AppConstants.messagePageSize,
        errorMessage: null,
      );
      unawaited(_persistVisibleHeaders(mergedMessages));
      unawaited(
        _syncReceiptStateAfterLoad(
          repository: repository,
          currentUserId: currentUserId,
          incomingIds: incomingIds,
          shouldMarkRead: shouldMarkRead,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (state.messages.isNotEmpty || AppErrorHelper.isNetworkRelated(error)) {
        state = state.copyWith(
          isLoadingInitial: false,
          isLoadingMore: false,
          errorMessage: null,
        );
        return;
      }

      state = state.copyWith(
        isLoadingInitial: false,
        isLoadingMore: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> _syncReceiptStateAfterLoad({
    required dynamic repository,
    required String currentUserId,
    required List<String> incomingIds,
    required bool shouldMarkRead,
  }) async {
    if (incomingIds.isEmpty) {
      return;
    }

    try {
      if (shouldMarkRead) {
        await repository.markMessagesRead(
          chatId: _chatId,
          userId: currentUserId,
          messageIds: incomingIds,
        );
      } else {
        await repository.markMessagesDelivered(
          chatId: _chatId,
          userId: currentUserId,
          messageIds: incomingIds,
        );
      }
      if (!mounted) {
        return;
      }
      _ref.invalidate(chatListProvider);
      _ref.invalidate(chatDetailsProvider(_chatId));
    } catch (_) {
      // Receipt sync should never block the conversation from rendering.
    }
  }

  Future<void> _persistVisibleHeaders(
    List<ResolvedChatMessage> messages,
  ) async {
    final currentUserId = _currentUserId;
    final persistableMessages = messages
        .where((message) => !message.isPendingLocal)
        .toList(growable: false);
    await _chatCache.writeMessageHeaders(
      userId: currentUserId,
      chatId: _chatId,
      messages: persistableMessages,
    );

    final latestPreview = messages.isEmpty
        ? null
        : messages.last.previewText.trim();
    await _chatCache.updateChatPreviewText(
      userId: currentUserId,
      chatId: _chatId,
      previewText: latestPreview == null || latestPreview.isEmpty
          ? null
          : latestPreview,
    );
  }

  Future<List<ResolvedChatMessage>> _enrichGridBreachMessages(
    Iterable<ResolvedChatMessage> items,
  ) async {
    final messages = items.toList(growable: false);
    final matchIds = messages
        .where((message) => message.kind == MessageKind.grid_breach)
        .map((message) => message.gameMatchId?.trim() ?? '')
        .where((matchId) => matchId.isNotEmpty)
        .toSet();
    if (matchIds.isEmpty) {
      return messages;
    }

    final matchesById = await _ref
        .read(gameRepositoryProvider)
        .getMatchesByIds(matchIds);

    return messages
        .map((message) {
          if (message.kind != MessageKind.grid_breach) {
            return message;
          }
          final matchId = message.gameMatchId?.trim();
          final match = matchId == null || matchId.isEmpty
              ? null
              : matchesById[matchId];
          return message.copyWith(
            isExpiredGridBreachSession: match == null || match.isExpiredSession,
          );
        })
        .toList(growable: false);
  }

  Future<void> _refreshGridBreachInviteStates() async {
    if (!_isActive || state.messages.isEmpty) {
      return;
    }

    final currentMessages = state.messages;
    final nextMessages = _visibleMessagesFrom(
      await _enrichGridBreachMessages(currentMessages),
    );
    if (!_isActive) {
      return;
    }

    state = state.copyWith(messages: nextMessages, errorMessage: null);
    unawaited(_persistVisibleHeaders(nextMessages));
  }

  Future<void> loadMore() => _loadPage(initial: false);

  Future<void> ensureMessageLoaded(String messageId) async {
    if (state.rawMessagesById.containsKey(messageId) ||
        state.messages.any((message) => message.id == messageId)) {
      return;
    }

    final rawMessage = await _ref
        .read(chatRepositoryProvider)
        .fetchMessageById(messageId);
    if (rawMessage.chatId != _chatId) {
      return;
    }

    final resolved = await _ref
        .read(secureChatServiceProvider)
        .resolveMessage(message: rawMessage, currentUserId: _currentUserId);

    if (!mounted) {
      return;
    }

    final nextMessages = _visibleMessagesFrom(
      await _enrichGridBreachMessages([...state.messages, resolved]),
    );
    state = state.copyWith(
      messages: nextMessages,
      rawMessagesById: {...state.rawMessagesById, rawMessage.id: rawMessage},
      errorMessage: null,
    );
    unawaited(_persistVisibleHeaders(nextMessages));
  }

  Future<void> sendText(String text, {String? replyToMessageId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final createdAt = DateTime.now();
    final messageId = _uuid.v4();
    final preview = ResolvedChatMessage(
      id: messageId,
      chatId: _chatId,
      senderId: _currentUserId,
      kind: MessageKind.text,
      createdAt: createdAt,
      isMine: true,
      deliveryState: MessageDeliveryState.sending,
      text: trimmed,
      replyToMessageId: replyToMessageId,
      isPendingLocal: true,
    );
    _insertOrReplaceLocalMessage(preview);

    await _enqueuePendingRecord(
      PendingOutgoingMessageRecord(
        messageId: messageId,
        chatId: _chatId,
        kind: MessageKind.text,
        createdAt: createdAt,
        text: trimmed,
        replyToMessageId: replyToMessageId,
      ),
    );
  }

  Future<void> sendSticker(String stickerId, {String? replyToMessageId}) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final createdAt = DateTime.now();
    final messageId = _uuid.v4();
    final preview = ResolvedChatMessage(
      id: messageId,
      chatId: _chatId,
      senderId: _currentUserId,
      kind: MessageKind.sticker,
      createdAt: createdAt,
      isMine: true,
      deliveryState: MessageDeliveryState.sending,
      stickerId: trimmed,
      replyToMessageId: replyToMessageId,
      isPendingLocal: true,
    );
    _insertOrReplaceLocalMessage(preview);

    await _enqueuePendingRecord(
      PendingOutgoingMessageRecord(
        messageId: messageId,
        chatId: _chatId,
        kind: MessageKind.sticker,
        createdAt: createdAt,
        stickerId: trimmed,
        replyToMessageId: replyToMessageId,
      ),
    );
  }

  Future<void> sendImage(String path, {String? replyToMessageId}) {
    return _sendAttachment(
      path: path,
      kind: MessageKind.image,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendVideo(
    String path, {
    required bool viewOnce,
    int? durationMs,
    String? replyToMessageId,
  }) {
    return _sendAttachment(
      path: path,
      kind: MessageKind.video,
      viewOnce: viewOnce,
      compressVideo: true,
      durationMs: durationMs,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendFile(String path, {String? replyToMessageId}) {
    return _sendAttachment(
      path: path,
      kind: MessageKind.file,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> sendAudio(
    String path, {
    int? durationMs,
    String? fileNameOverride,
    String? replyToMessageId,
  }) {
    return _sendAttachment(
      path: path,
      kind: MessageKind.audio,
      durationMs: durationMs,
      fileNameOverride: fileNameOverride,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<File> openAttachment(String messageId) {
    final existing = _attachmentOpenFutures[messageId];
    if (existing != null) {
      return existing;
    }

    final raw = state.rawMessagesById[messageId];
    final resolved = state.messages.firstWhere((item) => item.id == messageId);
    if (raw == null) {
      final localPath = resolved.attachment?.localPath;
      if (localPath != null && localPath.trim().isNotEmpty) {
        final localFile = File(localPath);
        final future = Future<File>(() async {
          if (await localFile.exists()) {
            return localFile;
          }
          throw StateError('Reconnect to open this saved attachment preview.');
        });
        _attachmentOpenFutures[messageId] = future;
        return future;
      }
      return Future<File>.error(
        StateError('Reconnect to open this saved attachment preview.'),
      );
    }

    final future = _ref
        .read(secureChatServiceProvider)
        .materializeAttachment(
          sourceMessage: raw,
          resolvedMessage: resolved,
          currentUserId: _currentUserId,
        );
    _attachmentOpenFutures[messageId] = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (_attachmentOpenFutures[messageId] == future) {
            _attachmentOpenFutures.remove(messageId);
          }
        },
      ),
    );
    return future;
  }

  Future<void> consumeViewOnce(String messageId) async {
    final raw = state.rawMessagesById[messageId];
    final resolved = state.messages.firstWhere((item) => item.id == messageId);
    if (raw == null) {
      return;
    }

    await _ref
        .read(secureChatServiceProvider)
        .consumeViewOnceMessage(
          sourceMessage: raw,
          resolvedMessage: resolved,
          currentUserId: _currentUserId,
        );
    _attachmentOpenFutures.remove(messageId);
  }

  Future<void> hideMessageForMe(String messageId) async {
    final nextHiddenIds = {...state.hiddenMessageIds, messageId};
    await _ref
        .read(localMessageVisibilityServiceProvider)
        .hideMessage(
          userId: _currentUserId,
          chatId: _chatId,
          messageId: messageId,
        );

    if (!mounted) {
      return;
    }

    final nextMessages = _visibleMessagesFrom(
      state.messages,
      hiddenMessageIds: nextHiddenIds,
    );
    state = state.copyWith(
      hiddenMessageIds: nextHiddenIds,
      messages: nextMessages,
      errorMessage: null,
    );
    unawaited(_persistVisibleHeaders(nextMessages));
  }

  Future<void> deleteMessageForEveryone(String messageId) async {
    final rawMessage = state.rawMessagesById[messageId];
    if (rawMessage == null) {
      throw StateError('Message not found.');
    }

    try {
      final updatedRaw = _preserveExistingReceipts(
        await _ref
            .read(secureChatServiceProvider)
            .deleteMessageForEveryone(
              sourceMessage: rawMessage,
              currentUserId: _currentUserId,
            ),
      );
      final updatedResolved = await _ref
          .read(secureChatServiceProvider)
          .resolveMessage(message: updatedRaw, currentUserId: _currentUserId);

      if (!mounted) {
        return;
      }

      if (updatedResolved.isDeletedForEveryone) {
        _attachmentOpenFutures.remove(messageId);
      }

      final nextMessages = _visibleMessagesFrom([
        ...state.messages.where((message) => message.id != messageId),
        updatedResolved,
      ]);
      state = state.copyWith(
        rawMessagesById: {...state.rawMessagesById, messageId: updatedRaw},
        messages: nextMessages,
        errorMessage: null,
      );
      unawaited(_persistVisibleHeaders(nextMessages));
      _ref.invalidate(chatListProvider);
      _ref.invalidate(chatDetailsProvider(_chatId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(errorMessage: AppErrorHelper.messageFor(error));
      rethrow;
    }
  }

  Future<void> _sendAttachment({
    required String path,
    required MessageKind kind,
    bool viewOnce = false,
    bool compressVideo = false,
    int? durationMs,
    String? fileNameOverride,
    String? replyToMessageId,
  }) async {
    final createdAt = DateTime.now();
    final messageId = _uuid.v4();
    final preview = _buildPendingAttachmentMessage(
      messageId: messageId,
      path: path,
      kind: kind,
      createdAt: createdAt,
      viewOnce: viewOnce,
      durationMs: durationMs,
      fileNameOverride: fileNameOverride,
      replyToMessageId: replyToMessageId,
    );
    _insertOrReplaceLocalMessage(preview);

    await _enqueuePendingRecord(
      PendingOutgoingMessageRecord(
        messageId: messageId,
        chatId: _chatId,
        kind: kind,
        createdAt: createdAt,
        localPath: path,
        replyToMessageId: replyToMessageId,
        viewOnce: viewOnce,
        compressVideo: compressVideo,
        durationMs: durationMs,
        fileNameOverride: fileNameOverride,
      ),
    );
  }

  ResolvedChatMessage _buildPendingAttachmentMessage({
    required String messageId,
    required String path,
    required MessageKind kind,
    required DateTime createdAt,
    required bool viewOnce,
    required int? durationMs,
    required String? fileNameOverride,
    required String? replyToMessageId,
  }) {
    final file = File(path);
    final fileName = fileNameOverride ?? p.basename(path);
    final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
    return ResolvedChatMessage(
      id: messageId,
      chatId: _chatId,
      senderId: _currentUserId,
      kind: kind,
      createdAt: createdAt,
      isMine: true,
      deliveryState: MessageDeliveryState.sending,
      replyToMessageId: replyToMessageId,
      isViewOnce: viewOnce,
      isPendingLocal: true,
      attachment: ResolvedAttachment(
        fileName: fileName.isEmpty ? 'attachment' : fileName,
        mimeType: _fallbackMimeType(kind),
        sizeBytes: sizeBytes,
        storagePath: '',
        blobNonceBase64: '',
        blobMacBase64: '',
        isViewOnce: viewOnce,
        durationMs: durationMs,
        localPath: path,
      ),
    );
  }

  Future<void> _enqueuePendingRecord(
    PendingOutgoingMessageRecord record,
  ) async {
    await _runSendOperation(() async {
      final result = await _ref
          .read(pendingOutgoingMessageSyncServiceProvider)
          .enqueueAndAttemptSend(userId: _currentUserId, record: record);
      if (!mounted) {
        return;
      }

      await _applyPendingSyncResult(result);
      await _reconcilePendingOutgoingMessages();
    });
  }

  Future<void> _syncPendingMessages() async {
    final result = await _ref
        .read(pendingOutgoingMessageSyncServiceProvider)
        .syncAllPendingMessages();
    if (!mounted) {
      return;
    }

    await _applyPendingSyncResult(result);
    await _reconcilePendingOutgoingMessages();
  }

  Future<void> _applyPendingSyncResult(PendingMessageSyncResult result) async {
    if (result.sentMessageIds.isEmpty && result.droppedMessageIds.isEmpty) {
      return;
    }

    for (final messageId in result.sentMessageIds) {
      _markLocalMessageAsSent(messageId);
    }
    for (final messageId in result.droppedMessageIds) {
      _removeLocalMessage(messageId);
    }

    if (result.droppedMessageIds.isNotEmpty && mounted) {
      state = state.copyWith(
        errorMessage: 'One or more pending messages could not be sent.',
      );
    }
  }

  Future<void> _reconcilePendingOutgoingMessages() async {
    try {
      final pending = await _ref
          .read(pendingOutgoingMessageSyncServiceProvider)
          .readPendingMessages(userId: _currentUserId, chatId: _chatId);
      if (!mounted) {
        return;
      }

      final pendingMessages = pending
          .map(_resolvedPendingMessageFromRecord)
          .toList(growable: false);
      final nextMessages = _visibleMessagesFrom([
        ...state.messages.where((message) => !message.isPendingLocal),
        ...pendingMessages,
      ]);
      state = state.copyWith(messages: nextMessages, errorMessage: null);
      unawaited(_persistVisibleHeaders(nextMessages));
    } catch (_) {
      // Pending outbox restore is best-effort and should not break chat loading.
    }
  }

  ResolvedChatMessage _resolvedPendingMessageFromRecord(
    PendingOutgoingMessageRecord record,
  ) {
    if (record.kind == MessageKind.text) {
      return ResolvedChatMessage(
        id: record.messageId,
        chatId: record.chatId,
        senderId: _currentUserId,
        kind: MessageKind.text,
        createdAt: record.createdAt,
        isMine: true,
        deliveryState: MessageDeliveryState.sending,
        text: record.text,
        replyToMessageId: record.replyToMessageId,
        isPendingLocal: true,
      );
    }

    if (record.kind == MessageKind.sticker) {
      return ResolvedChatMessage(
        id: record.messageId,
        chatId: record.chatId,
        senderId: _currentUserId,
        kind: MessageKind.sticker,
        createdAt: record.createdAt,
        isMine: true,
        deliveryState: MessageDeliveryState.sending,
        stickerId: record.stickerId,
        replyToMessageId: record.replyToMessageId,
        isPendingLocal: true,
      );
    }

    final path = record.localPath ?? '';
    final file = File(path);
    final fileName =
        record.fileNameOverride ??
        (path.trim().isEmpty ? 'attachment' : p.basename(path));
    final sizeBytes = file.existsSync() ? file.lengthSync() : 0;

    return ResolvedChatMessage(
      id: record.messageId,
      chatId: record.chatId,
      senderId: _currentUserId,
      kind: record.kind,
      createdAt: record.createdAt,
      isMine: true,
      deliveryState: MessageDeliveryState.sending,
      replyToMessageId: record.replyToMessageId,
      isViewOnce: record.viewOnce,
      isPendingLocal: true,
      attachment: ResolvedAttachment(
        fileName: fileName.isEmpty ? 'attachment' : fileName,
        mimeType: _fallbackMimeType(record.kind),
        sizeBytes: sizeBytes,
        storagePath: '',
        blobNonceBase64: '',
        blobMacBase64: '',
        isViewOnce: record.viewOnce,
        durationMs: record.durationMs,
        localPath: path.trim().isEmpty ? null : path,
      ),
    );
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
      case MessageKind.text:
        return 'text/plain';
      case MessageKind.grid_breach:
        return 'application/octet-stream';
    }
  }

  void _insertOrReplaceLocalMessage(ResolvedChatMessage message) {
    final nextMessages = _visibleMessagesFrom([
      ...state.messages.where((item) => item.id != message.id),
      message,
    ]);
    state = state.copyWith(messages: nextMessages, errorMessage: null);
    unawaited(_persistVisibleHeaders(nextMessages));
  }

  void _markLocalMessageAsSent(String messageId) {
    final nextMessages = state.messages
        .map(
          (message) => message.id != messageId
              ? message
              : message.copyWith(
                  deliveryState: MessageDeliveryState.sent,
                  isPendingLocal: false,
                ),
        )
        .toList(growable: false);
    state = state.copyWith(
      messages: _visibleMessagesFrom(nextMessages),
      errorMessage: null,
    );
    unawaited(_persistVisibleHeaders(state.messages));
  }

  void _removeLocalMessage(String messageId) {
    _attachmentOpenFutures.remove(messageId);
    final nextMessages = state.messages
        .where((message) => message.id != messageId)
        .toList(growable: false);
    state = state.copyWith(messages: _visibleMessagesFrom(nextMessages));
    unawaited(_persistVisibleHeaders(state.messages));
  }

  Future<void> _resubscribe() async {
    await _disposeSubscriptions();
    if (!mounted) {
      return;
    }
    _subscribe();
  }

  Future<void> _disposeSubscriptions() async {
    final repository = _ref.read(chatRepositoryProvider);
    final realtime = _ref.read(realtimeServiceProvider);

    final messageChannel = _messageChannel;
    _messageChannel = null;
    if (messageChannel != null) {
      await repository.disposeMessageChannel(messageChannel);
    }

    final receiptChannel = _receiptChannel;
    _receiptChannel = null;
    if (receiptChannel != null) {
      await repository.disposeMessageChannel(receiptChannel);
    }

    final gridBreachMatchChannel = _gridBreachMatchChannel;
    _gridBreachMatchChannel = null;
    if (gridBreachMatchChannel != null) {
      await realtime.disposeChannel(gridBreachMatchChannel);
    }
  }

  void _subscribe() {
    if (_messageChannel != null ||
        _receiptChannel != null ||
        _gridBreachMatchChannel != null) {
      return;
    }

    final repository = _ref.read(chatRepositoryProvider);
    final service = _ref.read(secureChatServiceProvider);
    _messageChannel = repository.subscribeToMessages(
      chatId: _chatId,
      onInsert: (message) async {
        final resolved = await service.resolveMessage(
          message: message,
          currentUserId: _currentUserId,
        );
        if (!_isActive) {
          return;
        }

        final existingMessages = state.messages;
        final existingRawMessages = state.rawMessagesById;
        final nextMessages = _visibleMessagesFrom(
          await _enrichGridBreachMessages([...existingMessages, resolved]),
        );
        if (!_isActive) {
          return;
        }

        state = state.copyWith(
          messages: nextMessages,
          rawMessagesById: {...existingRawMessages, message.id: message},
        );
        unawaited(_persistVisibleHeaders(nextMessages));

        if (message.senderId != _currentUserId) {
          final currentProfile = _ref.read(currentUserProfileProvider);
          await repository.markMessagesDelivered(
            chatId: _chatId,
            userId: _currentUserId,
            messageIds: [message.id],
          );
          if (!_isActive) {
            return;
          }
          if (currentProfile?.readReceiptsEnabled ?? true) {
            await repository.markMessagesRead(
              chatId: _chatId,
              userId: _currentUserId,
              messageIds: [message.id],
            );
            if (!_isActive) {
              return;
            }
          }
        }

        _ref.invalidate(chatListProvider);
        _ref.invalidate(chatDetailsProvider(_chatId));
      },
      onUpdate: (message) async {
        await _applyMessageUpsert(message);
      },
    );

    _receiptChannel = repository.subscribeToReceipts(
      chatId: _chatId,
      onUpsert: (receipt) async {
        await _applyReceiptUpdate(receipt);
      },
    );

    final client = _ref.read(supabaseServiceProvider).client;
    _gridBreachMatchChannel = client.channel('chat-grid-breach-$_chatId');
    _gridBreachMatchChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'grid_breach_matches',
          callback: (payload) {
            if (!_isActive) {
              return;
            }

            final changedId =
                (payload.newRecord['id'] ?? payload.oldRecord['id'])
                    ?.toString();
            if (changedId == null) {
              return;
            }
            final isTracked = state.messages.any(
              (message) =>
                  message.kind == MessageKind.grid_breach &&
                  message.gameMatchId == changedId,
            );
            if (!isTracked) {
              return;
            }
            unawaited(_refreshGridBreachInviteStates());
          },
        )
        .subscribe();
  }

  Future<void> _applyMessageUpsert(Message incomingMessage) async {
    if (!_isActive) {
      return;
    }

    final updatedRaw = _preserveExistingReceipts(incomingMessage);
    final updatedResolved = await _ref
        .read(secureChatServiceProvider)
        .resolveMessage(message: updatedRaw, currentUserId: _currentUserId);

    if (!_isActive) {
      return;
    }

    if (updatedResolved.isConsumed || updatedResolved.isDeletedForEveryone) {
      _attachmentOpenFutures.remove(updatedResolved.id);
    }

    final existingMessages = state.messages;
    final existingRawMessages = state.rawMessagesById;
    final nextMessages = _visibleMessagesFrom(
      await _enrichGridBreachMessages([
        ...existingMessages.where(
          (message) => message.id != updatedResolved.id,
        ),
        updatedResolved,
      ]),
    );
    if (!_isActive) {
      return;
    }

    state = state.copyWith(
      rawMessagesById: {...existingRawMessages, updatedRaw.id: updatedRaw},
      messages: nextMessages,
      errorMessage: null,
    );
    unawaited(_persistVisibleHeaders(nextMessages));
    _ref.invalidate(chatListProvider);
    _ref.invalidate(chatDetailsProvider(_chatId));
  }

  Future<void> _applyReceiptUpdate(MessageReceipt receipt) async {
    if (!_isActive) {
      return;
    }

    final existingRawMessages = state.rawMessagesById;
    final raw = existingRawMessages[receipt.messageId];
    if (raw == null) {
      return;
    }

    final nextReceipts = [...raw.receipts];
    final index = nextReceipts.indexWhere(
      (item) => item.userId == receipt.userId,
    );
    if (index == -1) {
      nextReceipts.add(receipt);
    } else {
      nextReceipts[index] = receipt;
    }

    final updatedRaw = raw.copyWith(receipts: nextReceipts);
    final updatedResolved = await _ref
        .read(secureChatServiceProvider)
        .resolveMessage(message: updatedRaw, currentUserId: _currentUserId);

    if (!_isActive) {
      return;
    }

    final existingMessages = state.messages;
    final nextMessages = _visibleMessagesFrom(
      await _enrichGridBreachMessages([
        ...existingMessages.where(
          (message) => message.id != updatedResolved.id,
        ),
        updatedResolved,
      ]),
    );
    if (!_isActive) {
      return;
    }

    state = state.copyWith(
      rawMessagesById: {...existingRawMessages, receipt.messageId: updatedRaw},
      messages: nextMessages,
    );
    unawaited(_persistVisibleHeaders(nextMessages));
  }

  Future<void> _runSendOperation(Future<void> Function() action) async {
    _sendOperations += 1;
    if (mounted) {
      state = state.copyWith(isSending: true, errorMessage: null);
    }

    try {
      await action();
    } finally {
      _sendOperations = (_sendOperations - 1).clamp(0, 1 << 30);
      if (mounted) {
        state = state.copyWith(isSending: _sendOperations > 0);
      }
    }
  }

  Message _preserveExistingReceipts(Message incomingMessage) {
    final existing = state.rawMessagesById[incomingMessage.id];
    if (existing == null || incomingMessage.receipts.isNotEmpty) {
      return incomingMessage;
    }

    return incomingMessage.copyWith(
      receipts: existing.receipts,
      deletedForEveryoneAt: incomingMessage.deletedForEveryoneAt,
      deletedForEveryoneBy: incomingMessage.deletedForEveryoneBy,
      keepDeletedFields: false,
    );
  }

  DateTime? _oldestLoadedCreatedAt() {
    DateTime? oldest;
    for (final message in state.rawMessagesById.values) {
      if (oldest == null || message.createdAt.isBefore(oldest)) {
        oldest = message.createdAt;
      }
    }
    return oldest;
  }

  List<ResolvedChatMessage> _visibleMessagesFrom(
    Iterable<ResolvedChatMessage> items, {
    Set<String>? hiddenMessageIds,
  }) {
    final hiddenIds = hiddenMessageIds ?? state.hiddenMessageIds;
    return _mergeResolvedMessages(
      items.where((message) => !hiddenIds.contains(message.id)).toList(),
    );
  }

  List<ResolvedChatMessage> _mergeResolvedMessages(
    List<ResolvedChatMessage> items,
  ) {
    final byId = <String, ResolvedChatMessage>{};
    for (final item in items) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return merged;
  }

  @override
  void dispose() {
    _isDisposing = true;
    _connectivitySubscription?.cancel();
    unawaited(_disposeSubscriptions());
    super.dispose();
  }
}
