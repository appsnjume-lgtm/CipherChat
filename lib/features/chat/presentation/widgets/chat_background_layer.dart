import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/chat_background_config.dart';
import '../providers/chat_background_provider.dart';

class ResolvedChatBackgroundLayer extends ConsumerWidget {
  const ResolvedChatBackgroundLayer({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(
      chatBackgroundProvider(chatId).select((state) => state.resolvedConfig),
    );
    return ChatBackgroundLayer(config: config);
  }
}

class ChatBackgroundLayer extends StatelessWidget {
  const ChatBackgroundLayer({super.key, required this.config});

  final ChatBackgroundConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = config.imagePath?.trim();
    final hasImage =
        imagePath != null &&
        imagePath.isNotEmpty &&
        File(imagePath).existsSync();
    final overlayColor = config.hasOverlay
        ? Color(config.overlayColor!).withValues(alpha: config.overlayOpacity)
        : null;

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surfaceContainerLow,
                    theme.colorScheme.surface,
                  ],
                ),
                image: hasImage
                    ? DecorationImage(
                        image: FileImage(File(imagePath)),
                        fit: BoxFit.cover,
                        alignment: Alignment(config.offsetX, config.offsetY),
                        colorFilter: _brightnessFilter(config.brightness),
                      )
                    : null,
              ),
            ),
            if (overlayColor != null) ColoredBox(color: overlayColor),
          ],
        ),
      ),
    );
  }

  ColorFilter? _brightnessFilter(double brightness) {
    if ((brightness - 1).abs() < 0.01) {
      return null;
    }

    return ColorFilter.matrix(<double>[
      brightness,
      0,
      0,
      0,
      0,
      0,
      brightness,
      0,
      0,
      0,
      0,
      0,
      brightness,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}
