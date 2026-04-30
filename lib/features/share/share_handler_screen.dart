import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/presentation/providers/auth_provider.dart';
import '../auth/presentation/screens/auth_screen.dart';
import 'share_controller.dart';

class ShareHandlerScreen extends ConsumerStatefulWidget {
  const ShareHandlerScreen({super.key});

  @override
  ConsumerState<ShareHandlerScreen> createState() => _ShareHandlerScreenState();
}

class _ShareHandlerScreenState extends ConsumerState<ShareHandlerScreen> {
  bool _didNavigate = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final shareState = ref.watch(shareControllerProvider);

    if (shareState.pendingContent == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Share to CipherChat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.share_outlined, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'There is no shared content waiting right now.',
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

    if ((authState.isInitializing || authState.isSessionLoading) &&
        authState.profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!authState.isAuthenticated) {
      return const AuthScreen();
    }

    if (!_didNavigate) {
      _didNavigate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/select-chat');
        }
      });
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
