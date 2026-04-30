import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme mode enum (system / light / dark / gx)
// ─────────────────────────────────────────────────────────────────────────────

enum AppThemePreference { system, light, dark, gx }

extension AppThemePreferenceX on AppThemePreference {
  ThemeMode get themeMode {
    switch (this) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
      case AppThemePreference.gx:
        return ThemeMode.dark;
    }
  }

  bool get isGX => this == AppThemePreference.gx;

  String get label {
    switch (this) {
      case AppThemePreference.system:
        return 'System';
      case AppThemePreference.light:
        return 'Light';
      case AppThemePreference.dark:
        return 'Dark';
      case AppThemePreference.gx:
        return 'GX';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme extension — lets any widget know if GX mode is active
// ─────────────────────────────────────────────────────────────────────────────

class GXThemeExtension extends ThemeExtension<GXThemeExtension> {
  const GXThemeExtension({required this.isGX, required this.accent});

  final bool isGX;
  final Color accent;

  @override
  GXThemeExtension copyWith({bool? isGX, Color? accent}) {
    return GXThemeExtension(
      isGX: isGX ?? this.isGX,
      accent: accent ?? this.accent,
    );
  }

  @override
  GXThemeExtension lerp(GXThemeExtension? other, double t) {
    if (other == null) return this;
    return GXThemeExtension(
      isGX: t < 0.5 ? isGX : other.isGX,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
    );
  }

  static GXThemeExtension of(BuildContext context) {
    return Theme.of(context).extension<GXThemeExtension>() ??
        const GXThemeExtension(isGX: false, accent: Color(0xFFFF1744));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Normal palette
// ─────────────────────────────────────────────────────────────────────────────

class AppColorPalette {
  const AppColorPalette({
    required this.id,
    required this.label,
    required this.seedColor,
    required this.lightBackground,
    required this.darkBackground,
    required this.previewStart,
    required this.previewEnd,
  });

  final String id;
  final String label;
  final Color seedColor;
  final Color lightBackground;
  final Color darkBackground;
  final Color previewStart;
  final Color previewEnd;
}

// ─────────────────────────────────────────────────────────────────────────────
// GX palette
// ─────────────────────────────────────────────────────────────────────────────

class GXColorPalette {
  const GXColorPalette({
    required this.id,
    required this.label,
    required this.accent,
    required this.accentAlt,
    required this.background,
    required this.surface,
    required this.surface2,
  });

  final String id;
  final String label;
  final Color accent; // neon primary — borders, glows, active states
  final Color accentAlt; // secondary accent for gradients / previews
  final Color background; // scaffold
  final Color surface; // card / bubble bg
  final Color surface2; // elevated surface (inputs, reply bg)
}

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  const AppTheme._();

  // ── Normal palette catalogue ──────────────────────────────────────────────

  static const String defaultPaletteId = 'ocean_glass';

  static const List<AppColorPalette> palettes = [
    AppColorPalette(
      id: 'ocean_glass',
      label: 'Ocean Glass',
      seedColor: Color(0xFF0F766E),
      lightBackground: Color(0xFFF3F8F8),
      darkBackground: Color(0xFF071515),
      previewStart: Color(0xFF0F766E),
      previewEnd: Color(0xFF6EE7B7),
    ),
    AppColorPalette(
      id: 'ember_plum',
      label: 'Ember Plum',
      seedColor: Color(0xFFC2410C),
      lightBackground: Color(0xFFFAF1EE),
      darkBackground: Color(0xFF1A0D14),
      previewStart: Color(0xFFDC2626),
      previewEnd: Color(0xFF581C87),
    ),
    AppColorPalette(
      id: 'golden_dust',
      label: 'Golden Dust',
      seedColor: Color(0xFFB98900),
      lightBackground: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF0E0E0E),
      previewStart: Color(0xFFDFAD08),
      previewEnd: Color(0xFFD4A017),
    ),
    AppColorPalette(
      id: 'forest_code',
      label: 'Forest Code',
      seedColor: Color(0xFF166534),
      lightBackground: Color(0xFFF0F8F2),
      darkBackground: Color(0xFF08140C),
      previewStart: Color(0xFF166534),
      previewEnd: Color(0xFF4ADE80),
    ),
  ];

  // ── GX palette catalogue ──────────────────────────────────────────────────

  static const String defaultGXPaletteId = 'gx_classic';

  static const List<GXColorPalette> gxPalettes = [
    GXColorPalette(
      id: 'gx_classic',
      label: 'GX Classic',
      accent: Color(0xFFFF1744),
      accentAlt: Color(0xFF7C1FFF),
      background: Color(0xFF0B0B14),
      surface: Color(0xFF12121E),
      surface2: Color(0xFF191926),
    ),
    GXColorPalette(
      id: 'ultraviolet',
      label: 'Ultraviolet',
      accent: Color(0xFF9D6FFF),
      accentAlt: Color(0xFFB040FB),
      background: Color(0xFF0C0B16),
      surface: Color(0xFF13121F),
      surface2: Color(0xFF1A1830),
    ),
    GXColorPalette(
      id: 'sub_zero',
      label: 'Sub Zero',
      accent: Color(0xFF00CFFF),
      accentAlt: Color(0xFF00E5FF),
      background: Color(0xFF080E14),
      surface: Color(0xFF0E1620),
      surface2: Color(0xFF14202E),
    ),
    GXColorPalette(
      id: 'frutti_di_mare',
      label: 'Frutti Di Mare',
      accent: Color(0xFFFF6D3B),
      accentAlt: Color(0xFFFF1744),
      background: Color(0xFF120A08),
      surface: Color(0xFF1C1008),
      surface2: Color(0xFF251510),
    ),
    GXColorPalette(
      id: 'purple_haze',
      label: 'Purple Haze',
      accent: Color(0xFF7EFF14),
      accentAlt: Color(0xFFFF1744),
      background: Color(0xFF0D0B14),
      surface: Color(0xFF141020),
      surface2: Color(0xFF1C1830),
    ),
  ];

  // ── Lookups ───────────────────────────────────────────────────────────────

  static AppColorPalette paletteById(String id) =>
      palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);

  static GXColorPalette gxPaletteById(String id) =>
      gxPalettes.firstWhere((p) => p.id == id, orElse: () => gxPalettes.first);

  // ── Public builders ───────────────────────────────────────────────────────

  static ThemeData lightTheme([AppColorPalette? palette]) {
    final p = paletteById(palette?.id ?? defaultPaletteId);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.seedColor,
      brightness: Brightness.light,
    );
    return _buildNormalTheme(
      scheme: scheme,
      backgroundColor: p.lightBackground,
      cardColor: Colors.white,
      inputFillColor: scheme.surfaceContainerHighest,
      overlayStyle: SystemUiOverlayStyle.dark,
    );
  }

  static ThemeData darkTheme([AppColorPalette? palette]) {
    final p = paletteById(palette?.id ?? defaultPaletteId);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.seedColor,
      brightness: Brightness.dark,
    );
    return _buildNormalTheme(
      scheme: scheme,
      backgroundColor: p.darkBackground,
      cardColor: scheme.surfaceContainerHigh,
      inputFillColor: scheme.surfaceContainerHighest,
      overlayStyle: SystemUiOverlayStyle.light,
    );
  }

  /// Fully hand-crafted GX theme — no fromSeed, pure neon-on-black.
  static ThemeData gxTheme([GXColorPalette? palette]) {
    final p = gxPaletteById(palette?.id ?? defaultGXPaletteId);
    return _buildGXTheme(p);
  }

  // ── Normal theme builder (unchanged logic) ────────────────────────────────

  static ThemeData _buildNormalTheme({
    required ColorScheme scheme,
    required Color backgroundColor,
    required Color cardColor,
    required Color inputFillColor,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    final borderRadius = BorderRadius.circular(20);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: backgroundColor,
      extensions: const [
        GXThemeExtension(isGX: false, accent: Color(0xFF0F766E)),
      ],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        filled: true,
        fillColor: inputFillColor,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
      ),
    );
  }

  // ── GX theme builder ──────────────────────────────────────────────────────

  static ThemeData _buildGXTheme(GXColorPalette p) {
    // Fully manual ColorScheme — no M3 seed algorithm.
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      // Accent family
      primary: p.accent,
      onPrimary: const Color(0xFF0B0B14),
      primaryContainer: Color.alphaBlend(
        p.accent.withValues(alpha: 0.15),
        p.surface2,
      ),
      onPrimaryContainer: p.accent,
      // Secondary (dimmed accent)
      secondary: Color.lerp(p.accent, const Color(0xFF888899), 0.5) ?? p.accent,
      onSecondary: const Color(0xFFF0F0F8),
      secondaryContainer: p.surface2,
      onSecondaryContainer: const Color(0xFFCCCCDD),
      // Tertiary
      tertiary: p.accentAlt,
      onTertiary: const Color(0xFF0B0B14),
      tertiaryContainer: Color.alphaBlend(
        p.accentAlt.withValues(alpha: 0.12),
        p.surface2,
      ),
      onTertiaryContainer: p.accentAlt,
      // Error
      error: const Color(0xFFFF5252),
      onError: const Color(0xFF0B0B14),
      errorContainer: const Color(0xFF3A0A0A),
      onErrorContainer: const Color(0xFFFF8A80),
      // Surfaces — deep blue-black family
      surface: p.surface,
      onSurface: const Color(0xFFF0F0F8),
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface2,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: Color.alphaBlend(
        const Color(0x22FFFFFF),
        p.surface2,
      ),
      onSurfaceVariant: const Color(0xFF8888AA),
      // Outlines
      outline: Color.alphaBlend(p.accent.withValues(alpha: 0.25), p.surface2),
      outlineVariant: Color.alphaBlend(
        p.accent.withValues(alpha: 0.10),
        p.surface,
      ),
      // Misc
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFF0F0F8),
      onInverseSurface: const Color(0xFF12121E),
      inversePrimary: p.accent,
      surfaceTint: Colors.transparent, // kill M3 tinting
    );

    const mono = TextStyle(fontFamily: 'monospace', letterSpacing: 0.6);
    final labelMono = mono.copyWith(
      fontSize: 11,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      applyElevationOverlayColor: false,

      // ── GX extension so widgets can detect GX mode ──────────────────────
      extensions: [GXThemeExtension(isGX: true, accent: p.accent)],

      // ── AppBar ───────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: labelMono.copyWith(
          fontSize: 14,
          letterSpacing: 1.8,
          color: const Color(0xFFF0F0F8),
        ),
        iconTheme: IconThemeData(color: p.accent),
        actionsIconTheme: IconThemeData(color: p.accent),
        // 1px accent bottom border — the GX HUD line
        shape: Border(
          bottom: BorderSide(color: p.accent.withValues(alpha: 0.35), width: 1),
        ),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.accent.withValues(alpha: 0.18), width: 0.8),
        ),
      ),

      // ── Popup menu ────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: p.accent.withValues(alpha: 0.22), width: 0.8),
        ),
        textStyle: mono.copyWith(fontSize: 13, color: const Color(0xFFF0F0F8)),
      ),

      // ── Bottom sheet ──────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          side: BorderSide(color: p.accent.withValues(alpha: 0.28), width: 0.8),
        ),
      ),

      // ── Chips ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        backgroundColor: p.surface2,
        selectedColor: p.accent.withValues(alpha: 0.18),
        side: BorderSide(color: p.accent.withValues(alpha: 0.28), width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        labelStyle: labelMono.copyWith(color: const Color(0xFFCCCCDD)),
        secondaryLabelStyle: labelMono.copyWith(color: p.accent),
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: p.accent.withValues(alpha: 0.14),
        thickness: 0.5,
      ),

      // ── Inputs ────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: p.accent.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: p.accent.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
        hintStyle: mono.copyWith(fontSize: 14, color: const Color(0xFF8888AA)),
        labelStyle: labelMono.copyWith(color: p.accent),
      ),

      // ── List tiles ────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        tileColor: Colors.transparent,
        iconColor: p.accent,
      ),

      // ── Snack bars ────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surface2,
        contentTextStyle: mono.copyWith(
          fontSize: 13,
          color: const Color(0xFFF0F0F8),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: p.accent.withValues(alpha: 0.4), width: 0.8),
        ),
      ),

      // ── Tab bar ───────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: p.accent,
        unselectedLabelColor: const Color(0xFF8888AA),
        dividerColor: p.accent.withValues(alpha: 0.15),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        labelStyle: labelMono,
        unselectedLabelStyle: labelMono,
      ),

      // ── Segmented button ──────────────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return p.accent.withValues(alpha: 0.18);
            }
            return p.surface2;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return p.accent;
            return const Color(0xFF8888AA);
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: p.accent.withValues(alpha: 0.28), width: 0.8),
          ),
          textStyle: WidgetStateProperty.all(labelMono),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),

      // ── Text ─────────────────────────────────────────────────────────────
      textTheme: TextTheme(
        // Body stays readable — not monospace
        bodyLarge: mono.copyWith(
          fontSize: 15,
          color: const Color(0xFFF0F0F8),
          height: 1.5,
        ),
        bodyMedium: mono.copyWith(
          fontSize: 14,
          color: const Color(0xFFF0F0F8),
          height: 1.45,
        ),
        bodySmall: mono.copyWith(
          fontSize: 12,
          color: const Color(0xFF8888AA),
          height: 1.4,
        ),
        // Labels, titles → monospace with letter-spacing
        labelLarge: labelMono.copyWith(fontSize: 13),
        labelMedium: labelMono.copyWith(fontSize: 11),
        labelSmall: labelMono.copyWith(fontSize: 10),
        titleLarge: labelMono.copyWith(
          fontSize: 18,
          color: const Color(0xFFF0F0F8),
        ),
        titleMedium: labelMono.copyWith(
          fontSize: 15,
          color: const Color(0xFFF0F0F8),
        ),
        titleSmall: labelMono.copyWith(
          fontSize: 13,
          color: const Color(0xFFF0F0F8),
        ),
        headlineMedium: labelMono.copyWith(
          fontSize: 22,
          color: const Color(0xFFF0F0F8),
        ),
      ),

      iconTheme: IconThemeData(color: p.accent, size: 22),
    );
  }
}
