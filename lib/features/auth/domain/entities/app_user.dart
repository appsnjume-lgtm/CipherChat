import '../../../../core/constants/app_constants.dart';

enum AppGender { male, female, other, preferNotToSay }

enum AppVisibility { everyone, contacts, nobody }

enum AccountPrivacy { public, private }

enum AutoDownloadSetting { never, wifiOnly, wifiAndMobile }

enum MediaQualityPreference { low, standard, high }

enum CallPermission { everyone, contacts, nobody }

extension AppGenderX on AppGender {
  String get storageValue {
    switch (this) {
      case AppGender.male:
        return 'male';
      case AppGender.female:
        return 'female';
      case AppGender.other:
        return 'other';
      case AppGender.preferNotToSay:
        return 'prefer_not_to_say';
    }
  }

  String get label {
    switch (this) {
      case AppGender.male:
        return 'Male';
      case AppGender.female:
        return 'Female';
      case AppGender.other:
        return 'Other';
      case AppGender.preferNotToSay:
        return 'Prefer not to say';
    }
  }

  String get defaultAvatarId {
    return storageValue == 'female'
        ? AppConstants.femaleAvatarIds.first
        : AppConstants.maleAvatarIds.first;
  }
}

extension AppVisibilityX on AppVisibility {
  String get storageValue {
    switch (this) {
      case AppVisibility.everyone:
        return 'everyone';
      case AppVisibility.contacts:
        return 'contacts';
      case AppVisibility.nobody:
        return 'nobody';
    }
  }

  String get label {
    switch (this) {
      case AppVisibility.everyone:
        return 'Everyone';
      case AppVisibility.contacts:
        return 'Contacts';
      case AppVisibility.nobody:
        return 'Nobody';
    }
  }

  bool allowsViewer({required bool isSelf, required bool isContact}) {
    if (isSelf) {
      return true;
    }

    switch (this) {
      case AppVisibility.everyone:
        return true;
      case AppVisibility.contacts:
        return isContact;
      case AppVisibility.nobody:
        return false;
    }
  }
}

extension AccountPrivacyX on AccountPrivacy {
  String get storageValue {
    switch (this) {
      case AccountPrivacy.public:
        return 'public';
      case AccountPrivacy.private:
        return 'private';
    }
  }

  String get label {
    switch (this) {
      case AccountPrivacy.public:
        return 'Public';
      case AccountPrivacy.private:
        return 'Private';
    }
  }
}

extension AutoDownloadSettingX on AutoDownloadSetting {
  String get storageValue {
    switch (this) {
      case AutoDownloadSetting.never:
        return 'never';
      case AutoDownloadSetting.wifiOnly:
        return 'wifi_only';
      case AutoDownloadSetting.wifiAndMobile:
        return 'wifi_and_mobile';
    }
  }

  String get label {
    switch (this) {
      case AutoDownloadSetting.never:
        return 'Never';
      case AutoDownloadSetting.wifiOnly:
        return 'Wi-Fi only';
      case AutoDownloadSetting.wifiAndMobile:
        return 'Wi-Fi + mobile';
    }
  }
}

extension MediaQualityPreferenceX on MediaQualityPreference {
  String get storageValue {
    switch (this) {
      case MediaQualityPreference.low:
        return 'low';
      case MediaQualityPreference.standard:
        return 'standard';
      case MediaQualityPreference.high:
        return 'high';
    }
  }

  String get label {
    switch (this) {
      case MediaQualityPreference.low:
        return 'Low';
      case MediaQualityPreference.standard:
        return 'Standard';
      case MediaQualityPreference.high:
        return 'High';
    }
  }
}

extension CallPermissionX on CallPermission {
  String get storageValue {
    switch (this) {
      case CallPermission.everyone:
        return 'everyone';
      case CallPermission.contacts:
        return 'contacts';
      case CallPermission.nobody:
        return 'nobody';
    }
  }

  String get label {
    switch (this) {
      case CallPermission.everyone:
        return 'Everyone';
      case CallPermission.contacts:
        return 'Contacts';
      case CallPermission.nobody:
        return 'Nobody';
    }
  }
}

AppGender appGenderFromValue(String? value, {String? fallbackAvatarId}) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == 'female') {
    return AppGender.female;
  }
  if (normalized == 'male') {
    return AppGender.male;
  }
  if (normalized == 'other') {
    return AppGender.other;
  }
  if (normalized == 'prefer_not_to_say') {
    return AppGender.preferNotToSay;
  }

  if (fallbackAvatarId != null &&
      AppConstants.femaleAvatarIds.contains(fallbackAvatarId)) {
    return AppGender.female;
  }

  return AppGender.male;
}

AppVisibility appVisibilityFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'contacts':
      return AppVisibility.contacts;
    case 'nobody':
      return AppVisibility.nobody;
    case 'everyone':
    default:
      return AppVisibility.everyone;
  }
}

