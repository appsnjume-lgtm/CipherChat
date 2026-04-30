import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/startup/app_startup.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../chat/presentation/screens/chat_list_screen.dart';
import '../providers/auth_provider.dart';
import 'auth_screen.dart';

class AuthGateScreen extends ConsumerWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: appStartupController,
      builder: (context, _) {
        final isGX = GXThemeExtension.of(context).isGX;

        if (!appStartupController.hasResolved) {
          return const AuthGateSkeleton();
        }

        final startupError = appStartupController.fatalError;
        if (startupError != null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                isGX
                    ? AppConstants.appName.toUpperCase()
                    : AppConstants.appName,
                style: isGX
                    ? const TextStyle(
                        fontFamily: 'monospace',
                        letterSpacing: 2.0,
                      )
                    : null,
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      isGX ? 'STARTUP FAILED' : 'Startup failed.',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: isGX ? 'monospace' : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$startupError',
                      textAlign: TextAlign.center,
                      style: isGX
                          ? const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!AppConstants.isSupabaseConfigured) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                isGX
                    ? AppConstants.appName.toUpperCase()
                    : AppConstants.appName,
                style: isGX
                    ? const TextStyle(
                        fontFamily: 'monospace',
                        letterSpacing: 2.0,
                      )
                    : null,
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      isGX
                          ? 'SUPABASE NOT CONFIGURED'
                          : 'Supabase is not configured.',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: isGX ? 'monospace' : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                      Text(
                        isGX
                            ? 'PASS SUPABASE_URL AND SUPABASE_ANON_KEY WITH DART-DEFINES TO INITIALIZE UPLINK.'
                            : 'Pass SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define to enable auth, messaging, invites, and realtime.',
                        textAlign: TextAlign.center,
                      style: isGX
                          ? const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final authState = ref.watch(authControllerProvider);
        if ((authState.isInitializing || authState.isSessionLoading) &&
            authState.session == null) {
          return const AuthGateSkeleton();
        }

        if (!authState.isAuthenticated) {
          return const AuthScreen();
        }

        if (authState.needsProfileSetup) {
          return const AuthScreen();
        }

        return const ChatListScreen();
      },
    );
  }
}
