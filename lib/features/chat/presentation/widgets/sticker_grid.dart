import 'package:flutter/material.dart';

import '../../domain/entities/sticker.dart';
import 'sticker_network_display.dart';

const double _kStickerTileMaxExtent = 120;
const double _kStickerPreviewSize = 108;

class StickerGrid extends StatelessWidget {
  const StickerGrid({
    super.key,
    required this.stickers,
    required this.onStickerTap,
    this.header,
    this.emptyTitle = 'No stickers yet',
    this.emptySubtitle = 'Create a sticker to start your library.',
  });

  final List<Sticker> stickers;
  final ValueChanged<Sticker> onStickerTap;
  final Widget? header;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (header != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: header,
            ),
          ),
        if (stickers.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 42,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      emptyTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      emptySubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final sticker = stickers[index];
                return RepaintBoundary(
                  child: _StickerGridTile(
                    sticker: sticker,
                    onTap: () => onStickerTap(sticker),
                  ),
                );
              }, childCount: stickers.length),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _kStickerTileMaxExtent,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
            ),
          ),
      ],
    );
  }
}

class _StickerGridTile extends StatelessWidget {
  const _StickerGridTile({required this.sticker, required this.onTap});

  final Sticker sticker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: StickerNetworkDisplay(
                    sticker: sticker,
                    size: _kStickerPreviewSize,
                  ),
                ),
              ),
            ),
            if (sticker.isFavorite)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Colors.amber.shade600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
