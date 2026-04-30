import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../common/widgets/app_avatar.dart';

import '../../data/models/call_models.dart';
import '../providers/call_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.callId, this.isIncoming = false});

  final String callId;
  final bool isIncoming;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(callControllerProvider(widget.callId).notifier)
          .initialize(isCaller: !widget.isIncoming);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider(widget.callId));
    final controller = ref.read(callControllerProvider(widget.callId).notifier);
    final session = state.session;

    ref.listen<CallState>(callControllerProvider(widget.callId), (
      previous,
      next,
    ) {
      final status = next.session?.status;
      if (status == AppCallStatus.ended ||
          status == AppCallStatus.rejected ||
          status == AppCallStatus.missed) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.isVideo == true ? 'Video call' : 'Audio call'),
      ),
      body: state.isInitializing || session == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: session.isVideo
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                color: Colors.black,
                                child: RTCVideoView(
                                  controller.remoteRenderer,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 16,
                              top: 16,
                              width: 120,
                              height: 160,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: RTCVideoView(
                                    controller.localRenderer,
                                    mirror: true,
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitCover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const AppAvatar(
                                size: 104,
                                avatarId: null,
                                fallbackIcon: Icons.call_rounded,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _statusLabel(session.status, widget.isIncoming),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                ),
                if (session.status == AppCallStatus.ringing &&
                    widget.isIncoming)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await controller.reject();
                                if (!context.mounted) {
                                  return;
                                }
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.call_end_rounded),
                              label: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => controller.accept(),
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            onPressed: () => controller.toggleMute(),
                            icon: Icon(
                              state.isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_none_rounded,
                            ),
                          ),
                          if (session.isVideo) ...[
                            const SizedBox(width: 16),
                            IconButton.filledTonal(
                              onPressed: () => controller.toggleCamera(),
                              icon: Icon(
                                state.isCameraEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                              ),
                            ),
                          ],
                          const SizedBox(width: 16),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onError,
                            ),
                            onPressed: () async {
                              await controller.endCall();
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.call_end_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _statusLabel(AppCallStatus status, bool isIncoming) {
    switch (status) {
      case AppCallStatus.ringing:
        return isIncoming ? 'Incoming secure call' : 'Calling...';
      case AppCallStatus.accepted:
        return 'Connected';
      case AppCallStatus.rejected:
        return 'Call rejected';
      case AppCallStatus.ended:
        return 'Call ended';
      case AppCallStatus.missed:
        return 'Missed call';
    }
  }
}
