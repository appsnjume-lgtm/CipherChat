import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../common/widgets/app_avatar.dart';
import '../../../../../core/services/connectivity_service.dart';
import '../../../../../core/utils/date_helper.dart';
import '../../../domain/entities/chat.dart';
import '../../providers/chat_provider.dart';

class ChatHeader extends ConsumerWidget {
  const ChatHeader({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onAvatarTap,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final participant = chat.otherMemberFor(currentUserId);
    final isOnline = ref
        .watch(connectivityStatusProvider)
        .maybeWhen(data: (value) => value, orElse: () => true);

    final typingLabel = ref
        .watch(chatListControllerProvider)
        .typingLabelFor(chat: chat, currentUserId: currentUserId);

    if (!chat.isGroup && participant != null) {
      final subtitle =
          typingLabel ??
          (!isOnline
              ? 'Waiting for network...'
              : participant.isOnline
              ? 'Online'
              : participant.lastSeenAt != null
              ? 'Last seen ${DateHelper.formatLastSeen(participant.lastSeenAt!)}'
              : 'Offline');

      return Row(
        children: [
          InkWell(
            onTap: onAvatarTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AppAvatar(
                size: 38,
                avatarId: participant.avatarId ?? 'avatar_1',
                imageUrl: participant.profileImageUrl,
                isOnline: participant.isOnline && isOnline,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  participant.username ?? 'Chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: typingLabel != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                    fontWeight: typingLabel != null
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        AppAvatar(
          size: 38,
          avatarId: null,
          imageUrl: chat.groupImageUrl,
          fallbackIcon: Icons.groups_rounded,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                chat.titleFor(currentUserId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                typingLabel ?? '${chat.members.length} members',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: typingLabel != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                  fontWeight: typingLabel != null
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HeaderText extends StatelessWidget {
  const HeaderText({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
