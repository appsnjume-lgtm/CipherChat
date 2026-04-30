import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/local_chat_cache_service.dart';
import '../../../../core/services/realtime_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../application/services/chat_typing_service.dart';
import '../../data/models/search_models.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_member.dart';
import '../../application/models/pending_outgoing_message_record.dart';
import '../../domain/entities/message.dart';
import 'invite_provider.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final realtime = ref.watch(realtimeServiceProvider);
  final chatCache = ref.watch(localChatCacheServiceProvider);
  return ChatRepository(client, realtime, chatCache);
});

final chatTypingServiceProvider = Provider<ChatTypingService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ChatTypingService(client);
});

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final chatListProvider = FutureProvider.autoDispose<List<Chat>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final profile = ref.watch(currentUserProfileProvider);
  if (userId == null || profile == null) {
    return const [];
  }

  return ref.watch(chatRepositoryProvider).fetchChats(userId);
});

final chatListControllerProvider =
    StateNotifierProvider.autoDispose<ChatListController, ChatListState>((ref) {
      final controller = ChatListController(ref);
      controller.handleBaseListUpdate(ref.read(chatListProvider));
      ref.listen<AsyncValue<List<Chat>>>(chatListProvider, (previous, next) {
        controller.handleBaseListUpdate(next);
      });
      return controller;
    });

final discoverGroupsProvider = FutureProvider.autoDispose<List<Chat>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return const [];
  }

  return ref.watch(chatRepositoryProvider).fetchDiscoverableGroups(userId);
});

final chatDetailsProvider = FutureProvider.autoDispose.family<Chat, String>((
  ref,
  chatId,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('No authenticated user.');
  }

  try {
    final chat = await ref
        .watch(chatRepositoryProvider)
        .fetchChat(chatId: chatId, currentUserId: userId);
    return _hydrateChatFromLocalProfiles(
      ref,
      currentUserId: userId,
      chat: chat,
    );
  } catch (_) {
    final cached = await ref
        .watch(localChatCacheServiceProvider)
        .readChatSnapshot(userId: userId, chatId: chatId);
    if (cached != null) {
      return _hydrateChatFromLocalProfiles(
        ref,
        currentUserId: userId,
        chat: cached,
      );
    }
    rethrow;
  }
});

final userSearchResultsProvider = FutureProvider.autoDispose<List<AppUser>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return const [];
  }

  final query = ref.watch(searchQueryProvider);
  return ref
      .watch(chatRepositoryProvider)
      .searchUsers(currentUserId: userId, query: query);
});

final globalSearchResultsProvider = FutureProvider.autoDispose
    .family<GlobalSearchResults, String>((ref, query) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || query.trim().isEmpty) {
        return const GlobalSearchResults();
      }

      return ref.watch(chatRepositoryProvider).searchGlobal(query);
    });

final chatActionsProvider = Provider<ChatActionsController>((ref) {
  return ChatActionsController(ref);
});

const _unset = Object();
const _typingExpiry = Duration(seconds: 4);

class ChatListState {
  const ChatListState({
    required this.chats,
    required this.typingByChatId,
    required this.pendingOutgoingByChatId,
    required this.isLoading,
    required this.errorMessage,
  });

  factory ChatListState.initial() {
    return const ChatListState(
      chats: [],
      typingByChatId: {},
      pendingOutgoingByChatId: {},
      isLoading: true,
      errorMessage: null,
    );
  }

  final List<Chat> chats;
  final Map<String, ChatTypingPresence> typingByChatId;
  final Map<String, PendingOutgoingMessageRecord> pendingOutgoingByChatId;
  final bool isLoading;
  final String? errorMessage;

