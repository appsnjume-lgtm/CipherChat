import 'package:flutter/material.dart';

import '../../domain/entities/chat_request.dart';

class InviteCard extends StatelessWidget {
  const InviteCard({
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
    final title = request.chat?.titleFor(request.userId) ?? 'Group invite';
    final inviter = request.requestedByUser?.username ?? 'Admin';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('$inviter invited you to join this group chat.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAccept(),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onReject(),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
