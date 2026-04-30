import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../utils/sticker_media_preprocessor.dart';

class StickerImageCropEditorScreen extends StatefulWidget {
  const StickerImageCropEditorScreen({super.key, required this.file});

  final File file;

  @override
  State<StickerImageCropEditorScreen> createState() =>
      _StickerImageCropEditorScreenState();
}

class _StickerImageCropEditorScreenState
    extends State<StickerImageCropEditorScreen> {
  late final Future<Size> _sizeFuture = _decodeImageSize(widget.file);
  NormalizedCropRect _cropRect = const NormalizedCropRect.full();

  Future<Size> _decodeImageSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  void _closeWithCrop() {
    Navigator.of(context).pop<StickerCropSelection>(
      _cropRect.isEffectivelyFullFrame
          ? const StickerCropSelection.useOriginal()
          : StickerCropSelection.cropped(_cropRect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StickerCropScaffold(
      title: 'Crop Image',
      subtitle: 'Pinch to zoom and drag to choose the sticker area.',
      onSkip: () =>
          Navigator.of(context).pop(const StickerCropSelection.useOriginal()),
      onConfirm: _closeWithCrop,
      child: FutureBuilder<Size>(
        future: _sizeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const _CropLoadError();
          }

          return _StickerCropViewport(
            mediaSize: snapshot.data!,
            onCropChanged: (value) => _cropRect = value,
            child: Image.file(
              widget.file,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          );
        },
      ),
    );
  }
}

class StickerVideoCropEditorScreen extends StatefulWidget {
  const StickerVideoCropEditorScreen({
    super.key,
    required this.file,
    required this.previewStartMs,
  });

  final File file;
  final int previewStartMs;

  @override
  State<StickerVideoCropEditorScreen> createState() =>
      _StickerVideoCropEditorScreenState();
}

class _StickerVideoCropEditorScreenState
    extends State<StickerVideoCropEditorScreen> {
  late final VideoPlayerController _controller;
  Future<void>? _initFuture;
  NormalizedCropRect _cropRect = const NormalizedCropRect.full();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initFuture = _controller.initialize().then((_) async {
      final duration = _controller.value.duration;
      final requestedPreview = Duration(milliseconds: widget.previewStartMs);
      final previewPosition = requestedPreview > duration
          ? duration
          : requestedPreview;
      await _controller.seekTo(previewPosition);
      await _controller.play();
      if (!mounted) {
        return;
      }
      setState(() => _isPlaying = true);
    });
  }

  @override
  void dispose() {
    unawaited(_controller.pause());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) {
      return;
    }
    if (_isPlaying) {
      await _controller.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }

    await _controller.play();
    if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  void _closeWithCrop() {
    Navigator.of(context).pop<StickerCropSelection>(
      _cropRect.isEffectivelyFullFrame
          ? const StickerCropSelection.useOriginal()
          : StickerCropSelection.cropped(_cropRect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StickerCropScaffold(
      title: 'Crop Video',
      subtitle:
          'Adjust the visible frame before your trimmed clip becomes a sticker.',
      onSkip: () =>
          Navigator.of(context).pop(const StickerCropSelection.useOriginal()),
      onConfirm: _closeWithCrop,
      child: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_controller.value.isInitialized) {
            return const _CropLoadError();
          }

          final mediaSize = _controller.value.size;
          return Stack(
            children: [
              _StickerCropViewport(
                mediaSize: mediaSize,
                onCropChanged: (value) => _cropRect = value,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: mediaSize.width,
                      height: mediaSize.height,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FilledButton.tonalIcon(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StickerCropScaffold extends StatelessWidget {
  const _StickerCropScaffold({
    required this.title,
    required this.subtitle,
    required this.onSkip,
    required this.onConfirm,
    required this.child,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSkip;
  final VoidCallback onConfirm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [TextButton(onPressed: onSkip, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AspectRatio(aspectRatio: 1, child: child),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use Crop'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerCropViewport extends StatefulWidget {
  const _StickerCropViewport({
    required this.mediaSize,
    required this.child,
    required this.onCropChanged,
  });

  final Size mediaSize;
  final Widget child;
  final ValueChanged<NormalizedCropRect> onCropChanged;

  @override
  State<_StickerCropViewport> createState() => _StickerCropViewportState();
}

class _StickerCropViewportState extends State<_StickerCropViewport> {
  static const double _kMinScale = 1;
  static const double _kMaxScale = 4;

  double _scale = 1;
  double _scaleStart = 1;
  Offset _offset = Offset.zero;
  Offset _offsetStart = Offset.zero;
  Offset _focalPointStart = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(28),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final fittedSizes = applyBoxFit(
              BoxFit.cover,
              widget.mediaSize,
              viewportSize,
            );
            final baseContentSize = fittedSizes.destination;

            final contentSize = Size(
              baseContentSize.width * _scale,
              baseContentSize.height * _scale,
            );
            final clampedOffset = _clampOffset(
              _offset,
              contentSize,
              viewportSize,
            );
            if (clampedOffset != _offset) {
              _offset = clampedOffset;
            }

            final left =
                (viewportSize.width - contentSize.width) / 2 + _offset.dx;
            final top =
                (viewportSize.height - contentSize.height) / 2 + _offset.dy;
            widget.onCropChanged(
              _buildCropRect(
                viewportSize: viewportSize,
                contentSize: contentSize,
                left: left,
                top: top,
              ),
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _scaleStart = _scale;
                _offsetStart = _offset;
                _focalPointStart = details.localFocalPoint;
              },
              onScaleUpdate: (details) {
                final nextScale = (_scaleStart * details.scale).clamp(
                  _kMinScale,
                  _kMaxScale,
                );
                final nextOffset = _clampOffset(
                  _offsetStart + (details.localFocalPoint - _focalPointStart),
                  Size(
                    baseContentSize.width * nextScale,
                    baseContentSize.height * nextScale,
                  ),
                  viewportSize,
                );
                setState(() {
                  _scale = nextScale;
                  _offset = nextOffset;
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    child: SizedBox(
                      width: contentSize.width,
                      height: contentSize.height,
                      child: widget.child,
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _CropGridPainter(
                        borderColor: Colors.white.withValues(alpha: 0.94),
                        lineColor: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          'Pinch to zoom, drag to position',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Offset _clampOffset(Offset offset, Size contentSize, Size viewportSize) {
    final maxDx = math.max(0, (contentSize.width - viewportSize.width) / 2);
    final maxDy = math.max(0, (contentSize.height - viewportSize.height) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  NormalizedCropRect _buildCropRect({
    required Size viewportSize,
    required Size contentSize,
    required double left,
    required double top,
  }) {
    final x = ((0 - left) / contentSize.width).clamp(0.0, 1.0).toDouble();
    final y = ((0 - top) / contentSize.height).clamp(0.0, 1.0).toDouble();
    final width = (viewportSize.width / contentSize.width)
        .clamp(0.0, 1.0 - x)
        .toDouble();
    final height = (viewportSize.height / contentSize.height)
        .clamp(0.0, 1.0 - y)
        .toDouble();
    return NormalizedCropRect(x: x, y: y, width: width, height: height);
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter({required this.borderColor, required this.lineColor});

  final Color borderColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rect = Offset.zero & size;
    canvas.drawRect(rect, borderPaint);

    final thirdWidth = size.width / 3;
    final thirdHeight = size.height / 3;
    for (var i = 1; i < 3; i += 1) {
      final dx = thirdWidth * i;
      final dy = thirdHeight * i;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), linePaint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.lineColor != lineColor;
  }
}

class _CropLoadError extends StatelessWidget {
  const _CropLoadError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Could not load media preview.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
