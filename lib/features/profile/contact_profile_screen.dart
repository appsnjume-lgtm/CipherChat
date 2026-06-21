import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/app_error_helper.dart';
import '../../core/widgets/app_error_card.dart';
import '../../core/widgets/no_internet_overlay.dart';
import '../auth/domain/entities/app_user.dart';
import '../auth/presentation/providers/auth_provider.dart';
import '../chat/data/repositories/chat_repository.dart';
import '../chat/presentation/providers/chat_provider.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'contact_profile_repository.dart';
import 'widgets/encryption_banner.dart';
import 'widgets/profile_actions.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_image_modal.dart';
import 'widgets/profile_info_section.dart';

final contactProfileProvider = FutureProvider.autoDispose
    .family<ContactProfileData, String>((ref, userId) async {
      final currentUserId = ref.watch(currentUserIdProvider);
      if (currentUserId == null) {
        throw StateError('No authenticated user found.');
      }

      return ref
          .watch(contactProfileRepositoryProvider)
          .fetchContactProfile(
            currentUserId: currentUserId,
            contactUserId: userId,
          );
    });

enum _ContactProfileMenuAction { block, report }

class ContactProfileScreen extends ConsumerWidget {
  const ContactProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(contactProfileProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Profile'),
        actions: [
          PopupMenuButton<_ContactProfileMenuAction>(
            onSelected: (action) => _handleMenuAction(context, ref, action),
            itemBuilder: (context) => const [
              PopupMenuItem<_ContactProfileMenuAction>(
                value: _ContactProfileMenuAction.block,
                child: Text('Block user'),
              ),
              PopupMenuItem<_ContactProfileMenuAction>(
                value: _ContactProfileMenuAction.report,
                child: Text('Report user'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBodyIndicator(),
          Expanded(
            child: profileAsync.when(
              data: (data) {
                final heroTag = 'contact-profile-${data.user.id}';
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ProfileHeader(
                      displayName: data.user.displayNameOrUsername,
                      username: data.user.username,
                      statusLabel: _statusLabel(data),
                      imageUrl: data.user.profileImageUrl,
                      avatarId: data.user.avatarId,
                      isOnline: data.user.isOnline,
                      heroTag: heroTag,
                      onAvatarTap: () => ProfileImageModal.show(
                        context,
                        imageUrl: data.user.profileImageUrl,
                        avatarId: data.user.avatarId,
                        title: data.user.displayNameOrUsername,
                        heroTag: heroTag,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const EncryptionBanner(),
                    const SizedBox(height: 16),
                    ProfileInfoSection(
                      gender: data.visibleGender,
                      bio: data.visibleBio,
                      isGenderVisible: data.canViewGender,
                      isBioVisible: data.canViewAbout,
                    ),
                    const SizedBox(height: 18),
                    ProfileActions(
                      label: data.actionLabel,
                      isEnabled: data.isActionEnabled,
                      helperText: _actionHelperText(data),
                      onPressed: () => _handlePrimaryAction(context, ref, data),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppErrorCard(
                    message: AppErrorHelper.messageFor(error),
                    actionLabel: 'Retry',
                    onAction: () =>
                        ref.invalidate(contactProfileProvider(userId)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ContactProfileData data) {
    if (!data.canViewLastSeen) {
      return 'Hidden';
    }

    if (data.user.isOnline) {
      return 'Online';
    }

    final lastSeen = data.visibleLastSeen;
    if (lastSeen == null) {
      return 'Offline';
    }

    return 'Last seen ${DateFormat('dd MMM, HH:mm').format(lastSeen)}';
  }

  String? _actionHelperText(ContactProfileData data) {
    switch (data.actionState) {
      case ContactProfileActionState.blocked:
        return 'Chat is unavailable while either user is blocked.';
      case ContactProfileActionState.pending:
        return 'A direct chat request is already waiting for approval.';
      case ContactProfileActionState.requestChat:
        return data.user.accountPrivacy == AccountPrivacy.private
            ? 'This account is private, so a request is required before chat opens.'
            : null;
      case ContactProfileActionState.chat:
        return null;
    }
  }

  Future<void> _handlePrimaryAction(
    BuildContext context,
    WidgetRef ref,
    ContactProfileData data,
  ) async {
    try {
      final result = await ref
          .read(chatActionsProvider)
          .openDirectChat(data.user.id);
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
          ref.invalidate(contactProfileProvider(userId));
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Chat request sent.')));
          break;
        case DirectConversationOutcome.requestAlreadyPending:
          ref.invalidate(contactProfileProvider(userId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A direct chat request is already pending.'),
            ),
          );
          break;
        case DirectConversationOutcome.blocked:
          ref.invalidate(contactProfileProvider(userId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This user cannot be contacted right now.'),
            ),
          );
          break;
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHelper.messageFor(error))),
        );
      }
    }
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    _ContactProfileMenuAction action,
  ) async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    try {
      switch (action) {
        case _ContactProfileMenuAction.block:
          await ref
              .read(chatRepositoryProvider)
              .blockUser(blockerId: currentUserId, blockedUserId: userId);
          ref.invalidate(chatListProvider);
          ref.invalidate(blockedUsersProvider);
          ref.invalidate(contactProfileProvider(userId));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('User blocked.')));
          }
          break;
        case _ContactProfileMenuAction.report:
          await ref
              .read(contactProfileRepositoryProvider)
              .reportUser(reporterId: currentUserId, reportedUserId: userId);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('User reported.')));
          }
          break;
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHelper.messageFor(error))),
        );
      }
    }
  }
}
