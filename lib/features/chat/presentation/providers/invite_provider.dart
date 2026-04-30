import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/local_notification_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/chat_request.dart';
import 'chat_provider.dart';

final invitesDashboardProvider =
    StateNotifierProvider.autoDispose<
      InviteDashboardController,
      AsyncValue<InviteDashboard>
    >((ref) {
      ref.watch(currentUserIdProvider);
      return InviteDashboardController(ref);
    });

final pendingInviteBadgeCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(
    invitesDashboardProvider.select(
      (state) => state.asData?.value.actionableCount ?? 0,
    ),
  );
});

final inviteActionsProvider = Provider<InviteActionsController>((ref) {
  return InviteActionsController(ref);
});

class InviteDashboardController
    extends StateNotifier<AsyncValue<InviteDashboard>> {
  InviteDashboardController(this._ref) : super(const AsyncLoading()) {
    _ref.onDispose(() {
      final channel = _requestsChannel;
      if (channel != null) {
        unawaited(
          _ref.read(chatRepositoryProvider).disposeRequestChannel(channel),
        );
      }
    });
    unawaited(_initialize());
  }

  final Ref _ref;
  RealtimeChannel? _requestsChannel;
  String? _subscribedUserId;
  Set<String> _adminChatIds = <String>{};
  int _lastActionableCount = 0;

  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      _subscribedUserId = null;
      _requestsChannel = null;
      _adminChatIds = <String>{};
      _lastActionableCount = 0;
      state = const AsyncData(InviteDashboard());
      return;
    }

    _ensureRealtimeSubscription(userId);

    try {
      final dashboard = await _fetchDashboard(userId);
      if (!mounted) {
        return;
      }
      _lastActionableCount = dashboard.actionableCount;
      state = AsyncData(dashboard);
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> refresh({bool notifyOnIncrease = false}) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      _lastActionableCount = 0;
      state = const AsyncData(InviteDashboard());
      return;
    }

    try {
      final previousCount =
          state.asData?.value.actionableCount ?? _lastActionableCount;
      final dashboard = await _fetchDashboard(userId);
      if (!mounted) {
        return;
      }

      state = AsyncData(dashboard);

      if (notifyOnIncrease && dashboard.actionableCount > previousCount) {
        await _showPendingRequestNotification(dashboard);
      }

      _lastActionableCount = dashboard.actionableCount;
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<InviteDashboard> _fetchDashboard(String userId) async {
    final repository = _ref.read(chatRepositoryProvider);
    final adminGroupIds = await repository.fetchAdminOwnedGroupIds(userId);
    _adminChatIds = adminGroupIds.toSet();

    final results = await Future.wait<dynamic>([
      repository.fetchIncomingInvites(userId),
      repository.fetchIncomingDirectRequests(userId),
      repository.fetchAdminRequests(userId, groupIds: adminGroupIds),
      repository.fetchSentRequests(userId),
    ]);

    return InviteDashboard(
      invites: results[0] as List<ChatRequest>,
      directRequests: results[1] as List<ChatRequest>,
      requests: results[2] as List<ChatRequest>,
      sent: results[3] as List<ChatRequest>,
    );
  }

  void _ensureRealtimeSubscription(String userId) {
    if (_subscribedUserId == userId && _requestsChannel != null) {
      return;
    }

    final existingChannel = _requestsChannel;
    if (existingChannel != null) {
      unawaited(
        _ref
            .read(chatRepositoryProvider)
            .disposeRequestChannel(existingChannel),
      );
    }

    _requestsChannel = _ref
        .read(chatRepositoryProvider)
        .subscribeToChatRequests(
          channelName: 'invite-dashboard-$userId',
          onChange: (_, payload) =>
              unawaited(_handleRequestChange(userId: userId, payload: payload)),
        );
    _subscribedUserId = userId;
  }

  Future<void> _handleRequestChange({
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    if (!await _isRelevantChange(userId: userId, payload: payload)) {
      return;
    }

    await refresh(notifyOnIncrease: true);
  }

  Future<bool> _isRelevantChange({
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    final targetUserId = payload['user_id'] as String?;
    final requestedBy = payload['requested_by'] as String?;
    if (targetUserId == userId || requestedBy == userId) {
      return true;
    }

    if (payload['type'] != 'join_request') {
      return false;
    }

    final chatId = payload['chat_id'] as String?;
    if (chatId == null) {
      return false;
    }

    if (_adminChatIds.contains(chatId)) {
      return true;
    }

    _adminChatIds =
        (await _ref
                .read(chatRepositoryProvider)
                .fetchAdminOwnedGroupIds(userId))
            .toSet();
    return _adminChatIds.contains(chatId);
  }

  Future<void> _showPendingRequestNotification(
    InviteDashboard dashboard,
  ) async {
    final count = dashboard.actionableCount;
    final title = count == 1
        ? 'New invite or request'
        : 'Invites & requests updated';
    final body = count == 1
        ? 'You have 1 pending invite or request.'
        : 'You now have $count pending invites or requests.';

    await LocalNotificationService.instance.showIncomingMessage(
      title: title,
      body: body,
      payload: '/invites',
    );
  }
}

class InviteDashboard {
  const InviteDashboard({
    this.invites = const [],
    this.directRequests = const [],
    this.requests = const [],
    this.sent = const [],
  });

  final List<ChatRequest> invites;
  final List<ChatRequest> directRequests;
  final List<ChatRequest> requests;
  final List<ChatRequest> sent;

  int get actionableCount =>
      invites.length + directRequests.length + requests.length;
}

class InviteActionsController {
  InviteActionsController(this._ref);

  final Ref _ref;

  Future<void> accept(ChatRequest request) async {
    await _respond(request, 'accepted');
  }

  Future<void> reject(ChatRequest request) async {
    await _respond(request, 'rejected');
  }

  Future<void> _respond(ChatRequest request, String status) async {
    final currentUserId = _ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      throw StateError('No authenticated user found.');
    }

    final chat = await _ref
        .read(chatRepositoryProvider)
        .respondToRequest(
          request: request,
          status: status,
          currentUserId: currentUserId,
        );
    _ref.invalidate(invitesDashboardProvider);
    _ref.invalidate(chatListProvider);
    _ref.invalidate(discoverGroupsProvider);
    final chatId = chat?.id ?? request.chatId;
    if (chatId != null) {
      _ref.invalidate(chatDetailsProvider(chatId));
    }
  }
}
