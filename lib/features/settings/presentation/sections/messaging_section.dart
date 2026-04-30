import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../widgets/settings_widgets.dart';

class MessagingSection extends StatelessWidget {
  const MessagingSection({
    super.key,
    required this.readReceiptsEnabled,
    required this.typingIndicatorEnabled,
    required this.enterToSendEnabled,
    required this.autoDownloadMedia,
    required this.mediaQualityPreference,
    required this.isSaving,
    required this.onReadReceiptsChanged,
    required this.onTypingIndicatorChanged,
    required this.onEnterToSendChanged,
    required this.onAutoDownloadChanged,
    required this.onMediaQualityChanged,
    required this.onSave,
  });

  final bool readReceiptsEnabled;
  final bool typingIndicatorEnabled;
  final bool enterToSendEnabled;
  final AutoDownloadSetting autoDownloadMedia;
  final MediaQualityPreference mediaQualityPreference;
  final bool isSaving;
  final ValueChanged<bool> onReadReceiptsChanged;
  final ValueChanged<bool> onTypingIndicatorChanged;
  final ValueChanged<bool> onEnterToSendChanged;
  final ValueChanged<AutoDownloadSetting> onAutoDownloadChanged;
  final ValueChanged<MediaQualityPreference> onMediaQualityChanged;
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
            title: isGX ? 'Messaging' : 'Messaging',
            icon: Icons.chat_bubble_outline_rounded,
            padding: isGX
                ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
                : EdgeInsets.zero,
          ),

          // ── Toggles ───────────────────────────────────────────────────
          if (isGX) ...[
            SettingsToggle(
              icon: Icons.done_all_rounded,
              title: 'Read receipts',
              subtitle: 'Send read status when you open messages.',
              value: readReceiptsEnabled,
              onChanged: onReadReceiptsChanged,
            ),
            SettingsToggle(
              icon: Icons.keyboard_rounded,
              title: 'Typing indicator',
              subtitle: 'Broadcast when you are composing.',
              value: typingIndicatorEnabled,
              onChanged: onTypingIndicatorChanged,
            ),
            SettingsToggle(
              icon: Icons.send_rounded,
              title: 'Enter to send',
              subtitle: 'Press Enter to send from the composer.',
              value: enterToSendEnabled,
              onChanged: onEnterToSendChanged,
            ),
          ] else ...[
            SettingsToggle(
              title: 'Read receipts',
              subtitle: 'Send read status when you open messages.',
              value: readReceiptsEnabled,
              onChanged: onReadReceiptsChanged,
            ),
            SettingsToggle(
              title: 'Typing indicator',
              subtitle: 'Broadcast when you are typing.',
              value: typingIndicatorEnabled,
              onChanged: onTypingIndicatorChanged,
            ),
            SettingsToggle(
              title: 'Enter to send',
              subtitle: 'Press Enter to send from the composer.',
              value: enterToSendEnabled,
              onChanged: onEnterToSendChanged,
            ),
          ],

          // ── Media dropdowns ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              isGX ? 14 : 0,
              isGX ? 14 : 10,
              isGX ? 14 : 0,
              isGX ? 16 : 0,
            ),
            child: Column(
              children: [
                SettingsDropdown<AutoDownloadSetting>(
                  label: 'Auto-download media',
                  icon: isGX ? Icons.download_rounded : null,
                  value: autoDownloadMedia,
                  values: AutoDownloadSetting.values,
                  itemLabel: (v) => v.label,
                  onChanged: onAutoDownloadChanged,
                ),
                const SizedBox(height: 12),
                SettingsDropdown<MediaQualityPreference>(
                  label: 'Media quality',
                  icon: isGX ? Icons.hd_rounded : null,
                  value: mediaQualityPreference,
                  values: MediaQualityPreference.values,
                  itemLabel: (v) => v.label,
                  onChanged: onMediaQualityChanged,
                ),
                const SizedBox(height: 18),
                SettingsSaveButton(
                  label: isGX ? 'Save Messaging' : 'Save Messaging',
                  icon: Icons.message_outlined,
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
