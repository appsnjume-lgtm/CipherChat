import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/startup/app_startup.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/auth_gate_screen.dart';
import '../../features/auth/presentation/screens/password_recovery_screen.dart';
import '../../features/call/presentation/screens/call_screen.dart';
import '../../features/chat/game/presentation/screens/game_screen.dart';
import '../../features/chat/presentation/screens/chat_background_editor_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/group_info_screen.dart';
import '../../features/chat/presentation/screens/invites_screen.dart';
import '../../features/chat/presentation/screens/user_search_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/profile/contact_profile_screen.dart';
import '../../features/settings/presentation/screens/privacy_policy_screen.dart';
import '../../features/settings/presentation/screens/profile_settings_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/theme_settings_screen.dart';
import '../../features/share/select_chat_screen.dart';
import '../../features/share/share_handler_screen.dart';
import '../../features/share/share_preview_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

bool _isPublicPath(String path) {
  return path == '/' ||
      path == '/onboarding' ||
      path == '/auth/recovery' ||
      path == '/settings/privacy';
}

final appRouterProvider = Provider.family<GoRouter, bool>((ref, isAuthReady) {
  final authState = isAuthReady ? ref.watch(authControllerProvider) : null;
  final hasSession = authState?.session != null;
  final hasCompletedProfile = hasSession && authState?.profile != null;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: appStartupController,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGateScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/recovery',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return PasswordRecoveryScreen(
            resetMode: mode == 'reset',
            initialErrorMessage: state.uri.queryParameters['error'],
          );
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          return UserSearchScreen(
            inviteChatId: state.uri.queryParameters['chatId'],
          );
        },
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          return ChatScreen(
            chatId: state.pathParameters['chatId']!,
            initialMessageId: state.uri.queryParameters['messageId'],
            initialSearchQuery: state.uri.queryParameters['search'],
          );
        },
      ),
      GoRoute(
        path: '/chat/game/:matchId',
        builder: (context, state) {
          return GameScreen(matchId: state.pathParameters['matchId']!);
        },
      ),
      GoRoute(
        path: '/profile/:userId',
        builder: (context, state) {
          return ContactProfileScreen(userId: state.pathParameters['userId']!);
        },
      ),
      GoRoute(
        path: '/call/:callId',
        builder: (context, state) {
          return CallScreen(
            callId: state.pathParameters['callId']!,
            isIncoming: state.uri.queryParameters['incoming'] == 'true',
          );
        },
      ),
      GoRoute(
        path: '/invites',
        builder: (context, state) => const InvitesScreen(),
      ),
      GoRoute(
        path: '/group/:chatId',
        builder: (context, state) {
          return GroupInfoScreen(chatId: state.pathParameters['chatId']!);
        },
      ),
      GoRoute(
        path: '/share-handler',
        builder: (context, state) => const ShareHandlerScreen(),
      ),
      GoRoute(
        path: '/select-chat',
        builder: (context, state) => const SelectChatScreen(),
      ),
      GoRoute(
        path: '/share-preview',
        builder: (context, state) => const SharePreviewScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/profile',
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/theme',
        builder: (context, state) => const ThemeSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/chat-background',
        builder: (context, state) => const ChatBackgroundEditorScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
    ],
    redirect: (context, state) {
      final path = state.uri.path;
      final isPublic = _isPublicPath(path);

      if (!appStartupController.onboardingCompleted && path != '/onboarding') {
        return '/onboarding';
      }

      if (appStartupController.onboardingCompleted && path == '/onboarding') {
        return '/';
      }

      if (!isAuthReady) {
        if (!isPublic) {
          final redirectTarget = state.uri.toString();
          return Uri(
            path: '/',
            queryParameters: {'redirect': redirectTarget},
          ).toString();
        }
        return null;
      }

      if (!hasSession && !isPublic) {
        final redirectTarget = state.uri.toString();
        return Uri(
          path: '/',
          queryParameters: {'redirect': redirectTarget},
        ).toString();
      }

      if (hasSession && !hasCompletedProfile && !isPublic) {
        final redirectTarget = state.uri.toString();
        return Uri(
          path: '/',
          queryParameters: {'redirect': redirectTarget},
        ).toString();
      }

      if (hasCompletedProfile && path == '/') {
        final redirectTarget = state.uri.queryParameters['redirect']?.trim();
        if (redirectTarget != null &&
            redirectTarget.isNotEmpty &&
            redirectTarget != state.uri.toString()) {
          return redirectTarget;
        }
      }

      return null;
    },
  );
});
