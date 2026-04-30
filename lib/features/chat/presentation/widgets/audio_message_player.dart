import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioMessagePlayer extends StatefulWidget {
  const AudioMessagePlayer({
    super.key,
    required this.fileSizeLabel,
    required this.loadFile,
    this.durationMs,
  });

  final String fileSizeLabel;
  final int? durationMs;
  final Future<File> Function() loadFile;

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPreparing = false;
  String? _loadedFilePath;
  String? _errorLabel;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPreparing) {
      return;
    }

    final isLoaded = _loadedFilePath != null;
    if (!isLoaded) {
      setState(() {
        _isPreparing = true;
        _errorLabel = null;
      });
    } else {
      setState(() {
        _errorLabel = null;
      });
    }

    try {
      final file = await widget.loadFile();
      if (_loadedFilePath != file.path) {
        await _player.setFilePath(file.path);
        _loadedFilePath = file.path;
      }

      final playerState = _player.playerState;
      if (playerState.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }

      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isPreparing = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
        _errorLabel = 'Unable to play audio';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, stateSnapshot) {
        final playerState = stateSnapshot.data ?? _player.playerState;
        final processingState = playerState.processingState;
        final isPlaying =
            playerState.playing && processingState != ProcessingState.completed;
        final isBuffering =
            processingState == ProcessingState.loading ||
            processingState == ProcessingState.buffering;

        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          initialData: _player.duration,
          builder: (context, durationSnapshot) {
            final resolvedDuration =
                durationSnapshot.data ??
                (widget.durationMs == null
                    ? Duration.zero
                    : Duration(milliseconds: widget.durationMs!));

            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              initialData: _player.position,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final safeDuration = resolvedDuration > Duration.zero
                    ? resolvedDuration
                    : Duration.zero;
                final clampedPosition = safeDuration > Duration.zero
                    ? Duration(
                        milliseconds: position.inMilliseconds.clamp(
                          0,
                          safeDuration.inMilliseconds,
                        ),
                      )
                    : position;
                final progress = safeDuration.inMilliseconds > 0
                    ? (clampedPosition.inMilliseconds /
                              safeDuration.inMilliseconds)
                          .clamp(0.0, 1.0)
                    : 0.0;
                final totalLabel = safeDuration > Duration.zero
                    ? _formatDuration(safeDuration)
                    : '--:--';
                final currentLabel = safeDuration > Duration.zero
                    ? _formatDuration(clampedPosition)
                    : '0:00';

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: _togglePlayback,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.08,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _isPreparing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.onSurface,
                                    ),
                                  ),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 24,
                                  color: theme.colorScheme.onSurface,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              height: 18,
                              child: Center(
                                child:
                                    isBuffering && safeDuration == Duration.zero
                                    ? LinearProgressIndicator(
                                        minHeight: 3.5,
                                        backgroundColor: theme
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.14),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              theme.colorScheme.onSurface,
                                            ),
                                      )
                                    : SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3.5,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 5,
                                              ),
                                          overlayShape:
                                              SliderComponentShape.noOverlay,
                                          inactiveTrackColor: theme
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.14),
                                          activeTrackColor:
                                              theme.colorScheme.onSurface,
                                          thumbColor:
                                              theme.colorScheme.onSurface,
                                        ),
                                        child: Slider(
                                          value: progress,
                                          onChanged:
                                              safeDuration > Duration.zero
                                              ? (value) {
                                                  final nextPosition = Duration(
                                                    milliseconds:
                                                        (safeDuration
                                                                    .inMilliseconds *
                                                                value)
                                                            .round(),
                                                  );
                                                  _player.seek(nextPosition);
                                                }
                                              : null,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                currentLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorLabel ??
                                      '$totalLabel ${widget.fileSizeLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _errorLabel == null
                                        ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.64)
                                        : theme.colorScheme.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
