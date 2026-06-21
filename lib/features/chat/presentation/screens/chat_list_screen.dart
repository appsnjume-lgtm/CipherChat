import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../common/widgets/app_avatar.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../../core/widgets/no_internet_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/widgets/profile_image_modal.dart';
import '../../domain/entities/chat.dart';
import '../../data/models/search_models.dart';
import '../../data/repositories/chat_repository.dart';
import '../providers/chat_provider.dart';
import '../providers/invite_provider.dart';
import '../screens/widgets/attachment_card.dart';
import '../widgets/chat_tile.dart';
import '../widgets/highlighted_text.dart';

enum _ChatListFilter { all, unread, groups }

enum _ChatMenuAction { startDirect, createGroup, settings, signOut }

class ChatListSelectionConfig {
  const ChatListSelectionConfig({
    required this.title,
    required this.infoText,
    required this.emptyStateText,
    required this.onChatSelected,
  });

  final String title;
  final String? infoText;
  final String emptyStateText;
  final Future<void> Function(Chat chat) onChatSelected;
}

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key, this.selectionConfig});

  final ChatListSelectionConfig? selectionConfig;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedChatIds = <String>{};
  Timer? _searchDebounce;
  String _searchInputText = '';
  String _searchQuery = '';
  String? _pendingSearchContactId;
  _ChatListFilter _activeFilter = _ChatListFilter.all;
  bool _isDeletingSelected = false;

  bool get _isSelectionMode => widget.selectionConfig != null;
  bool get _isDeleteSelectionMode =>
      !_isSelectionMode && _selectedChatIds.isNotEmpty;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    final chatListState = ref.watch(chatListControllerProvider);
    final hasStandaloneError =
        chatListState.errorMessage != null &&
        !AppErrorHelper.isNetworkMessage(chatListState.errorMessage);
    final filteredChats = _applyFilters(chatListState.chats, currentUserId);
    final selectionConfig = widget.selectionConfig;
    final inviteBadgeCount = ref.watch(pendingInviteBadgeCountProvider);
    final isGlobalSearchMode =
        !_isSelectionMode && _searchQuery.trim().isNotEmpty;
    final globalSearchQuery = _searchQuery.trim();
    final globalSearchAsync = isGlobalSearchMode
        ? ref.watch(globalSearchResultsProvider(globalSearchQuery))
        : const AsyncData(GlobalSearchResults());

    final isGX = GXThemeExtension.of(context).isGX;

    // Calculate unread counts for badges
    final totalUnreadChats = chatListState.chats
        .where((c) => c.unreadCount > 0)
        .length;
    final unreadGroupsCount = chatListState.chats
        .where((c) => c.isGroup && c.unreadCount > 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        leading: _isDeleteSelectionMode
            ? null
            : _isSelectionMode
            ? const BackButton()
            : null,
        automaticallyImplyLeading: !_isDeleteSelectionMode,
        title: Text(
          _isDeleteSelectionMode
              ? '${_selectedChatIds.length} selected'
              : selectionConfig?.title ?? 'CIPHERCHAT',
          style: isGX
              ? const TextStyle(fontFamily: 'monospace', letterSpacing: 2.0)
              : null,
        ),
        actions: _isDeleteSelectionMode
            ? [
                IconButton(
                  tooltip: 'Delete selected chats',
                  onPressed: _isDeletingSelected
                      ? null
                      : () => _deleteSelectedChats(chatListState.chats),
                  icon: _isDeletingSelected
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: _clearChatSelection,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]
            : _isSelectionMode
            ? null
            : [
                IconButton(
                  tooltip: 'Search users',
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.person_search_rounded),
                ),
                IconButton(
                  tooltip: 'Invites & requests',
                  onPressed: () => context.push('/invites'),
                  icon: _InviteInboxIcon(count: inviteBadgeCount),
                ),
                IconButton(
                  tooltip: 'Menu',
                  onPressed: _openMenuSheet,
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
      ),
      body: Column(
        children: [
          if (_isSelectionMode &&
              selectionConfig?.infoText != null &&
              selectionConfig!.infoText!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share destination'),
                  subtitle: Text(selectionConfig.infoText!.trim()),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, _isSelectionMode ? 12 : 14, 16, 0),
            child: _SearchBar(
              controller: _searchController,
              hasText: _searchInputText.isNotEmpty,
              onChanged: _handleSearchChanged,
              onClear: _clearSearch,
            ),
          ),
          if (!isGlobalSearchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _FilterChips(
                activeFilter: _activeFilter,
                totalUnreadChats: totalUnreadChats,
                unreadGroupsCount: unreadGroupsCount,
                onSelected: (filter) {
                  setState(() => _activeFilter = filter);
                },
              ),
            ),
          if (hasStandaloneError &&
              chatListState.chats.isNotEmpty &&
              !isGlobalSearchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AppErrorCard(
                message: chatListState.errorMessage!,
                actionLabel: 'Retry',
                onAction: () =>
                    ref.read(chatListControllerProvider.notifier).refresh(),
              ),
            ),
          const ConnectivityBodyIndicator(),
          Expanded(
            child: isGlobalSearchMode
                ? globalSearchAsync.when(
                    data: (results) => _GlobalSearchResultsView(
                      query: globalSearchQuery,
                      results: results,
                      pendingContactUserId: _pendingSearchContactId,
                      onMessageTap: _handleGlobalMessageTap,
                      onContactTap: _handleGlobalContactTap,
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: AppErrorCard(
                          message: AppErrorHelper.messageFor(error),
                          actionLabel: 'Retry',
                          onAction: () => ref.invalidate(
                            globalSearchResultsProvider(globalSearchQuery),
                          ),
                        ),
                      ),
                    ),
                  )
                : chatListState.isLoading && chatListState.chats.isEmpty
                ? const ChatListSkeleton()
                : hasStandaloneError && chatListState.chats.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppErrorCard(
                        message: chatListState.errorMessage!,
                        actionLabel: 'Retry',
                        onAction: () => ref
                            .read(chatListControllerProvider.notifier)
                            .refresh(),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(chatListControllerProvider.notifier).refresh(),
                    child: filteredChats.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 120,
                            ),
                            children: [
                              Center(
                                child: _emptyStateContent(
                                  allChats: chatListState.chats,
                                  isGX: isGX,
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                            itemCount: filteredChats.length,
                            itemBuilder: (context, index) {
                              final chat = filteredChats[index];
                              final isSelected = _selectedChatIds.contains(
                                chat.id,
                              );
                              return Padding(
                                key: ValueKey(chat.id),
                                padding: EdgeInsets.only(
                                  bottom: index == filteredChats.length - 1
                                      ? 0
                                      : 12,
                                ),
                                child: ChatTile(
                                  chat: chat,
                                  currentUserId: currentUserId,
                                  typingLabel: chatListState.typingLabelFor(
                                    chat: chat,
                                    currentUserId: currentUserId,
                                  ),
                                  pendingOutgoing: chatListState
                                      .latestPendingFor(chat.id),
                                  isSelected: isSelected,
                                  trailing: _tileTrailing(isSelected),
                                  onTap: () => _handleChatTap(chat),
                                  onLongPress: _isSelectionMode
                                      ? null
                                      : () => _toggleChatSelection(chat),
                                  onAvatarTap: () => _openAvatarModal(
                                    context,
                                    chat,
                                    currentUserId,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _tileTrailing(bool isSelected) {
    if (_isSelectionMode) {
      return const Icon(Icons.chevron_right_rounded);
    }
    if (_isDeleteSelectionMode && isSelected) {
      return const Icon(Icons.check_circle_rounded);
    }
    return null;
  }

  Future<void> _handleChatTap(Chat chat) async {
    final selectionConfig = widget.selectionConfig;
    if (selectionConfig != null) {
      await selectionConfig.onChatSelected(chat);
      return;
    }

    if (_isDeleteSelectionMode) {
      _toggleChatSelection(chat);
      return;
    }

    context.push('/chat/${chat.id}');
  }

  void _handleGlobalMessageTap(GlobalMessageSearchResult result) {
    final route = Uri(
      path: '/chat/${result.chatId}',
      queryParameters: {
        'messageId': result.messageId,
        'search': _searchQuery.trim(),
      },
    );
    context.push(route.toString());
  }

  Future<void> _handleGlobalContactTap(GlobalContactSearchResult result) async {
    setState(() => _pendingSearchContactId = result.userId);

    try {
      final directChatId = result.directChatId?.trim();
      if (directChatId != null && directChatId.isNotEmpty) {
        if (!mounted) {
          return;
        }
        context.push('/chat/$directChatId');
        return;
      }

      final openResult = await ref
          .read(chatActionsProvider)
          .openDirectChat(result.userId);
      if (!mounted) {
        return;
      }

      switch (openResult.outcome) {
        case DirectConversationOutcome.opened:
          final chat = openResult.chat;
          if (chat != null) {
            context.push('/chat/${chat.id}');
          }
          break;
        case DirectConversationOutcome.requestSent:
          _showSnackBar('Chat request sent.');
          break;
        case DirectConversationOutcome.requestAlreadyPending:
          _showSnackBar('A direct chat request is already pending.');
          break;
        case DirectConversationOutcome.blocked:
          _showSnackBar('This user cannot be contacted right now.');
          break;
      }
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _pendingSearchContactId = null);
      }
    }
  }

  void _toggleChatSelection(Chat chat) {
    if (!_canDeleteChat(chat)) {
      _showSnackBar(_deletePermissionMessage(chat));
      return;
    }

    final wasSelected = _selectedChatIds.contains(chat.id);
    if (!wasSelected) {
      HapticFeedback.vibrate();
    }

    setState(() {
      if (wasSelected) {
        _selectedChatIds.remove(chat.id);
      } else {
        _selectedChatIds.add(chat.id);
      }
    });
  }

  void _clearChatSelection() {
    if (_selectedChatIds.isEmpty) {
      return;
    }

    setState(() => _selectedChatIds.clear());
  }

  bool _canDeleteChat(Chat chat) {
    if (!chat.isCurrentUserMember) {
      return false;
    }
    if (chat.isGroup) {
      return chat.isCurrentUserAdmin;
    }
    return true;
  }

  String _deletePermissionMessage(Chat chat) {
    if (chat.isGroup) {
      return 'Only group admins can delete a group chat.';
    }
    return 'This chat cannot be deleted right now.';
  }

  Future<void> _deleteSelectedChats(List<Chat> allChats) async {
    final selectedChats = allChats
        .where((chat) => _selectedChatIds.contains(chat.id))
        .toList(growable: false);
    if (selectedChats.isEmpty) {
      _clearChatSelection();
      return;
    }

    final confirmed = await _confirmDeleteSelectedChats(selectedChats);
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeletingSelected = true);

    final deletedIds = <String>[];
    final failedTitles = <String>[];

    for (final chat in selectedChats) {
      try {
        await ref.read(chatActionsProvider).deleteChat(chat.id);
        deletedIds.add(chat.id);
      } catch (_) {
        failedTitles.add(chat.titleFor(ref.read(currentUserIdProvider)!));
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isDeletingSelected = false;
      _selectedChatIds.removeAll(deletedIds);
    });

    if (_selectedChatIds.isEmpty) {
      _clearChatSelection();
    }

    final deletedCount = deletedIds.length;
    if (deletedCount > 0 && failedTitles.isEmpty) {
      _showSnackBar(
        deletedCount == 1 ? 'Chat deleted.' : '$deletedCount chats deleted.',
      );
      return;
    }

    if (deletedCount > 0) {
      _showSnackBar(
        '$deletedCount chats deleted. ${failedTitles.length} could not be deleted.',
      );
      return;
    }

    _showSnackBar('Selected chats could not be deleted.');
  }

  Future<bool?> _confirmDeleteSelectedChats(List<Chat> chats) {
    final hasDirectChats = chats.any((chat) => !chat.isGroup);
    final hasGroupChats = chats.any((chat) => chat.isGroup);
    final lines = <String>[
      'This will permanently delete the selected chats from CipherChat.',
      if (hasDirectChats) 'Direct chats will disappear for both participants.',
      if (hasGroupChats) 'Group chats will disappear for all members.',
    ];

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            chats.length == 1
                ? 'Delete selected chat?'
                : 'Delete selected chats?',
          ),
          content: Text(lines.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _openAvatarModal(BuildContext context, Chat chat, String currentUserId) {
    if (chat.isGroup) {
      ProfileImageModal.show(
        context,
        imageUrl: chat.groupImageUrl,
        avatarId: null,
        title: chat.titleFor(currentUserId),
        heroTag: 'chat-list-group-${chat.id}',
        storageBucket: AppConstants.groupImagesBucket,
        useSignedUrl: true,
      );
      return;
    }

    ProfileImageModal.show(
      context,
      imageUrl: chat.profileImageUrlFor(currentUserId),
      avatarId: chat.avatarIdFor(currentUserId),
      title: chat.titleFor(currentUserId),
      heroTag: 'chat-list-user-${chat.id}',
    );
  }

  List<Chat> _applyFilters(List<Chat> chats, String currentUserId) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return chats
        .where((chat) {
          final matchesFilter = switch (_activeFilter) {
            _ChatListFilter.all => true,
            _ChatListFilter.unread => chat.unreadCount > 0,
            _ChatListFilter.groups => chat.isGroup,
          };
          if (!matchesFilter) {
            return false;
          }

          if (normalizedQuery.isEmpty) {
            return true;
          }

          final title = chat.titleFor(currentUserId).toLowerCase();
          final subtitle = chat.subtitleFor(currentUserId).toLowerCase();
          final lastPreview =
              chat.latestMessage?.previewLabel.toLowerCase() ?? '';
          return title.contains(normalizedQuery) ||
              subtitle.contains(normalizedQuery) ||
              lastPreview.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Widget _emptyStateContent({
    required List<Chat> allChats,
    required bool isGX,
  }) {
    final textStyle = isGX ? const TextStyle(fontFamily: 'monospace') : null;

    if (_searchQuery.trim().isNotEmpty) {
      return Text(
        'No chats match your search yet.',
        textAlign: TextAlign.center,
        style: textStyle,
      );
    }

    if (_isSelectionMode) {
      return Text(
        widget.selectionConfig!.emptyStateText,
        textAlign: TextAlign.center,
        style: textStyle,
      );
    }

    switch (_activeFilter) {
      case _ChatListFilter.all:
        return _EmptyChatListAction(
          message: 'No chats yet. Start a secure conversation.',
          buttonLabel: 'Find Friends',
          icon: Icons.person_search_rounded,
          textStyle: textStyle,
          onPressed: () => context.push('/search'),
        );
      case _ChatListFilter.groups:
        if (allChats.isEmpty) {
          return _EmptyChatListAction(
            message:
                'No group chats yet. Add a friend to create a group chat with them.',
            buttonLabel: 'Find Friends',
            icon: Icons.person_search_rounded,
            textStyle: textStyle,
            onPressed: () => context.push('/search'),
          );
        }

        return _EmptyChatListAction(
          message: 'No group chats yet. Create a group to add friend.',
          buttonLabel: 'Create Group',
          icon: Icons.group_add_rounded,
          textStyle: textStyle,
          onPressed: _createGroupFromEmptyState,
        );
      case _ChatListFilter.unread:
        return Text(
          'No unread chats right now.',
          textAlign: TextAlign.center,
          style: textStyle,
        );
    }
  }

  Future<void> _createGroupFromEmptyState() async {
    try {
      final chat = await ref.read(chatActionsProvider).createGroup();
      if (mounted) {
        context.push('/group/${chat.id}');
      }
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchInputText = value);
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }
      setState(() => _searchQuery = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchInputText = '';
      _searchQuery = '';
    });
  }

  Future<void> _openMenuSheet() async {
    final action = await showModalBottomSheet<_ChatMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (modalContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AttachmentCard(
                  onTap: () => Navigator.of(
                    modalContext,
                  ).pop(_ChatMenuAction.startDirect),
                  icon: Icons.person_search_rounded,
                  title: 'Start 1v1 Chat',
                  subtitle: 'Search users and open a secure direct chat.',
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  onTap: () => Navigator.of(
                    modalContext,
                  ).pop(_ChatMenuAction.createGroup),
                  icon: Icons.group_add_rounded,
                  title: 'Create Group',
                  subtitle: 'Create a group chat and invite members later.',
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  onTap: () =>
                      Navigator.of(modalContext).pop(_ChatMenuAction.settings),
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Profile, preferences, and app security options.',
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  onTap: () =>
                      Navigator.of(modalContext).pop(_ChatMenuAction.signOut),
                  icon: Icons.logout_rounded,
                  title: 'Sign Out',
                  subtitle: 'Leave your current session on this device.',
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ChatMenuAction.startDirect:
        context.push('/search');
        break;
      case _ChatMenuAction.createGroup:
        final chat = await ref.read(chatActionsProvider).createGroup();
        if (mounted) {
          context.push('/group/${chat.id}');
        }
        break;
      case _ChatMenuAction.settings:
        context.push('/settings');
        break;
      case _ChatMenuAction.signOut:
        await ref.read(authControllerProvider.notifier).signOut();
        break;
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
}

class _EmptyChatListAction extends StatelessWidget {
  const _EmptyChatListAction({
    required this.message,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
    this.textStyle,
  });

  final String message;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: textStyle),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _InviteInboxIcon extends StatelessWidget {
  const _InviteInboxIcon({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeLabel = count > 99 ? '99+' : '$count';

    final isGX = GXThemeExtension.of(context).isGX;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.mark_email_unread_outlined),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFamily: isGX ? 'monospace' : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GlobalSearchResultsView extends StatelessWidget {
  const _GlobalSearchResultsView({
    required this.query,
    required this.results,
    required this.pendingContactUserId,
    required this.onMessageTap,
    required this.onContactTap,
  });

  final String query;
  final GlobalSearchResults results;
  final String? pendingContactUserId;
  final ValueChanged<GlobalMessageSearchResult> onMessageTap;
  final ValueChanged<GlobalContactSearchResult> onContactTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
        children: const [Center(child: Text('No results found'))],
      );
    }

    final items = <Widget>[];
    if (results.messages.isNotEmpty) {
      items.add(const _SearchSectionHeader(title: 'MESSAGES'));
      items.addAll(
        results.messages.map(
          (result) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MessageSearchResultTile(
              result: result,
              query: query,
              onTap: () => onMessageTap(result),
            ),
          ),
        ),
      );
    }

    if (results.contacts.isNotEmpty) {
      if (items.isNotEmpty) {
        items.add(const SizedBox(height: 12));
      }
      items.add(const _SearchSectionHeader(title: 'CONTACTS'));
      items.addAll(
        results.contacts.map(
          (result) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ContactSearchResultTile(
              result: result,
              query: query,
              isBusy: pendingContactUserId == result.userId,
              onTap: () => onContactTap(result),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: items,
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
          fontFamily: isGX ? 'monospace' : null,
          letterSpacing: isGX ? 1.5 : null,
        ),
      ),
    );
  }
}

class _MessageSearchResultTile extends StatelessWidget {
  const _MessageSearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  final GlobalMessageSearchResult result;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          child: Icon(
            result.isGroup ? Icons.groups_rounded : Icons.chat_bubble_rounded,
          ),
        ),
        title: Text(
          isGX ? result.chatLabel.toUpperCase() : result.chatLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isGX
              ? const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              result.senderUsername,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontFamily: isGX ? 'monospace' : null,
              ),
            ),
            const SizedBox(height: 4),
            HighlightedText(
              text: result.snippet.isEmpty ? result.searchText : result.snippet,
              query: query,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: isGX ? 'monospace' : null,
              ),
              highlightStyle: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                backgroundColor: Colors.amber.withValues(alpha: 0.55),
                fontFamily: isGX ? 'monospace' : null,
              ),
            ),
          ],
        ),
        trailing: Text(
          TimeOfDay.fromDateTime(result.createdAt).format(context),
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: isGX ? 'monospace' : null,
          ),
        ),
      ),
    );
  }
}

