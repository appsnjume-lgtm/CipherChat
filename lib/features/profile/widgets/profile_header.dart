import 'package:flutter/material.dart';

import '../../../common/widgets/app_avatar.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.displayName,
    required this.username,
    required this.statusLabel,
    required this.imageUrl,
    required this.avatarId,
    required this.onAvatarTap,
    this.heroTag,
    this.isOnline = false,
  });

  final String displayName;
  final String username;
  final String statusLabel;
  final String? imageUrl;
  final String avatarId;
  final VoidCallback onAvatarTap;
  final String? heroTag;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final avatar = AppAvatar(
      size: 112,
      imageUrl: imageUrl,
      avatarId: avatarId,
      showOutline: true,
      isOnline: isOnline,
    );

    return Column(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: heroTag == null ? avatar : Hero(tag: heroTag!, child: avatar),
        ),
        const SizedBox(height: 18),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '@$username',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          statusLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
