import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_helper.dart';
import '../../application/models/pending_outgoing_message_record.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_member.dart';
import '../../domain/entities/message.dart';

class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onTap,
    required this.onAvatarTap,
    this.onLongPress,
    this.trailing,
    this.typingLabel,
    this.pendingOutgoing,
    this.isSelected = false,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final String? typingLabel;
  final PendingOutgoingMessageRecord? pendingOutgoing;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGX = GXThemeExtension.of(context).isGX;
    final latest = chat.latestMessage;
    final title = chat.titleFor(currentUserId);
    final effectiveTime = _effectiveTime(latest);
    final hasUnread = chat.unreadCount > 0;
    final showTyping = typingLabel != null && typingLabel!.trim().isNotEmpty;
    final otherMember = chat.otherMemberFor(currentUserId);
    final hasPendingPreview = _hasPendingPreview(latest);

    if (isGX) {
      return _GXChatTile(
        chat: chat,
        title: title,
        effectiveTime: effectiveTime,
        hasUnread: hasUnread,
        showTyping: showTyping,
        typingLabel: typingLabel,
        otherMember: otherMember,
        hasPendingPreview: hasPendingPreview,
        latest: latest,
        currentUserId: currentUserId,
        isSelected: isSelected,
        onTap: onTap,
        onAvatarTap: onAvatarTap,
        onLongPress: onLongPress,
        trailing: trailing,
        accent: GXThemeExtension.of(context).accent,
        pendingOutgoing: pendingOutgoing,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.72)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: onTap,
          onLongPress: onLongPress,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          leading: _ChatAvatar(
            chat: chat,
            otherMember: otherMember,
            onAvatarTap: onAvatarTap,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: showTyping
                ? Text(
                    typingLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : _PreviewRow(
                    latestMessage: latest,
                    currentUserId: currentUserId,
                    text: _subtitleFor(latest),
                    forceSendingState: hasPendingPreview,
                    textStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.88)
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: hasUnread
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
          ),
          trailing:
              trailing ??
              _ChatTileTrailing(
                timeLabel: effectiveTime,
                unreadCount: chat.unreadCount,
              ),
        ),
      ),
    );
  }

  bool _hasPendingPreview(Message? latest) {
    final pending = pendingOutgoing;
    if (pending == null) {
      return false;
    }
    if (latest == null) {
      return true;
    }
    if (latest.id == pending.messageId) {
      return true;
    }
    return !pending.createdAt.isBefore(latest.createdAt);
  }

  String? _effectiveTime(Message? latest) {
    if (_hasPendingPreview(latest)) {
      return DateHelper.formatMessageTime(pendingOutgoing!.createdAt);
    }
    if (latest == null) {
      return null;
    }
    return DateHelper.formatMessageTime(latest.createdAt);
  }

  String _subtitleFor(Message? latest) {
    if (_hasPendingPreview(latest)) {
      final preview = _pendingPreviewText(pendingOutgoing!);
      if (!chat.isGroup) {
        return preview;
      }
      return 'You: $preview';
    }

    if (latest == null) {
      return chat.subtitleFor(currentUserId);
    }

    final cachedPreview = chat.latestMessagePreviewText?.trim();
    final preview = cachedPreview != null && cachedPreview.isNotEmpty
        ? cachedPreview
        : latest.previewLabel;
    if (!chat.isGroup) {
      return preview;
    }

    String? sender;
    for (final member in chat.members) {
      if (member.userId != latest.senderId) {
        continue;
      }
      sender = member.userId == currentUserId
          ? 'You'
          : (member.username?.trim().isNotEmpty ?? false)
          ? member.username!.trim()
          : 'Member';
      break;
    }

    if (sender == null || sender.isEmpty) {
      return preview;
    }

    return '$sender: $preview';
  }

  String _pendingPreviewText(PendingOutgoingMessageRecord pending) {
    switch (pending.kind) {
      case MessageKind.text:
        return pending.text?.trim().isNotEmpty ?? false
            ? pending.text!.trim()
            : 'Message';
      case MessageKind.image:
        return 'Photo';
      case MessageKind.video:
        return 'Video';
      case MessageKind.audio:
        return 'Audio message';
      case MessageKind.sticker:
        return 'Sticker';
      case MessageKind.file:
        final fileName = pending.fileNameOverride?.trim();
        if (fileName != null && fileName.isNotEmpty) {
          return fileName;
        }
        final path = pending.localPath?.trim();
        if (path != null && path.isNotEmpty) {
          return p.basename(path);
        }
        return 'File';
      case MessageKind.grid_breach:
        return 'GRID BREACH';
    }
  }
}