  ChatListState copyWith({
    List<Chat>? chats,
    Map<String, ChatTypingPresence>? typingByChatId,
    Map<String, PendingOutgoingMessageRecord>? pendingOutgoingByChatId,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return ChatListState(
      chats: chats ?? this.chats,
      typingByChatId: typingByChatId ?? this.typingByChatId,
      pendingOutgoingByChatId:
          pendingOutgoingByChatId ?? this.pendingOutgoingByChatId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  PendingOutgoingMessageRecord? latestPendingFor(String chatId) {
    return pendingOutgoingByChatId[chatId];
  }

  String? typingLabelFor({required Chat chat, required String currentUserId}) {
    final typing = typingByChatId[chat.id];
    if (typing == null || typing.userId == currentUserId) {
      return null;
    }

    if (chat.isGroup) {
      final username = typing.username?.trim();
      return '${username != null && username.isNotEmpty ? username : 'Someone'} is typing...';
    }

    return 'typing...';
  }
}

class ChatTypingPresence {
  const ChatTypingPresence({
    required this.chatId,
    required this.userId,
    required this.username,
    required this.lastEventAt,
  });

  final String chatId;
  final String userId;
  final String? username;
  final DateTime lastEventAt;
}

class ChatListController extends StateNotifier<ChatListState> {
  ChatListController(this._ref) : super(ChatListState.initial()) {
    unawaited(_hydrateCachedChats());
    unawaited(_refreshPendingOutgoingState());
  }

  final Ref _ref;
  RealtimeChannel? _inboxChannel;
  bool _isRefreshingInbox = false;
  final Map<String, Timer> _typingTimers = {};

  ChatRepository get _repository => _ref.read(chatRepositoryProvider);
  LocalChatCacheService get _chatCache =>
      _ref.read(localChatCacheServiceProvider);

  String? get _currentUserId => _ref.read(currentUserIdProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: state.chats.isEmpty, errorMessage: null);
    _ref.invalidate(chatListProvider);
    await _ref.read(chatListProvider.future);
  }

  void handleBaseListUpdate(AsyncValue<List<Chat>> next) {
    next.when(
      data: (chats) {
        unawaited(_applyRemoteChats(chats));
      },
      loading: () {
        if (state.chats.isEmpty) {
          state = state.copyWith(isLoading: true, errorMessage: null);
        }
      },
      error: (error, _) {
        unawaited(_applyRemoteError(error));
      },
    );
  }

  Future<void> _hydrateCachedChats() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }

    final cachedChats = await _chatCache.readChatSnapshots(currentUserId);
    if (!mounted || cachedChats.isEmpty || state.chats.isNotEmpty) {
      return;
    }

    final hydrated = await Future.wait(
      cachedChats.map(
        (chat) => _hydrateChatFromLocalProfiles(
          _ref,
          currentUserId: currentUserId,
          chat: chat,
        ),
      ),
    );
    if (!mounted) {
      return;
    }

    state = state.copyWith(
      chats: _sortChats(hydrated),
      isLoading: false,
      errorMessage: null,
    );
  }

