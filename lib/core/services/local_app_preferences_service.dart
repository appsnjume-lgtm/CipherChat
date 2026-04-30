import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class LocalAppPreferences {
  final AppThemePreference themePreference;
  final String paletteId;
  final String? gxPaletteId;

  const LocalAppPreferences({
    required this.themePreference,
    required this.paletteId,
    this.gxPaletteId,
  });
}

class LocalAppPreferencesService {
  static const String _userIdKey = 'user_id';
  static const String _themeModeKey = 'theme_mode';
  static const String _paletteIdKey = 'palette_id';
  static const String _gxPaletteIdKey = 'gx_palette_id';
  static const String _languageCodeKey = 'language_code';
  static const String _isFirstLaunchKey = 'is_first_launch';
  static const String _notificationEnabledKey = 'notifications_enabled';
  static const String _stickerLibraryVisibilityKey =
      'sticker_library_visibility';
  static const String _hapticFeedbackKey = 'haptic_feedback_enabled';
  static const String _pinchToZoomKey = 'pinch_to_zoom_enabled';
  static const String _doubleTapToReplyKey = 'double_tap_to_reply_enabled';
  static const String _autoDownloadMediaKey = 'auto_download_media';
  static const String _lastSyncTimestampKey = 'last_sync_timestamp';
  static const String _onboardingCompletedKey = 'onboarding_completed';

  static final LocalAppPreferencesService instance =
      LocalAppPreferencesService._internal();
  LocalAppPreferencesService._internal();
  factory LocalAppPreferencesService() => instance;

  // User ID
  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<void> clearUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
  }

  // Preferences Object for Settings
  Future<LocalAppPreferences> readPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr =
        prefs.getString(_themeModeKey) ?? AppThemePreference.system.name;
    final themePreference = AppThemePreference.values.firstWhere(
      (e) => e.name == themeStr,
      orElse: () => AppThemePreference.system,
    );
    final paletteId =
        prefs.getString(_paletteIdKey) ?? AppTheme.defaultPaletteId;
    final gxPaletteId = prefs.getString(_gxPaletteIdKey);

    return LocalAppPreferences(
      themePreference: themePreference,
      paletteId: paletteId,
      gxPaletteId: gxPaletteId,
    );
  }

  Future<void> writePreferences(LocalAppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, preferences.themePreference.name);
    await prefs.setString(_paletteIdKey, preferences.paletteId);
    if (preferences.gxPaletteId != null) {
      await prefs.setString(_gxPaletteIdKey, preferences.gxPaletteId!);
    } else {
      await prefs.remove(_gxPaletteIdKey);
    }
  }

  // Theme Mode
  Future<void> saveThemeMode(String themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, themeMode);
  }

  Future<String?> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey);
  }

  // Language Code
  Future<void> saveLanguageCode(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, languageCode);
  }

  Future<String?> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageCodeKey);
  }

  // First Launch
  Future<void> setFirstLaunchCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isFirstLaunchKey, false);
  }

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstLaunchKey) ?? true;
  }

  // Notifications
  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);
  }

  Future<bool?> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey);
  }

  // Sticker Library Visibility
  Future<void> setStickerLibraryVisibility(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stickerLibraryVisibilityKey, visible);
  }

  Future<bool?> getStickerLibraryVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_stickerLibraryVisibilityKey) ?? true;
  }

  // Haptic Feedback
  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticFeedbackKey, enabled);
  }

  Future<bool> isHapticFeedbackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hapticFeedbackKey) ?? true;
  }

  // Pinch to Zoom
  Future<void> setPinchToZoomEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinchToZoomKey, enabled);
  }

  Future<bool> isPinchToZoomEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pinchToZoomKey) ?? true;
  }

  // Double Tap to Reply
  Future<void> setDoubleTapToReplyEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doubleTapToReplyKey, enabled);
  }

  Future<bool> isDoubleTapToReplyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doubleTapToReplyKey) ?? true;
  }

  // Auto Download Media
  Future<void> setAutoDownloadMedia(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoDownloadMediaKey, enabled);
  }

  Future<bool> isAutoDownloadMediaEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoDownloadMediaKey) ?? false;
  }

  // Last Sync Timestamp
  Future<void> saveLastSyncTimestamp(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncTimestampKey, timestamp);
  }

  Future<int?> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSyncTimestampKey);
  }

  // Onboarding Completed
  Future<void> setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, true);
  }

  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  // Clear all preferences
  Future<void> clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
