import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/sticker.dart';
import '../providers/sticker_provider.dart';
import '../utils/sticker_media_preprocessor.dart';
import 'widgets/attachment_card.dart';
import 'widgets/sticker_crop_editor_screen.dart';
import 'widgets/video_sticker_editor.dart';

class CreateStickerScreen extends ConsumerStatefulWidget {
  const CreateStickerScreen({super.key, this.presentedInBottomSheet = false});

  final bool presentedInBottomSheet;

  @override
  ConsumerState<CreateStickerScreen> createState() =>
      _CreateStickerScreenState();
}

class _CreateStickerScreenState extends ConsumerState<CreateStickerScreen> {
  static const int _kAnimatedStickerFps = 15;
  static const int _kAnimatedStickerCanvasSize = 384;
  static const int _kAnimatedStickerQuality = 68;
  static const int _kAnimatedStickerCompressionLevel = 6;
  static const int _kStaticStickerCanvasSize = 512;
  static const int _kStaticStickerQuality = 78;
  static const int _kStaticStickerCompressionLevel = 6;

  final ImagePicker _imagePicker = ImagePicker();

  String? _selectedImagePath;
  String? _preparedImageInputPath;
  String? _selectedVideoPath;
  String? _generatedVideoStickerPath;
  String? _processingLabel;
  int? _clipDurationMs;
  int? _activeFfmpegSessionId;

  bool _isPublic = false;
  bool _isSubmitting = false;
  bool _isProcessing = false;
  bool _processingWasCancelled = false;

  String? get _activePath => _selectedVideoPath ?? _selectedImagePath;
  bool get _hasSelection => _activePath != null;
  bool get _busy => _isSubmitting || _isProcessing;