  Future<void> _refreshPendingOutgoingState() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }

    final pending = await _chatCache.readPendingOutgoingMessages(
      userId: currentUserId,
    );
    if (!mounted) {
      return;
    }

    final latestByChat = <String, PendingOutgoingMessageRecord>{};
    for (final record in pending) {
      final existing = latestByChat[record.chatId];
      if (existing == null || record.createdAt.isAfter(existing.createdAt)) {
        latestByChat[record.chatId] = record;
      }
    }

    state = state.copyWith(pendingOutgoingByChatId: latestByChat);
  }

  Future<void> _applyRemoteChats(List<Chat> chats) async {
    final enrichedChats = await Future.wait(chats.map(_enrichRemoteChat));
    if (!mounted) {
      return;
    }

    final sortedChats = _sortChats(enrichedChats);
    state = state.copyWith(
      chats: sortedChats,
      isLoading: false,
      errorMessage: null,
    );
    _syncInboxSubscription();
    unawaited(_persistChatSnapshots(sortedChats));
    unawaited(_refreshPendingOutgoingState());
  }

  Future<void> _applyRemoteError(Object error) async {
    final currentUserId = _currentUserId;
    if (currentUserId != null) {
      final cachedChats = await _chatCache.readChatSnapshots(currentUserId);
      if (!mounted) {
        return;
      }
      if (cachedChats.isNotEmpty) {
        final hydrated = await Future.wait(
          cachedChats.map(
            (chat) => _hydrateChatFromLocalProfiles(
              _ref,
              currentUserId: currentUserId,
              chat: chat,
            ),
          ),
        );
        if (!mounted) {
          return;
        }
        state = state.copyWith(
          chats: _sortChats(hydrated),
          isLoading: false,
          errorMessage: null,
        );
        return;
      }
    }

    if (!mounted) {
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorMessage: AppErrorHelper.isNetworkRelated(error)
          ? null
          : AppErrorHelper.messageFor(error),
    );
  }

  Future<void> _persistChatSnapshots(List<Chat> chats) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }

    await _chatCache.writeChatSnapshots(userId: currentUserId, chats: chats);
  }

  Future<Chat> _enrichRemoteChat(Chat chat) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return chat;
    }

    final hydrated = await _hydrateChatFromLocalProfiles(
      _ref,
      currentUserId: currentUserId,
      chat: chat,
    );
    final previewText = await _cachedPreviewForMessage(
      chatId: hydrated.id,
      messageId: hydrated.latestMessage?.id,
    );
    return _copyChat(hydrated, previewText: previewText, setPreviewText: true);
  }

  Future<String?> _cachedPreviewForMessage({
    required String chatId,
    required String? messageId,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null ||
        messageId == null ||
        messageId.trim().isEmpty) {
      return null;
    }

    final headers = await _chatCache.readMessageHeaders(
      userId: currentUserId,
      chatId: chatId,
    );
    for (final header in headers.reversed) {
      if (header.id != messageId) {
        continue;
      }
      final preview = header.previewText.trim();
      return preview.isEmpty ? null : preview;
    }
    return null;
  }

  void _syncInboxSubscription() {
    final currentUserId = _currentUserId;
    if (currentUserId == null || _inboxChannel != null) {
      return;
    }

    _inboxChannel = _repository.subscribeToInboxChanges(
      userId: currentUserId,
      onChange: () => unawaited(_refreshInboxFromRealtime()),
    );
  }

  Future<void> _refreshInboxFromRealtime() async {
    if (_isRefreshingInbox || !mounted) {
      return;
    }

    _isRefreshingInbox = true;
    try {
      _ref.invalidate(chatListProvider);
      await _ref.read(chatListProvider.future);
    } catch (_) {
      if (mounted) {
        _ref.invalidate(chatListProvider);
      }
    } finally {
      _isRefreshingInbox = false;
      unawaited(_refreshPendingOutgoingState());
    }
  }

  void handleTypingSignal(ChatTypingSignal signal) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || signal.userId == currentUserId) {
      return;
    }

    if (!signal.isTyping) {
      clearTyping(chatId: signal.chatId);
      return;
    }

    _typingTimers[signal.chatId]?.cancel();
    _typingTimers[signal.chatId] = Timer(_typingExpiry, () {
      clearTyping(chatId: signal.chatId);
    });

    final nextTyping =
        Map<String, ChatTypingPresence>.from(state.typingByChatId)
          ..[signal.chatId] = ChatTypingPresence(
            chatId: signal.chatId,
            userId: signal.userId,
            username: signal.username,
            lastEventAt: signal.sentAt,
          );

    state = state.copyWith(typingByChatId: nextTyping);
  }

  void clearTyping({required String chatId}) {
    _typingTimers.remove(chatId)?.cancel();
    if (!state.typingByChatId.containsKey(chatId)) {
      return;
    }

    final nextTyping = Map<String, ChatTypingPresence>.from(
      state.typingByChatId,
    )..remove(chatId);
    state = state.copyWith(typingByChatId: nextTyping);
  }

  List<Chat> _sortChats(List<Chat> chats) {
    final sorted = [...chats];
    sorted.sort((left, right) {
      final rightTime = right.latestMessage?.createdAt ?? right.createdAt;
      final leftTime = left.latestMessage?.createdAt ?? left.createdAt;
      return rightTime.compareTo(leftTime);
    });
    return sorted;
  }

  @override
  void dispose() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    final inboxChannel = _inboxChannel;
    if (inboxChannel != null) {
      unawaited(_repository.disposeMessageChannel(inboxChannel));
    }
    super.dispose();
  }
}

