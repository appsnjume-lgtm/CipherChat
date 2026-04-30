import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/local_profile_cache_service.dart';
import '../../features/auth/domain/entities/app_user.dart';

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
      .toList(growable: false);
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

String? resolveStorageObjectPath(String? imageUrl) {
  final trimmed = imageUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return trimmed;
  }

  final segments = uri.pathSegments;
  final publicIndex = segments.indexOf('public');
  if (publicIndex != -1 && publicIndex + 2 < segments.length) {
    return Uri.decodeComponent(segments.skip(publicIndex + 2).join('/'));
  }

  final signIndex = segments.indexOf('sign');
  if (signIndex != -1 && signIndex + 2 < segments.length) {
    return Uri.decodeComponent(segments.skip(signIndex + 2).join('/'));
  }

  final authenticatedIndex = segments.indexOf('authenticated');
  if (authenticatedIndex != -1 && authenticatedIndex + 2 < segments.length) {
    return Uri.decodeComponent(segments.skip(authenticatedIndex + 2).join('/'));
  }

  return trimmed;
}

class AvatarMedia extends ConsumerStatefulWidget {
  const AvatarMedia({
    super.key,
    required this.imageUrl,
    required this.avatarId,
    this.storageBucket = AppConstants.profileImagesBucket,
    this.useSignedUrl = true,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.person_rounded,
    this.backgroundColor,
  });

  final String? imageUrl;
  final String? avatarId;
  final String storageBucket;
  final bool useSignedUrl;
  final BoxFit fit;
  final IconData fallbackIcon;
  final Color? backgroundColor;

  @override
  ConsumerState<AvatarMedia> createState() => _AvatarMediaState();
}

class _AvatarMediaState extends ConsumerState<AvatarMedia> {
  File? _cachedImageFile;
  String? _activeCacheKey;
  String? _activeSourceUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedImage());
  }

  @override
  void didUpdateWidget(covariant AvatarMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.storageBucket != widget.storageBucket ||
        oldWidget.useSignedUrl != widget.useSignedUrl) {
      _cachedImageFile = null;
      _activeCacheKey = null;
      _activeSourceUrl = null;
      unawaited(_loadCachedImage());
    }
  }

  Future<void> _loadCachedImage() async {
    final cacheKey = widget.imageUrl?.trim();
    if (cacheKey == null || cacheKey.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() => _cachedImageFile = null);
      return;
    }

    final cached = await ref
        .read(localProfileCacheServiceProvider)
        .readCachedProfileImage(cacheKey);
    if (!mounted) {
      return;
    }

    setState(() => _cachedImageFile = cached);
  }

  @override
  Widget build(BuildContext context) {
    final objectPath = resolveStorageObjectPath(widget.imageUrl);
    final trimmedImage = widget.imageUrl?.trim();
    final directUrl = _isNetworkUrl(trimmedImage) ? trimmedImage : null;

    if (_cachedImageFile != null) {
      return Image.file(
        _cachedImageFile!,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _fallback(context),
      );
    }

    if (directUrl != null) {
      _maybeRefreshCachedImage(cacheKey: trimmedImage!, imageUrl: directUrl);
      return _NetworkAvatarImage(
        url: directUrl,
        fit: widget.fit,
        placeholder: _loadingState(context),
        fallback: _fallback(context),
      );
    }

    if (objectPath != null && objectPath.isNotEmpty) {
      if (widget.useSignedUrl) {
        return FutureBuilder<String>(
          future: Supabase.instance.client.storage
              .from(widget.storageBucket)
              .createSignedUrl(objectPath, 60 * 60),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _loadingState(context);
              }
              return _fallback(context);
            }

            _maybeRefreshCachedImage(
              cacheKey: trimmedImage ?? objectPath,
              imageUrl: url,
            );
            return _NetworkAvatarImage(
              url: url,
              fit: widget.fit,
              placeholder: _loadingState(context),
              fallback: _fallback(context),
            );
          },
        );
      }

      final publicUrl = Supabase.instance.client.storage
          .from(widget.storageBucket)
          .getPublicUrl(objectPath);

      _maybeRefreshCachedImage(
        cacheKey: trimmedImage ?? objectPath,
        imageUrl: publicUrl,
      );
      return _NetworkAvatarImage(
        url: publicUrl,
        fit: widget.fit,
        placeholder: _loadingState(context),
        fallback: _fallback(context),
      );
    }

    return _fallback(context);
  }

  void _maybeRefreshCachedImage({
    required String cacheKey,
    required String imageUrl,
  }) {
    if (_activeCacheKey == cacheKey && _activeSourceUrl == imageUrl) {
      return;
    }

    _activeCacheKey = cacheKey;
    _activeSourceUrl = imageUrl;

    unawaited(() async {
      final file = await ref
          .read(localProfileCacheServiceProvider)
          .refreshProfileImage(cacheKey: cacheKey, imageUrl: imageUrl);
      if (!mounted || file == null) {
        return;
      }

      setState(() => _cachedImageFile = file);
    }());
  }

  Widget _fallback(BuildContext context) {
    final resolvedAvatarId = widget.avatarId?.trim();
    if (resolvedAvatarId != null && resolvedAvatarId.isNotEmpty) {
      final avatar = presetAvatarById(resolvedAvatarId);
      return Image.asset(
        avatar.assetPath,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _iconFallback(context),
      );
    }

    return _iconFallback(context);
  }

  Widget _iconFallback(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color:
          widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(widget.fallbackIcon, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _loadingState(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color:
          widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  bool _isNetworkUrl(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return false;
    }

    return uri.scheme == 'http' || uri.scheme == 'https';
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.avatarId,
    this.storageBucket = AppConstants.profileImagesBucket,
    this.useSignedUrl = true,
    this.showOutline = false,
    this.fallbackIcon = Icons.person_rounded,
    this.backgroundColor,
    this.isOnline = false,
  });

  final double size;
  final String? imageUrl;
  final String? avatarId;
  final String storageBucket;
  final bool useSignedUrl;
  final bool showOutline;
  final IconData fallbackIcon;
  final Color? backgroundColor;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: showOutline
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.22),
                    width: 2,
                  )
                : null,
          ),
          child: ClipOval(
            child: AvatarMedia(
              imageUrl: imageUrl,
              avatarId: avatarId,
              storageBucket: storageBucket,
              useSignedUrl: useSignedUrl,
              fallbackIcon: fallbackIcon,
              backgroundColor: backgroundColor,
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: size * 0.05,
            bottom: size * 0.05,
            child: Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: size * 0.04,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NetworkAvatarImage extends StatelessWidget {
  const _NetworkAvatarImage({
    required this.url,
    required this.fit,
    required this.placeholder,
    required this.fallback,
  });

  final String url;
  final BoxFit fit;
  final Widget placeholder;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return placeholder;
      },
    );
  }
}
