import 'package:flutter/material.dart';

import '../../domain/entities/sticker.dart';
import '../providers/sticker_provider.dart';
import '../screens/widgets/attachment_card.dart';
import '../widgets/sticker_grid.dart';

class StickerPanel extends StatelessWidget {
  const StickerPanel({
    super.key,
    required this.state,
    required this.onStickerTap,
    required this.onCreateSticker,
    required this.onRetry,
  });

  final StickerLibraryState state;
  final ValueChanged<Sticker> onStickerTap;
  final VoidCallback onCreateSticker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 10,
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: 340,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: const TabBar(
                  tabs: [
                    Tab(text: 'Stickers'),
                    Tab(text: 'Favorites'),
                  ],
                ),
              ),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.errorMessage != null
                    ? _StickerPanelError(
                        message: state.errorMessage!,
                        onRetry: onRetry,
                      )
                    : TabBarView(
                        children: [
                          StickerGrid(
                            header: AttachmentCard(
                              icon: Icons.add_photo_alternate_outlined,
                              title: 'Create sticker',
                              subtitle:
                                  'Upload an image and add it to your library',
                              onTap: onCreateSticker,
                            ),
                            stickers: state.stickersTabStickers,
                            onStickerTap: onStickerTap,
                            emptyTitle: 'No stickers in your library yet',
                            emptySubtitle:
                                'Save a sticker from chat or create your own to start building this tab.',
                          ),
                          StickerGrid(
                            stickers: state.favoriteStickers,
                            onStickerTap: onStickerTap,
                            emptyTitle: 'No favorites yet',
                            emptySubtitle:
                                'Save a public sticker to your library, then star it to keep it here.',
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerPanelError extends StatelessWidget {
  const _StickerPanelError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load stickers',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
