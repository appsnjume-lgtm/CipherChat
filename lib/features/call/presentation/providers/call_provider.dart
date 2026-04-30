import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/call_models.dart';
import '../../data/repositories/call_repository.dart';

final incomingCallProvider =
    StateNotifierProvider<IncomingCallController, CallSessionModel?>((ref) {
      return IncomingCallController(ref);
    });

final callControllerProvider = StateNotifierProvider.autoDispose
    .family<CallController, CallState, String>((ref, callId) {
      return CallController(ref, callId);
    });

class CallState {
  const CallState({
    required this.session,
    required this.isInitializing,
    required this.isConnecting,
    required this.isMuted,
    required this.isCameraEnabled,
    required this.errorMessage,
  });

  factory CallState.initial() {
    return const CallState(
      session: null,
      isInitializing: true,
      isConnecting: false,
      isMuted: false,
      isCameraEnabled: true,
      errorMessage: null,
    );
  }

  final CallSessionModel? session;
  final bool isInitializing;
  final bool isConnecting;
  final bool isMuted;
  final bool isCameraEnabled;
  final String? errorMessage;

  CallState copyWith({
    CallSessionModel? session,
    bool? isInitializing,
    bool? isConnecting,
    bool? isMuted,
    bool? isCameraEnabled,
    String? errorMessage,
  }) {
    return CallState(
      session: session ?? this.session,
      isInitializing: isInitializing ?? this.isInitializing,
      isConnecting: isConnecting ?? this.isConnecting,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class IncomingCallController extends StateNotifier<CallSessionModel?> {
  IncomingCallController(this._ref) : super(null) {
    _subscribe();
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  void _subscribe() {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      return;
    }

    _channel = _ref
        .read(callRepositoryProvider)
        .subscribeToIncomingCalls(
          userId: userId,
          onUpsert: (session) {
            if (session.status == AppCallStatus.ringing) {
              state = session;
            } else if (state?.id == session.id) {
              state = null;
            }
          },
        );
  }

  void clear() {
    state = null;
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      unawaited(
        _ref
            .read(callRepositoryProvider)
            .disposeChannel(channel)
            .catchError(
              (Object error) => debugPrint('channel dispose error: $error'),
            ),
      );
    }
    super.dispose();
  }
}

class CallController extends StateNotifier<CallState> {
  CallController(this._ref, this._callId) : super(CallState.initial());

  final Ref _ref;
  final String _callId;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RealtimeChannel? _signalChannel;
  RealtimeChannel? _sessionChannel;
  Map<String, dynamic>? _pendingOffer;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _initialized = false;

  String get _currentUserId {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }
    return userId;
  }

  Future<void> initialize({required bool isCaller}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      final session = await _ref
          .read(callRepositoryProvider)
          .fetchCallSession(_callId);
      state = state.copyWith(session: session, isInitializing: false);
      _subscribeRealtime();

      if (isCaller && session.status == AppCallStatus.ringing) {
        await _startOutgoingOffer(session);
      }
    } catch (error) {
      await _closePeerConnection();
      state = state.copyWith(
        isInitializing: false,
        errorMessage: AppErrorHelper.messageFor(error),
      );
    }
  }

  Future<void> accept() async {
    final session = state.session;
    if (session == null) {
      return;
    }

    await _ref
        .read(callRepositoryProvider)
        .updateCallStatus(callId: session.id, status: AppCallStatus.accepted);
    await _ensureLocalMedia(session);
    await _ensurePeerConnection(session);

    if (_pendingOffer != null) {
      await _applyOffer(_pendingOffer!);
      _pendingOffer = null;
    }
  }

  Future<void> reject() async {
    final session = state.session;
    if (session == null) {
      return;
    }

    await _ref
        .read(callRepositoryProvider)
        .updateCallStatus(callId: session.id, status: AppCallStatus.rejected);
    await _closePeerConnection();
  }

  Future<void> endCall() async {
    final session = state.session;
    if (session == null) {
      return;
    }

    await _ref
        .read(callRepositoryProvider)
        .sendSignal(
          callId: session.id,
          senderId: _currentUserId,
          eventType: 'hangup',
          payload: const {},
        );
    await _ref
        .read(callRepositoryProvider)
        .updateCallStatus(callId: session.id, status: AppCallStatus.ended);
    await _closePeerConnection();
  }

  Future<void> toggleMute() async {
    final muted = !state.isMuted;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    state = state.copyWith(isMuted: muted);
  }

