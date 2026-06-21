import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_error_helper.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../widgets/settings_widgets.dart';

class PrivacySection extends StatelessWidget {
  const PrivacySection({
    super.key,
    required this.accountPrivacy,
    required this.genderVisibility,
    required this.profilePhotoVisibility,
    required this.lastSeenVisibility,
    required this.aboutVisibility,
    required this.whoCanCall,
    required this.blockedUsers,
    required this.isSaving,
    required this.onAccountPrivacyChanged,
    required this.onGenderVisibilityChanged,
    required this.onProfilePhotoVisibilityChanged,
    required this.onLastSeenVisibilityChanged,
    required this.onAboutVisibilityChanged,
    required this.onWhoCanCallChanged,
    required this.onUnblockUser,
    required this.onSave,
  });

  final AccountPrivacy accountPrivacy;
  final AppVisibility genderVisibility;
  final AppVisibility profilePhotoVisibility;
  final AppVisibility lastSeenVisibility;
  final AppVisibility aboutVisibility;
  final CallPermission whoCanCall;
  final AsyncValue<List<AppUser>> blockedUsers;
  final bool isSaving;
  final ValueChanged<AccountPrivacy> onAccountPrivacyChanged;
  final ValueChanged<AppVisibility> onGenderVisibilityChanged;
  final ValueChanged<AppVisibility> onProfilePhotoVisibilityChanged;
  final ValueChanged<AppVisibility> onLastSeenVisibilityChanged;
  final ValueChanged<AppVisibility> onAboutVisibilityChanged;
  final ValueChanged<CallPermission> onWhoCanCallChanged;
  final Future<void> Function(String userId) onUnblockUser;
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
            title: isGX ? 'Privacy' : 'Privacy',
            icon: Icons.lock_outline_rounded,
            padding: isGX
                ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
                : EdgeInsets.zero,
          ),

          // ── Visibility controls ─────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(isGX ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isGX) const SizedBox(height: 14),

                if (isGX) ...[
                  _GXPrivacyGroup(
                    label: 'VISIBILITY CONTROLS',
                    accent: accent,
                    children: [
                      SettingsDropdown<AccountPrivacy>(
                        label: 'Account type',
                        icon: Icons.manage_accounts_rounded,
                        value: accountPrivacy,
                        values: AccountPrivacy.values,
                        itemLabel: (v) => v.label,
                        onChanged: onAccountPrivacyChanged,
                      ),
                      const SizedBox(height: 10),
                      SettingsDropdown<AppVisibility>(
                        label: 'Profile photo',
                        icon: Icons.photo_camera_outlined,
                        value: profilePhotoVisibility,
                        values: AppVisibility.values,
                        itemLabel: (v) => v.label,
                        onChanged: onProfilePhotoVisibilityChanged,
                      ),
                      const SizedBox(height: 10),
                      SettingsDropdown<AppVisibility>(
                        label: 'Last seen',
                        icon: Icons.access_time_rounded,
                        value: lastSeenVisibility,
                        values: AppVisibility.values,
                        itemLabel: (v) => v.label,
                        onChanged: onLastSeenVisibilityChanged,
                      ),
                      const SizedBox(height: 10),
                      SettingsDropdown<AppVisibility>(
                        label: 'About / bio',
                        icon: Icons.notes_rounded,
                        value: aboutVisibility,
                        values: AppVisibility.values,
                        itemLabel: (v) => v.label,
                        onChanged: onAboutVisibilityChanged,
                      ),
                      const SizedBox(height: 10),
                      SettingsDropdown<AppVisibility>(
                        label: 'Gender',
                        icon: Icons.people_outline_rounded,
                        value: genderVisibility,
                        values: AppVisibility.values,
                        itemLabel: (v) => v.label,
                        onChanged: onGenderVisibilityChanged,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GXPrivacyGroup(
                    label: 'COMMUNICATION',
                    accent: accent,
                    children: [
                      SettingsDropdown<CallPermission>(
                        label: 'Who can call me',
                        icon: Icons.call_outlined,
                        value: whoCanCall,
                        values: CallPermission.values,
                        itemLabel: (v) => v.label,
                        onChanged: onWhoCanCallChanged,
                      ),
                    ],
                  ),
                ] else ...[
                  SettingsDropdown<AccountPrivacy>(
                    label: 'Account type',
                    value: accountPrivacy,
                    values: AccountPrivacy.values,
                    itemLabel: (v) => v.label,
                    onChanged: onAccountPrivacyChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsDropdown<AppVisibility>(
                    label: 'Gender visibility',
                    value: genderVisibility,
                    values: AppVisibility.values,
                    itemLabel: (v) => v.label,
                    onChanged: onGenderVisibilityChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsDropdown<AppVisibility>(
                    label: 'Profile photo visibility',
                    value: profilePhotoVisibility,
                    values: AppVisibility.values,
                    itemLabel: (v) => v.label,
                    onChanged: onProfilePhotoVisibilityChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsDropdown<AppVisibility>(
                    label: 'Last seen visibility',
                    value: lastSeenVisibility,
                    values: AppVisibility.values,
                    itemLabel: (v) => v.label,
                    onChanged: onLastSeenVisibilityChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsDropdown<AppVisibility>(
                    label: 'About visibility',
                    value: aboutVisibility,
                    values: AppVisibility.values,
                    itemLabel: (v) => v.label,
                    onChanged: onAboutVisibilityChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsDropdown<CallPermission>(
                    label: 'Who can call me',
                    value: whoCanCall,
                    values: CallPermission.values,
                    itemLabel: (v) => v.label,
                    onChanged: onWhoCanCallChanged,
                  ),
                ],

                SizedBox(height: isGX ? 20 : 18),

                // ── Blocked users ─────────────────────────────────────────
                SettingsSubHeading(
                  text: isGX ? 'Blocked users' : 'Blocked users',
                ),
                const SizedBox(height: 10),
                blockedUsers.when(
                  data: (users) {
                    if (users.isEmpty) {
                      return _EmptyBlocked(isGX: isGX, accent: accent);
                    }
                    return Column(
                      children: users
                          .map(
                            (user) => _BlockedUserRow(
                              user: user,
                              isSaving: isSaving,
                              isGX: isGX,
                              accent: accent,
                              onUnblock: () => onUnblockUser(user.id),
                            ),
                          )
                          .toList(),
                    );
                  },
                  loading: () => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: isGX ? accent : null,
                        ),
                      ),
                    ),
                  ),
                  error: (error, _) => Text(
                    AppErrorHelper.messageFor(error),
                    style: TextStyle(
                      fontFamily: isGX ? 'monospace' : null,
                      fontSize: isGX ? 11 : 13,
                      color: isGX
                          ? const Color(0xFFFF5252)
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),

                SizedBox(height: isGX ? 20 : 18),

                SettingsSaveButton(
                  label: isGX ? 'Save Privacy' : 'Save Privacy',
                  icon: Icons.lock_outline_rounded,
                  isSaving: isSaving,
                  onSave: onSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── GX grouped box ───────────────────────────────────────────────────────────

class _GXPrivacyGroup extends StatelessWidget {
  const _GXPrivacyGroup({
    required this.label,
    required this.accent,
    required this.children,
  });

  final String label;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.chevron_right_rounded,
              color: accent.withValues(alpha: 0.5),
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 1.4,
                color: accent.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0B14),
            border: Border.all(
              color: accent.withValues(alpha: 0.12),
              width: 0.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

// ─── Blocked user row ─────────────────────────────────────────────────────────

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow({
    required this.user,
    required this.isSaving,
    required this.isGX,
    required this.accent,
    required this.onUnblock,
  });

  final AppUser user;
  final bool isSaving;
  final bool isGX;
  final Color accent;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0B14),
          border: Border.all(
            color: const Color(0xFFFF5252).withValues(alpha: 0.15),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            AppAvatar(
              size: 36,
              avatarId: user.avatarId,
              imageUrl: user.profileImageUrl,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrUsername,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF0F0F8),
                    ),
                  ),
                  Text(
                    user.usernameHandle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xFF8888AA),
                    ),
                  ),
                  if (user.bio.trim().isNotEmpty)
                    Text(
                      user.bio.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Color(0xFF8888AA),
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onTap: isSaving ? null : onUnblock,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                  border: Border.all(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: const Text(
                  'UNBLOCK',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF5252),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppAvatar(
        size: 40,
        avatarId: user.avatarId,
        imageUrl: user.profileImageUrl,
      ),
      title: Text(user.displayNameOrUsername),
      subtitle: Text(
        user.bio.trim().isEmpty
            ? '${user.usernameHandle} - Blocked'
            : '${user.usernameHandle} - ${user.bio.trim()}',
      ),
      trailing: TextButton(
        onPressed: isSaving ? null : onUnblock,
        child: const Text('Unblock'),
      ),
    );
  }
}

// ─── Empty blocked state ──────────────────────────────────────────────────────

class _EmptyBlocked extends StatelessWidget {
  const _EmptyBlocked({required this.isGX, required this.accent});
  final bool isGX;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (isGX) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0B14),
          border: Border.all(color: accent.withValues(alpha: 0.10), width: 0.6),
        ),
        child: const Text(
          'NO BLOCKED USERS',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 1.0,
            color: Color(0xFF8888AA),
          ),
        ),
      );
    }
    return const Text('No blocked users.');
  }
}
