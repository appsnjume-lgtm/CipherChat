import 'package:flutter/material.dart';

import '../../domain/entities/sticker.dart';

class StickerNetworkDisplay extends StatelessWidget {
  const StickerNetworkDisplay({
    super.key,
    required this.sticker,
    required this.size,
    this.filterQuality = FilterQuality.medium,
  });

  final Sticker sticker;
  final double size;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spinnerSize = (size * 0.18).clamp(14.0, 22.0);

    if (!sticker.usesImageRendering) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
            size: 28,
          ),
        ),
      );
    }

    return Image.network(
      sticker.imageUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: filterQuality,
      errorBuilder: (_, _, _) => Icon(
        Icons.broken_image_outlined,
        color: theme.colorScheme.onSurfaceVariant,
        size: 28,
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return Center(
          child: SizedBox.square(
            dimension: spinnerSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}