class _GXChatTile extends StatelessWidget {
  const _GXChatTile({
    required this.chat,
    required this.title,
    required this.effectiveTime,
    required this.hasUnread,
    required this.showTyping,
    required this.typingLabel,
    required this.otherMember,
    required this.hasPendingPreview,
    required this.latest,
    required this.currentUserId,
    required this.isSelected,
    required this.onTap,
    required this.onAvatarTap,
    required this.accent,
    this.onLongPress,
    this.trailing,
    this.pendingOutgoing,
  });

  final Chat chat;
  final String title;
  final String? effectiveTime;
  final bool hasUnread;
  final bool showTyping;
  final String? typingLabel;
  final ChatMember? otherMember;
  final bool hasPendingPreview;
  final Message? latest;
  final String currentUserId;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Color accent;
  final PendingOutgoingMessageRecord? pendingOutgoing;

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF0F0F8);
    const textSecondary = Color(0xFF8888AA);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: CustomPaint(
          painter: _GXTilePainter(
            accent: accent,
            isSelected: isSelected,
            hasUnread: hasUnread,
          ),
          child: ClipPath(
            clipper: _GXTileClipper(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.surface,
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(56, 56),
                        painter: _GXAvatarFramePainter(
                          accent: accent,
                          isOnline:
                              !chat.isGroup && (otherMember?.isOnline ?? false),
                          hasUnread: hasUnread,
                        ),
                      ),
                      ClipPath(
                        clipper: _HexagonClipper(),
                        child: AppAvatar(
                          size: 52,
                          avatarId: otherMember?.avatarId ?? 'avatar_1',
                          imageUrl: chat.isGroup
                              ? chat.groupImageUrl
                              : otherMember?.profileImageUrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: hasUnread ? accent : textPrimary,
                                ),
                              ),
                            ),
                            if (effectiveTime != null)
                              Text(
                                effectiveTime!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: hasUnread ? accent : textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: showTyping
                                  ? Text(
                                      typingLabel!.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : _GXPreviewRow(
                                      latestMessage: latest,
                                      currentUserId: currentUserId,
                                      text: _subtitleForGX(),
                                      forceSendingState: hasPendingPreview,
                                      accent: accent,
                                      textStyle: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: hasUnread
                                            ? textPrimary
                                            : textSecondary,
                                      ),
                                    ),
                            ),
                            if (hasUnread)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  '${chat.unreadCount}',
                                  style: const TextStyle(
                                    color: Color(0xFF12121E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            if (trailing != null) trailing!,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleForGX() {
    if (hasPendingPreview && pendingOutgoing != null) {
      final preview = _pendingPreviewTextGX(pendingOutgoing!);
      if (!chat.isGroup) {
        return preview;
      }
      return 'YOU: $preview';
    }

    if (latest == null) {
      return chat.subtitleFor(currentUserId).toUpperCase();
    }

    final cachedPreview = chat.latestMessagePreviewText?.trim();
    final preview = cachedPreview != null && cachedPreview.isNotEmpty
        ? cachedPreview
        : latest!.previewLabel;
    if (!chat.isGroup) {
      return preview;
    }

    String? sender;
    for (final member in chat.members) {
      if (member.userId != latest!.senderId) {
        continue;
      }
      sender = member.userId == currentUserId
          ? 'YOU'
          : (member.username?.trim().isNotEmpty ?? false)
          ? member.username!.trim().toUpperCase()
          : 'MEMBER';
      break;
    }

    if (sender == null || sender.isEmpty) {
      return preview;
    }

    return '$sender: $preview';
  }

  String _pendingPreviewTextGX(PendingOutgoingMessageRecord pending) {
    switch (pending.kind) {
      case MessageKind.text:
        return pending.text?.trim().isNotEmpty ?? false
            ? pending.text!.trim().toUpperCase()
            : 'MESSAGE';
      case MessageKind.image:
        return 'PHOTO';
      case MessageKind.video:
        return 'VIDEO';
      case MessageKind.audio:
        return 'AUDIO MESSAGE';
      case MessageKind.sticker:
        return 'STICKER';
      case MessageKind.file:
        final fileName = pending.fileNameOverride?.trim();
        if (fileName != null && fileName.isNotEmpty) {
          return fileName.toUpperCase();
        }
        final path = pending.localPath?.trim();
        if (path != null && path.isNotEmpty) {
          return p.basename(path).toUpperCase();
        }
        return 'FILE';
      case MessageKind.grid_breach:
        return 'GRID BREACH';
    }
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.chat,
    required this.otherMember,
    required this.onAvatarTap,
  });

  final Chat chat;
  final ChatMember? otherMember;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAvatarTap,
      borderRadius: BorderRadius.circular(999),
      child: Hero(
        tag: chat.isGroup
            ? 'chat-list-group-${chat.id}'
            : 'chat-list-user-${chat.id}',
        child: chat.isGroup
            ? AppAvatar(
                size: 52,
                avatarId: null,
                imageUrl: chat.groupImageUrl,
                storageBucket: AppConstants.groupImagesBucket,
                useSignedUrl: true,
                fallbackIcon: Icons.groups_rounded,
              )
            : AppAvatar(
                size: 52,
                avatarId: otherMember?.avatarId ?? 'avatar_1',
                imageUrl: otherMember?.profileImageUrl,
                isOnline: otherMember?.isOnline ?? false,
              ),
      ),
    );
  }
}

