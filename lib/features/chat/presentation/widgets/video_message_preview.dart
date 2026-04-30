import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';

class VideoMessagePreview extends StatefulWidget {
  const VideoMessagePreview({
    super.key,
    required this.loadFile,
    required this.fileName,
    required this.subtitle,
  });

  final Future<File> Function() loadFile;
  final String fileName;
  final String subtitle;

  @override
  State<VideoMessagePreview> createState() => _VideoMessagePreviewState();
}

class _VideoMessagePreviewState extends State<VideoMessagePreview> {
  late final Future<_VideoPreviewData> _previewFuture = _loadPreview();

  Future<_VideoPreviewData> _loadPreview() async {
    final videoFile = await widget.loadFile();
    File? thumbnailFile;
    try {
      thumbnailFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 70,
        position: -1,
      );
    } catch (_) {
      thumbnailFile = null;
    }

    return _VideoPreviewData(
      videoFile: videoFile,
      thumbnailFile: thumbnailFile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: FutureBuilder<_VideoPreviewData>(
          future: _previewFuture,
          builder: (context, snapshot) {
            final thumbnailFile = snapshot.data?.thumbnailFile;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailFile != null &&
                    snapshot.connectionState == ConnectionState.done)
                  Image.file(thumbnailFile, fit: BoxFit.cover)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.surfaceContainerHighest,
                          theme.colorScheme.surfaceContainer,
                        ],
                      ),
                    ),
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.videocam_rounded,
                            size: 46,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.06),
                        Colors.black.withValues(alpha: 0.40),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.54),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VideoPreviewData {
  const _VideoPreviewData({required this.videoFile, this.thumbnailFile});

  final File videoFile;
  final File? thumbnailFile;
}
