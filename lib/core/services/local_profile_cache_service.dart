import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/auth/data/models/profile_model.dart';
import '../../features/auth/domain/entities/app_user.dart';

final localProfileCacheServiceProvider = Provider<LocalProfileCacheService>((
  ref,
) {
  return LocalProfileCacheService.instance;
});

class LocalProfileCacheService {
  LocalProfileCacheService._();

  static final LocalProfileCacheService instance = LocalProfileCacheService._();

  final HttpClient _httpClient = HttpClient();

  Future<ProfileModel?> readProfile(String userId) async {
    final profiles = await _readProfilesIndex();
    final raw = profiles[userId];
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    try {
      return ProfileModel.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheProfile(AppUser user) async {
    final profiles = await _readProfilesIndex();
    final previousRaw = profiles[user.id];
    final previous = previousRaw is Map<String, dynamic>
        ? ProfileModel.fromMap(previousRaw)
        : null;

    profiles[user.id] = _profileToMap(user);
    await _writeProfilesIndex(profiles);

    final previousImageUrl = previous?.profileImageUrl?.trim();
    final nextImageUrl = user.profileImageUrl?.trim();

    if (previousImageUrl != null &&
        previousImageUrl.isNotEmpty &&
        previousImageUrl != nextImageUrl) {
      await removeCachedProfileImage(previousImageUrl);
    }

    if (nextImageUrl != null && nextImageUrl.isNotEmpty) {
      unawaited(
        refreshProfileImage(cacheKey: nextImageUrl, imageUrl: nextImageUrl),
      );
    }
  }

  Future<void> removeProfile(String userId) async {
    final profiles = await _readProfilesIndex();
    final raw = profiles.remove(userId);
    await _writeProfilesIndex(profiles);

    if (raw is Map<String, dynamic>) {
      final imageUrl = (raw['profile_image_url'] as String?)?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await removeCachedProfileImage(imageUrl);
      }
    }
  }

  Future<File?> readCachedProfileImage(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final file = await _imageFileFor(normalized);
    if (await file.exists()) {
      return file;
    }

    return null;
  }

  Future<File?> refreshProfileImage({
    required String cacheKey,
    required String imageUrl,
  }) async {
    final normalizedKey = cacheKey.trim();
    final normalizedUrl = imageUrl.trim();
    if (normalizedKey.isEmpty || normalizedUrl.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      return null;
    }

    final file = await _imageFileFor(normalizedKey);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> removeCachedProfileImage(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) {
      return;
    }

    final file = await _imageFileFor(normalized);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _baseDirectory() async {
    final directory = await getApplicationSupportDirectory();
    final base = Directory(p.join(directory.path, 'cipherchat_local_cache'));
    await base.create(recursive: true);
    return base;
  }

  Future<File> _profilesIndexFile() async {
    final base = await _baseDirectory();
    return File(p.join(base.path, 'profiles.json'));
  }

  Future<Directory> _profileImagesDirectory() async {
    final base = await _baseDirectory();
    final directory = Directory(p.join(base.path, 'profile_images'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Map<String, dynamic>> _readProfilesIndex() async {
    final file = await _profilesIndexFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Corrupt cache is treated as empty and rebuilt on the next refresh.
    }

    return <String, dynamic>{};
  }

  Future<void> _writeProfilesIndex(Map<String, dynamic> profiles) async {
    final file = await _profilesIndexFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(profiles), flush: true);
  }

  Future<File> _imageFileFor(String cacheKey) async {
    final directory = await _profileImagesDirectory();
    final fileName = '${_stableHash(cacheKey)}.img';
    return File(p.join(directory.path, fileName));
  }

  Map<String, dynamic> _profileToMap(AppUser user) {
    return {
      'id': user.id,
      'username': user.username,
      'gender': user.gender.storageValue,
      'avatar_id': user.avatarId,
      'profile_image_url': user.profileImageUrl,
      'bio': user.bio,
      'gender_visibility': user.genderVisibility.storageValue,
      'profile_photo_visibility': user.profilePhotoVisibility.storageValue,
      'last_seen_visibility': user.lastSeenVisibility.storageValue,
      'about_visibility': user.aboutVisibility.storageValue,
      'account_privacy': user.accountPrivacy.storageValue,
      'read_receipts_enabled': user.readReceiptsEnabled,
      'typing_indicator_enabled': user.typingIndicatorEnabled,
      'enter_to_send_enabled': user.enterToSendEnabled,
      'message_notifications_enabled': user.messageNotificationsEnabled,
      'group_notifications_enabled': user.groupNotificationsEnabled,
      'notification_preview_enabled': user.notificationPreviewEnabled,
      'auto_download_media': user.autoDownloadMedia.storageValue,
      'media_quality_preference': user.mediaQualityPreference.storageValue,
      'who_can_call': user.whoCanCall.storageValue,
      'is_online': user.isOnline,
      'created_at': user.createdAt.toUtc().toIso8601String(),
      'last_seen': user.lastSeenAt?.toUtc().toIso8601String(),
      'last_seen_at': user.lastSeenAt?.toUtc().toIso8601String(),
      'updated_at': user.updatedAt?.toUtc().toIso8601String(),
    };
  }

  String _stableHash(String input) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;

    for (final codeUnit in utf8.encode(input)) {
      hash ^= codeUnit;
      hash = (hash * prime) & mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