class _GXTilePainter extends CustomPainter {
  const _GXTilePainter({
    required this.accent,
    required this.isSelected,
    required this.hasUnread,
  });

  final Color accent;
  final bool isSelected;
  final bool hasUnread;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isSelected ? accent : accent.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 1.2 : 0.8;

    final path = Path();
    const cut = 8.0;
    path.moveTo(cut, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height - cut);
    path.lineTo(size.width - cut, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, cut);
    path.close();

    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.05)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(path, paint);

    if (hasUnread || isSelected) {
      final accentPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, cut, 3, size.height - cut * 2),
        accentPaint,
      );

      if (hasUnread) {
        canvas.drawRect(
          Rect.fromLTWH(-1, cut, 4, size.height - cut * 2),
          Paint()
            ..color = accent.withValues(alpha: 0.3)
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GXTilePainter old) =>
      old.accent != accent ||
      old.isSelected != isSelected ||
      old.hasUnread != hasUnread;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.latestMessage,
    required this.currentUserId,
    required this.text,
    required this.textStyle,
    required this.forceSendingState,
  });

  final Message? latestMessage;
  final String currentUserId;
  final String text;
  final TextStyle? textStyle;
  final bool forceSendingState;

  @override
  Widget build(BuildContext context) {
    final latest = latestMessage;
    final showStatus =
        forceSendingState ||
        (latest != null && latest.senderId == currentUserId);

    return Row(
      children: [
        if (showStatus)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _MessageStatusIcon(
              state: forceSendingState
                  ? MessageDeliveryState.sending
                  : latest!.deliveryStateFor(currentUserId),
            ),
          ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _GXPreviewRow extends StatelessWidget {
  const _GXPreviewRow({
    required this.latestMessage,
    required this.currentUserId,
    required this.text,
    required this.textStyle,
    required this.forceSendingState,
    required this.accent,
  });

  final Message? latestMessage;
  final String currentUserId;
  final String text;
  final TextStyle? textStyle;
  final bool forceSendingState;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final latest = latestMessage;
    final showStatus =
        forceSendingState ||
        (latest != null && latest.senderId == currentUserId);

    return Row(
      children: [
        if (showStatus)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _GXMessageStatusIcon(
              state: forceSendingState
                  ? MessageDeliveryState.sending
                  : latest!.deliveryStateFor(currentUserId),
              accent: accent,
            ),
          ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _ChatTileTrailing extends StatelessWidget {
  const _ChatTileTrailing({required this.timeLabel, required this.unreadCount});

  final String? timeLabel;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (timeLabel == null && unreadCount <= 0) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timeLabel != null)
            Text(
              timeLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: unreadCount > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: unreadCount > 0 ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.state});

  final MessageDeliveryState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(_iconFor(state), size: 16, color: _colorFor(theme, state));
  }

  IconData _iconFor(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.sending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.sent:
        return Icons.check_rounded;
      case MessageDeliveryState.delivered:
      case MessageDeliveryState.read:
        return Icons.done_all_rounded;
      case MessageDeliveryState.consumed:
        return Icons.visibility_off_rounded;
      case MessageDeliveryState.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color _colorFor(ThemeData theme, MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.read:
        return theme.colorScheme.primary;
      case MessageDeliveryState.failed:
        return theme.colorScheme.error;
      case MessageDeliveryState.consumed:
        return theme.colorScheme.tertiary;
      case MessageDeliveryState.sending:
      case MessageDeliveryState.sent:
      case MessageDeliveryState.delivered:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}

class _GXMessageStatusIcon extends StatelessWidget {
  const _GXMessageStatusIcon({required this.state, required this.accent});

  final MessageDeliveryState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Icon(_iconFor(state), size: 14, color: _colorFor(state));
  }

  IconData _iconFor(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.sending:
        return Icons.hourglass_empty_rounded;
      case MessageDeliveryState.sent:
        return Icons.keyboard_arrow_right_rounded;
      case MessageDeliveryState.delivered:
      case MessageDeliveryState.read:
        return Icons.done_all_rounded;
      case MessageDeliveryState.consumed:
        return Icons.visibility_off_rounded;
      case MessageDeliveryState.failed:
        return Icons.bolt_rounded;
    }
  }

  Color _colorFor(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.read:
        return accent;
      case MessageDeliveryState.failed:
        return const Color(0xFFFF5252);
      case MessageDeliveryState.consumed:
        return accent.withValues(alpha: 0.5);
      case MessageDeliveryState.sending:
      case MessageDeliveryState.sent:
      case MessageDeliveryState.delivered:
        return const Color(0xFF8888AA);
    }
  }
}

class _GXAvatarFramePainter extends CustomPainter {
  const _GXAvatarFramePainter({
    required this.accent,
    required this.isOnline,
    required this.hasUnread,
  });

  final Color accent;
  final bool isOnline;
  final bool hasUnread;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = hasUnread ? accent : accent.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasUnread ? 1.5 : 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * (math.pi / 180);
      final x = center.dx + radius * 0.95 * math.cos(angle);
      final y = center.dy + radius * 0.95 * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    if (isOnline) {
      final onlinePaint = Paint()
        ..color = accent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(center.dx + radius * 0.7, center.dy + radius * 0.7),
        4,
        onlinePaint,
      );
      canvas.drawCircle(
        Offset(center.dx + radius * 0.7, center.dy + radius * 0.7),
        6,
        Paint()
          ..color = accent.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_GXAvatarFramePainter old) =>
      old.accent != accent ||
      old.isOnline != isOnline ||
      old.hasUnread != hasUnread;
}

class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.25, 0);
    path.lineTo(w * 0.75, 0);
    path.lineTo(w, h * 0.5);
    path.lineTo(w * 0.75, h);
    path.lineTo(w * 0.25, h);
    path.lineTo(0, h * 0.5);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

class _GXTileClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const cut = 8.0;

    final path = Path();
    path.moveTo(cut, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height - cut);
    path.lineTo(size.width - cut, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, cut);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}