  @override
  void dispose() {
    unawaited(_cancelActiveFfmpegProcessing());
    final generatedVideoStickerPath = _generatedVideoStickerPath;
    if (generatedVideoStickerPath != null) {
      unawaited(_deleteFileIfExists(generatedVideoStickerPath));
    }
    final preparedImageInputPath = _preparedImageInputPath;
    if (preparedImageInputPath != null) {
      unawaited(_deleteFileIfExists(preparedImageInputPath));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.presentedInBottomSheet,
          leading: widget.presentedInBottomSheet
              ? IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          title: const Text('Create sticker'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 280,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildPreview(theme),
                ),
                const SizedBox(height: 16),
                AttachmentCard(
                  icon: Icons.photo_library_outlined,
                  title: 'Choose from gallery',
                  subtitle:
                      'Pick an image, crop it, then use the cropped result as the sticker input',
                  onTap: _busy ? null : () => _pickImage(ImageSource.gallery),
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  icon: Icons.camera_alt_outlined,
                  title: 'Take a photo',
                  subtitle:
                      'Capture a photo, crop it, and create a static sticker',
                  onTap: _busy ? null : () => _pickImage(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                AttachmentCard(
                  icon: Icons.videocam_outlined,
                  title: 'Choose a video clip',
                  subtitle:
                      'Trim, crop, and convert a short clip into an animated WebP sticker',
                  onTap: _busy ? null : _pickVideoClip,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Make sticker public'),
                  subtitle: const Text(
                    'Allow other users to add it to their libraries.',
                  ),
                  value: _isPublic,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _isPublic = value),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || !_hasSelection ? null : _createSticker,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_isSubmitting ? 'Creating...' : 'Create sticker'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_isProcessing) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            _processingLabel ?? 'Preparing sticker...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (_selectedVideoPath != null) {
      final durLabel = _clipDurationMs != null
          ? '${(_clipDurationMs! / 1000.0).toStringAsFixed(1)} s clip'
          : 'Animated WebP';
      return Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Image.file(
              File(_selectedVideoPath!),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.motion_photos_on_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$durLabel - Trimmed, cropped, animated WebP',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _pickVideoClip,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_selectedImagePath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Image.file(
              File(_selectedImagePath!),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.crop_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _preparedImageInputPath == null
                            ? 'Original image selected'
                            : 'Cropped image ready for sticker creation',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Change'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.sticky_note_2_outlined,
          size: 54,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Pick an image or video clip',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Images can be cropped first. Videos go trim -> crop -> animated WebP.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(source: source);
    if (image == null || !mounted) {
      return;
    }

    final cropSelection = await Navigator.of(context)
        .push<StickerCropSelection>(
          MaterialPageRoute<StickerCropSelection>(
            fullscreenDialog: true,
            builder: (_) =>
                StickerImageCropEditorScreen(file: File(image.path)),
          ),
        );
    if (cropSelection == null || !mounted) {
      return;
    }

    final shouldCrop = cropSelection.crop != null;
    if (shouldCrop) {
      setState(() {
        _isProcessing = true;
        _processingLabel = 'Cropping image...';
      });
    }

    try {
      final nextImagePath = shouldCrop
          ? await _cropImageForSticker(
              sourceImagePath: image.path,
              cropRect: cropSelection.crop!,
            )
          : image.path;
      await _clearGeneratedVideoSticker();
      await _clearPreparedImageInput();
      if (!mounted) {
        if (shouldCrop) {
          await _deleteFileIfExists(nextImagePath);
        }
        return;
      }

      setState(() {
        _selectedImagePath = nextImagePath;
        _preparedImageInputPath = shouldCrop ? nextImagePath : null;
        _selectedVideoPath = null;
        _clipDurationMs = null;
        _isProcessing = false;
        _processingLabel = null;
      });
    } on _StickerProcessingCancelled {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _processingLabel = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _processingLabel = null;
      });
      _showSnackBar('Could not crop image: $error');
    }
  }

  Future<void> _pickVideoClip() async {
    final video = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (video == null || !mounted) {
      return;
    }

    final trimResult = await Navigator.of(context).push<VideoTrimResult>(
      MaterialPageRoute<VideoTrimResult>(
        fullscreenDialog: true,
        builder: (_) => VideoStickerEditorScreen(file: File(video.path)),
      ),
    );
    if (trimResult == null || !mounted) {
      return;
    }

    final cropSelection = await Navigator.of(context)
        .push<StickerCropSelection>(
          MaterialPageRoute<StickerCropSelection>(
            fullscreenDialog: true,
            builder: (_) => StickerVideoCropEditorScreen(
              file: File(video.path),
              previewStartMs: trimResult.startMs,
            ),
          ),
        );
    if (cropSelection == null || !mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingLabel = 'Cropping and converting video...';
    });
    try {
      final webpPath = await _convertVideoToAnimatedWebp(
        sourceVideoPath: video.path,
        startMs: trimResult.startMs,
        durationMs: trimResult.durationMs,
        cropRect: cropSelection.crop,
      );
      await _clearGeneratedVideoSticker();
      await _clearPreparedImageInput();
      if (!mounted) {
        await _deleteFileIfExists(webpPath);
        return;
      }

      setState(() {
        _selectedVideoPath = webpPath;
        _generatedVideoStickerPath = webpPath;
        _selectedImagePath = null;
        _clipDurationMs = trimResult.durationMs;
        _isProcessing = false;
        _processingLabel = null;
      });
    } on _StickerProcessingCancelled {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _processingLabel = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _processingLabel = null;
      });
      _showSnackBar('Could not process video: $error');
    }
  }

  Future<String> _cropImageForSticker({
    required String sourceImagePath,
    required NormalizedCropRect cropRect,
  }) async {
    final outputPath = await StickerMediaPreprocessor.createTemporaryOutputPath(
      prefix: 'sticker_image_input',
      extension: 'webp',
    );
    final cropFilter = StickerMediaPreprocessor.buildCropFilter(cropRect);
    final command =
        '-i ${StickerMediaPreprocessor.quoteForFfmpeg(sourceImagePath)} '
        '-vf "$cropFilter,scale=$_kStaticStickerCanvasSize:$_kStaticStickerCanvasSize:force_original_aspect_ratio=decrease" '
        '-loop 0 '
        '-vcodec libwebp '
        '-lossless 0 '
        '-q:v $_kStaticStickerQuality '
        '-compression_level $_kStaticStickerCompressionLevel '
        '-preset picture '
        '-y ${StickerMediaPreprocessor.quoteForFfmpeg(outputPath)}';

    final session = await _executeFfmpeg(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isCancel(returnCode) || _processingWasCancelled) {
      await _deleteFileIfExists(outputPath);
      throw const _StickerProcessingCancelled();
    }
    if (!ReturnCode.isSuccess(returnCode)) {
      await _deleteFileIfExists(outputPath);
      final logs = await session.getLogs();
      final logMessage = logs.map((log) => log.getMessage()).join('\n');
      throw StateError('FFmpeg failed: $returnCode\n$logMessage');
    }

    final outputFile = File(outputPath);
    if (!await outputFile.exists()) {
      throw StateError('Cropped image output file was not created.');
    }
    return outputPath;
  }

  Future<String> _convertVideoToAnimatedWebp({
    required String sourceVideoPath,
    required int startMs,
    required int durationMs,
    NormalizedCropRect? cropRect,
  }) async {
    final outputPath = await StickerMediaPreprocessor.createTemporaryOutputPath(
      prefix: 'sticker_video',
      extension: 'webp',
    );
    final startSeconds = (startMs / 1000).toStringAsFixed(3);
    final durationSeconds = (durationMs / 1000).toStringAsFixed(3);
    final filters = <String>[
      if (cropRect != null) StickerMediaPreprocessor.buildCropFilter(cropRect),
      'fps=$_kAnimatedStickerFps',
      'scale=$_kAnimatedStickerCanvasSize:$_kAnimatedStickerCanvasSize:force_original_aspect_ratio=decrease',
      'pad=$_kAnimatedStickerCanvasSize:$_kAnimatedStickerCanvasSize:(ow-iw)/2:(oh-ih)/2:color=0x00000000',
      'format=rgba',
    ].join(',');
    final command =
        '-ss $startSeconds '
        '-t $durationSeconds '
        '-i ${StickerMediaPreprocessor.quoteForFfmpeg(sourceVideoPath)} '
        '-an '
        '-vf "$filters" '
        '-loop 0 '
        '-vcodec libwebp '
        '-lossless 0 '
        '-q:v $_kAnimatedStickerQuality '
        '-compression_level $_kAnimatedStickerCompressionLevel '
        '-preset picture '
        '-y ${StickerMediaPreprocessor.quoteForFfmpeg(outputPath)}';

    final session = await _executeFfmpeg(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isCancel(returnCode) || _processingWasCancelled) {
      await _deleteFileIfExists(outputPath);
      throw const _StickerProcessingCancelled();
    }
    if (!ReturnCode.isSuccess(returnCode)) {
      await _deleteFileIfExists(outputPath);
      final logs = await session.getLogs();
      final logMessage = logs.map((log) => log.getMessage()).join('\n');
      throw StateError('FFmpeg failed: $returnCode\n$logMessage');
    }

    final webpFile = File(outputPath);
    if (!await webpFile.exists()) {
      throw StateError('Animated WebP output file was not created.');
    }
    return outputPath;
  }

  Future<FFmpegSession> _executeFfmpeg(String command) async {
    _processingWasCancelled = false;
    final completer = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeAsync(command, (completedSession) {
      if (!completer.isCompleted) {
        completer.complete(completedSession);
      }
    });
    _activeFfmpegSessionId = session.getSessionId();
    try {
      return await completer.future;
    } finally {
      _activeFfmpegSessionId = null;
    }
  }

  Future<void> _cancelActiveFfmpegProcessing() async {
    final sessionId = _activeFfmpegSessionId;
    if (sessionId == null) {
      return;
    }
    _processingWasCancelled = true;
    try {
      await FFmpegKit.cancel(sessionId);
    } catch (_) {
      // Best-effort cancellation when the sheet is dismissed mid-process.
    }
  }

  Future<void> _clearGeneratedVideoSticker() async {
    final generatedPath = _generatedVideoStickerPath;
    _generatedVideoStickerPath = null;
    if (generatedPath == null || generatedPath.trim().isEmpty) {
      return;
    }
    await _deleteFileIfExists(generatedPath);
  }

  Future<void> _clearPreparedImageInput() async {
    final preparedPath = _preparedImageInputPath;
    _preparedImageInputPath = null;
    if (preparedPath == null || preparedPath.trim().isEmpty) {
      return;
    }
    await _deleteFileIfExists(preparedPath);
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return;
    }
    try {
      await file.delete();
    } catch (_) {
      // Best-effort temp file cleanup.
    }
  }

  Future<void> _createSticker() async {
    final sourcePath = _activePath;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final sticker = await ref
          .read(stickerLibraryProvider.notifier)
          .createSticker(sourcePath: sourcePath, isPublic: _isPublic);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop<Sticker>(sticker);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString());
      setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _StickerProcessingCancelled implements Exception {
  const _StickerProcessingCancelled();
}
