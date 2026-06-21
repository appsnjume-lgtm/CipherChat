import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/widgets/profile_image_modal.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_member.dart';
import '../providers/chat_provider.dart';

class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key, this.inviteChatId});

  final String? inviteChatId;

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _controller = TextEditingController();
  String? _pendingUserId;

  @override
  void dispose() {
    ref.read(searchQueryProvider.notifier).state = '';
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(userSearchResultsProvider);
    final isInviteMode = widget.inviteChatId != null;
    final currentUserId = ref.watch(currentUserIdProvider);
    var existingGroupMemberIds = <String>{};

    if (isInviteMode) {
      final groupDetails = ref.watch(chatDetailsProvider(widget.inviteChatId!));
      existingGroupMemberIds = groupDetails.maybeWhen(
        data: (chat) => chat.members.map((member) => member.userId).toSet(),
        orElse: () => <String>{},
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isInviteMode ? 'Invite People' : 'Search Users'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                labelText: isInviteMode
                    ? 'Search users to invite'
                    : 'Search users by username',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            if (isInviteMode && currentUserId != null) ...[
              const SizedBox(height: 16),
              _ExistingChatsInviteSection(
                currentUserId: currentUserId,
                existingGroupMemberIds: existingGroupMemberIds,
                pendingUserId: _pendingUserId,
                onInvite: (userId) => _handleTap(context, userId),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: results.when(
                data: (users) {
                  if (users.isEmpty) {
                    return const Center(
                      child: Text('No matching users found.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final isBusy = _pendingUserId == user.id;

                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: InkWell(
                            onTap: () => ProfileImageModal.show(
                              context,
                              imageUrl: user.profileImageUrl,
                              avatarId: user.avatarId,
                              title: user.username,
                              heroTag: 'search-user-${user.id}',
                            ),
                            borderRadius: BorderRadius.circular(999),
                            child: Hero(
                              tag: 'search-user-${user.id}',
                              child: AppAvatar(
                                size: 48,
                                avatarId: user.avatarId,
                                imageUrl: user.profileImageUrl,
                              ),
                            ),
                          ),
                          title: Text(user.displayNameOrUsername),
                          subtitle: Text(_subtitleFor(user, isInviteMode)),
                          trailing: isBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton(
                                      onPressed: () =>
                                          _handleTap(context, user.id),
                                      child: Text(
                                        isInviteMode ? 'Invite' : 'Chat',
                                      ),
                                    ),
                                    if (!isInviteMode)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'block') {
                                            _blockUser(context, user);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem<String>(
                                            value: 'block',
                                            child: Text('Block user'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const SearchResultsSkeleton(),
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppErrorCard(
                      message: AppErrorHelper.messageFor(error),
                      actionLabel: 'Retry',
                      onAction: () => ref.invalidate(userSearchResultsProvider),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(AppUser user, bool isInviteMode) {
    final privacy = user.accountPrivacy == AccountPrivacy.private
        ? 'Private account'
        : 'Public account';
    final bio = user.bio.trim();

    final handle = user.usernameHandle;
    final detail = bio.isEmpty ? privacy : '$privacy - $bio';

    return isInviteMode ? '$handle - $detail' : '$handle - $detail';
  }

  Future<void> _blockUser(BuildContext context, AppUser user) async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(chatRepositoryProvider)
          .blockUser(blockerId: currentUserId, blockedUserId: user.id);
      ref.invalidate(blockedUsersProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${user.username} blocked.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppErrorHelper.messageFor(error))),
      );
    }
  }

  Future<void> _handleTap(BuildContext context, String userId) async {
    setState(() => _pendingUserId = userId);

    try {
      if (widget.inviteChatId != null) {
        await ref
            .read(chatActionsProvider)
            .inviteUser(chatId: widget.inviteChatId!, targetUserId: userId);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invite sent.')));
          Navigator.of(context).pop();
        }
      } else {
        final result = await ref
            .read(chatActionsProvider)
            .openDirectChat(userId);
        if (!context.mounted) {
          return;
        }

        switch (result.outcome) {
          case DirectConversationOutcome.opened:
            final chat = result.chat;
            if (chat != null) {
              context.push('/chat/${chat.id}');
            }
            break;
          case DirectConversationOutcome.requestSent:
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Chat request sent.')));
            break;
          case DirectConversationOutcome.requestAlreadyPending:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('A direct chat request is already pending.'),
              ),
            );
            break;
          case DirectConversationOutcome.blocked:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This user cannot be contacted right now.'),
              ),
            );
            break;
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHelper.messageFor(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingUserId = null);
      }
    }
  }
}

class _ExistingChatsInviteSection extends ConsumerWidget {
  const _ExistingChatsInviteSection({
    required this.currentUserId,
    required this.existingGroupMemberIds,
    required this.pendingUserId,
    required this.onInvite,
  });

  final String currentUserId;
  final Set<String> existingGroupMemberIds;
  final String? pendingUserId;
  final ValueChanged<String> onInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatListState = ref.watch(chatListControllerProvider);
    final candidates = _inviteCandidates(
      chats: chatListState.chats,
      currentUserId: currentUserId,
      existingGroupMemberIds: existingGroupMemberIds,
    );

    if (chatListState.isLoading && candidates.isEmpty) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'From your chats',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (candidates.isEmpty)
              Text(
                'No one from your direct chats is available to invite.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    final member = candidate.member;
                    final isBusy = pendingUserId == member.userId;
                    final username = member.displayNameOrUsername;
                    final subtitle = member.bioPreview?.trim();

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: InkWell(
                        onTap: () => ProfileImageModal.show(
                          context,
                          imageUrl: member.profileImageUrl,
                          avatarId: member.avatarId,
                          title: username,
                          heroTag: 'invite-chat-user-${member.userId}',
                        ),
                        borderRadius: BorderRadius.circular(999),
                        child: Hero(
                          tag: 'invite-chat-user-${member.userId}',
                          child: AppAvatar(
                            size: 44,
                            avatarId: member.avatarId,
                            imageUrl: member.profileImageUrl,
                            isOnline: member.isOnline,
                          ),
                        ),
                      ),
                      title: Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitle == null || subtitle.isEmpty
                            ? member.usernameHandle ?? candidate.chat.titleFor(currentUserId)
                            : '${member.usernameHandle ?? candidate.chat.titleFor(currentUserId)} - $subtitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton(
                              onPressed: () => onInvite(member.userId),
                              child: const Text('Invite'),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_InviteCandidate> _inviteCandidates({
    required List<Chat> chats,
    required String currentUserId,
    required Set<String> existingGroupMemberIds,
  }) {
    final candidatesByUserId = <String, _InviteCandidate>{};

    for (final chat in chats) {
      if (chat.isGroup) {
        continue;
      }

      final member = chat.otherMemberFor(currentUserId);
      if (member == null || existingGroupMemberIds.contains(member.userId)) {
        continue;
      }

      candidatesByUserId.putIfAbsent(
        member.userId,
        () => _InviteCandidate(chat: chat, member: member),
      );
    }

    return candidatesByUserId.values.toList(growable: false);
  }
}

class _InviteCandidate {
  const _InviteCandidate({required this.chat, required this.member});

  final Chat chat;
  final ChatMember member;
}
