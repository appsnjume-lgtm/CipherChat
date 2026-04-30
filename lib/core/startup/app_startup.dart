import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../constants/app_constants.dart';
import '../services/local_app_preferences_service.dart';

final appStartupController = AppStartupController();

class StartupTrace {
  const StartupTrace._();

  static T sync<T>(String label, T Function() action) {
    if (!kDebugMode) {
      return action();
    }

    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      debugPrint('[startup] $label: ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  static Future<T> async<T>(String label, Future<T> Function() action) async {
    if (!kDebugMode) {
      return action();
    }

    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      debugPrint('[startup] $label: ${stopwatch.elapsedMilliseconds}ms');
    }
  }
}

class AppStartupController extends ChangeNotifier {
  ThemeSettings _themeSettings = ThemeSettings.initial();
  bool _hasResolved = false;
  bool _isInitializing = false;
  bool _isSupabaseInitialized = false;
  Object? _fatalError;

  ThemeSettings get themeSettings => _themeSettings;
  bool get hasResolved => _hasResolved;
  bool get isReady => _hasResolved && _fatalError == null;
  bool get isSupabaseInitialized => _isSupabaseInitialized;
  Object? get fatalError => _fatalError;

  Future<void> initialize() async {
    if (_isInitializing || _hasResolved) {
      return;
    }

    _isInitializing = true;

    try {
      final results = await Future.wait<Object?>([_readInitialThemeSettings()]);

      final themeSettings = results.first as ThemeSettings?;
      if (themeSettings != null) {
        _themeSettings = themeSettings;
      }

      await StartupTrace.async(
        'runtime config read',
        AppConstants.loadRuntimeConfig,
      );

      final isSupabaseConfigured = StartupTrace.sync(
        'Supabase config read',
        () => AppConstants.isSupabaseConfigured,
      );

      if (isSupabaseConfigured) {
        await StartupTrace.async(
          'Supabase.initialize',
          () => Supabase.initialize(
            url: AppConstants.supabaseUrl,
            anonKey: AppConstants.supabaseAnonKey,
          ),
        );
        StartupTrace.sync(
          'Auth session recovery',
          () => Supabase.instance.client.auth.currentSession,
        );
        _isSupabaseInitialized = true;
      }
    } catch (error) {
      _fatalError = error;
    } finally {
      _isInitializing = false;
      _hasResolved = true;
      notifyListeners();
    }
  }

  Future<ThemeSettings?> _readInitialThemeSettings() async {
    try {
      final preferences = await LocalAppPreferencesService.instance
          .readPreferences();
      return ThemeSettings.fromPreferences(preferences);
    } catch (_) {
      // A preferences read failure should not block app startup.
      return null;
    }
  }
}
