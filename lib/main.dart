import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/startup/app_startup.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_error_helper.dart';
import 'features/auth/presentation/providers/auth_provider.dart'
    show authControllerProvider, authRepositoryProvider;
import 'features/call/presentation/providers/call_provider.dart';
import 'features/chat/application/services/pending_outgoing_message_sync_service.dart';
import 'features/chat/data/models/message_model.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/share/share_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep system UI setup, but do not let it delay the first frame.
  unawaited(_enableImmersiveSystemUi());

  SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
    if (systemOverlaysAreVisible) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await _enableImmersiveSystemUi();
    }
  });

  runApp(const ProviderScope(child: CipherChatApp()));
}

Future<void> _enableImmersiveSystemUi() {
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
}

class CipherChatApp extends ConsumerStatefulWidget {
  const CipherChatApp({super.key});

  @override
  ConsumerState<CipherChatApp> createState() => _CipherChatAppState();
}

class _CipherChatAppState extends ConsumerState<CipherChatApp>
    with WidgetsBindingObserver {
  final AppLinks _appLinks = AppLinks();
  final LocalNotificationService _notificationService =
      LocalNotificationService.instance;

  late final ShareHandler _shareHandler;
  StreamSubscription<Uri>? _appLinkSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  RealtimeChannel? _messageNotificationChannel;
  String? _subscribedUserId;
  Timer? _presenceHeartbeatTimer;
  Timer? _systemUiRestoreTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _firstFrameRendered = false;
  bool _startupTasksScheduled = false;
  bool _themeHydrated = false;
  final Map<String, _TimedCacheEntry<String>> _senderNameCache = {};
  final Map<String, _TimedCacheEntry<_NotificationChatMetadata>>
  _chatMetadataCache = {};

  static const _presenceHeartbeatInterval = Duration(seconds: 45);
  static const _systemUiRestoreDelay = Duration(seconds: 1);
  static const _pendingOutboxStartupDelay = Duration(seconds: 2);
  static const _notificationLookupTtl = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shareHandler = ShareHandler(ref);
    appStartupController.addListener(_handleStartupStateChanged);

    // Defer non-visual startup work until after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _firstFrameRendered) {
        return;
      }

      _firstFrameRendered = true;

      // Start heavy async initialization only after the first Flutter frame.
      unawaited(
        StartupTrace.async(
          'App startup controller initialize',
          appStartupController.initialize,
        ),
      );
      unawaited(_shareHandler.initialize());
      unawaited(_restoreSystemUiSoon());
      _handleStartupStateChanged();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appStartupController.removeListener(_handleStartupStateChanged);
    _appLinkSubscription?.cancel();
    _authStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _presenceHeartbeatTimer?.cancel();
    _systemUiRestoreTimer?.cancel();
    unawaited(_shareHandler.dispose());
    final channel = _messageNotificationChannel;
    if (channel != null && AppConstants.isSupabaseConfigured) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _handleStartupStateChanged() {
    if (!mounted || !_firstFrameRendered) {
      return;
    }

    if (appStartupController.hasResolved && !_themeHydrated) {
      _themeHydrated = true;
      ref
          .read(themeSettingsProvider.notifier)
          .hydrate(appStartupController.themeSettings);
    }

    if (!appStartupController.isReady || _startupTasksScheduled) {
      return;
    }

    _startupTasksScheduled = true;
    _listenForConnectivityChanges();
    unawaited(_listenForAuthCallbacks());
    unawaited(_initializeNotifications());
    _scheduleInitialPendingOutboxSync();
  }

  void _scheduleInitialPendingOutboxSync() {
    unawaited(
      Future<void>.delayed(_pendingOutboxStartupDelay, () async {
        if (!mounted || !appStartupController.isReady) {
          return;
        }

        await ref
            .read(pendingOutgoingMessageSyncServiceProvider)
            .syncAllPendingMessages();
      }),
    );
  }

  void _listenForConnectivityChanges() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = ref
        .read(connectivityServiceProvider)
        .watchConnection()
        .listen((isOnline) {
          if (isOnline) {
            unawaited(
              ref
                  .read(pendingOutgoingMessageSyncServiceProvider)
                  .syncAllPendingMessages(),
            );
          }
        });
  }

  Future<void> _listenForAuthCallbacks() async {
    if (!AppConstants.isSupabaseConfigured ||
        !appStartupController.isSupabaseInitialized) {
      return;
    }

    final initialUri = await _appLinks.getInitialLink();
    await _handleAuthCallback(initialUri);

    _appLinkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      await _handleAuthCallback(uri);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncPresenceHeartbeatLoop();
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreSystemUiSoon());
    }
    unawaited(_syncPresenceForLifecycle(state));
  }

  void _syncPresenceHeartbeatLoop() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;

    if (!AppConstants.isSupabaseConfigured ||
        !appStartupController.isSupabaseInitialized) {
      return;
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || _lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    _presenceHeartbeatTimer = Timer.periodic(
      _presenceHeartbeatInterval,
      (_) => unawaited(_sendPresenceHeartbeat(userId: currentUserId)),
    );
  }

  Future<void> _sendPresenceHeartbeat({String? userId}) async {
    if (!AppConstants.isSupabaseConfigured ||
        !appStartupController.isSupabaseInitialized) {
      return;
    }

    final currentUserId =
        userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      _presenceHeartbeatTimer?.cancel();
      _presenceHeartbeatTimer = null;
      return;
    }

    try {
      await ref.read(authRepositoryProvider).touchLastSeen(currentUserId);
    } catch (_) {
      // Presence heartbeats should never interrupt the app lifecycle.
    }
  }

  Future<void> _syncPresenceForLifecycle(AppLifecycleState state) async {
    if (!AppConstants.isSupabaseConfigured ||
        !appStartupController.isSupabaseInitialized) {
      return;
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      _presenceHeartbeatTimer?.cancel();
      _presenceHeartbeatTimer = null;
      return;
    }

    final repository = ref.read(authRepositoryProvider);
    try {
      switch (state) {
        case AppLifecycleState.resumed:
          _syncPresenceHeartbeatLoop();
          await _sendPresenceHeartbeat(userId: currentUserId);
          break;
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          _presenceHeartbeatTimer?.cancel();
          _presenceHeartbeatTimer = null;
          await repository.setOnlineStatus(
            userId: currentUserId,
            isOnline: false,
          );
          break;
        case AppLifecycleState.inactive:
          break;
      }
    } catch (_) {
      // Presence updates should never interrupt the app lifecycle.
    }
  }

  Future<void> _initializeNotifications() async {
    if (!AppConstants.isSupabaseConfigured ||
        !appStartupController.isSupabaseInitialized) {
      return;
    }

    await _notificationService.initialize();

    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) async {
          await _syncMessageNotificationSubscription();
          _syncPresenceHeartbeatLoop();
        });

    await _syncMessageNotificationSubscription();
    _syncPresenceHeartbeatLoop();
  }

  Future<void> _syncMessageNotificationSubscription() async {
    if (!appStartupController.isSupabaseInitialized) {
      return;
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (currentUserId == _subscribedUserId &&
        _messageNotificationChannel != null) {
      return;
    }

    final existingChannel = _messageNotificationChannel;
    if (existingChannel != null) {
      await Supabase.instance.client.removeChannel(existingChannel);
      _messageNotificationChannel = null;
      _subscribedUserId = null;
      _clearNotificationLookupCaches();
    }

    if (currentUserId == null) {
      _presenceHeartbeatTimer?.cancel();
      _presenceHeartbeatTimer = null;
      _clearNotificationLookupCaches();
      return;
    }

    final channel = StartupTrace.sync(
      'Notification realtime setup',
      () =>
          Supabase.instance.client
              .channel('incoming-message-notifications-$currentUserId')
              .onPostgresChanges(
                event: PostgresChangeEvent.insert,
                schema: 'public',
                table: 'messages',
                callback: (payload) async {
                  final message = MessageModel.fromMap(payload.newRecord);
                  if (message.senderId == currentUserId) {
                    return;
                  }

                  await _showIncomingMessageNotification(message);
                },
              )
            ..subscribe(),
    );

    _messageNotificationChannel = channel;
    _subscribedUserId = currentUserId;
    _syncPresenceHeartbeatLoop();
    unawaited(_sendPresenceHeartbeat(userId: currentUserId));
  }

  Future<void> _showIncomingMessageNotification(MessageModel message) async {
    if (!appStartupController.isSupabaseInitialized) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) {
        return;
      }

      final currentProfile = ref.read(authControllerProvider).profile;
      final messageNotificationsEnabled =
          currentProfile?.messageNotificationsEnabled ?? true;
      final groupNotificationsEnabled =
          currentProfile?.groupNotificationsEnabled ?? true;
      final previewEnabled =
          currentProfile?.notificationPreviewEnabled ?? true;

      final results = await Future.wait<Object?>([
        _senderDisplayName(message.senderId),
        _chatNotificationMetadata(message.chatId),
      ]);

      final senderName = results[0] as String? ?? 'Encrypted chat';
      final chatMetadata =
          results[1] as _NotificationChatMetadata? ??
          const _NotificationChatMetadata(isGroup: false, title: null);
      final groupTitle = chatMetadata.title?.trim();

      if ((!chatMetadata.isGroup && !messageNotificationsEnabled) ||
          (chatMetadata.isGroup && !groupNotificationsEnabled)) {
        return;
      }

      await _notificationService.showIncomingMessage(
        title: chatMetadata.isGroup && (groupTitle?.isNotEmpty ?? false)
            ? groupTitle!
            : senderName,
        body: previewEnabled
            ? 'New encrypted ${message.kind.name} message'
            : 'New message',
        payload: message.chatId,
      );
    } catch (_) {
      // Notification failures should never break the chat app.
    }
  }

  Future<String> _senderDisplayName(String senderId) async {
    final cached = _senderNameCache[senderId];
    if (_isFresh(cached)) {
      return cached!.value;
    }

    final rows = await Supabase.instance.client.rpc(
      'get_visible_profiles_by_ids',
      params: {
        'p_user_ids': [senderId],
      },
    );
    final senderRow = rows is List && rows.isNotEmpty
        ? Map<String, dynamic>.from(rows.first as Map)
        : null;
    final name = (senderRow?['username'] as String?)?.trim();
    final displayName = name == null || name.isEmpty
        ? 'Encrypted chat'
        : name;
    _senderNameCache[senderId] = _TimedCacheEntry(
      value: displayName,
      cachedAt: DateTime.now(),
    );
    return displayName;
  }

  Future<_NotificationChatMetadata> _chatNotificationMetadata(
    String chatId,
  ) async {
    final cached = _chatMetadataCache[chatId];
    if (_isFresh(cached)) {
      return cached!.value;
    }

    final row = await Supabase.instance.client
        .from('chats')
        .select('is_group, title')
        .eq('id', chatId)
        .maybeSingle();
    final metadata = _NotificationChatMetadata(
      isGroup: row?['is_group'] as bool? ?? false,
      title: (row?['title'] as String?)?.trim(),
    );
    _chatMetadataCache[chatId] = _TimedCacheEntry(
      value: metadata,
      cachedAt: DateTime.now(),
    );
    return metadata;
  }

  bool _isFresh<T>(_TimedCacheEntry<T>? entry) {
    return entry != null &&
        DateTime.now().difference(entry.cachedAt) < _notificationLookupTtl;
  }

  void _clearNotificationLookupCaches() {
    _senderNameCache.clear();
    _chatMetadataCache.clear();
  }

  Future<void> _handleAuthCallback(Uri? uri) async {
    if (!appStartupController.isSupabaseInitialized ||
        uri == null ||
        !AppConstants.isAuthCallbackUri(uri)) {
      return;
    }

    final router = ref.read(
      appRouterProvider(appStartupController.isSupabaseInitialized),
    );
    final isRecoveryFlow = AppConstants.isPasswordRecoveryCallback(uri);

    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      if (isRecoveryFlow) {
        router.go('/auth/recovery?mode=reset');
      }
    } catch (error) {
      if (isRecoveryFlow) {
        final message = Uri.encodeComponent(
          AppErrorHelper.passwordRecoveryCallbackMessageFor(error),
        );
        router.go('/auth/recovery?mode=reset&error=$message');
      }
    }
  }

  Future<void> _restoreSystemUiSoon() async {
    _systemUiRestoreTimer?.cancel();
    _systemUiRestoreTimer = Timer(_systemUiRestoreDelay, () {
      unawaited(_enableImmersiveSystemUi());
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeSettingsProvider);
    final palette = ref.watch(activePaletteProvider);

    return AnimatedBuilder(
      animation: appStartupController,
      builder: (context, _) {
        final brightness = switch (settings.themePreference) {
          AppThemePreference.light => Brightness.light,
          AppThemePreference.dark || AppThemePreference.gx => Brightness.dark,
          AppThemePreference.system =>
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
        };

        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: brightness,
          ),
        );

        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(palette),
          darkTheme: settings.themePreference == AppThemePreference.gx
              ? AppTheme.gxTheme(settings.gxPalette)
              : AppTheme.darkTheme(palette),
          themeMode: settings.themeMode,
          routerConfig: ref.watch(
            appRouterProvider(appStartupController.isSupabaseInitialized),
          ),
          builder: (context, child) {
            final appChild = appStartupController.isReady
                ? IncomingCallListener(child: child ?? const SizedBox.shrink())
                : child ?? const SizedBox.shrink();

            return _GlobalTapToDismissKeyboard(
              onPointerDown: _restoreSystemUiSoon,
              child: appChild,
            );
          },
        );
      },
    );
  }
}

class _TimedCacheEntry<T> {
  const _TimedCacheEntry({required this.value, required this.cachedAt});

  final T value;
  final DateTime cachedAt;
}

class _NotificationChatMetadata {
  const _NotificationChatMetadata({required this.isGroup, required this.title});

  final bool isGroup;
  final String? title;
}

class _GlobalTapToDismissKeyboard extends StatelessWidget {
  const _GlobalTapToDismissKeyboard({
    required this.child,
    required this.onPointerDown,
  });

  final Widget child;
  final Future<void> Function() onPointerDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        unawaited(onPointerDown());

        final focused = FocusManager.instance.primaryFocus;
        if (focused == null) {
          return;
        }

        final focusContext = focused.context;
        final renderObject = focusContext?.findRenderObject();
        if (renderObject is! RenderBox) {
          focused.unfocus();
          return;
        }

        final localPosition = renderObject.globalToLocal(event.position);
        if (!renderObject.paintBounds.contains(localPosition)) {
          focused.unfocus();
        }
      },
      child: child,
    );
  }
}
