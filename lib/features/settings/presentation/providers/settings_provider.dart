import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/services/local_app_preferences_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/providers/chat_provider.dart';

final localAppPreferencesServiceProvider = Provider<LocalAppPreferencesService>(
  (ref) {
    return LocalAppPreferencesService.instance;
  },
);

final initialThemeSettingsProvider = Provider<ThemeSettings>((ref) {
  return ThemeSettings.initial();
});

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsController, ThemeSettings>((ref) {
      return ThemeSettingsController(
        ref.watch(localAppPreferencesServiceProvider),
        initialState: ref.watch(initialThemeSettingsProvider),
      );
    });

final activePaletteProvider = Provider<AppColorPalette>((ref) {
  return ref.watch(themeSettingsProvider).palette;
});

final blockedUsersProvider = FutureProvider.autoDispose<List<AppUser>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return const [];
  }

  return ref.watch(chatRepositoryProvider).fetchBlockedUsers(userId);
});

class ThemeSettings {
  const ThemeSettings({
    required this.themePreference,
    required this.paletteId,
    this.gxPaletteId,
  });

  factory ThemeSettings.initial() {
    return const ThemeSettings(
      themePreference: AppThemePreference.system,
      paletteId: AppTheme.defaultPaletteId,
      gxPaletteId: null,
    );
  }

  factory ThemeSettings.fromPreferences(LocalAppPreferences preferences) {
    return ThemeSettings(
      themePreference: preferences.themePreference,
      paletteId: preferences.paletteId,
      gxPaletteId: preferences.gxPaletteId,
    );
  }

  final AppThemePreference themePreference;
  final String paletteId;
  final String? gxPaletteId;

  ThemeMode get themeMode => themePreference.themeMode;

  AppColorPalette get palette => AppTheme.paletteById(paletteId);

  GXColorPalette get gxPalette =>
      AppTheme.gxPaletteById(gxPaletteId ?? AppTheme.defaultGXPaletteId);

  ThemeSettings copyWith({
    AppThemePreference? themePreference,
    String? paletteId,
    String? gxPaletteId,
  }) {
    return ThemeSettings(
      themePreference: themePreference ?? this.themePreference,
      paletteId: paletteId ?? this.paletteId,
      gxPaletteId: gxPaletteId ?? this.gxPaletteId,
    );
  }
}

class ThemeSettingsController extends StateNotifier<ThemeSettings> {
  ThemeSettingsController(
    this._preferencesService, {
    required ThemeSettings initialState,
  }) : super(initialState);

  final LocalAppPreferencesService _preferencesService;

  void setThemePreference(AppThemePreference preference) {
    state = state.copyWith(themePreference: preference);
    unawaited(_persist());
  }

  void setPalette(String paletteId) {
    state = state.copyWith(paletteId: paletteId);
    unawaited(_persist());
  }

  void setGXPalette(String gxPaletteId) {
    state = state.copyWith(gxPaletteId: gxPaletteId);
    unawaited(_persist());
  }

  void hydrate(ThemeSettings settings) {
    state = settings;
  }

  Future<void> _persist() {
    return _preferencesService.writePreferences(
      LocalAppPreferences(
        themePreference: state.themePreference,
        paletteId: state.paletteId,
        gxPaletteId: state.gxPaletteId,
      ),
    );
  }
}
