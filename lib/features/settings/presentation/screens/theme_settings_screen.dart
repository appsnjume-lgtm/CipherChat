import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final controller = ref.read(themeSettingsProvider.notifier);
    final isGX = settings.themePreference.isGX;
    final gx = GXThemeExtension.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('THEME')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Mode selector ───────────────────────────────────────────────
          _SectionCard(
            isGX: isGX,
            accent: gx.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                  text: 'Theme mode',
                  isGX: isGX,
                  accent: gx.accent,
                ),
                const SizedBox(height: 6),
                Text(
                  isGX
                      ? 'GX mode active — full cyber interface engaged.'
                      : 'Switch between system, light, and dark — or go full GX.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                // Four-segment button — wraps on narrow screens
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppThemePreference.values.map((pref) {
                    final selected = settings.themePreference == pref;
                    return _ModeChip(
                      label: pref.label,
                      selected: selected,
                      isGXChip: pref.isGX,
                      accent: gx.accent,
                      isGXMode: isGX,
                      onTap: () => controller.setThemePreference(pref),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Palette heading ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: _SectionLabel(
              text: isGX ? 'GX colour preset' : 'Colour theme',
              isGX: isGX,
              accent: gx.accent,
            ),
          ),
          Text(
            isGX
                ? 'Each preset rewires the accent colour and surface depth across the entire interface.'
                : 'Pick a mood and the app updates in real time across screens.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // ── Palette grid ────────────────────────────────────────────────
          if (isGX)
            ...AppTheme.gxPalettes.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GXPaletteCard(
                  palette: p,
                  isSelected: settings.gxPalette.id == p.id,
                  onTap: () => controller.setGXPalette(p.id),
                ),
              ),
            )
          else
            ...AppTheme.palettes.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NormalPaletteCard(
                  palette: p,
                  isSelected: settings.paletteId == p.id,
                  onTap: () => controller.setPalette(p.id),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // ── Bubble style preview ────────────────────────────────────────
          _SectionCard(
            isGX: isGX,
            accent: gx.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                  text: 'Message bubble style',
                  isGX: isGX,
                  accent: gx.accent,
                ),
                const SizedBox(height: 16),
                _BubblePreview(isGX: isGX, accent: gx.accent),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.text,
    required this.isGX,
    required this.accent,
  });

  final String text;
  final bool isGX;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isGX) {
      return Row(
        children: [
          Container(width: 2, height: 14, color: accent),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      );
    }
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    required this.isGX,
    required this.accent,
  });

  final Widget child;
  final bool isGX;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isGX) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.8),
        ),
        child: child,
      );
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode chip
// ─────────────────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.isGXChip,
    required this.accent,
    required this.isGXMode,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isGXChip;
  final Color accent;
  final bool isGXMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // GX chip gets special neon treatment regardless of current mode
    if (isGXChip) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFF1744).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFF1744).withValues(alpha: 0.4),
              width: selected ? 1.4 : 0.8,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF1744).withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFF1744).withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    // Normal chip
    final selectedColor = isGXMode ? accent : theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: isGXMode ? 0.14 : 0.10)
              : (isGXMode
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(isGXMode ? 5 : 10),
          border: Border.all(
            color: selected
                ? selectedColor
                : (isGXMode
                      ? accent.withValues(alpha: 0.22)
                      : theme.colorScheme.outlineVariant),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: isGXMode ? 'monospace' : null,
            fontSize: 12,
            letterSpacing: isGXMode ? 1.2 : 0,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? selectedColor
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Normal palette card
// ─────────────────────────────────────────────────────────────────────────────

class _NormalPaletteCard extends StatelessWidget {
  const _NormalPaletteCard({
    required this.palette,
    required this.isSelected,
    required this.onTap,
  });

  final AppColorPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.previewStart, palette.previewEnd],
          ),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: palette.previewEnd.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      palette.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _ColorDot(color: palette.previewStart),
                        const SizedBox(width: 8),
                        _ColorDot(color: palette.previewEnd),
                        const SizedBox(width: 8),
                        _ColorDot(color: palette.seedColor),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GX palette card
// ─────────────────────────────────────────────────────────────────────────────

class _GXPaletteCard extends StatelessWidget {
  const _GXPaletteCard({
    required this.palette,
    required this.isSelected,
    required this.onTap,
  });

  final GXColorPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = palette.accent;
    final accentAlt = palette.accentAlt;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : accent.withValues(alpha: 0.22),
            width: isSelected ? 1.4 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // Background gradient bleed — top-right corner
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentAlt.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Left: colour swatches mimicking the GX preset preview
                    _GXSwatchPreview(
                      accent: accent,
                      accentAlt: accentAlt,
                      bg: palette.background,
                      surface: palette.surface2,
                    ),
                    const SizedBox(width: 16),
                    // Middle: label + swatch dots
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            palette.label.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _GXDot(color: accent),
                              const SizedBox(width: 6),
                              _GXDot(color: accentAlt),
                              const SizedBox(width: 6),
                              _GXDot(color: palette.surface2),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Right: selected indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? accent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : accent.withValues(alpha: 0.35),
                          width: isSelected ? 1.4 : 0.8,
                        ),
                      ),
                      child: isSelected
                          ? Icon(Icons.check, size: 12, color: accent)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small mini-preview of 3 dots arranged like the GX panel screenshot.
