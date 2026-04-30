import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/app_error_helper.dart';
import '../../../../core/widgets/app_error_card.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../domain/entities/chat_request.dart';
import '../providers/invite_provider.dart';
import '../widgets/invite_card.dart';
import '../widgets/request_card.dart';

class InvitesScreen extends ConsumerWidget {
  const InvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(invitesDashboardProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Invites & Requests'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Invites'),
              Tab(text: 'Direct'),
              Tab(text: 'Groups'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: dashboard.when(
          data: (data) => TabBarView(
            children: [
              _RequestList(
                emptyLabel: 'No incoming invites right now.',
                requests: data.invites,
                builder: (request) => InviteCard(
                  request: request,
                  onAccept: () =>
                      ref.read(inviteActionsProvider).accept(request),
                  onReject: () =>
                      ref.read(inviteActionsProvider).reject(request),
                ),
              ),
              _RequestList(
                emptyLabel: 'No private chat requests right now.',
                requests: data.directRequests,
                builder: (request) => RequestCard(
                  request: request,
                  onAccept: () =>
                      ref.read(inviteActionsProvider).accept(request),
                  onReject: () =>
                      ref.read(inviteActionsProvider).reject(request),
                ),
              ),
              _RequestList(
                emptyLabel: 'No pending join requests for your groups.',
                requests: data.requests,
                builder: (request) => RequestCard(
                  request: request,
                  onAccept: () =>
                      ref.read(inviteActionsProvider).accept(request),
                  onReject: () =>
                      ref.read(inviteActionsProvider).reject(request),
                ),
              ),
              _RequestList(
                emptyLabel:
                    'You have not sent any pending invites or requests.',
                requests: data.sent,
                builder: (request) => _SentCard(request: request),
              ),
            ],
          ),
          loading: () => const InvitesSkeleton(),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppErrorCard(
                message: AppErrorHelper.messageFor(error),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(invitesDashboardProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.builder,
    required this.emptyLabel,
  });

  final List<ChatRequest> requests;
  final Widget Function(ChatRequest request) builder;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(emptyLabel)),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => builder(requests[index]),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.request});

  final ChatRequest request;

  @override
  Widget build(BuildContext context) {
    final label = request.isInvite
        ? 'Invite sent to ${request.user?.username ?? request.userId}'
        : request.isDirectRequest
        ? 'Chat request sent to ${request.user?.username ?? request.userId}'
        : 'Join request sent by ${request.user?.username ?? request.userId}';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        title: Text(
          request.chat?.titleFor(request.userId) ??
              (request.isDirectRequest
                  ? 'Direct chat request'
                  : 'Pending request'),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(label),
        ),
        trailing: const Chip(label: Text('Pending')),
      ),
    );
  }
}
