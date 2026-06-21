import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/no_internet_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../call/data/models/call_models.dart';
import '../../../call/data/repositories/call_repository.dart';
import '../../application/models/resolved_chat_message.dart';
import '../../application/services/chat_typing_service.dart';
import '../../application/services/secure_chat_service.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/sticker.dart';
import '../../data/models/search_models.dart';
import '../providers/chat_background_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/message_provider.dart';
import '../providers/sticker_provider.dart';
import '../widgets/audio_message_player.dart';
import '../widgets/chat_background_layer.dart';
import '../widgets/sticker_network_display.dart';
import '../widgets/video_message_preview.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sticker_panel.dart';
import '../widgets/typing_indicator.dart';

import '../screens/chat_background_editor_screen.dart';
import '../screens/create_sticker_screen.dart';
import '../screens/widgets/attachment_card.dart';
import '../screens/widgets/chat_header.dart';
import '../screens/widgets/chat_composer.dart';
import '../screens/widgets/video_screen_viewer.dart';
import '../screens/widgets/video_sticker_editor.dart';
import '../screens/widgets/encryption_badge_action.dart';
import '../screens/widgets/image_viewer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialMessageId,
    this.initialSearchQuery,
  });

  final String chatId;
  final String? initialMessageId;
  final String? initialSearchQuery;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _composerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};
  String? _selectedMessageId;
  String? _replyingToMessageId;
  String? _lastObservedLastMessageId;
  String? _lastObservedOwnMessageId;
  String? _lastObservedIncomingMessageId;
  String? _encryptingMessageId;
  String? _decryptingMessageId;
  bool _showScrollToBottom = false;
  bool _didInitialScrollToBottom = false;
  bool _didSeedCryptoTooltips = false;
  bool _didHandleInitialSearchRoute = false;
  bool _isSearchMode = false;
  bool _isRunningSearch = false;
  String _searchDraftQuery = '';
  String _executedSearchQuery = '';
  List<ChatMessageSearchMatch> _searchMatches = const [];
  int _activeSearchMatchIndex = 0;
  double? _scrollOffsetBeforeSearch;
  Timer? _encryptingTimer;
  Timer? _decryptingTimer;
  Timer? _typingPauseTimer;
  late final ChatTypingService _chatTypingService;
  late final void Function(ChatTypingSignal signal) _handleTypingSignal;
  RealtimeChannel? _typingChannel;
  String? _cachedCurrentUserId;
  String? _cachedTypingUsername;
  bool _cachedTypingIndicatorEnabled = true;
  bool _isTypingActive = false;
  bool _hasComposerText = false;
  bool _isStickerPanelOpen = false;
  bool _isRecordingVoiceNote = false;
  Duration _voiceNoteDuration = Duration.zero;
  Timer? _voiceNoteTimer;
  Set<String> _pendingStickerHydrationIds = <String>{};
  List<ResolvedChatMessage> _retainedVisibleMessages = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _composerFocusNode.addListener(_handleComposerFocusChanged);
    _chatTypingService = ref.read(chatTypingServiceProvider);
    _handleTypingSignal = ref
        .read(chatListControllerProvider.notifier)
        .handleTypingSignal;
    _typingChannel = _chatTypingService.joinChannel(
      chatId: widget.chatId,
      onSignal: _handleTypingSignal,
      includeSelf: false,
    );

    if ((widget.initialMessageId?.trim().isNotEmpty ?? false) ||
        (widget.initialSearchQuery?.trim().isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_applyInitialSearchRoute());
      });
    }
  }

  @override
  void dispose() {
    _typingPauseTimer?.cancel();
    _voiceNoteTimer?.cancel();
    if (_isRecordingVoiceNote) {
      unawaited(_audioRecorder.cancel());
    }
    unawaited(_audioRecorder.dispose());
    unawaited(_stopTypingBroadcast(force: true));
    final typingChannel = _typingChannel;
    if (typingChannel != null) {
      unawaited(
        _chatTypingService.disposeChannel(
          typingChannel,
          onSignal: _handleTypingSignal,
        ),
      );
    }
    ref
        .read(chatListControllerProvider.notifier)
        .clearTyping(chatId: widget.chatId);
    _textController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _composerFocusNode
      ..removeListener(_handleComposerFocusChanged)
      ..dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _encryptingTimer?.cancel();
    _decryptingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshChatView(reconnectRealtime: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final currentProfile = ref.watch(currentUserProfileProvider);
    _cachedCurrentUserId = currentUserId;
    _cachedTypingUsername = currentProfile?.username;
    _cachedTypingIndicatorEnabled =
        currentProfile?.typingIndicatorEnabled ?? true;
    final chatAsync = ref.watch(chatDetailsProvider(widget.chatId));
    final messageState = ref.watch(messageProvider(widget.chatId));
    final stickerState = ref.watch(stickerLibraryProvider);
    final outgoingBubbleColorValue = ref.watch(
      chatBackgroundProvider(
        widget.chatId,
      ).select((state) => state.resolvedConfig.bubbleColor),
    );
    final outgoingBubbleColor = outgoingBubbleColorValue == null
        ? null
        : Color(outgoingBubbleColorValue);

    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('No user found.')));
    }

    final typingPresence = ref.watch(
      chatListControllerProvider.select((s) => s.typingByChatId[widget.chatId]),
    );
    final isSomeoneTyping =
        typingPresence != null && typingPresence.userId != currentUserId;

    ref.listen(
      chatListControllerProvider.select((s) => s.typingByChatId[widget.chatId]),
      (previous, next) {
        final wasTyping = previous != null && previous.userId != currentUserId;
        final isNowTyping = next != null && next.userId != currentUserId;
        if (!wasTyping && isNowTyping && _isNearBottom()) {
          _scheduleScrollToBottom(animated: true);
        }
      },
    );

    if (messageState.messages.isNotEmpty) {
      _retainedVisibleMessages = messageState.messages;
    }
    final visibleMessages = messageState.messages.isNotEmpty
        ? messageState.messages
        : _retainedVisibleMessages;
    final selectedMessage = _selectedMessageFrom(visibleMessages);
    final replyingMessage = _replyingMessageFrom(visibleMessages);
    final isSelectionMode = selectedMessage != null;
    if (_selectedMessageId != null && selectedMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedMessageId = null);
        }
      });
    }
    if (_replyingToMessageId != null && replyingMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _replyingToMessageId = null);
        }
      });
    }

    final activeChat = chatAsync.asData?.value;
    final messageById = {
      for (final message in visibleMessages) message.id: message,
    };
    final senderLabels = _senderLabelsFor(activeChat, currentUserId);
    final showSenderNames = activeChat?.isGroup ?? false;
    final items = _buildListItems(visibleMessages);
    final latestOwnMessage = _latestMessageFor(
      visibleMessages,
      predicate: (message) => message.isMine,
    );
    final latestIncomingMessage = _latestMessageFor(
      visibleMessages,
      predicate: (message) => !message.isMine,
    );
    final activeSearchMessageId = _searchMatches.isEmpty
        ? null
        : _searchMatches[_activeSearchMatchIndex].messageId;
    final matchedMessageIds = _searchMatches
        .map((match) => match.messageId)
        .toSet();

    String? latestGridBreachInviteId;
    for (final visibleMessage in visibleMessages) {
      if (visibleMessage.kind == MessageKind.grid_breach &&
          !visibleMessage.isDeletedForEveryone &&
          (visibleMessage.gameMatchId?.isNotEmpty ?? false)) {
        latestGridBreachInviteId = visibleMessage.id;
      }
    }

    _handleAutoScrollSignals(visibleMessages);
    _hydrateVisibleStickerMetadata(
      messages: visibleMessages,
      stickerState: stickerState,
    );
    _handleCryptoTooltipSignals(
      latestOwnMessage: latestOwnMessage,
      latestIncomingMessage: latestIncomingMessage,
    );

    final isGX = GXThemeExtension.of(context).isGX;

    return Scaffold(
      appBar: _isSearchMode
          ? _buildSearchAppBar(context)
          : AppBar(
              automaticallyImplyLeading: !isSelectionMode,
              leading: isSelectionMode
                  ? IconButton(
                      tooltip: 'Cancel selection',
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              titleSpacing: isSelectionMode ? 0 : 8,
              title: isSelectionMode
                  ? Text(
                      isGX ? '1 SELECTED' : '1 selected',
                      style: isGX
                          ? const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            )
                          : null,
                    )
                  : chatAsync.when(
                      data: (chat) => ChatHeader(
                        chat: chat,
                        currentUserId: currentUserId,
                        onAvatarTap: () =>
                            _openContactProfile(chat, currentUserId),
                      ),
                      loading: () => const HeaderText(title: 'Chat'),
                      error: (error, stackTrace) =>
                          const HeaderText(title: 'Chat'),
                    ),
              actions: isSelectionMode
                  ? [
                      if (selectedMessage.kind == MessageKind.sticker &&
                          selectedMessage.stickerId != null)
                        IconButton(
                          tooltip:
                              stickerState.isInLibrary(
                                selectedMessage.stickerId!,
                              )
                              ? 'Already in Stickers'
                              : 'Add to Stickers',
                          onPressed: () =>
                              _addSelectedStickerToLibrary(selectedMessage),
                          icon: Icon(
                            stickerState.isInLibrary(selectedMessage.stickerId!)
                                ? Icons.download_done_rounded
                                : Icons.download_rounded,
                          ),
                        ),
                      if (selectedMessage.kind == MessageKind.sticker &&
                          selectedMessage.stickerId != null)
                        IconButton(
                          tooltip:
                              stickerState.isFavorite(
                                selectedMessage.stickerId!,
                              )
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          onPressed: () =>
                              _toggleSelectedStickerFavorite(selectedMessage),
                          icon: Icon(
                            stickerState.isFavorite(selectedMessage.stickerId!)
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Copy',
                        onPressed: selectedMessage.canBeCopied
                            ? () => _copySelectedMessage(selectedMessage)
                            : null,
                        icon: const Icon(Icons.content_copy_rounded),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () =>
                            _deleteSelectedMessage(selectedMessage),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ]
                  : [
                      const EncryptionBadgeAction(),
                      if (messageState.hasMore)
                        IconButton(
                          tooltip: 'Load older messages',
                          onPressed: () => ref
                              .read(messageProvider(widget.chatId).notifier)
                              .loadMore(),
                          icon: const Icon(Icons.history_rounded),
                        ),
                      chatAsync.when(
                        data: (chat) => PopupMenuButton<_ChatMenuAction>(
                          tooltip: 'More actions',
                          onSelected: (action) {
                            switch (action) {
                              case _ChatMenuAction.search:
                                _enterSearchMode();
                                break;
                              case _ChatMenuAction.refresh:
                                unawaited(_refreshChatView());
                                break;
                              case _ChatMenuAction.background:
                                unawaited(_openChatBackgroundEditor());
                                break;
                              case _ChatMenuAction.audio:
                                _startCall(chat: chat, withVideo: false);
                                break;
                              case _ChatMenuAction.video:
                                _startCall(chat: chat, withVideo: true);
                                break;
                              case _ChatMenuAction.groupInfo:
                                context.push('/group/${chat.id}');
                                break;
                              case _ChatMenuAction.gridBreach:
                                _launchGridBreach(chat, currentUserId);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem<_ChatMenuAction>(
                              value: _ChatMenuAction.search,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.search_rounded),
                                title: Text(isGX ? 'SEARCH' : 'Search'),
                              ),
                            ),
                            PopupMenuItem<_ChatMenuAction>(
                              value: _ChatMenuAction.refresh,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.refresh_rounded),
                                title: Text(isGX ? 'REFRESH' : 'Refresh'),
                              ),
                            ),
                            PopupMenuItem<_ChatMenuAction>(
                              value: _ChatMenuAction.background,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.wallpaper_outlined),
                                title: Text(isGX ? 'CHAT THEME' : 'Chat Theme'),
                              ),
                            ),
                            if (isGX && !chat.isGroup)
                              PopupMenuItem<_ChatMenuAction>(
                                value: _ChatMenuAction.gridBreach,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.grid_on_rounded),
                                  title: const Text('GRID BREACH'),
                                ),
                              ),
                            if (chat.isGroup)
                              PopupMenuItem<_ChatMenuAction>(
                                value: _ChatMenuAction.groupInfo,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.info_outline_rounded,
                                  ),
                                  title: Text(
                                    isGX ? 'GROUP INFO' : 'Group info',
                                  ),
                                ),
                              )
                            else ...[
                              PopupMenuItem<_ChatMenuAction>(
                                value: _ChatMenuAction.audio,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.call_outlined),
                                  title: Text(
                                    isGX ? 'AUDIO CALL' : 'Audio call',
                                  ),
                                ),
                              ),
                              PopupMenuItem<_ChatMenuAction>(
                                value: _ChatMenuAction.video,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.videocam_outlined),
                                  title: Text(
                                    isGX ? 'VIDEO CALL' : 'Video call',
                                  ),
                                ),
                              ),
                            ],
                          ],
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ],
            ),
      floatingActionButton:
          !isSelectionMode && !_isSearchMode && _showScrollToBottom
          ? Padding(
              padding: EdgeInsets.only(bottom: _isStickerPanelOpen ? 428 : 84),
              child: FloatingActionButton.small(
                tooltip: 'Scroll to bottom',
                onPressed: () => _scheduleScrollToBottom(animated: true),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            )
          : null,
      body: Column(
        children: [
          const ConnectivityBodyIndicator(),
          if (messageState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AppErrorCard(
                message: messageState.errorMessage!,
                actionLabel: 'Retry',
                onAction: () => unawaited(_refreshChatView()),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ResolvedChatBackgroundLayer(chatId: widget.chatId),
                if (messageState.isLoadingInitial)
                  ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.76),
                    child: const ChatMessagesSkeleton(),
                  )
                else if (items.isEmpty)
                  Center(
                    child: Text(
                      isGX
                          ? 'SECURE CHANNEL ENGAGED Ã¢â‚¬â€ NO DATA'
                          : 'No messages yet. Start the secure conversation.',
                      style: isGX
                          ? const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              letterSpacing: 1.1,
                            )
                          : null,
                    ),
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    itemCount: items.length + (isSomeoneTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return const TypingIndicator();
                      }
                      final item = items[index];
                      if (item is _DateListItem) {
                        return DateSeparator(
                          label: isGX ? item.label.toUpperCase() : item.label,
                        );
                      }
                      final message = item as _MessageListItem;
                      final bubbleMessage = message.message;
                      final replyTarget = bubbleMessage.replyToMessageId == null
                          ? null
                          : messageById[bubbleMessage.replyToMessageId];
                      return KeyedSubtree(
                        key: _messageItemKeyFor(bubbleMessage.id),
                        child: MessageBubble(
                          message: bubbleMessage,
                          isInactiveGridBreachInvite:
                              bubbleMessage.kind == MessageKind.grid_breach &&
                              (bubbleMessage.isExpiredGridBreachSession ||
                                  (latestGridBreachInviteId != null &&
                                      bubbleMessage.id !=
                                          latestGridBreachInviteId)),
                          outgoingBubbleColor: outgoingBubbleColor,
                          isSelected: bubbleMessage.id == _selectedMessageId,
                          isActiveSearchResult:
                              activeSearchMessageId == bubbleMessage.id,
                          highlightQuery:
                              matchedMessageIds.contains(bubbleMessage.id)
                              ? _executedSearchQuery
                              : null,
                          senderLabel: showSenderNames
                              ? _senderLabelFor(
                                  senderLabels,
                                  bubbleMessage.senderId,
                                  currentUserId,
                                )
                              : null,
                          replyPreviewText: _replyPreviewTextFor(replyTarget),
                          replyPreviewAttachment: _buildReplyPreviewAttachment(
                            replyTarget,
                            stickerState,
                          ),
                          replyAuthorLabel: _replyAuthorLabelFor(
                            replyTarget,
                            senderLabels,
                            currentUserId,
                          ),
                          onLongPress: _isSearchMode
                              ? null
                              : () => _selectMessage(bubbleMessage.id),
                          onAttachmentTap:
                              bubbleMessage.kind == MessageKind.audio ||
                                  bubbleMessage.kind == MessageKind.sticker ||
                                  bubbleMessage.kind == MessageKind.grid_breach
                              ? null
                              : () => _handleMessageTap(bubbleMessage),
                          onReplySwipe: isSelectionMode || _isSearchMode
                              ? null
                              : () => _startReply(bubbleMessage),
                          cryptoStatusLabel: _cryptoStatusLabelFor(
                            message: bubbleMessage,
                            latestOwnMessage: latestOwnMessage,
                            latestIncomingMessage: latestIncomingMessage,
                          ),
                          attachmentPreview: _buildAttachmentPreview(
                            bubbleMessage,
                            stickerState,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          if (!_isSearchMode) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _isStickerPanelOpen
                  ? StickerPanel(
                      key: const ValueKey('sticker-panel'),
                      state: stickerState,
                      onStickerTap: (sticker) =>
                          unawaited(_sendSticker(sticker)),
                      onCreateSticker: () =>
                          unawaited(_openCreateStickerScreen()),
                      onRetry: () =>
                          ref.read(stickerLibraryProvider.notifier).refresh(),
                    )
                  : const SizedBox.shrink(),
            ),
            Composer(
              controller: _textController,
              focusNode: _composerFocusNode,
              isSending: messageState.isSending,
              hasText: _hasComposerText,
              isRecordingVoiceNote: _isRecordingVoiceNote,
              recordingDuration: _voiceNoteDuration,
              onPrimaryAction: _handleComposerPrimaryAction,
              onChanged: _handleComposerChanged,
              onStickerTap: _toggleStickerPanel,
              onTextFieldTap: _handleComposerTextFieldTap,
              isStickerPanelOpen: _isStickerPanelOpen,
              onAttachments: ({bool imagesOnly = false}) {
                _closeStickerPanel();
                return _showAttachmentSheet(imagesOnly: imagesOnly);
              },
              replyPreviewText: _replyPreviewTextFor(replyingMessage),
              replyPreviewAttachment: _buildReplyPreviewAttachment(
                replyingMessage,
                stickerState,
              ),
              replyAuthorLabel: _replyAuthorLabelFor(
                replyingMessage,
                senderLabels,
                currentUserId,
              ),
              onCancelReply: replyingMessage == null ? null : _cancelReply,
              onCancelRecording: _isRecordingVoiceNote
                  ? _cancelVoiceNoteRecording
                  : null,
              enterToSendEnabled: currentProfile?.enterToSendEnabled ?? false,
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final hasResults = _searchMatches.isNotEmpty;
    final isGX = GXThemeExtension.of(context).isGX;

    return AppBar(
      leading: IconButton(
        tooltip: 'Exit search',
        onPressed: _exitSearchMode,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: false,
        textInputAction: TextInputAction.search,
        style: isGX ? const TextStyle(fontFamily: 'monospace') : null,
        onChanged: (value) {
          setState(() => _searchDraftQuery = value);
        },
        onSubmitted: (_) => unawaited(_executeSearch()),
        decoration: InputDecoration(
          hintText: isGX ? 'SEARCH IN CHAT' : 'Search in chat',
          hintStyle: isGX ? const TextStyle(fontFamily: 'monospace') : null,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchDraftQuery.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchDraftQuery = '';
                      _executedSearchQuery = '';
                      _searchMatches = const [];
                      _activeSearchMatchIndex = 0;
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isGX ? 8 : 18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isGX ? 8 : 18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isGX ? 8 : 18),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
      actions: [
        if (_isRunningSearch)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                hasResults
                    ? '${_activeSearchMatchIndex + 1}/${_searchMatches.length}'
                    : '0/0',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFamily: isGX ? 'monospace' : null,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous match',
            onPressed: hasResults
                ? () =>
                      unawaited(_jumpToSearchMatch(_activeSearchMatchIndex - 1))
                : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: 'Next match',
            onPressed: hasResults
                ? () =>
                      unawaited(_jumpToSearchMatch(_activeSearchMatchIndex + 1))
                : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          IconButton(
            tooltip: 'Run search',
            onPressed: () => unawaited(_executeSearch()),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ],
    );
  }

  void _enterSearchMode({String? initialQuery, bool autofocus = true}) {
    _scrollOffsetBeforeSearch ??= _scrollController.hasClients
        ? _scrollController.offset
        : null;

    final nextQuery = initialQuery ?? _searchController.text;
    _searchController.value = TextEditingValue(
      text: nextQuery,
      selection: TextSelection.collapsed(offset: nextQuery.length),
    );

    setState(() {
      _isSearchMode = true;
      _searchDraftQuery = nextQuery;
      _selectedMessageId = null;
      _replyingToMessageId = null;
    });

    if (autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _exitSearchMode() async {
    final restoreOffset = _scrollOffsetBeforeSearch;
    _searchFocusNode.unfocus();
    _searchController.clear();

    setState(() {
      _isSearchMode = false;
      _isRunningSearch = false;
      _searchDraftQuery = '';
      _executedSearchQuery = '';
      _searchMatches = const [];
      _activeSearchMatchIndex = 0;
      _scrollOffsetBeforeSearch = null;
    });

    if (restoreOffset != null && _scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      await _scrollController.animateTo(
        restoreOffset.clamp(0.0, maxExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _applyInitialSearchRoute() async {
    if (_didHandleInitialSearchRoute || !mounted) {
      return;
    }
    _didHandleInitialSearchRoute = true;

    final initialQuery = widget.initialSearchQuery?.trim() ?? '';
    final initialMessageId = widget.initialMessageId?.trim();

    if (initialQuery.isNotEmpty) {
      _enterSearchMode(initialQuery: initialQuery, autofocus: false);
      await _executeSearch(
        queryOverride: initialQuery,
        preferredMessageId: initialMessageId,
      );
      return;
    }

    if (initialMessageId != null && initialMessageId.isNotEmpty) {
      await ref
          .read(messageProvider(widget.chatId).notifier)
          .ensureMessageLoaded(initialMessageId);
      if (!mounted) {
        return;
      }
      await _scrollToMessageById(initialMessageId, animated: false);
    }
  }

  Future<void> _executeSearch({
    String? queryOverride,
    String? preferredMessageId,
  }) async {
    final query = (queryOverride ?? _searchController.text).trim();
    if (query.isEmpty) {
      setState(() {
        _executedSearchQuery = '';
        _searchMatches = const [];
        _activeSearchMatchIndex = 0;
        _isRunningSearch = false;
      });
      return;
    }

    setState(() {
      _isRunningSearch = true;
      _searchDraftQuery = query;
    });

    try {
      final matches = await ref
          .read(chatRepositoryProvider)
          .searchChatMessages(chatId: widget.chatId, query: query);
      if (!mounted) {
        return;
      }

      final preferredIndex = preferredMessageId == null
          ? -1
          : matches.indexWhere(
              (match) => match.messageId == preferredMessageId,
            );
      final nextIndex = matches.isEmpty
          ? 0
          : preferredIndex >= 0
          ? preferredIndex
          : 0;

      setState(() {
        _executedSearchQuery = query;
        _searchMatches = matches;
        _activeSearchMatchIndex = nextIndex;
        _isRunningSearch = false;
      });

      if (matches.isNotEmpty) {
        await _jumpToSearchMatch(nextIndex, animated: true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isRunningSearch = false);
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  Future<void> _jumpToSearchMatch(int index, {bool animated = true}) async {
    if (_searchMatches.isEmpty) {
      return;
    }

    final normalizedIndex =
        (index % _searchMatches.length + _searchMatches.length) %
        _searchMatches.length;
    final match = _searchMatches[normalizedIndex];

    setState(() {
      _activeSearchMatchIndex = normalizedIndex;
    });

    await ref
        .read(messageProvider(widget.chatId).notifier)
        .ensureMessageLoaded(match.messageId);
    if (!mounted) {
      return;
    }

    await _scrollToMessageById(match.messageId, animated: animated);
  }

  Future<void> _scrollToMessageById(
    String messageId, {
    required bool animated,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) {
        return;
      }

      await _approximateScrollToMessage(
        messageId,
        animated: animated && attempt == 0,
      );
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 20 : 80),
      );
      if (!mounted) {
        return;
      }

      final messageContext = _messageItemKeyFor(messageId).currentContext;
      if (messageContext != null && messageContext.mounted) {
        await Scrollable.ensureVisible(
          messageContext,
          duration: animated
              ? const Duration(milliseconds: 260)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
        return;
      }
    }
  }

  Future<void> _approximateScrollToMessage(
    String messageId, {
    required bool animated,
  }) async {
    if (!_scrollController.hasClients) {
      return;
    }

    final messages = ref.read(messageProvider(widget.chatId)).messages;
    final messageIndex = messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) {
      return;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }

    final fraction = messages.length <= 1
        ? 0.0
        : messageIndex / (messages.length - 1);
    final targetOffset = (maxExtent * fraction).clamp(0.0, maxExtent);
    if (animated) {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _scrollController.jumpTo(targetOffset);
  }

  GlobalKey _messageItemKeyFor(String messageId) {
    return _messageItemKeys.putIfAbsent(
      messageId,
      () => GlobalObjectKey('chat-message-$messageId'),
    );
  }

  void _handleScroll() {
    final shouldShow = !_isNearBottom();
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.position.maxScrollExtent -
            _scrollController.offset <=
        120;
  }

  void _handleAutoScrollSignals(List<ResolvedChatMessage> messages) {
    if (messages.isEmpty) {
      _lastObservedLastMessageId = null;
      _didInitialScrollToBottom = false;
      return;
    }

    final lastMessage = messages.last;
    final isNewLastMessage = lastMessage.id != _lastObservedLastMessageId;

    if (!_didInitialScrollToBottom) {
      _didInitialScrollToBottom = true;
      _lastObservedLastMessageId = lastMessage.id;
      _scheduleScrollToBottom(animated: false);
      return;
    }

    if (isNewLastMessage) {
      _lastObservedLastMessageId = lastMessage.id;
      if (lastMessage.isMine) {
        _scheduleScrollToBottom(animated: true);
      }
    }
  }

  void _scheduleScrollToBottom({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }

      if (mounted && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
    });
  }

  void _handleCryptoTooltipSignals({
    required ResolvedChatMessage? latestOwnMessage,
    required ResolvedChatMessage? latestIncomingMessage,
  }) {
    if (!_didSeedCryptoTooltips) {
      _didSeedCryptoTooltips = true;
      _lastObservedOwnMessageId = latestOwnMessage?.id;
      _lastObservedIncomingMessageId = latestIncomingMessage?.id;
      return;
    }

    if (latestOwnMessage?.id != null &&
        latestOwnMessage!.id != _lastObservedOwnMessageId) {
      _lastObservedOwnMessageId = latestOwnMessage.id;
      _encryptingMessageId = latestOwnMessage.id;
      _encryptingTimer?.cancel();
      _encryptingTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _encryptingMessageId != latestOwnMessage.id) {
          return;
        }
        setState(() => _encryptingMessageId = null);
      });
    }

    if (latestIncomingMessage?.id != null &&
        latestIncomingMessage!.id != _lastObservedIncomingMessageId) {
      _lastObservedIncomingMessageId = latestIncomingMessage.id;
      _decryptingMessageId = latestIncomingMessage.id;
      _decryptingTimer?.cancel();
      _decryptingTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || _decryptingMessageId != latestIncomingMessage.id) {
          return;
        }
        setState(() => _decryptingMessageId = null);
      });
    }
  }

  ResolvedChatMessage? _latestMessageFor(
    List<ResolvedChatMessage> messages, {
    required bool Function(ResolvedChatMessage message) predicate,
  }) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (predicate(message)) {
        return message;
      }
    }
    return null;
  }

  String? _cryptoStatusLabelFor({
    required ResolvedChatMessage message,
    required ResolvedChatMessage? latestOwnMessage,
    required ResolvedChatMessage? latestIncomingMessage,
  }) {
    if (message.isPendingLocal) {
      return 'Encrypting...';
    }

    if (latestOwnMessage?.id == message.id) {
      if (_encryptingMessageId == message.id) {
        return 'Encrypting...';
      }
      return 'Encrypted';
    }

    if (latestIncomingMessage?.id == message.id) {
      if (_decryptingMessageId == message.id) {
        return 'Decrypting...';
      }
      return 'Decrypted';
    }

    return null;
  }

  Map<String, String> _senderLabelsFor(Chat? chat, String currentUserId) {
    if (chat == null) {
      return {currentUserId: 'You'};
    }

    return {
      for (final member in chat.members)
        member.userId: member.userId == currentUserId
            ? 'You'
            : (member.username?.trim().isNotEmpty ?? false)
            ? member.username!.trim()
            : 'Member',
    };
  }

  String _senderLabelFor(
    Map<String, String> senderLabels,
    String senderId,
    String currentUserId,
  ) {
    return senderLabels[senderId] ??
        (senderId == currentUserId ? 'You' : 'Member');
  }

  String? _replyPreviewTextFor(ResolvedChatMessage? message) {
    if (message == null) {
      return null;
    }
    return message.previewText;
  }

  Widget? _buildReplyPreviewAttachment(
    ResolvedChatMessage? message,
    StickerLibraryState stickerState,
  ) {
    if (message == null ||
        message.kind != MessageKind.sticker ||
        message.isDeletedForEveryone) {
      return null;
    }

    final stickerId = message.stickerId?.trim();
    if (stickerId == null || stickerId.isEmpty) {
      return null;
    }

    final theme = Theme.of(context);
    final sticker = stickerState.stickersById[stickerId];

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 40,
        child: sticker == null
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : StickerNetworkDisplay(
                sticker: sticker,
                size: 40,
                filterQuality: FilterQuality.low,
              ),
      ),
    );
  }

  String? _replyAuthorLabelFor(
    ResolvedChatMessage? message,
    Map<String, String> senderLabels,
    String currentUserId,
  ) {
    if (message == null) {
      return null;
    }
    return _senderLabelFor(senderLabels, message.senderId, currentUserId);
  }

  List<Object> _buildListItems(List<ResolvedChatMessage> messages) {
    final items = <Object>[];
    DateTime? previousDay;

    for (final message in messages) {
      final day = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (previousDay == null || previousDay != day) {
        items.add(_DateListItem(_formatDate(day)));
      }
      items.add(_MessageListItem(message));
      previousDay = day;
    }

    return items;
  }

  void _handleComposerFocusChanged() {
    if (!_composerFocusNode.hasFocus || !_isStickerPanelOpen || !mounted) {
      return;
    }
    setState(() => _isStickerPanelOpen = false);
  }

  void _handleComposerTextFieldTap() {
    if (!_isStickerPanelOpen) {
      return;
    }
    setState(() => _isStickerPanelOpen = false);
  }

  void _closeStickerPanel() {
    if (!_isStickerPanelOpen) {
      return;
    }
    setState(() => _isStickerPanelOpen = false);
  }

  void _toggleStickerPanel() {
    FocusScope.of(context).unfocus();
    setState(() => _isStickerPanelOpen = !_isStickerPanelOpen);
  }

  void _hydrateVisibleStickerMetadata({
    required List<ResolvedChatMessage> messages,
    required StickerLibraryState stickerState,
  }) {
    final missingIds = messages
        .where((message) => message.kind == MessageKind.sticker)
        .map((message) => message.stickerId?.trim() ?? '')
        .where(
          (stickerId) =>
              stickerId.isNotEmpty &&
              !stickerState.stickersById.containsKey(stickerId),
        )
        .toSet();
    if (setEquals(missingIds, _pendingStickerHydrationIds)) {
      return;
    }

    _pendingStickerHydrationIds = missingIds;
    if (missingIds.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(stickerLibraryProvider.notifier)
            .ensureStickersLoaded(missingIds),
      );
    });
  }

  Future<void> _sendSticker(Sticker sticker) async {
    final replyToMessageId = _replyingToMessageId;
    await _stopTypingBroadcast(force: true);
    _cancelReply();
    await ref
        .read(stickerLibraryProvider.notifier)
        .registerStickerUse(sticker.id);
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendSticker(sticker.id, replyToMessageId: replyToMessageId);
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _openChatBackgroundEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChatBackgroundEditorScreen(chatId: widget.chatId),
      ),
    );
  }

  Future<void> _openCreateStickerScreen() async {
    final createdSticker = await Navigator.of(context).push<Sticker>(
      MaterialPageRoute<Sticker>(
        fullscreenDialog: true,
        builder: (_) => const CreateStickerScreen(),
      ),
    );
    if (!mounted || createdSticker == null) {
      return;
    }
    _showSnackBar('Sticker added to your library');
    setState(() => _isStickerPanelOpen = true);
  }

  Future<void> _addSelectedStickerToLibrary(ResolvedChatMessage message) async {
    final stickerId = message.stickerId?.trim();
    if (stickerId == null || stickerId.isEmpty) {
      return;
    }

    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    final sticker = await _resolveStickerForAction(stickerId);
    if (sticker == null) {
      _showSnackBar('This sticker is unavailable right now.');
      return;
    }
    if (!sticker.canBeSavedBy(currentUserId)) {
      _showSnackBar('This sticker cannot be saved');
      return;
    }

    final stickerState = ref.read(stickerLibraryProvider);
    if (stickerState.isInLibrary(stickerId)) {
      _clearSelection();
      _showSnackBar('Sticker is already in your Stickers');
      return;
    }

    try {
      await ref.read(stickerLibraryProvider.notifier).saveToLibrary(stickerId);
      _clearSelection();
      _showSnackBar('Sticker added to your Stickers');
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  Future<void> _toggleSelectedStickerFavorite(
    ResolvedChatMessage message,
  ) async {
    final stickerId = message.stickerId?.trim();
    if (stickerId == null || stickerId.isEmpty) {
      return;
    }

    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    final sticker = await _resolveStickerForAction(stickerId);
    if (sticker == null) {
      _showSnackBar('This sticker is unavailable right now.');
      return;
    }
    if (!sticker.canBeSavedBy(currentUserId)) {
      _showSnackBar('This sticker is private and cannot be added to favorites');
      return;
    }

    final stickerState = ref.read(stickerLibraryProvider);
    if (!stickerState.isInLibrary(stickerId)) {
      _showSnackBar('Add this sticker to Stickers first');
      return;
    }

    final isFavorite = stickerState.isFavorite(stickerId);
    try {
      await ref.read(stickerLibraryProvider.notifier).toggleFavorite(stickerId);
      _clearSelection();
      _showSnackBar(
        isFavorite
            ? 'Sticker removed from favorites'
            : 'Sticker added to favorites',
      );
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  Future<Sticker?> _resolveStickerForAction(String stickerId) {
    return ref.read(stickerLibraryProvider.notifier).getSticker(stickerId);
  }

  Widget? _buildAttachmentPreview(
    ResolvedChatMessage message,
    StickerLibraryState stickerState,
  ) {
    if (message.kind == MessageKind.sticker) {
      if (message.isDeletedForEveryone) {
        return null;
      }

      final theme = Theme.of(context);
      final stickerId = message.stickerId?.trim();
      final sticker = stickerId == null || stickerId.isEmpty
          ? null
          : stickerState.stickersById[stickerId];

      final stickerSize = message.replyToMessageId == null ? 168.0 : 120.0;

      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            message.replyToMessageId == null ? 20 : 18,
          ),
          child: SizedBox.square(
            dimension: stickerSize,
            child: sticker == null
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : StickerNetworkDisplay(sticker: sticker, size: stickerSize),
          ),
        ),
      );
    }

    final attachment = message.attachment;
    if (attachment == null ||
        message.isConsumed ||
        message.isDeletedForEveryone) {
      return null;
    }

    if (message.kind == MessageKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FutureBuilder<File>(
          future: ref
              .read(messageProvider(widget.chatId).notifier)
              .openAttachment(message.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                height: 180,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.image_not_supported_outlined),
              );
            }
            if (!snapshot.hasData) {
              return Container(
                height: 180,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }
            return Image.file(
              snapshot.data!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            );
          },
        ),
      );
    }

    if (message.kind == MessageKind.video) {
      return VideoMessagePreview(
        fileName: attachment.fileName,
        subtitle: message.isViewOnce
            ? 'View once'
            : _formatFileSize(attachment.sizeBytes),
        loadFile: () => ref
            .read(messageProvider(widget.chatId).notifier)
            .openAttachment(message.id),
      );
    }

    if (message.kind == MessageKind.audio) {
      return AudioMessagePlayer(
        durationMs: attachment.durationMs,
        fileSizeLabel: _formatFileSize(attachment.sizeBytes),
        loadFile: () => ref
            .read(messageProvider(widget.chatId).notifier)
            .openAttachment(message.id),
      );
    }

    return AttachmentCard(
      icon: Icons.attach_file_rounded,
      title: attachment.fileName,
      subtitle: _formatFileSize(attachment.sizeBytes),
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final replyToMessageId = _replyingToMessageId;
    _textController.clear();
    if (_hasComposerText) {
      setState(() => _hasComposerText = false);
    }
    await _stopTypingBroadcast(force: true);
    _clearSelection();
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendText(text, replyToMessageId: replyToMessageId);
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _handleComposerPrimaryAction() async {
    if (_hasComposerText) {
      await _sendText();
      return;
    }

    if (_isRecordingVoiceNote) {
      await _stopAndSendVoiceNote();
      return;
    }

    await _startVoiceNoteRecording();
  }

  Future<void> _startVoiceNoteRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnackBar(
          'Microphone permission is required to record a voice note.',
        );
        return;
      }

      await _stopTypingBroadcast(force: true);
      final directory = await getTemporaryDirectory();
      final filePath =
          '${directory.path}${Platform.pathSeparator}voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      _voiceNoteTimer?.cancel();
      _voiceNoteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceNoteDuration += const Duration(seconds: 1);
        });
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoiceNote = true;
        _voiceNoteDuration = Duration.zero;
      });
    } catch (_) {
      _showSnackBar('Unable to start voice note recording.');
    }
  }

  Future<void> _cancelVoiceNoteRecording() async {
    if (!_isRecordingVoiceNote) {
      return;
    }

    _voiceNoteTimer?.cancel();
    try {
      await _audioRecorder.cancel();
    } catch (_) {
      // If cleanup fails, we still reset the local recording state.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRecordingVoiceNote = false;
      _voiceNoteDuration = Duration.zero;
    });
  }

  Future<void> _stopAndSendVoiceNote() async {
    if (!_isRecordingVoiceNote) {
      return;
    }

    final durationMs = _voiceNoteDuration.inMilliseconds;
    _voiceNoteTimer?.cancel();

    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {
      _showSnackBar('Unable to finish the voice note recording.');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRecordingVoiceNote = false;
      _voiceNoteDuration = Duration.zero;
    });

    if (path == null || path.isEmpty) {
      _showSnackBar('Voice note recording was empty.');
      return;
    }

    final replyToMessageId = _replyingToMessageId;
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendAudio(
          path,
          durationMs: durationMs > 0 ? durationMs : null,
          fileNameOverride: 'voice-note.m4a',
          replyToMessageId: replyToMessageId,
        );
    _scheduleScrollToBottom(animated: true);
  }

  void _handleComposerChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasComposerText && mounted) {
      setState(() => _hasComposerText = hasText);
    }

    if (!_cachedTypingIndicatorEnabled) {
      return;
    }

    _typingPauseTimer?.cancel();

    if (value.trim().isEmpty) {
      unawaited(_stopTypingBroadcast(force: true));
      return;
    }

    if (!_isTypingActive) {
      unawaited(_broadcastTypingState(isTyping: true));
    }

    _typingPauseTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_stopTypingBroadcast());
    });
  }

  Future<void> _broadcastTypingState({required bool isTyping}) async {
    final channel = _typingChannel;
    final currentUserId = _cachedCurrentUserId;
    final username = _cachedTypingUsername;
    if (channel == null || currentUserId == null || username == null) {
      return;
    }
    if (!_cachedTypingIndicatorEnabled && isTyping) {
      return;
    }

    _isTypingActive = isTyping;
    await _chatTypingService.sendTypingState(
      channel: channel,
      chatId: widget.chatId,
      userId: currentUserId,
      username: username,
      isTyping: isTyping,
    );
  }

  Future<void> _stopTypingBroadcast({bool force = false}) async {
    _typingPauseTimer?.cancel();
    if (!_isTypingActive && !force) {
      return;
    }

    if (_isTypingActive || force) {
      await _broadcastTypingState(isTyping: false);
    }
  }

  Future<void> _showAttachmentSheet({bool imagesOnly = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AttachmentCard(
                  icon: Icons.photo_library_outlined,
                  title: 'Photo from gallery',
                  subtitle: 'Pick an image from your device library',
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_pickImage(ImageSource.gallery));
                  },
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  icon: Icons.camera_alt_outlined,
                  title: 'Photo from camera',
                  subtitle: 'Take a new photo with your camera',
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_pickImage(ImageSource.camera));
                  },
                ),
                if (!imagesOnly) ...[
                  const SizedBox(height: 12),
                  AttachmentCard(
                    icon: Icons.videocam_outlined,
                    title: 'Video',
                    subtitle: 'Share a video file with members',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pickVideo());
                    },
                  ),
                  const SizedBox(height: 12),
                  AttachmentCard(
                    icon: Icons.folder_zip_outlined,
                    title: 'Document or file',
                    subtitle: 'Send PDF, DOC, ZIP or other files',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pickFile());
                    },
                  ),
                  const SizedBox(height: 12),
                  AttachmentCard(
                    icon: Icons.audiotrack_outlined,
                    title: 'Audio',
                    subtitle: 'Share music or recordings',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pickAudio());
                    },
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _imagePicker.pickImage(source: source, imageQuality: 95);
    if (file == null) {
      return;
    }

    final replyToMessageId = _replyingToMessageId;
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendImage(file.path, replyToMessageId: replyToMessageId);
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _pickVideo() async {
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (file == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final sendMode = await showModalBottomSheet<_VideoSendMode>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Send standard video'),
                onTap: () => Navigator.of(context).pop(_VideoSendMode.standard),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Send as view once'),
                subtitle: const Text(
                  'The receiver can decrypt and open it only one time.',
                ),
                onTap: () => Navigator.of(context).pop(_VideoSendMode.viewOnce),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Send as video sticker (3 s)'),
                subtitle: const Text(
                  'Clip a short looping segment before sending.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_VideoSendMode.videoSticker),
              ),
            ],
          ),
        );
      },
    );

    if (sendMode == null || !mounted) return;

    int? durationMs;
    if (sendMode == _VideoSendMode.videoSticker) {
      final result = await Navigator.of(context).push<VideoTrimResult>(
        MaterialPageRoute<VideoTrimResult>(
          fullscreenDialog: true,
          builder: (_) => VideoStickerEditorScreen(file: File(file.path)),
        ),
      );
      if (result == null || !mounted) return;
      durationMs = result.durationMs;
    }

    final replyToMessageId = _replyingToMessageId;
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendVideo(
          file.path,
          viewOnce: sendMode == _VideoSendMode.viewOnce,
          durationMs: durationMs,
          replyToMessageId: replyToMessageId,
        );
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    final replyToMessageId = _replyingToMessageId;
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendFile(path, replyToMessageId: replyToMessageId);
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    final replyToMessageId = _replyingToMessageId;
    _cancelReply();
    await ref
        .read(messageProvider(widget.chatId).notifier)
        .sendAudio(path, replyToMessageId: replyToMessageId);
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _handleMessageTap(ResolvedChatMessage message) async {
    if (_selectedMessageId != null) {
      _selectMessage(message.id);
      return;
    }

    if (message.kind == MessageKind.text ||
        message.kind == MessageKind.audio ||
        message.kind == MessageKind.sticker ||
        message.kind == MessageKind.grid_breach ||
        message.isDeletedForEveryone) {
      return;
    }

    await _openAttachment(message);
  }

  void _selectMessage(String messageId) {
    HapticFeedback.mediumImpact();
    setState(() => _selectedMessageId = messageId);
  }

  void _clearSelection() {
    if (_selectedMessageId == null) {
      return;
    }
    setState(() => _selectedMessageId = null);
  }

  void _startReply(ResolvedChatMessage message) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMessageId = null;
      _replyingToMessageId = message.id;
    });
  }

  void _cancelReply() {
    if (_replyingToMessageId == null) {
      return;
    }
    setState(() => _replyingToMessageId = null);
  }

  ResolvedChatMessage? _selectedMessageFrom(
    List<ResolvedChatMessage> messages,
  ) {
    final selectedId = _selectedMessageId;
    if (selectedId == null) {
      return null;
    }

    for (final message in messages) {
      if (message.id == selectedId) {
        return message;
      }
    }

    return null;
  }

  ResolvedChatMessage? _replyingMessageFrom(
    List<ResolvedChatMessage> messages,
  ) {
    final replyingId = _replyingToMessageId;
    if (replyingId == null) {
      return null;
    }

    for (final message in messages) {
      if (message.id == replyingId) {
        return message;
      }
    }

    return null;
  }

  Future<void> _copySelectedMessage(ResolvedChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.previewText));
    _clearSelection();
    _showSnackBar('Message copied');
  }

  Future<void> _deleteSelectedMessage(ResolvedChatMessage message) async {
    final action = await _showDeleteOptions(message);
    if (action == null) {
      return;
    }

    try {
      final controller = ref.read(messageProvider(widget.chatId).notifier);
      switch (action) {
        case _MessageDeleteAction.deleteForMe:
          await controller.hideMessageForMe(message.id);
          _showSnackBar('Message removed from this device');
          break;
        case _MessageDeleteAction.deleteForEveryone:
          await controller.deleteMessageForEveryone(message.id);
          _showSnackBar('Message deleted for everyone');
          break;
      }
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    } finally {
      _clearSelection();
    }
  }

  Future<_MessageDeleteAction?> _showDeleteOptions(
    ResolvedChatMessage message,
  ) {
    final canDeleteForEveryone =
        message.isMine && !message.isDeletedForEveryone;

    return showModalBottomSheet<_MessageDeleteAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Delete message'),
                subtitle: Text('Choose where this message should be removed.'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete for me'),
                subtitle: const Text(
                  'Remove this message only from this device chat screen.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_MessageDeleteAction.deleteForMe),
              ),
              if (canDeleteForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Delete for everyone'),
                  subtitle: const Text(
                    'Replace it with a deleted message bubble for all chat members.',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_MessageDeleteAction.deleteForEveryone),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAttachment(ResolvedChatMessage message) async {
    try {
      final file = await ref
          .read(messageProvider(widget.chatId).notifier)
          .openAttachment(message.id);

      if (!mounted) {
        return;
      }

      if (message.kind == MessageKind.image) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImageViewerScreen(
              file: file,
              title: message.previewText,
              isViewOnce: message.isViewOnce,
            ),
          ),
        );

        await _consumeViewOnceAfterViewing(message);
        return;
      }

      if (message.kind == MessageKind.video) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoViewerScreen(
              file: file,
              title: message.attachment?.fileName ?? 'Video',
              isViewOnce: message.isViewOnce,
            ),
          ),
        );

        await _consumeViewOnceAfterViewing(message);
        return;
      }

      await OpenFilex.open(file.path);
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  Future<void> _consumeViewOnceAfterViewing(ResolvedChatMessage message) async {
    if (!message.isViewOnce || message.isMine) {
      return;
    }

    await ref
        .read(messageProvider(widget.chatId).notifier)
        .consumeViewOnce(message.id);
  }

  Future<void> _startCall({required Chat chat, required bool withVideo}) async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    final peer = chat.otherMemberFor(currentUserId);
    if (peer == null) {
      return;
    }

    try {
      final session = await ref
          .read(callRepositoryProvider)
          .createCallSession(
            chatId: chat.id,
            callerId: currentUserId,
            calleeId: peer.userId,
            type: withVideo ? AppCallType.video : AppCallType.audio,
          );

      if (!mounted) {
        return;
      }

      context.push('/call/${session.id}');
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  Future<void> _launchGridBreach(Chat chat, String currentUserId) async {
    final peer = chat.otherMemberFor(currentUserId);
    if (peer == null) return;

    try {
      final match = await ref
          .read(gameRepositoryProvider)
          .createMatch(
            player1Id: currentUserId,
            player2Id: peer.userId,
            chatId: chat.id,
          );

      await ref
          .read(secureChatServiceProvider)
          .sendGridBreachInvite(
            chatId: chat.id,
            currentUserId: currentUserId,
            matchId: match.id,
          );

      if (!mounted) return;
      context.push('/chat/game/${match.id}');
    } catch (e) {
      _showSnackBar(AppErrorHelper.messageFor(e));
    }
  }

  Future<void> _refreshChatView({bool reconnectRealtime = true}) async {
    try {
      await ref
          .read(messageProvider(widget.chatId).notifier)
          .refresh(reconnectRealtime: reconnectRealtime);
      ref.invalidate(chatDetailsProvider(widget.chatId));
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) {
      return 'Today';
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _openContactProfile(Chat chat, String currentUserId) {
    final participant = chat.otherMemberFor(currentUserId);
    if (participant == null || !mounted) {
      return;
    }

    context.push('/profile/${participant.userId}');
  }
}

class _DateListItem {
  const _DateListItem(this.label);

  final String label;
}

class _MessageListItem {
  const _MessageListItem(this.message);

  final ResolvedChatMessage message;
}

enum _MessageDeleteAction { deleteForMe, deleteForEveryone }

enum _ChatMenuAction {
  search,
  refresh,
  background,
  audio,
  video,
  groupInfo,
  gridBreach,
}

enum _VideoSendMode { standard, viewOnce, videoSticker }
