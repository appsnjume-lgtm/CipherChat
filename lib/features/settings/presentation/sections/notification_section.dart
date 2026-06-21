import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../widgets/settings_widgets.dart';

class NotificationSection extends StatelessWidget {
  const NotificationSection({
    super.key,
    required this.messageNotificationsEnabled,
    required this.groupNotificationsEnabled,
    required this.notificationPreviewEnabled,
    required this.isSaving,
    required this.onMessageNotificationsChanged,
    required this.onGroupNotificationsChanged,
    required this.onNotificationPreviewChanged,
    required this.onSave,
  });

  final bool messageNotificationsEnabled;
  final bool groupNotificationsEnabled;
  final bool notificationPreviewEnabled;
  final bool isSaving;
  final ValueChanged<bool> onMessageNotificationsChanged;
  final ValueChanged<bool> onGroupNotificationsChanged;
  final ValueChanged<bool> onNotificationPreviewChanged;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;

    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionHeader(
            title: isGX ? 'Notifications' : 'Notifications',
            icon: Icons.notifications_outlined,
            padding: isGX
                ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
                : EdgeInsets.zero,
          ),

          SettingsToggle(
            icon: isGX ? Icons.chat_rounded : null,
            title: 'Message notifications',
            subtitle: 'Notify for direct messages.',
            value: messageNotificationsEnabled,
            onChanged: onMessageNotificationsChanged,
          ),
          SettingsToggle(
            icon: isGX ? Icons.group_rounded : null,
            title: 'Group notifications',
            subtitle: 'Notify for group conversations.',
            value: groupNotificationsEnabled,
            onChanged: onGroupNotificationsChanged,
          ),
          SettingsToggle(
            icon: isGX ? Icons.preview_rounded : null,
            title: 'Notification preview',
            subtitle: 'Show message type details in notifications.',
            value: notificationPreviewEnabled,
            onChanged: onNotificationPreviewChanged,
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              isGX ? 14 : 0,
              isGX ? 14 : 18,
              isGX ? 14 : 0,
              isGX ? 16 : 0,
            ),
            child: SettingsSaveButton(
              label: isGX ? 'Save Notifications' : 'Save Notifications',
              icon: Icons.notifications_outlined,
              isSaving: isSaving,
              onSave: onSave,
            ),
          ),
        ],
      ),
    );
  }
}