  Future<void> toggleCamera() async {
    final session = state.session;
    if (session == null || !session.isVideo) {
      return;
    }

    final enabled = !state.isCameraEnabled;
    for (final track
        in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
    state = state.copyWith(isCameraEnabled: enabled);
  }

  void _subscribeRealtime() {
    final repository = _ref.read(callRepositoryProvider);
    _signalChannel = repository.subscribeToSignals(
      callId: _callId,
      onInsert: (signal) async {
        if (signal.senderId == _currentUserId) {
          return;
        }
        await _handleSignal(signal);
      },
    );

    _sessionChannel = repository.subscribeToCallSession(
      callId: _callId,
      onUpsert: (session) async {
        state = state.copyWith(session: session);
        if (session.status == AppCallStatus.rejected ||
            session.status == AppCallStatus.ended ||
            session.status == AppCallStatus.missed) {
          await _closePeerConnection();
        }
      },
    );
  }

  Future<void> _startOutgoingOffer(CallSessionModel session) async {
    state = state.copyWith(isConnecting: true, session: session);
    await _ensureLocalMedia(session);
    await _ensurePeerConnection(session);
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _ref
        .read(callRepositoryProvider)
        .sendSignal(
          callId: session.id,
          senderId: _currentUserId,
          eventType: 'offer',
          payload: {'type': offer.type, 'sdp': offer.sdp},
        );
  }

  Future<void> _handleSignal(CallSignalModel signal) async {
    switch (signal.eventType) {
      case 'offer':
        _pendingOffer = signal.payload;
        if (state.session?.status == AppCallStatus.accepted) {
          await _applyOffer(signal.payload);
          _pendingOffer = null;
        }
        break;
      case 'answer':
        final description = RTCSessionDescription(
          signal.payload['sdp'] as String,
          signal.payload['type'] as String,
        );
        await _peerConnection?.setRemoteDescription(description);
        state = state.copyWith(isConnecting: false);
        break;
      case 'candidate':
        final candidate = RTCIceCandidate(
          signal.payload['candidate'] as String?,
          signal.payload['sdpMid'] as String?,
          signal.payload['sdpMLineIndex'] as int?,
        );
        if (_peerConnection == null) {
          _pendingCandidates.add(candidate);
        } else {
          await _peerConnection!.addCandidate(candidate);
        }
        break;
      case 'hangup':
        await _closePeerConnection();
        break;
    }
  }

  Future<void> _applyOffer(Map<String, dynamic> payload) async {
    final session = state.session;
    if (session == null) {
      return;
    }

    await _ensureLocalMedia(session);
    await _ensurePeerConnection(session);
    final description = RTCSessionDescription(
      payload['sdp'] as String,
      payload['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(description);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await _ref
        .read(callRepositoryProvider)
        .sendSignal(
          callId: session.id,
          senderId: _currentUserId,
          eventType: 'answer',
          payload: {'type': answer.type, 'sdp': answer.sdp},
        );
    state = state.copyWith(isConnecting: false);
  }

  Future<void> _ensureLocalMedia(CallSessionModel session) async {
    if (_localStream != null) {
      return;
    }

    final constraints = {
      'audio': true,
      'video': session.isVideo ? {'facingMode': 'user'} : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localRenderer.srcObject = _localStream;
  }

  Future<void> _ensurePeerConnection(CallSessionModel session) async {
    if (_peerConnection != null) {
      return;
    }

    // Free calling path: STUN only. This keeps cost at zero but will be less
    // reliable on restrictive NATs because we intentionally do not use TURN.
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': [AppConstants.stunServerUrl],
        },
      ],
    });

    for (final track
        in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) {
        return;
      }
      await _ref
          .read(callRepositoryProvider)
          .sendSignal(
            callId: session.id,
            senderId: _currentUserId,
            eventType: 'candidate',
            payload: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          );
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
    };

    for (final candidate in _pendingCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _closePeerConnection() async {
    final peerConnection = _peerConnection;
    _peerConnection = null;
    await _releaseLocalMedia();
    await peerConnection?.close();
    _pendingOffer = null;
    _pendingCandidates.clear();
    if (!mounted) {
      return;
    }
    state = state.copyWith(
      isConnecting: false,
      isMuted: false,
      isCameraEnabled: true,
    );
  }

  Future<void> _releaseLocalMedia() async {
    final localStream = _localStream;
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    if (localStream == null) {
      return;
    }

    for (final track in localStream.getTracks()) {
      track.stop();
    }
    await localStream.dispose();
  }

  @override
  void dispose() {
    final signalChannel = _signalChannel;
    if (signalChannel != null) {
      unawaited(
        _ref
            .read(callRepositoryProvider)
            .disposeChannel(signalChannel)
            .catchError(
              (Object error) => debugPrint('channel dispose error: $error'),
            ),
      );
    }
    final sessionChannel = _sessionChannel;
    if (sessionChannel != null) {
      unawaited(
        _ref
            .read(callRepositoryProvider)
            .disposeChannel(sessionChannel)
            .catchError(
              (Object error) => debugPrint('channel dispose error: $error'),
            ),
      );
    }
    unawaited(_closePeerConnection());
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}

class IncomingCallListener extends ConsumerStatefulWidget {
  const IncomingCallListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  String? _activeCallId;

  @override
  Widget build(BuildContext context) {
    ref.listen<CallSessionModel?>(incomingCallProvider, (previous, next) {
      if (next == null || next.id == _activeCallId) {
        return;
      }
      _activeCallId = next.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.push('/call/${next.id}?incoming=true');
      });
    });

    return widget.child;
  }
}