AccountPrivacy accountPrivacyFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'private':
      return AccountPrivacy.private;
    case 'public':
    default:
      return AccountPrivacy.public;
  }
}

AutoDownloadSetting autoDownloadSettingFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'never':
      return AutoDownloadSetting.never;
    case 'wifi_and_mobile':
      return AutoDownloadSetting.wifiAndMobile;
    case 'wifi_only':
    default:
      return AutoDownloadSetting.wifiOnly;
  }
}

MediaQualityPreference mediaQualityPreferenceFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'low':
      return MediaQualityPreference.low;
    case 'high':
      return MediaQualityPreference.high;
    case 'standard':
    default:
      return MediaQualityPreference.standard;
  }
}

CallPermission callPermissionFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'contacts':
      return CallPermission.contacts;
    case 'nobody':
      return CallPermission.nobody;
    case 'everyone':
    default:
      return CallPermission.everyone;
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.gender,
    required this.avatarId,
    required this.createdAt,
    this.profileImageUrl,
    this.bio = '',
    this.genderVisibility = AppVisibility.everyone,
    this.profilePhotoVisibility = AppVisibility.everyone,
    this.lastSeenVisibility = AppVisibility.everyone,
    this.aboutVisibility = AppVisibility.everyone,
    this.accountPrivacy = AccountPrivacy.public,
    this.readReceiptsEnabled = true,
    this.typingIndicatorEnabled = true,
    this.enterToSendEnabled = false,
    this.messageNotificationsEnabled = true,
    this.groupNotificationsEnabled = true,
    this.notificationPreviewEnabled = true,
    this.autoDownloadMedia = AutoDownloadSetting.wifiOnly,
    this.mediaQualityPreference = MediaQualityPreference.standard,
    this.whoCanCall = CallPermission.everyone,
    this.isOnline = false,
    this.lastSeenAt,
    this.updatedAt,
  });

  final String id;
  final String username;
  final AppGender gender;
  final String avatarId;
  final String? profileImageUrl;
  final String bio;
  final AppVisibility genderVisibility;
  final AppVisibility profilePhotoVisibility;
  final AppVisibility lastSeenVisibility;
  final AppVisibility aboutVisibility;
  final AccountPrivacy accountPrivacy;
  final bool readReceiptsEnabled;
  final bool typingIndicatorEnabled;
  final bool enterToSendEnabled;
  final bool messageNotificationsEnabled;
  final bool groupNotificationsEnabled;
  final bool notificationPreviewEnabled;
  final AutoDownloadSetting autoDownloadMedia;
  final MediaQualityPreference mediaQualityPreference;
  final CallPermission whoCanCall;
  final bool isOnline;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  bool get hasCustomProfileImage =>
      profileImageUrl != null && profileImageUrl!.trim().isNotEmpty;

  AppUser copyWith({
    String? id,
    String? username,
    AppGender? gender,
    String? avatarId,
    String? profileImageUrl,
    String? bio,
    AppVisibility? genderVisibility,
    AppVisibility? profilePhotoVisibility,
    AppVisibility? lastSeenVisibility,
    AppVisibility? aboutVisibility,
    AccountPrivacy? accountPrivacy,
    bool? readReceiptsEnabled,
    bool? typingIndicatorEnabled,
    bool? enterToSendEnabled,
    bool? messageNotificationsEnabled,
    bool? groupNotificationsEnabled,
    bool? notificationPreviewEnabled,
    AutoDownloadSetting? autoDownloadMedia,
    MediaQualityPreference? mediaQualityPreference,
    CallPermission? whoCanCall,
    bool? isOnline,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      gender: gender ?? this.gender,
      avatarId: avatarId ?? this.avatarId,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      genderVisibility: genderVisibility ?? this.genderVisibility,
      profilePhotoVisibility:
          profilePhotoVisibility ?? this.profilePhotoVisibility,
      lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
      aboutVisibility: aboutVisibility ?? this.aboutVisibility,
      accountPrivacy: accountPrivacy ?? this.accountPrivacy,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      typingIndicatorEnabled:
          typingIndicatorEnabled ?? this.typingIndicatorEnabled,
      enterToSendEnabled: enterToSendEnabled ?? this.enterToSendEnabled,
      messageNotificationsEnabled:
          messageNotificationsEnabled ?? this.messageNotificationsEnabled,
      groupNotificationsEnabled:
          groupNotificationsEnabled ?? this.groupNotificationsEnabled,
      notificationPreviewEnabled:
          notificationPreviewEnabled ?? this.notificationPreviewEnabled,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      mediaQualityPreference:
          mediaQualityPreference ?? this.mediaQualityPreference,
      whoCanCall: whoCanCall ?? this.whoCanCall,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
