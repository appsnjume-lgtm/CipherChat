import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Section card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    if (isGX) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
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
// Section heading row (title + optional icon)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  final String title;
  final IconData? icon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;
    final theme = Theme.of(context);

    if (isGX) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: accent.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Container(width: 2, height: 14, color: accent),
              const SizedBox(width: 10),
              if (icon != null) ...[
                Icon(icon, color: accent, size: 15),
                const SizedBox(width: 8),
              ],
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-heading (used inside sections for groups like "Blocked users")
// ─────────────────────────────────────────────────────────────────────────────

class SettingsSubHeading extends StatelessWidget {
  const SettingsSubHeading({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;
    final theme = Theme.of(context);

    if (isGX) {
      return Row(
        children: [
          Icon(Icons.chevron_right_rounded, color: accent, size: 14),
          const SizedBox(width: 4),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save button
// ─────────────────────────────────────────────────────────────────────────────

class SettingsSaveButton extends StatelessWidget {
  const SettingsSaveButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isSaving,
    required this.onSave,
  });

  final String label;
  final IconData icon;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    final loadingIndicator = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 1.8,
        color: isGX ? accent : null,
      ),
    );

    if (isGX) {
      return GestureDetector(
        onTap: isSaving ? null : onSave,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isSaving
                ? accent.withValues(alpha: 0.06)
                : accent.withValues(alpha: 0.12),
            border: Border.all(
              color: isSaving
                  ? accent.withValues(alpha: 0.2)
                  : accent.withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isSaving ? loadingIndicator : Icon(icon, color: accent, size: 14),
              const SizedBox(width: 10),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: isSaving ? accent.withValues(alpha: 0.5) : accent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: isSaving ? null : onSave,
      icon: isSaving ? loadingIndicator : Icon(icon),
      label: Text(label),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown (replaces DropdownButtonFormField with GX-aware styling)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    if (isGX) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF191926),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF191926),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: accent,
              size: 18,
            ),
            hint: icon != null
                ? Row(
                    children: [
                      Icon(icon, color: accent, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1.0,
                          color: accent.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  )
                : null,
            selectedItemBuilder: (context) => values
                .map(
                  (item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null)
                          Row(
                            children: [
                              Icon(icon, color: accent, size: 12),
                              const SizedBox(width: 6),
                              Text(
                                label.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  letterSpacing: 1.0,
                                  color: accent.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              letterSpacing: 1.0,
                              color: accent.withValues(alpha: 0.6),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          itemLabel(item),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF0F0F8),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            items: values
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      itemLabel(item),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFF0F0F8),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      );
    }

    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      items: values
          .map(
            (item) =>
                DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle row (replaces SwitchListTile)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    if (isGX) {
      return GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: value ? accent.withValues(alpha: 0.06) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: accent.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: value ? accent : const Color(0xFF8888AA),
                  size: 16,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value ? accent : const Color(0xFFF0F0F8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Color(0xFF8888AA),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _GXToggleSwitch(value: value, accent: accent),
            ],
          ),
        ),
      );
    }

    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: icon != null ? Icon(icon) : null,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GXToggleSwitch extends StatelessWidget {
  const _GXToggleSwitch({required this.value, required this.accent});
  final bool value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 36,
      height: 20,
      decoration: BoxDecoration(
        color: value ? accent.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: value ? accent : const Color(0xFF8888AA),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeInOut,
            left: value ? 18 : 2,
            top: 2,
            child: Container(
              width: 14,
              height: 14,
              color: value ? accent : const Color(0xFF8888AA),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav tile (for AppearanceSection)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    if (isGX) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: accent.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF0F0F8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Color(0xFF8888AA),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Divider
// ─────────────────────────────────────────────────────────────────────────────

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    if (isGX) {
      return Container(height: 0.5, color: accent.withValues(alpha: 0.10));
    }
    return const Divider(height: 1);
  }
}
