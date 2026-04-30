import 'package:flutter/material.dart';

import '../../../common/widgets/app_avatar.dart';

class ProfileImageModal extends StatelessWidget {
  const ProfileImageModal({
    super.key,
    required this.imageUrl,
    required this.avatarId,
    this.title,
    this.heroTag,
    this.storageBucket,
    this.useSignedUrl = false,
  });

  final String? imageUrl;
  final String? avatarId;
  final String? title;
  final String? heroTag;
  final String? storageBucket;
  final bool useSignedUrl;

  static Future<void> show(
    BuildContext context, {
    required String? imageUrl,
    required String? avatarId,
    String? title,
    String? heroTag,
    String? storageBucket,
    bool useSignedUrl = false,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: ProfileImageModal(
              imageUrl: imageUrl,
              avatarId: avatarId,
              title: title,
              heroTag: heroTag,
              storageBucket: storageBucket,
              useSignedUrl: useSignedUrl,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = Container(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      clipBehavior: Clip.antiAlias,
      child: AvatarMedia(
        imageUrl: imageUrl,
        avatarId: avatarId,
        storageBucket: storageBucket ?? 'profile-images',
        useSignedUrl: useSignedUrl,
        fit: BoxFit.contain,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.5,
                child: Center(
                  child: heroTag == null
                      ? media
                      : Hero(tag: heroTag!, child: media),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  if (title != null && title!.trim().isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
