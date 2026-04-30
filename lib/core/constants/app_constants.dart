import 'dart:convert';

import 'package:flutter/services.dart';

class AppConstants {
  const AppConstants._();

  static const String appName = 'CipherChat';
  static const String authCallbackScheme = 'cipherchat';
  static const String authCallbackHost = 'auth-callback';
  static const int messagePageSize = 30;
  static const String secureMediaBucket = 'secure-media';
  static const String stickersBucket = 'stickers';
  static const String profileImagesBucket = 'profile-images';
  static const String groupImagesBucket = 'group-images';
  static const String encryptedMediaCacheFolder = 'cipherchat_secure_media';
  static const String hiddenMessagesStoragePrefix =
      'cipherchat_hidden_messages';
  static const String stunServerUrl = 'stun:stun.l.google.com:19302';
  static const List<String> maleAvatarIds = [
    'avatar_1',
    'avatar_2',
    'avatar_3',
  ];
  static const List<String> femaleAvatarIds = [
    'avatar_4',
    'avatar_5',
    'avatar_6',
  ];
  static const List<String> availableAvatarIds = [
    ...maleAvatarIds,
    ...femaleAvatarIds,
  ];

  static const String _dartDefineSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );

  static const String _dartDefineSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static String _configFileSupabaseUrl = '';
  static String _configFileSupabaseAnonKey = '';

  static String get supabaseUrl => _dartDefineSupabaseUrl.trim().isNotEmpty
      ? _dartDefineSupabaseUrl.trim()
      : _configFileSupabaseUrl;

  static String get supabaseAnonKey =>
      _dartDefineSupabaseAnonKey.trim().isNotEmpty
      ? _dartDefineSupabaseAnonKey.trim()
      : _configFileSupabaseAnonKey;

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> loadRuntimeConfig() async {
    if (_dartDefineSupabaseUrl.trim().isNotEmpty &&
        _dartDefineSupabaseAnonKey.trim().isNotEmpty) {
      return;
    }

    try {
      final rawConfig = await rootBundle.loadString('config.json');
      final decoded = jsonDecode(rawConfig);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      _configFileSupabaseUrl = (decoded['SUPABASE_URL'] as String? ?? '')
          .trim();
      _configFileSupabaseAnonKey =
          (decoded['SUPABASE_ANON_KEY'] as String? ?? '').trim();
    } on FormatException {
      // Invalid JSON should behave like missing runtime config.
    } catch (_) {
      // config.json is optional when the app is configured with dart-defines.
    }
  }

  static Uri get authCallbackUri =>
      Uri(scheme: authCallbackScheme, host: authCallbackHost);

  static String get authCallbackUrl => authCallbackUri.toString();

  static bool isAuthCallbackUri(Uri uri) {
    return uri.scheme == authCallbackScheme && uri.host == authCallbackHost;
  }

  static String? authCallbackType(Uri uri) {
    return authCallbackParameter(uri, 'type')?.toLowerCase();
  }

  static bool isPasswordRecoveryCallback(Uri uri) {
    return authCallbackType(uri) == 'recovery';
  }

  static String? authCallbackParameter(Uri uri, String key) {
    final direct = uri.queryParameters[key]?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }

    try {
      final fragmentParams = Uri.splitQueryString(fragment);
      final value = fragmentParams[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    } catch (_) {
      // Some providers may send non-query fragments; ignore them safely.
    }

    return null;
  }

  static String defaultAvatarIdForGender(String gender) {
    return gender == 'female' ? femaleAvatarIds.first : maleAvatarIds.first;
  }

  static bool isAvatarAllowedForGender({
    required String avatarId,
    required String gender,
  }) {
    if (!availableAvatarIds.contains(avatarId)) {
      return false;
    }

    if (gender == 'female') {
      return femaleAvatarIds.contains(avatarId);
    }

    return maleAvatarIds.contains(avatarId);
  }
}
