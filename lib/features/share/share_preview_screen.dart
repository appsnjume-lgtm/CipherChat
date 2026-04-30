import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/app_error_helper.dart';

import '../auth/presentation/providers/auth_provider.dart';
import '../chat/presentation/providers/chat_provider.dart';
import 'share_controller.dart';

class SharePreviewScreen extends ConsumerStatefulWidget {
  const SharePreviewScreen({super.key});

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  late final TextEditingController _textController;
  String _lastSyncedDraft = '';

  @override
  void initState() {
    super.initState();
    final initialDraft = ref.read(shareControllerProvider).draftText;
    _lastSyncedDraft = initialDraft;
    _textController = TextEditingController(text: initialDraft)
      ..addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareControllerProvider);
    final content = shareState.pendingContent;
    final chatId = shareState.selectedChatId;
    final currentUserId = ref.watch(currentUserIdProvider);

    if (_lastSyncedDraft != shareState.draftText &&
        _textController.text != shareState.draftText) {
      _lastSyncedDraft = shareState.draftText;
      _textController.value = TextEditingValue(
        text: shareState.draftText,
        selection: TextSelection.collapsed(offset: shareState.draftText.length),
      );
    }

    if (content == null || chatId == null || currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Share preview')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.share_outlined, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Your share session is no longer active.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Open chats'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chatAsync = ref.watch(chatDetailsProvider(chatId));
    final canSend =
        !shareState.isSending &&
        (content.type != SharedType.text ||
            shareState.draftText.trim().isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Share preview')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Card(
                    child: chatAsync.when(
                      data: (chat) => ListTile(
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text('Send to ${chat.titleFor(currentUserId)}'),
                        subtitle: Text(
                          chat.isGroup ? 'Group chat' : 'Direct chat',
                        ),
                      ),
                      loading: () => const ListTile(
                        leading: Icon(Icons.chat_bubble_outline_rounded),
                        title: Text('Loading chat...'),
                      ),
                      error: (error, _) => ListTile(
                        leading: const Icon(Icons.error_outline_rounded),
                        title: const Text('Unable to load chat'),
                        subtitle: Text(AppErrorHelper.messageFor(error)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PreviewCard(content: content),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textController,
                    minLines: content.type == SharedType.text ? 6 : 3,
                    maxLines: content.type == SharedType.text ? 10 : 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: content.type == SharedType.text
                          ? 'Edit text before sending'
                          : 'Optional caption',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (shareState.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      shareState.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: shareState.isSending
                          ? null
                          : () {
                              ref
                                  .read(shareControllerProvider.notifier)
                                  .clearShare();
                              context.go('/');
                            },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSend ? _sendSharedContent : null,
                      child: shareState.isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDraftChanged() {
    final value = _textController.text;
    if (_lastSyncedDraft == value) {
      return;
    }

    _lastSyncedDraft = value;
    ref.read(shareControllerProvider.notifier).updateDraftText(value);
  }

  Future<void> _sendSharedContent() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final chatId = await ref
          .read(shareControllerProvider.notifier)
          .sendSelectedContent();
      if (!mounted) {
        return;
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Shared content sent successfully.')),
        );
      context.go('/chat/$chatId');
    } catch (error) {
      if (!mounted) {
        return;
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppErrorHelper.messageFor(error))),
        );
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.content});

  final SharedContent content;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (content.type) {
          SharedType.text => _SharedTextPreview(text: content.text ?? ''),
          SharedType.image => _SharedImagePreview(
            paths: content.filePaths ?? const [],
          ),
          SharedType.file => _SharedFilePreview(
            paths: content.filePaths ?? const [],
          ),
        },
      ),
    );
  }
}

class _SharedTextPreview extends StatelessWidget {
  const _SharedTextPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shared text',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(text.isEmpty ? 'No text detected.' : text),
      ],
    );
  }
}

class _SharedImagePreview extends StatelessWidget {
  const _SharedImagePreview({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paths.length > 1 ? 'Shared images (${paths.length})' : 'Shared image',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: paths.length,
          itemBuilder: (context, index) {
            final path = paths[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SharedFilePreview extends StatelessWidget {
  const _SharedFilePreview({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paths.length > 1 ? 'Shared files (${paths.length})' : 'Shared file',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final path in paths) _SharedFileTile(path: path),
      ],
    );
  }
}

class _SharedFileTile extends StatelessWidget {
  const _SharedFileTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final sizeBytes = file.existsSync() ? file.lengthSync() : 0;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(p.basename(path)),
      subtitle: Text(_formatSize(sizeBytes)),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