class _GXSwatchPreview extends StatelessWidget {
  const _GXSwatchPreview({
    required this.accent,
    required this.accentAlt,
    required this.bg,
    required this.surface,
  });

  final Color accent;
  final Color accentAlt;
  final Color bg;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _miniDot(accent),
            _miniDot(accentAlt.withValues(alpha: 0.7)),
            _miniDot(surface),
          ],
        ),
      ),
    );
  }

  Widget _miniDot(Color c) => Container(
    width: 10,
    height: 4,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
  );
}

class _GXDot extends StatelessWidget {
  const _GXDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 0.8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bubble style preview (shown at bottom of settings)
// ─────────────────────────────────────────────────────────────────────────────

class _BubblePreview extends StatelessWidget {
  const _BubblePreview({required this.isGX, required this.accent});

  final bool isGX;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Incoming
        Align(
          alignment: Alignment.centerLeft,
          child: isGX
              ? _GXBubble(
                  text: 'CIPHER MSG — 14:22',
                  isMine: false,
                  accent: accent,
                )
              : _NormalBubble(
                  text: 'Hey! How are you?',
                  isMine: false,
                  theme: theme,
                ),
        ),
        const SizedBox(height: 10),
        // Outgoing
        Align(
          alignment: Alignment.centerRight,
          child: isGX
              ? _GXBubble(
                  text: 'ALL SYSTEMS NOMINAL — 14:23',
                  isMine: true,
                  accent: accent,
                )
              : _NormalBubble(
                  text: "I'm good, thanks!",
                  isMine: true,
                  theme: theme,
                ),
        ),
      ],
    );
  }
}

class _NormalBubble extends StatelessWidget {
  const _NormalBubble({
    required this.text,
    required this.isMine,
    required this.theme,
  });

  final String text;
  final bool isMine;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: isMine
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _GXBubble extends StatelessWidget {
  const _GXBubble({
    required this.text,
    required this.isMine,
    required this.accent,
  });

  final String text;
  final bool isMine;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const cut = 8.0;
    final bg = isMine
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.08),
            const Color(0xFF12121E),
          )
        : const Color(0xFF12121E);

    return CustomPaint(
      foregroundPainter: _ChamferBorderPainter(
        accent: accent,
        cut: cut,
        glowOpacity: isMine ? 0.4 : 0.0,
      ),
      child: ClipPath(
        clipper: _ChamferClipper(cut: cut),
        child: Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 0.8,
              color: isMine ? accent : const Color(0xFFCCCCDD),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chamfer helpers (duplicated locally so settings screen is self-contained) ─

class _ChamferClipper extends CustomClipper<Path> {
  const _ChamferClipper({this.cut = 10});
  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(_ChamferClipper old) => old.cut != cut;
}

class _ChamferBorderPainter extends CustomPainter {
  const _ChamferBorderPainter({
    required this.accent,
    required this.cut,
    this.glowOpacity = 0.0,
  });

  final Color accent;
  final double cut;
  final double glowOpacity;

  Path _path(Size size) {
    final c = cut;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    if (glowOpacity > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: glowOpacity * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_ChamferBorderPainter old) =>
      old.accent != accent || old.cut != cut || old.glowOpacity != glowOpacity;
}