class ChatActionsController {
  ChatActionsController(this._ref);

  final Ref _ref;

  ChatRepository get _repository => _ref.read(chatRepositoryProvider);

  String get _currentUserId {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    return userId;
  }

  Future<DirectConversationResult> openDirectChat(String otherUserId) async {
    final result = await _repository.startDirectConversation(
      currentUserId: _currentUserId,
      otherUserId: otherUserId,
    );
    final chat = result.chat;
    if (chat != null) {
      _refreshChatViews(chat.id);
    }
    _ref.invalidate(invitesDashboardProvider);
    return result;
  }

  Future<Chat> createGroup({String? title}) async {
    final chat = await _repository.createGroupChat(
      currentUserId: _currentUserId,
      title: title,
    );
    _refreshChatViews(chat.id);
    return chat;
  }

  Future<void> requestToJoin(String chatId) async {
    await _repository.createJoinRequest(chatId: chatId, userId: _currentUserId);
    _ref.invalidate(invitesDashboardProvider);
    _ref.invalidate(discoverGroupsProvider);
  }

  Future<void> inviteUser({
    required String chatId,
    required String targetUserId,
  }) async {
    await _repository.sendInvite(
      chatId: chatId,
      adminUserId: _currentUserId,
      targetUserId: targetUserId,
    );
    _ref.invalidate(invitesDashboardProvider);
    _ref.invalidate(chatDetailsProvider(chatId));
  }

  Future<void> deleteChat(String chatId) async {
    await _repository.deleteChat(chatId: chatId, currentUserId: _currentUserId);
    _ref.invalidate(chatListProvider);
    _ref.invalidate(chatListControllerProvider);
    _ref.invalidate(discoverGroupsProvider);
    _ref.invalidate(chatDetailsProvider(chatId));
    _ref.invalidate(invitesDashboardProvider);
  }

  void _refreshChatViews(String chatId) {
    _ref.invalidate(chatListProvider);
    _ref.invalidate(chatListControllerProvider);
    _ref.invalidate(discoverGroupsProvider);
    _ref.invalidate(chatDetailsProvider(chatId));
    _ref.invalidate(invitesDashboardProvider);
  }
}

Future<Chat> _hydrateChatFromLocalProfiles(
  Ref ref, {
  required String currentUserId,
  required Chat chat,
}) async {
  return chat;
}

Chat _copyChat(
  Chat chat, {
  String? title,
  String? groupImageUrl,
  List<ChatMember>? members,
  Message? latestMessage,
  String? previewText,
  int? unreadCount,
  bool? isCurrentUserMember,
  bool? isCurrentUserAdmin,
  bool setPreviewText = false,
}) {
  return Chat(
    id: chat.id,
    isGroup: chat.isGroup,
    createdBy: chat.createdBy,
    createdAt: chat.createdAt,
    title: title ?? chat.title,
    groupImageUrl: groupImageUrl ?? chat.groupImageUrl,
    members: members ?? chat.members,
    latestMessage: latestMessage ?? chat.latestMessage,
    latestMessagePreviewText: setPreviewText
        ? previewText
        : chat.latestMessagePreviewText,
    unreadCount: unreadCount ?? chat.unreadCount,
    isCurrentUserMember: isCurrentUserMember ?? chat.isCurrentUserMember,
    isCurrentUserAdmin: isCurrentUserAdmin ?? chat.isCurrentUserAdmin,
  );
}
