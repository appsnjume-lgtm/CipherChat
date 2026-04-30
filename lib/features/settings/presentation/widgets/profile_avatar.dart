import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../auth/domain/entities/app_user.dart';

class PresetAvatarData {
  const PresetAvatarData({
    required this.id,
    required this.label,
    required this.gender,
    required this.assetPath,
  });

  final String id;
  final String label;
  final AppGender gender;
  final String assetPath;
}

const presetAvatars = [
  PresetAvatarData(
    id: 'avatar_1',
    label: 'Avatar 1',
    gender: AppGender.male,
    assetPath: 'assets/avatars/avatar_1.png',
  ),
  PresetAvatarData(
    id: 'avatar_2',
    label: 'Avatar 2',
    gender: AppGender.male,
    assetPath: 'assets/avatars/avatar_2.png',
  ),
  PresetAvatarData(
    id: 'avatar_3',
    label: 'Avatar 3',
    gender: AppGender.male,
    assetPath: 'assets/avatars/avatar_3.png',
  ),
  PresetAvatarData(
    id: 'avatar_4',
    label: 'Avatar 4',
    gender: AppGender.female,
    assetPath: 'assets/avatars/avatar_4.png',
  ),
  PresetAvatarData(
    id: 'avatar_5',
    label: 'Avatar 5',
    gender: AppGender.female,
    assetPath: 'assets/avatars/avatar_5.png',
  ),
  PresetAvatarData(
    id: 'avatar_6',
    label: 'Avatar 6',
    gender: AppGender.female,
    assetPath: 'assets/avatars/avatar_6.png',
  ),
];

List<PresetAvatarData> presetAvatarsForGender(AppGender gender) {
  final resolvedGender = gender == AppGender.female
      ? AppGender.female
      : AppGender.male;
  return presetAvatars
      .where((avatar) => avatar.gender == resolvedGender)
      .toList();
}

PresetAvatarData presetAvatarById(String? avatarId) {
  final normalized = (avatarId == null || avatarId.trim().isEmpty)
      ? AppConstants.maleAvatarIds.first
      : avatarId.trim();

  return presetAvatars.firstWhere(
    (avatar) => avatar.id == normalized,
    orElse: () => presetAvatars.first,
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarId,
    this.profileImageUrl,
    this.radius = 34,
    this.showOutline = false,
    this.isOnline = false,
  });

  final String avatarId;
  final String? profileImageUrl;
  final double radius;
  final bool showOutline;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final fallback = _assetFallback(context);
    final trimmedImage = profileImageUrl?.trim();

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: showOutline
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.25),
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: trimmedImage == null || trimmedImage.isEmpty
              ? fallback
              : StorageAvatarImage(
                  bucket: AppConstants.profileImagesBucket,
                  objectPath: trimmedImage,
                  fallback: fallback,
                ),
        ),
        if (isOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: size * 0.60,
              height: size * 0.60,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E), // Green-500
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: size * 0.04,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _assetFallback(BuildContext context) {
    final avatar = presetAvatarById(avatarId);

    return Image.asset(
      avatar.assetPath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return _iconFallback(context);
      },
    );
  }

  Widget _iconFallback(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person_rounded,
        size: radius,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class StorageAvatarImage extends StatelessWidget {
  const StorageAvatarImage({
    super.key,
    required this.bucket,
    required this.objectPath,
    required this.fallback,
  });

  final String bucket;
  final String objectPath;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(objectPath, 60 * 60),
      builder: (context, snapshot) {
        final signedUrl = snapshot.data;
        if (signedUrl == null || signedUrl.isEmpty) {
          return fallback;
        }

        return Image.network(
          signedUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return fallback;
          },
        );
      },
    );
  }
}
