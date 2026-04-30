import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({
    super.key,
    required this.file,
    required this.title,
    this.isViewOnce = false,
  });

  final File file;
  final String title;

  /// When [true] the save/download action is blocked.
  final bool isViewOnce;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller = VideoPlayerController.file(
    widget.file,
  );
  Future<void>? _initializeFuture;
  Timer? _seekOverlayTimer;
  Duration? _seekBasePosition;
  Duration? _pendingSeekPosition;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _seekOverlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!_controller.value.isInitialized) {
      return;
    }

    _seekOverlayTimer?.cancel();
    _seekBasePosition = _controller.value.position;
    _pendingSeekPosition = _controller.value.position;
    setState(() {});
  }

  void _handleHorizontalDragUpdate(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    if (!_controller.value.isInitialized || _seekBasePosition == null) {
      return;
    }

    final duration = _controller.value.duration;
    if (duration <= Duration.zero) {
      return;
    }

    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final dragFraction = details.localPosition.dx / width;
    final target = Duration(
      milliseconds: (duration.inMilliseconds * dragFraction).round().clamp(
        0,
        duration.inMilliseconds,
      ),
    );

    _pendingSeekPosition = target;
    setState(() {});
  }

  Future<void> _handleHorizontalDragEnd(DragEndDetails details) async {
    final pending = _pendingSeekPosition;
    if (pending != null) {
      await _controller.seekTo(pending);
    }

    _seekBasePosition = null;
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      setState(() => _pendingSeekPosition = null);
    });
    setState(() {});
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _saveToDevice(BuildContext context) async {
    if (widget.isViewOnce) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Cannot save view-once media.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(dir.path, 'CipherChat'));
      if (!destDir.existsSync()) destDir.createSync(recursive: true);

      final fileName = p.basename(widget.file.path).isEmpty
          ? 'video.mp4'
          : p.basename(widget.file.path);
      final dest = File(p.join(destDir.path, fileName));
      await widget.file.copy(dest.path);

      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Saved to ${dest.path}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Could not save video: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayTop = MediaQuery.paddingOf(context).top + 14;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: widget.isViewOnce
                ? 'Cannot save view-once media'
                : 'Save video',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _saveToDevice(context),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final duration = value.duration;
              final position = value.position > duration
                  ? duration
                  : value.position;
              final displayPosition = _pendingSeekPosition ?? position;
              final progressValue = duration.inMilliseconds > 0
                  ? displayPosition.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble()
                  : 0.0;
              final progressMax = duration.inMilliseconds > 0
                  ? duration.inMilliseconds.toDouble()
                  : 1.0;
              final seekDeltaLabel =
                  _pendingSeekPosition == null || _seekBasePosition == null
                  ? null
                  : _pendingSeekPosition! >= _seekBasePosition!
                  ? '+${_formatDuration(_pendingSeekPosition! - _seekBasePosition!)}'
                  : '-${_formatDuration(_seekBasePosition! - _pendingSeekPosition!)}';

              return LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(_togglePlayback),
                              onHorizontalDragStart: _handleHorizontalDragStart,
                              onHorizontalDragUpdate: (details) =>
                                  _handleHorizontalDragUpdate(
                                    details,
                                    constraints,
                                  ),
                              onHorizontalDragEnd: _handleHorizontalDragEnd,
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: value.aspectRatio,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      VideoPlayer(_controller),
                                      if (!value.isPlaying)
                                        Center(
                                          child: Container(
                                            width: 72,
                                            height: 72,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.42,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.play_arrow_rounded,
                                              size: 42,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape:
                                          SliderComponentShape.noOverlay,
                                    ),
                                    child: Slider(
                                      value: progressValue,
                                      max: progressMax,
                                      onChanged: duration > Duration.zero
                                          ? (nextValue) {
                                              _controller.seekTo(
                                                Duration(
                                                  milliseconds: nextValue
                                                      .round(),
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton.filledTonal(
                                        onPressed: () =>
                                            setState(_togglePlayback),
                                        icon: Icon(
                                          value.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '${_formatDuration(displayPosition)} / ${_formatDuration(duration)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_pendingSeekPosition != null)
                        Positioned(
                          top: overlayTop,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (seekDeltaLabel != null)
                                        Text(
                                          seekDeltaLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      Text(
                                        _formatDuration(_pendingSeekPosition!),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
