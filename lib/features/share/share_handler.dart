import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/router/app_router.dart';
import '../../core/startup/app_startup.dart';
import '../../core/utils/app_error_helper.dart';
import 'share_controller.dart';

class ShareHandler {
  ShareHandler(this._ref);

  final WidgetRef _ref;
  final ReceiveSharingIntent _receiveSharingIntent =
      ReceiveSharingIntent.instance;

  StreamSubscription<List<SharedMediaFile>>? _mediaSubscription;
  String? _lastHandledSignature;
  bool _initialized = false;

  Future<String?> getInitialText() async {
    return _extractText(await getInitialMedia());
  }

  Future<List<SharedMediaFile>> getInitialMedia() {
    return _receiveSharingIntent.getInitialMedia();
  }

  Stream<String> getTextStream() {
    return getMediaStream()
        .map(_extractText)
        .where((text) => text != null && text.isNotEmpty)
        .cast<String>();
  }

  Stream<List<SharedMediaFile>> getMediaStream() {
    return _receiveSharingIntent.getMediaStream();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _mediaSubscription = getMediaStream().listen(
      _handleSharedMedia,
      onError: (error, _) {
        _ref
            .read(shareControllerProvider.notifier)
            .setError(AppErrorHelper.messageFor(error));
      },
    );

    final initialMedia = await getInitialMedia();
    await _handleSharedMedia(initialMedia, resetAfterHandling: true);
  }

  Future<void> dispose() async {
    await _mediaSubscription?.cancel();
  }

  Future<void> _handleSharedMedia(
    List<SharedMediaFile> media, {
    bool resetAfterHandling = false,
  }) async {
    try {
      if (media.isEmpty) {
        if (resetAfterHandling) {
          await _receiveSharingIntent.reset();
        }
        return;
      }

      final signature = _signatureFor(media);
      if (signature == _lastHandledSignature) {
        if (resetAfterHandling) {
          await _receiveSharingIntent.reset();
        }
        return;
      }

      final content = ShareController.fromSharedMedia(media);
      if (content == null) {
        if (resetAfterHandling) {
          await _receiveSharingIntent.reset();
        }
        return;
      }

      _lastHandledSignature = signature;
      await _ref
          .read(shareControllerProvider.notifier)
          .receiveSharedContent(content);
      _openShareFlow();

      if (resetAfterHandling) {
        await _receiveSharingIntent.reset();
      }
    } catch (error) {
      _ref
          .read(shareControllerProvider.notifier)
          .setError(AppErrorHelper.messageFor(error));
    }
  }

  String? _extractText(List<SharedMediaFile> media) {
    final content = ShareController.fromSharedMedia(media);
    return content?.type == SharedType.text ? content?.text : null;
  }

  String _signatureFor(List<SharedMediaFile> media) {
    return media
        .map((item) => '${item.type.value}|${item.path}|${item.message ?? ''}')
        .join('||');
  }

  void _openShareFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref
          .read(appRouterProvider(appStartupController.isSupabaseInitialized))
          .go('/share-handler');
    });
  }
}
