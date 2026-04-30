import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Returned when the user confirms a clip selection.
class VideoTrimResult {
  const VideoTrimResult({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;
}

/// Constrained video sticker editor.
///
/// Rules enforced:
///  • Max selection = [kMaxDurationMs] (3 s)
///  • Min selection = [kMinDurationMs] (0.5 s)
///  • Default selection = (0, min(duration, max))
///  • User can shrink the selection but not expand beyond max
///  • Preview loops only the selected segment
///  • Shows selected duration in the UI
class VideoStickerEditorScreen extends StatefulWidget {
  const VideoStickerEditorScreen({super.key, required this.file});

  final File file;

  static const int kMaxDurationMs = 3000;
  static const int kMinDurationMs = 500;

  @override
  State<VideoStickerEditorScreen> createState() =>
      _VideoStickerEditorScreenState();
}

class _VideoStickerEditorScreenState extends State<VideoStickerEditorScreen> {
  late final VideoPlayerController _controller;
  Future<void>? _initFuture;

  double _startMs = 0;
  double _endMs = VideoStickerEditorScreen.kMaxDurationMs.toDouble();
  double _totalMs = 1; // 1 to avoid division-by-zero before init

  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      final totalMs = _controller.value.duration.inMilliseconds.toDouble();
      final clampedEnd = totalMs.clamp(
        VideoStickerEditorScreen.kMinDurationMs.toDouble(),
        VideoStickerEditorScreen.kMaxDurationMs.toDouble(),
      );
      setState(() {
        _totalMs = totalMs > 0 ? totalMs : 1;
        _startMs = 0;
        _endMs = clampedEnd;
      });
      _controller.addListener(_onPlayerTick);
      _controller.setLooping(false);
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onPlayerTick)
      ..dispose();
    super.dispose();
  }

  // Loop playback within the selected window.
  void _onPlayerTick() {
    if (!mounted || !_isPlaying) return;
    final posMs = _controller.value.position.inMilliseconds.toDouble();
    if (posMs >= _endMs) {
      // Seek back to start of clip and continue playing.
      _controller
          .seekTo(Duration(milliseconds: _startMs.round()))
          .then((_) => _controller.play());
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _controller.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _controller.seekTo(Duration(milliseconds: _startMs.round()));
      await _controller.play();
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  /// Called when the RangeSlider changes.
  /// Enforces: min duration, max duration (cannot expand beyond max).
  void _onRangeChanged(RangeValues values) {
    double newStart = values.start;
    double newEnd = values.end;
    final dur = newEnd - newStart;

    // Reject if below minimum.
    if (dur < VideoStickerEditorScreen.kMinDurationMs) return;

    // If exceeds max, clamp the handle that moved.
    if (dur > VideoStickerEditorScreen.kMaxDurationMs) {
      final startMoved = (newStart - _startMs).abs() > (newEnd - _endMs).abs();
      if (startMoved) {
        newEnd = newStart + VideoStickerEditorScreen.kMaxDurationMs;
      } else {
        newStart = newEnd - VideoStickerEditorScreen.kMaxDurationMs;
      }
    }

    newStart = newStart.clamp(0, _totalMs);
    newEnd = newEnd.clamp(0, _totalMs);

    if (newEnd - newStart < VideoStickerEditorScreen.kMinDurationMs) {
      return;
    }

    setState(() {
      _startMs = newStart;
      _endMs = newEnd;
    });

    // If playing, restart from new start.
    if (_isPlaying) {
      _controller
          .seekTo(Duration(milliseconds: newStart.round()))
          .then((_) => _controller.play());
    }
  }

  String _formatMs(double ms) => '${(ms / 1000.0).toStringAsFixed(1)}s';

  void _confirm() {
    Navigator.of(
      context,
    ).pop(VideoTrimResult(startMs: _startMs.round(), endMs: _endMs.round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDuration = _endMs - _startMs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Sticker'),
        actions: [
          TextButton(
            onPressed: _totalMs > 1 ? _confirm : null,
            child: const Text('Use Clip'),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final value = _controller.value;

          return Column(
            children: [
              // ── Video preview ──────────────────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: _togglePlayback,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio > 0
                          ? value.aspectRatio
                          : 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_controller),
                          if (!_isPlaying)
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Trim controls ─────────────────────────────────
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Duration label row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Selected: ${_formatMs(selectedDuration)}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            'Max: ${_formatMs(VideoStickerEditorScreen.kMaxDurationMs.toDouble())}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Range slider — constrained trim handles
                      RangeSlider(
                        values: RangeValues(_startMs, _endMs),
                        min: 0,
                        max: _totalMs,
                        labels: RangeLabels(
                          _formatMs(_startMs),
                          _formatMs(_endMs),
                        ),
                        onChanged: _onRangeChanged,
                      ),

                      // Start / end time labels
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatMs(_startMs),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _formatMs(_totalMs),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      FilledButton.icon(
                        onPressed: _totalMs > 1 ? _confirm : null,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Use Clip'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
