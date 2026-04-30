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
                          title: Text(user.username),
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

    if (isInviteMode) {
      return bio.isEmpty ? privacy : '$privacy - $bio';
    }

    return bio.isEmpty ? privacy : bio;
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
