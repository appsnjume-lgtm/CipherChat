import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../common/widgets/app_avatar.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/avatar_picker_sheet.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  late final TextEditingController _usernameController;
  late String _selectedAvatarId;
  late AppGender _selectedGender;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _usernameController = TextEditingController(text: profile?.username ?? '');
    _selectedGender = profile?.gender ?? AppGender.male;
    _selectedAvatarId = profile?.avatarId ?? _selectedGender.defaultAvatarId;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;

    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No profile available.')));
    }

    final canSave =
        !authState.isLoading &&
        _usernameController.text.trim().isNotEmpty &&
        (_usernameController.text.trim() != profile.username ||
            _selectedAvatarId != profile.avatarId ||
            _selectedGender != profile.gender);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  AppAvatar(
                    size: 92,
                    avatarId: _selectedAvatarId,
                    imageUrl: profile.profileImageUrl,
                    showOutline: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _usernameController.text.trim().isEmpty
                        ? profile.username
                        : _usernameController.text.trim(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedGender.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Choose Avatar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Profile details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can keep a preset avatar as fallback, or upload a custom profile photo from Settings.',
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Username'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Gender',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<AppGender>(
                    showSelectedIcon: false,
                    segments: AppGender.values
                        .map(
                          (gender) => ButtonSegment<AppGender>(
                            value: gender,
                            label: Text(gender.label),
                          ),
                        )
                        .toList(),
                    selected: {_selectedGender},
                    onSelectionChanged: (selection) {
                      final nextGender = selection.first;
                      setState(() {
                        _selectedGender = nextGender;
                        if (!AppConstants.isAvatarAllowedForGender(
                          avatarId: _selectedAvatarId,
                          gender: nextGender.storageValue,
                        )) {
                          _selectedAvatarId = nextGender.defaultAvatarId;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: canSave ? _saveProfile : null,
                    icon: authState.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final avatarId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return AvatarPickerSheet(
          selectedAvatarId: _selectedAvatarId,
          gender: _selectedGender,
        );
      },
    );

    if (avatarId == null || !mounted) {
      return;
    }

    setState(() {
      _selectedAvatarId = avatarId;
    });
  }

  Future<void> _saveProfile() async {
    await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          username: _usernameController.text.trim(),
          gender: _selectedGender,
          avatarId: _selectedAvatarId,
        );

    final nextState = ref.read(authControllerProvider);
    if (!mounted) {
      return;
    }

    if (nextState.errorMessage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }
}
