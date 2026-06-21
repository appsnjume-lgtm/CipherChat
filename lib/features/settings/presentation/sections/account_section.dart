import 'package:flutter/material.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../widgets/settings_widgets.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.formKey,
    required this.profile,
    required this.displayNameController,
    required this.usernameController,
    required this.bioController,
    required this.selectedGender,
    required this.avatarId,
    required this.isSaving,
    required this.onGenderChanged,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
    required this.onChooseAvatar,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final AppUser profile;
  final TextEditingController displayNameController;
  final TextEditingController usernameController;
  final TextEditingController bioController;
  final AppGender selectedGender;
  final String avatarId;
  final bool isSaving;
  final ValueChanged<AppGender> onGenderChanged;
  final Future<void> Function() onUploadPhoto;
  final Future<void> Function() onRemovePhoto;
  final Future<void> Function() onChooseAvatar;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;
    final accent = GXThemeExtension.of(context).accent;

    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionHeader(
            title: isGX ? 'Identity' : 'Account',
            icon: Icons.person_outline_rounded,
            padding: isGX
                ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
                : EdgeInsets.zero,
          ),
          Padding(
            padding: EdgeInsets.all(isGX ? 16 : 0),
            child: Form(
              key: formKey,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isGX) const SizedBox(height: 14),

                // ── Avatar row ──────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _AvatarShell(
                      avatarId: avatarId,
                      imageUrl: profile.profileImageUrl,
                      isGX: isGX,
                      accent: accent,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: isGX
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _GXPhotoButton(
                                  icon: Icons.upload_rounded,
                                  label: 'Upload Photo',
                                  accent: accent,
                                  onTap: isSaving ? null : onUploadPhoto,
                                ),
                                const SizedBox(height: 8),
                                _GXPhotoButton(
                                  icon: Icons.face_retouching_natural_outlined,
                                  label: 'Choose Avatar',
                                  accent: accent,
                                  onTap: isSaving ? null : onChooseAvatar,
                                ),
                                if (profile.hasCustomProfileImage) ...[
                                  const SizedBox(height: 8),
                                  _GXPhotoButton(
                                    icon: Icons.delete_outline_rounded,
                                    label: 'Remove Photo',
                                    accent: const Color(0xFFFF5252),
                                    onTap: isSaving ? null : onRemovePhoto,
                                    destructive: true,
                                  ),
                                ],
                              ],
                            )
                          : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () => onUploadPhoto(),
                                  icon: const Icon(Icons.upload_rounded),
                                  label: const Text('Upload Photo'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () => onChooseAvatar(),
                                  icon: const Icon(
                                    Icons.face_retouching_natural_outlined,
                                  ),
                                  label: const Text('Choose Avatar'),
                                ),
                                if (profile.hasCustomProfileImage)
                                  TextButton.icon(
                                    onPressed: isSaving
                                        ? null
                                        : () => onRemovePhoto(),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    label: const Text('Remove Photo'),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),

                SizedBox(height: isGX ? 20 : 18),

                // ── Username ────────────────────────────────────────────
                TextField(
                  controller: displayNameController,
                  textInputAction: TextInputAction.next,
                  style: isGX
                      ? const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFFF0F0F8),
                        )
                      : null,
                  decoration: InputDecoration(
                    labelText: isGX ? 'DISPLAY NAME' : 'Display name',
                    prefixIcon: isGX
                        ? Icon(Icons.badge_outlined, color: accent, size: 16)
                        : null,
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: usernameController,
                  textInputAction: TextInputAction.next,
                  validator: AppErrorHelper.usernameValidationMessage,
                  style: isGX
                      ? const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFFF0F0F8),
                        )
                      : null,
                  decoration: InputDecoration(
                    labelText: isGX ? 'USERNAME' : 'Username',
                    helperText: isGX
                        ? null
                        : 'Use lowercase letters, numbers, dots, and underscores.',
                    prefixIcon: isGX
                        ? Icon(
                            Icons.alternate_email_rounded,
                            color: accent,
                            size: 16,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Bio ─────────────────────────────────────────────────
                TextField(
                  controller: bioController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 280,
                  style: isGX
                      ? const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFFF0F0F8),
                        )
                      : null,
                  decoration: InputDecoration(
                    labelText: isGX ? 'BIO / ABOUT' : 'Bio / About',
                    prefixIcon: isGX
                        ? Icon(Icons.notes_rounded, color: accent, size: 16)
                        : null,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Gender ──────────────────────────────────────────────
                SettingsSubHeading(text: isGX ? 'Gender identity' : 'Gender'),
                const SizedBox(height: 10),
                isGX
                    ? _GXSegmented<AppGender>(
                        values: AppGender.values,
                        selected: selectedGender,
                        label: (g) => g.label,
                        onChanged: onGenderChanged,
                        accent: accent,
                      )
                    : SegmentedButton<AppGender>(
                        showSelectedIcon: false,
                        segments: AppGender.values
                            .map(
                              (g) => ButtonSegment<AppGender>(
                                value: g,
                                label: Text(g.label),
                              ),
                            )
                            .toList(),
                        selected: {selectedGender},
                        onSelectionChanged: (s) => onGenderChanged(s.first),
                      ),

                const SizedBox(height: 20),

                // ── Save ────────────────────────────────────────────────
                SettingsSaveButton(
                  label: isGX ? 'Save Identity' : 'Save Account',
                  icon: Icons.save_outlined,
                  isSaving: isSaving,
                  onSave: onSave,
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Avatar shell ─────────────────────────────────────────────────────────────

class _AvatarShell extends StatelessWidget {
  const _AvatarShell({
    required this.avatarId,
    required this.imageUrl,
    required this.isGX,
    required this.accent,
  });

  final String avatarId;
  final String? imageUrl;
  final bool isGX;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return CustomPaint(
        foregroundPainter: _CornerBracketPainter(accent: accent),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AppAvatar(size: 66, avatarId: avatarId, imageUrl: imageUrl),
        ),
      );
    }
    return AppAvatar(
      size: 72,
      avatarId: avatarId,
      imageUrl: imageUrl,
      showOutline: true,
    );
  }
}

/// Draws GX-style corner brackets around the avatar.
class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const len = 10.0;

    // Top-left
    canvas.drawLine(Offset(0, len), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(len, 0), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - len, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    // Bottom-left
    canvas.drawLine(
      Offset(0, size.height - len),
      Offset(0, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    // Bottom-right
    canvas.drawLine(
      Offset(size.width, size.height - len),
      Offset(size.width, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - len, size.height),
      Offset(size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.accent != accent;
}

// ─── GX photo action button ───────────────────────────────────────────────────

class _GXPhotoButton extends StatelessWidget {
  const _GXPhotoButton({
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Future<void> Function()? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled ? accent.withValues(alpha: 0.3) : accent;

    return GestureDetector(
      onTap: onTap != null ? () => onTap!() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 7),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── GX segmented control ─────────────────────────────────────────────────────

class _GXSegmented<T> extends StatelessWidget {
  const _GXSegmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    required this.accent,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: values.map((v) {
        final isSelected = v == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected ? accent : accent.withValues(alpha: 0.22),
                  width: isSelected ? 1.0 : 0.6,
                ),
              ),
              child: Text(
                label(v).toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? accent : const Color(0xFF8888AA),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
