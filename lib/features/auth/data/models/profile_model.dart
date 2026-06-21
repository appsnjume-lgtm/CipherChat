import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/app_user.dart';

class ProfileModel extends AppUser {
  const ProfileModel({
    required super.id,
    required super.username,
    required super.gender,
    required super.avatarId,
    required super.createdAt,
    super.displayName,
    super.profileImageUrl,
    super.bio,
    super.genderVisibility,
    super.profilePhotoVisibility,
    super.lastSeenVisibility,
    super.aboutVisibility,
    super.accountPrivacy,
    super.readReceiptsEnabled,
    super.typingIndicatorEnabled,
    super.enterToSendEnabled,
    super.messageNotificationsEnabled,
    super.groupNotificationsEnabled,
    super.notificationPreviewEnabled,
    super.autoDownloadMedia,
    super.mediaQualityPreference,
    super.whoCanCall,
    super.isOnline,
    super.lastSeenAt,
    super.updatedAt,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    final rawAvatarId = (map['avatar_id'] as String?)?.trim();
    final gender = appGenderFromValue(
      map['gender'] as String?,
      fallbackAvatarId: rawAvatarId,
    );
    final avatarId = rawAvatarId == null || rawAvatarId.isEmpty
        ? gender.defaultAvatarId
        : rawAvatarId;

    final rawIsOnline = map['is_online'] as bool? ?? false;
    final presenceExpiresAt = _parseDate(map['presence_expires_at'] as String?);
    final effectiveOnline = presenceExpiresAt == null
        ? rawIsOnline
        : rawIsOnline && presenceExpiresAt.isAfter(DateTime.now());

    return ProfileModel(
      id: map['id'] as String,
      username: map['username'] as String,
      displayName: (map['display_name'] as String?) ?? map['username'] as String,
      gender: gender,
      avatarId: AppConstants.availableAvatarIds.contains(avatarId)
          ? avatarId
          : gender.defaultAvatarId,
      profileImageUrl: (map['profile_image_url'] as String?)?.trim(),
      bio: (map['bio'] as String?)?.trim() ?? '',
      genderVisibility: appVisibilityFromValue(
        map['gender_visibility'] as String?,
      ),
      profilePhotoVisibility: appVisibilityFromValue(
        map['profile_photo_visibility'] as String?,
      ),
      lastSeenVisibility: appVisibilityFromValue(
        map['last_seen_visibility'] as String?,
      ),
      aboutVisibility: appVisibilityFromValue(
        map['about_visibility'] as String?,
      ),
      accountPrivacy: accountPrivacyFromValue(
        map['account_privacy'] as String?,
      ),
      readReceiptsEnabled: map['read_receipts_enabled'] as bool? ?? true,
      typingIndicatorEnabled: map['typing_indicator_enabled'] as bool? ?? true,
      enterToSendEnabled: map['enter_to_send_enabled'] as bool? ?? false,
      messageNotificationsEnabled:
          map['message_notifications_enabled'] as bool? ?? true,
      groupNotificationsEnabled:
          map['group_notifications_enabled'] as bool? ?? true,
      notificationPreviewEnabled:
          map['notification_preview_enabled'] as bool? ?? true,
      autoDownloadMedia: autoDownloadSettingFromValue(
        map['auto_download_media'] as String?,
      ),
      mediaQualityPreference: mediaQualityPreferenceFromValue(
        map['media_quality_preference'] as String?,
      ),
      whoCanCall: callPermissionFromValue(map['who_can_call'] as String?),
      isOnline: effectiveOnline,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      lastSeenAt: _parseDate(
        map['last_seen'] as String? ?? map['last_seen_at'] as String?,
      ),
      updatedAt: _parseDate(map['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'gender': gender.storageValue,
      'avatar_id': avatarId,
      'profile_image_url': profileImageUrl,
      'bio': bio,
      'gender_visibility': genderVisibility.storageValue,
      'profile_photo_visibility': profilePhotoVisibility.storageValue,
      'last_seen_visibility': lastSeenVisibility.storageValue,
      'about_visibility': aboutVisibility.storageValue,
      'account_privacy': accountPrivacy.storageValue,
      'read_receipts_enabled': readReceiptsEnabled,
      'typing_indicator_enabled': typingIndicatorEnabled,
      'enter_to_send_enabled': enterToSendEnabled,
      'message_notifications_enabled': messageNotificationsEnabled,
      'group_notifications_enabled': groupNotificationsEnabled,
      'notification_preview_enabled': notificationPreviewEnabled,
      'auto_download_media': autoDownloadMedia.storageValue,
      'media_quality_preference': mediaQualityPreference.storageValue,
      'who_can_call': whoCanCall.storageValue,
      'is_online': isOnline,
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_seen': lastSeenAt?.toUtc().toIso8601String(),
      'last_seen_at': lastSeenAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value)?.toLocal();
  }
}
