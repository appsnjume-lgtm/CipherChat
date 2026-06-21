import 'package:flutter/material.dart';

import '../../domain/entities/chat_request.dart';

class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final ChatRequest request;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title();
    final description = _description();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAccept(),
                    child: Text(request.isDirectRequest ? 'Accept' : 'Approve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onReject(),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _title() {
    if (request.isDirectRequest) {
      return request.requestedByUser?.displayNameOrUsername ??
          'Private chat request';
    }

    return request.chat?.titleFor(request.userId) ?? 'Group request';
  }

  String _description() {
    final requester =
        request.user?.displayNameOrUsername ??
        request.requestedByUser?.displayNameOrUsername ??
        'User';

    if (request.isDirectRequest) {
      return '$requester wants to start a private chat with you.';
    }

    return '$requester requested to join this group.';
  }
}
