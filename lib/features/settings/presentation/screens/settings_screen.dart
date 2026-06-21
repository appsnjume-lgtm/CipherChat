import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/app_error_helper.dart';

import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../sections/account_section.dart';
import '../sections/appearance_section.dart';
import '../sections/messaging_section.dart';
import '../sections/notification_section.dart';
import '../sections/privacy_section.dart';
import '../widgets/avatar_picker_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _accountFormKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  final ImagePicker _imagePicker = ImagePicker();

  bool _didSeedProfile = false;
  bool _isSavingAccount = false;
  bool _isSavingPrivacy = false;
  bool _isSavingMessaging = false;
  bool _isSavingNotifications = false;

  late AppGender _selectedGender;
  late AppVisibility _genderVisibility;
  late AppVisibility _profilePhotoVisibility;
  late AppVisibility _lastSeenVisibility;
  late AppVisibility _aboutVisibility;
  late AccountPrivacy _accountPrivacy;
  late CallPermission _whoCanCall;
  late String _selectedAvatarId;
  late bool _readReceiptsEnabled;
  late bool _typingIndicatorEnabled;
  late bool _enterToSendEnabled;
  late bool _messageNotificationsEnabled;
  late bool _groupNotificationsEnabled;
  late bool _notificationPreviewEnabled;
  late AutoDownloadSetting _autoDownloadMedia;
  late MediaQualityPreference _mediaQualityPreference;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _usernameController = TextEditingController();
    _bioController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No profile available.')));
    }

    if (!_didSeedProfile) {
      _seedFromProfile(profile);
    }

    final blockedUsers = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AccountSection(
            formKey: _accountFormKey,
            profile: profile.copyWith(
              avatarId: _selectedAvatarId,
              gender: _selectedGender,
            ),
            displayNameController: _displayNameController,
            usernameController: _usernameController,
            bioController: _bioController,
            selectedGender: _selectedGender,
            avatarId: _selectedAvatarId,
            isSaving: _isSavingAccount || authState.isLoading,
            onGenderChanged: (value) {
              setState(() {
                _selectedGender = value;
              });
            },
            onUploadPhoto: _uploadProfilePhoto,
            onRemovePhoto: _removeProfilePhoto,
            onChooseAvatar: _chooseAvatar,
            onSave: _saveAccountSection,
          ),
          const SizedBox(height: 16),
          PrivacySection(
            accountPrivacy: _accountPrivacy,
            genderVisibility: _genderVisibility,
            profilePhotoVisibility: _profilePhotoVisibility,
            lastSeenVisibility: _lastSeenVisibility,
            aboutVisibility: _aboutVisibility,
            whoCanCall: _whoCanCall,
            blockedUsers: blockedUsers,
            isSaving: _isSavingPrivacy || authState.isLoading,
            onAccountPrivacyChanged: (value) {
              setState(() => _accountPrivacy = value);
            },
            onGenderVisibilityChanged: (value) {
              setState(() => _genderVisibility = value);
            },
            onProfilePhotoVisibilityChanged: (value) {
              setState(() => _profilePhotoVisibility = value);
            },
            onLastSeenVisibilityChanged: (value) {
              setState(() => _lastSeenVisibility = value);
            },
            onAboutVisibilityChanged: (value) {
              setState(() => _aboutVisibility = value);
            },
            onWhoCanCallChanged: (value) {
              setState(() => _whoCanCall = value);
            },
            onUnblockUser: _unblockUser,
            onSave: _savePrivacySection,
          ),
          const SizedBox(height: 16),
          MessagingSection(
            readReceiptsEnabled: _readReceiptsEnabled,
            typingIndicatorEnabled: _typingIndicatorEnabled,
            enterToSendEnabled: _enterToSendEnabled,
            autoDownloadMedia: _autoDownloadMedia,
            mediaQualityPreference: _mediaQualityPreference,
            isSaving: _isSavingMessaging || authState.isLoading,
            onReadReceiptsChanged: (value) {
              setState(() => _readReceiptsEnabled = value);
            },
            onTypingIndicatorChanged: (value) {
              setState(() => _typingIndicatorEnabled = value);
            },
            onEnterToSendChanged: (value) {
              setState(() => _enterToSendEnabled = value);
            },
            onAutoDownloadChanged: (value) {
              setState(() => _autoDownloadMedia = value);
            },
            onMediaQualityChanged: (value) {
              setState(() => _mediaQualityPreference = value);
            },
            onSave: _saveMessagingSection,
          ),
          const SizedBox(height: 16),
          NotificationSection(
            messageNotificationsEnabled: _messageNotificationsEnabled,
            groupNotificationsEnabled: _groupNotificationsEnabled,
            notificationPreviewEnabled: _notificationPreviewEnabled,
            isSaving: _isSavingNotifications || authState.isLoading,
            onMessageNotificationsChanged: (value) {
              setState(() => _messageNotificationsEnabled = value);
            },
            onGroupNotificationsChanged: (value) {
              setState(() => _groupNotificationsEnabled = value);
            },
            onNotificationPreviewChanged: (value) {
              setState(() => _notificationPreviewEnabled = value);
            },
            onSave: _saveNotificationSection,
          ),
          const SizedBox(height: 16),
          AppearanceSection(
            onOpenTheme: () => context.push('/settings/theme'),
            onOpenChatBackground: () =>
                context.push('/settings/chat-background'),
            onOpenPrivacyPolicy: () => context.push('/settings/privacy'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _seedFromProfile(AppUser profile) {
    _didSeedProfile = true;
    _displayNameController.text = profile.displayName;
    _usernameController.text = profile.username;
    _bioController.text = profile.bio;
    _selectedGender = profile.gender;
    _genderVisibility = profile.genderVisibility;
    _profilePhotoVisibility = profile.profilePhotoVisibility;
    _lastSeenVisibility = profile.lastSeenVisibility;
    _aboutVisibility = profile.aboutVisibility;
    _accountPrivacy = profile.accountPrivacy;
    _whoCanCall = profile.whoCanCall;
    _selectedAvatarId = profile.avatarId;
    _readReceiptsEnabled = profile.readReceiptsEnabled;
    _typingIndicatorEnabled = profile.typingIndicatorEnabled;
    _enterToSendEnabled = profile.enterToSendEnabled;
    _messageNotificationsEnabled = profile.messageNotificationsEnabled;
    _groupNotificationsEnabled = profile.groupNotificationsEnabled;
    _notificationPreviewEnabled = profile.notificationPreviewEnabled;
    _autoDownloadMedia = profile.autoDownloadMedia;
    _mediaQualityPreference = profile.mediaQualityPreference;
  }

  Future<void> _chooseAvatar() async {
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

    setState(() => _selectedAvatarId = avatarId);
  }

  Future<void> _uploadProfilePhoto() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    setState(() => _isSavingAccount = true);
    await ref
        .read(authControllerProvider.notifier)
        .uploadProfileImage(image.path);
    setState(() => _isSavingAccount = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Profile photo updated.',
    );
  }

  Future<void> _removeProfilePhoto() async {
    setState(() => _isSavingAccount = true);
    await ref.read(authControllerProvider.notifier).removeProfileImage();
    setState(() => _isSavingAccount = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Profile photo removed.',
    );
  }

  Future<void> _saveAccountSection() async {
    if (!(_accountFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSavingAccount = true);
    await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          username: _usernameController.text,
          displayName: _displayNameController.text,
          bio: _bioController.text.trim(),
          gender: _selectedGender,
          avatarId: _selectedAvatarId,
        );
    setState(() => _isSavingAccount = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Account settings saved.',
    );
  }

  Future<void> _savePrivacySection() async {
    setState(() => _isSavingPrivacy = true);
    await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          genderVisibility: _genderVisibility,
          accountPrivacy: _accountPrivacy,
          profilePhotoVisibility: _profilePhotoVisibility,
          lastSeenVisibility: _lastSeenVisibility,
          aboutVisibility: _aboutVisibility,
          whoCanCall: _whoCanCall,
        );
    setState(() => _isSavingPrivacy = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Privacy settings saved.',
    );
  }

  Future<void> _saveMessagingSection() async {
    setState(() => _isSavingMessaging = true);
    await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          readReceiptsEnabled: _readReceiptsEnabled,
          typingIndicatorEnabled: _typingIndicatorEnabled,
          enterToSendEnabled: _enterToSendEnabled,
          autoDownloadMedia: _autoDownloadMedia,
          mediaQualityPreference: _mediaQualityPreference,
        );
    setState(() => _isSavingMessaging = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Messaging settings saved.',
    );
  }

  Future<void> _saveNotificationSection() async {
    setState(() => _isSavingNotifications = true);
    await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          messageNotificationsEnabled: _messageNotificationsEnabled,
          groupNotificationsEnabled: _groupNotificationsEnabled,
          notificationPreviewEnabled: _notificationPreviewEnabled,
        );
    setState(() => _isSavingNotifications = false);
    _showResult(
      ref.read(authControllerProvider).errorMessage,
      'Notification settings saved.',
    );
  }

  Future<void> _unblockUser(String userId) async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      return;
    }

    try {
      await ref
          .read(chatRepositoryProvider)
          .unblockUser(blockerId: currentUserId, blockedUserId: userId);
      ref.invalidate(blockedUsersProvider);
      _showSnackBar('User unblocked.');
    } catch (error) {
      _showSnackBar(AppErrorHelper.messageFor(error));
    }
  }

  void _showResult(String? errorMessage, String successMessage) {
    if (errorMessage == null) {
      _showSnackBar(successMessage);
    } else {
      _showSnackBar(errorMessage);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
