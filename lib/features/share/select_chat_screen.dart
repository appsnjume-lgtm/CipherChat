import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/presentation/screens/chat_list_screen.dart';
import 'share_controller.dart';

class SelectChatScreen extends ConsumerWidget {
  const SelectChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shareState = ref.watch(shareControllerProvider);
    final content = shareState.pendingContent;
    if (content == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Select chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.share_outlined, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'There is no shared content available to send.',
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

    return ChatListScreen(
      selectionConfig: ChatListSelectionConfig(
        title: 'Select chat',
        infoText: _infoTextFor(content),
        emptyStateText: 'You need an existing chat before you can share here.',
        onChatSelected: (chat) async {
          final decision = await ref
              .read(shareControllerProvider.notifier)
              .validateChatSelection(chat);
          if (!context.mounted) {
            return;
          }

          if (!decision.isAllowed) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    decision.message ?? 'This chat is unavailable.',
                  ),
                ),
              );
            return;
          }

          ref.read(shareControllerProvider.notifier).selectChat(chat.id);
          context.push('/share-preview');
        },
      ),
    );
  }

  String _infoTextFor(SharedContent content) {
    switch (content.type) {
      case SharedType.text:
        return 'Choose a chat to share your text.';
      case SharedType.image:
        return content.fileCount > 1
            ? 'Choose a chat to share ${content.fileCount} images.'
            : 'Choose a chat to share your image.';
      case SharedType.file:
        return content.fileCount > 1
            ? 'Choose a chat to share ${content.fileCount} files.'
            : 'Choose a chat to share your file.';
    }
  }
}
