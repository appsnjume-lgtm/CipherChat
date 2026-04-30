import 'package:flutter/material.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../auth/domain/entities/app_user.dart';

class AvatarPickerSheet extends StatelessWidget {
  const AvatarPickerSheet({
    super.key,
    required this.selectedAvatarId,
    required this.gender,
  });

  final String selectedAvatarId;
  final AppGender gender;

  @override
  Widget build(BuildContext context) {
    final avatars = presetAvatarsForGender(gender);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose an avatar',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a preset avatar to use as your fallback image.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              itemCount: avatars.length,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, index) {
                final avatar = avatars[index];
                final isSelected = avatar.id == selectedAvatarId;

                return InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.of(context).pop(avatar.id),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppAvatar(size: 56, avatarId: avatar.id),
                          const SizedBox(height: 10),
                          Text(
                            avatar.label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