class _ContactSearchResultTile extends StatelessWidget {
  const _ContactSearchResultTile({
    required this.result,
    required this.query,
    required this.isBusy,
    required this.onTap,
  });

  final GlobalContactSearchResult result;
  final String query;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;
    final subtitle = result.sharedChatCount > 0
        ? '${result.sharedChatCount} shared chats'
        : 'Start a secure direct chat';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        onTap: isBusy ? null : onTap,
        leading: AppAvatar(size: 48, avatarId: result.avatarId),
        title: HighlightedText(
          text: result.username,
          query: query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFamily: isGX ? 'monospace' : null,
          ),
          highlightStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            backgroundColor: Colors.amber.withValues(alpha: 0.55),
            fontFamily: isGX ? 'monospace' : null,
          ),
        ),
        subtitle: Text(
          isGX ? subtitle.toUpperCase() : subtitle,
          style: isGX
              ? const TextStyle(fontFamily: 'monospace', fontSize: 11)
              : null,
        ),
        trailing: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: isGX ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        hintText: isGX ? 'SEARCH YOUR CHATS' : 'Search your chats',
        hintStyle: isGX ? const TextStyle(fontFamily: 'monospace') : null,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: !hasText
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isGX ? 8 : 20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isGX ? 8 : 20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isGX ? 8 : 20),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.activeFilter,
    required this.onSelected,
    required this.totalUnreadChats,
    required this.unreadGroupsCount,
  });

  final _ChatListFilter activeFilter;
  final ValueChanged<_ChatListFilter> onSelected;
  final int totalUnreadChats;
  final int unreadGroupsCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, right: 8),
        child: Row(
          children: [
            _FilterChipButton(
              label: 'All',
              isSelected: activeFilter == _ChatListFilter.all,
              onTap: () => onSelected(_ChatListFilter.all),
            ),
            const SizedBox(width: 14),
            _FilterChipButton(
              label: 'Unread',
              isSelected: activeFilter == _ChatListFilter.unread,
              onTap: () => onSelected(_ChatListFilter.unread),
              badgeCount: totalUnreadChats,
            ),
            const SizedBox(width: 14),
            _FilterChipButton(
              label: 'Groups',
              isSelected: activeFilter == _ChatListFilter.groups,
              onTap: () => onSelected(_ChatListFilter.groups),
              badgeCount: unreadGroupsCount,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    Widget chip = FilterChip(
      selected: isSelected,
      label: Text(isGX ? label.toUpperCase() : label),
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.18),
      backgroundColor: theme.colorScheme.surfaceContainer,
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.45)
            : theme.colorScheme.outlineVariant,
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontFamily: isGX ? 'monospace' : null,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isGX ? 4 : 999),
      ),
    );

    if (badgeCount > 0) {
      return Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: TextStyle(
            fontFamily: isGX ? 'monospace' : null,
            fontWeight: FontWeight.bold,
            fontSize: 9,
          ),
        ),
        backgroundColor: isGX ? accent : theme.colorScheme.primary,
        textColor: isGX ? const Color(0xFF0B0B14) : theme.colorScheme.onPrimary,
        offset: const Offset(4, -4),
        child: chip,
      );
    }

    return chip;
  }
}
