import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../widgets/settings_widgets.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({
    super.key,
    required this.onOpenTheme,
    required this.onOpenChatBackground,
    required this.onOpenPrivacyPolicy,
  });

  final VoidCallback onOpenTheme;
  final VoidCallback onOpenChatBackground;
  final VoidCallback onOpenPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    final isGX = GXThemeExtension.of(context).isGX;

    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionHeader(
            title: isGX ? 'Appearance' : 'Appearance',
            icon: Icons.palette_outlined,
            padding: isGX
                ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
                : EdgeInsets.zero,
          ),
          if (!isGX) const SizedBox(height: 4),
          SettingsNavTile(
            icon: Icons.palette_outlined,
            title: isGX ? 'Theme' : 'Theme',
            subtitle: isGX
                ? 'System, light, dark, and GX modes.'
                : 'System, light, dark, and palette options.',
            onTap: onOpenTheme,
          ),
          SettingsNavTile(
            icon: Icons.wallpaper_outlined,
            title: isGX ? 'Chat background' : 'Chat background',
            subtitle: isGX
                ? 'Customize the chat wallpaper on this device.'
                : 'Customize the default chat wallpaper on this device.',
            onTap: onOpenChatBackground,
          ),
          SettingsNavTile(
            icon: Icons.privacy_tip_outlined,
            title: isGX ? 'Privacy policy' : 'Privacy policy',
            subtitle: isGX
                ? 'Review encryption and storage protocol.'
                : 'Review the app privacy and storage notes.',
            onTap: onOpenPrivacyPolicy,
            isLast: true,
          ),
        ],
      ),
    );
  }
}
