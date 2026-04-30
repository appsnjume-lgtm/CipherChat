import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/local_profile_cache_service.dart';
import '../../domain/entities/app_user.dart';
import '../models/profile_model.dart';

class AuthRepository {
  AuthRepository(this._client, this._localProfileCache);

  final SupabaseClient _client;
  final LocalProfileCacheService _localProfileCache;

  Session? get currentSession => _client.auth.currentSession;

  Stream<Session?> authStateChanges() {
    return _client.auth.onAuthStateChange.map((event) => event.session);
  }

  Future<AuthResponse> signInAnonymously() {
    return _client.auth.signInAnonymously();
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: AppConstants.authCallbackUrl,
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConstants.authCallbackUrl,
    );
  }

  Future<UserResponse> updatePassword(String password) {
    return _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  Future<AppUser?> fetchCachedProfile(String userId) {
    return _localProfileCache.readProfile(userId);
  }

  Future<AppUser?> fetchProfile(String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) {
        return null;
      }

      final profile = ProfileModel.fromMap(data);
      await _localProfileCache.cacheProfile(profile);
      return profile;
    } catch (_) {
      final cached = await fetchCachedProfile(userId);
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  /// Creates or updates a user profile.
  /// Uses upsert to be idempotent and safe for retries.
  Future<AppUser> createProfile({
    required String userId,
    required String username,
    required AppGender gender,
    String? avatarId,
  }) async {
    final resolvedAvatarId = avatarId == null || avatarId.trim().isEmpty
        ? gender.defaultAvatarId
        : avatarId.trim();
    final data = await _client
        .from('profiles')
        .upsert({
          'id': userId,
          'username': username.trim(),
          'gender': gender.storageValue,
          'avatar_id': resolvedAvatarId,
          'is_online': true,
        })
        .select()
        .single();

    AppUser profile = ProfileModel.fromMap(data);

    try {
      await touchLastSeen(userId);
      final refreshed = await fetchProfile(userId);
      if (refreshed != null) {
        profile = refreshed;
      }
    } catch (_) {
      // Fall back to the immediate upsert response if the heartbeat refresh fails.
    }

    await _localProfileCache.cacheProfile(profile);
    return profile;
  }

  Future<bool> isUsernameAvailable(String username) async {
    if (username.trim().isEmpty) return false;

    final data = await _client
        .from('profiles')
        .select('id')
        .eq('username', username.trim())
        .maybeSingle();

    return data == null;
  }

  Future<AppUser> updateProfile({
    required String userId,
    String? username,
    AppGender? gender,
    String? avatarId,
    String? profileImageUrl,
    bool clearProfileImage = false,
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
  }) async {
    final updates = <String, dynamic>{};

    if (username != null) {
      updates['username'] = username.trim();
    }
    if (gender != null) {
      updates['gender'] = gender.storageValue;
    }
    if (avatarId != null) {
      updates['avatar_id'] = avatarId;
    }
    if (clearProfileImage) {
      updates['profile_image_url'] = null;
    } else if (profileImageUrl != null) {
      updates['profile_image_url'] = profileImageUrl;
    }
    if (bio != null) {
      updates['bio'] = bio.trim();
    }
    if (genderVisibility != null) {
      updates['gender_visibility'] = genderVisibility.storageValue;
    }
    if (profilePhotoVisibility != null) {
      updates['profile_photo_visibility'] = profilePhotoVisibility.storageValue;
    }
    if (lastSeenVisibility != null) {
      updates['last_seen_visibility'] = lastSeenVisibility.storageValue;
    }
    if (aboutVisibility != null) {
      updates['about_visibility'] = aboutVisibility.storageValue;
    }
    if (accountPrivacy != null) {
      updates['account_privacy'] = accountPrivacy.storageValue;
    }
    if (readReceiptsEnabled != null) {
      updates['read_receipts_enabled'] = readReceiptsEnabled;
    }
    if (typingIndicatorEnabled != null) {
      updates['typing_indicator_enabled'] = typingIndicatorEnabled;
    }
    if (enterToSendEnabled != null) {
      updates['enter_to_send_enabled'] = enterToSendEnabled;
    }
    if (messageNotificationsEnabled != null) {
      updates['message_notifications_enabled'] = messageNotificationsEnabled;
    }
    if (groupNotificationsEnabled != null) {
      updates['group_notifications_enabled'] = groupNotificationsEnabled;
    }
    if (notificationPreviewEnabled != null) {
      updates['notification_preview_enabled'] = notificationPreviewEnabled;
    }
    if (autoDownloadMedia != null) {
      updates['auto_download_media'] = autoDownloadMedia.storageValue;
    }
    if (mediaQualityPreference != null) {
      updates['media_quality_preference'] = mediaQualityPreference.storageValue;
    }
    if (whoCanCall != null) {
      updates['who_can_call'] = whoCanCall.storageValue;
    }

    if (updates.isEmpty) {
      final profile = await fetchProfile(userId);
      if (profile == null) {
        throw Exception('Profile not found.');
      }
      return profile;
    }

    updates['is_online'] = true;

    final data = await _client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();

    AppUser profile = ProfileModel.fromMap(data);

    try {
      await touchLastSeen(userId);
      final refreshed = await fetchProfile(userId);
      if (refreshed != null) {
        profile = refreshed;
      }
    } catch (_) {
      // Fall back to the immediate update response if the heartbeat refresh fails.
    }

    await _localProfileCache.cacheProfile(profile);
    return profile;
  }

  Future<AppUser> uploadProfileImage({
    required String userId,
    required String sourcePath,
  }) async {
    final currentProfile = await fetchProfile(userId);
    final existingObjectPath = _storageObjectPath(
      currentProfile?.profileImageUrl,
    );
    final bytes = await _compressProfileImage(sourcePath);
    final filename = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final objectPath = '$userId/$filename';

    await _client.storage
        .from(AppConstants.profileImagesBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    if (existingObjectPath != null && existingObjectPath != objectPath) {
      await _client.storage.from(AppConstants.profileImagesBucket).remove([
        existingObjectPath,
      ]);
    }

    final profile = await updateProfile(
      userId: userId,
      profileImageUrl: objectPath,
    );
    final signedUrl = await _client.storage
        .from(AppConstants.profileImagesBucket)
        .createSignedUrl(objectPath, 60 * 60);
    unawaited(
      _localProfileCache.refreshProfileImage(
        cacheKey: objectPath,
        imageUrl: signedUrl,
      ),
    );
    return profile;
  }

  Future<AppUser> removeProfileImage({
    required String userId,
    String? existingPath,
  }) async {
    final trimmed = _storageObjectPath(existingPath);
    if (trimmed != null && trimmed.isNotEmpty) {
      await _client.storage.from(AppConstants.profileImagesBucket).remove([
        trimmed,
      ]);
    }

    final profile = await updateProfile(
      userId: userId,
      clearProfileImage: true,
    );
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      await _localProfileCache.removeCachedProfileImage(existingPath.trim());
    }
    return profile;
  }

  Future<void> touchLastSeen(String userId) async {
    await _client.rpc('heartbeat_profile_presence');
  }

  Future<void> setOnlineStatus({
    required String userId,
    required bool isOnline,
  }) async {
    if (isOnline) {
      await touchLastSeen(userId);
      return;
    }

    await _client.rpc('set_profile_presence_offline');
  }

  String generateAnonymousUsername(String userId) {
    return 'user_${userId.replaceAll('-', '').substring(0, 8)}';
  }

  Future<Uint8List> _compressProfileImage(String sourcePath) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      sourcePath,
      format: CompressFormat.jpeg,
      quality: 82,
      minWidth: 720,
      minHeight: 720,
    );

    if (compressed == null || compressed.isEmpty) {
      throw Exception('Unable to prepare profile image.');
    }

    return compressed;
  }

  String? _storageObjectPath(String? imageUrl) {
    final trimmed = imageUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return trimmed;
    }

    final publicPattern = '/object/public/${AppConstants.profileImagesBucket}/';
    final signPattern = '/object/sign/${AppConstants.profileImagesBucket}/';
    final authenticatedPattern =
        '/object/authenticated/${AppConstants.profileImagesBucket}/';

    for (final pattern in [publicPattern, signPattern, authenticatedPattern]) {
      final index = trimmed.indexOf(pattern);
      if (index == -1) {
        continue;
      }

      final start = index + pattern.length;
      final remainder = trimmed.substring(start);
      final clean = remainder.split('?').first;
      if (clean.isEmpty) {
        return null;
      }
      return Uri.decodeComponent(clean);
    }

    return p.basename(trimmed);
  }
}
