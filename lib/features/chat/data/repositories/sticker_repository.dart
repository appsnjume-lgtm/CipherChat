import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/sticker.dart';

const Set<String> _supportedStickerMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
};

const Set<String> _supportedStickerExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
};

const int _stickerSignedUrlExpirySeconds = 60 * 60;

class StickerRepository {
  StickerRepository(this._client);

  final SupabaseClient _client;

  Future<List<Sticker>> fetchLibrary({required String userId}) async {
    final rows = await _client
        .from('user_stickers')
        .select('sticker_id, is_favorite, added_at')
        .eq('user_id', userId)
        .order('added_at', ascending: false);

    final libraryRows = (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final stickerIds = libraryRows
        .map((row) => row['sticker_id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final stickersById = await fetchStickersByIds(stickerIds);

    return libraryRows
        .map((row) {
          final stickerId = row['sticker_id'] as String?;
          if (stickerId == null) {
            return null;
          }
          final sticker = stickersById[stickerId];
          if (sticker == null) {
            return null;
          }
          return sticker.copyWith(
            isFavorite: row['is_favorite'] as bool? ?? false,
            addedAt: _parseDate(row['added_at'] as String?),
            setAddedAt: true,
          );
        })
        .whereType<Sticker>()
        .toList(growable: false);
  }

  Future<List<Sticker>> fetchRecent({
    required String userId,
    int limit = 60,
  }) async {
    final rows = await _client
        .from('messages')
        .select('sticker_id, created_at')
        .eq('sender_id', userId)
        .eq('message_type', 'sticker')
        .order('created_at', ascending: false)
        .limit(limit);

    final recentRows = (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final recentOrder = <String>[];
    final recentTimes = <String, DateTime>{};
    for (final row in recentRows) {
      final stickerId = row['sticker_id'] as String?;
      if (stickerId == null || recentTimes.containsKey(stickerId)) {
        continue;
      }
      recentOrder.add(stickerId);
      recentTimes[stickerId] =
          _parseDate(row['created_at'] as String?) ?? DateTime.now();
    }

    final stickersById = await fetchStickersByIds(recentOrder);
    return recentOrder
        .map((stickerId) {
          final sticker = stickersById[stickerId];
          if (sticker == null) {
            return null;
          }
          return sticker.copyWith(
            lastUsedAt: recentTimes[stickerId],
            setLastUsedAt: true,
          );
        })
        .whereType<Sticker>()
        .toList(growable: false);
  }

  Future<Map<String, Sticker>> fetchStickersByIds(
    Iterable<String> stickerIds,
  ) async {
    final ids = stickerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) {
      return const <String, Sticker>{};
    }

    final rows = await _client.from('stickers').select().inFilter('id', ids);
    final stickersById = <String, Sticker>{};
    for (final dynamic row in rows as List<dynamic>) {
      try {
        final sticker = await _stickerFromMap(
          Map<String, dynamic>.from(row as Map),
        );
        stickersById[sticker.id] = sticker;
      } catch (_) {
        // Ignore invalid sticker records so other stickers can still render.
      }
    }
    return stickersById;
  }

  Future<Sticker?> fetchStickerById(String stickerId) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final row = await _client
        .from('stickers')
        .select()
        .eq('id', trimmed)
        .maybeSingle();
    if (row == null) {
      return null;
    }

    try {
      return await _stickerFromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureStickerInLibrary({
    required String userId,
    required String stickerId,
  }) async {
    await _client.from('user_stickers').upsert({
      'user_id': userId,
      'sticker_id': stickerId,
    }, onConflict: 'user_id,sticker_id');
  }

  Future<void> setFavorite({
    required String userId,
    required String stickerId,
    required bool isFavorite,
  }) async {
    if (isFavorite) {
      await _client.from('user_stickers').upsert({
        'user_id': userId,
        'sticker_id': stickerId,
        'is_favorite': true,
      }, onConflict: 'user_id,sticker_id');
      return;
    }

    await _client
        .from('user_stickers')
        .update({'is_favorite': false})
        .eq('user_id', userId)
        .eq('sticker_id', stickerId);
  }

  Future<Sticker> createSticker({
    required String userId,
    required String sourcePath,
    bool isPublic = false,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw StateError('Selected sticker file could not be found.');
    }

    final bytes = await file.readAsBytes();
    final mimeType = _resolveStickerMimeType(
      sourcePath: sourcePath,
      bytes: bytes,
    );
    _validateStickerAsset(
      path: sourcePath,
      mimeType: mimeType,
      contextLabel: 'Selected sticker file',
    );

    final extension = _fileExtensionForMimeType(mimeType);
    final filename =
        'sticker_${DateTime.now().millisecondsSinceEpoch}$extension';
    final objectPath = 'users/$userId/$filename';
    _validateStickerAsset(
      path: objectPath,
      mimeType: mimeType,
      contextLabel: 'Sticker upload path',
    );

    await _client.storage
        .from(AppConstants.stickersBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '31536000',
            upsert: false,
            contentType: mimeType,
          ),
        );

    final inserted = await _client
        .from('stickers')
        .insert({
          'user_id': userId,
          'storage_path': objectPath,
          'mime_type': mimeType,
          'is_public': isPublic,
        })
        .select()
        .single();

    final sticker = (await _stickerFromMap(
      Map<String, dynamic>.from(inserted),
    )).copyWith(addedAt: DateTime.now(), setAddedAt: true);
    await ensureStickerInLibrary(userId: userId, stickerId: sticker.id);
    return sticker;
  }

  Future<Sticker> _stickerFromMap(Map<String, dynamic> map) async {
    final storagePath = map['storage_path'] as String? ?? '';
    final mimeType =
        _normalizedMimeType(map['mime_type'] as String?) ??
        _inferMimeTypeFromPath(storagePath);
    if (mimeType == null) {
      throw StateError('Sticker metadata is missing a supported mime type.');
    }

    _validateStickerAsset(
      path: storagePath,
      mimeType: mimeType,
      contextLabel: 'Sticker metadata',
    );

    return Sticker(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      storagePath: storagePath,
      imageUrl: await _client.storage
          .from(AppConstants.stickersBucket)
          .createSignedUrl(storagePath, _stickerSignedUrlExpirySeconds),
      mimeType: mimeType,
      isPublic: map['is_public'] as bool? ?? true,
      createdAt: _parseDate(map['created_at'] as String?) ?? DateTime.now(),
    );
  }

  String _resolveStickerMimeType({
    required String sourcePath,
    required List<int> bytes,
  }) {
    final detectedMimeType = lookupMimeType(
      sourcePath,
      headerBytes: bytes.take(32).toList(growable: false),
    );
    final normalizedMimeType =
        _normalizedMimeType(detectedMimeType) ??
        _inferMimeTypeFromPath(sourcePath);
    if (normalizedMimeType != null &&
        _supportedStickerMimeTypes.contains(normalizedMimeType)) {
      return normalizedMimeType;
    }

    throw StateError(
      'Invalid sticker format. Use PNG/JPG images or WebP files. Video stickers must be converted to animated WebP before upload.',
    );
  }

  void _validateStickerAsset({
    required String path,
    required String mimeType,
    required String contextLabel,
  }) {
    final extension = p.extension(path).toLowerCase();
    if (!_supportedStickerExtensions.contains(extension)) {
      throw StateError(
        '$contextLabel must end in .png, .jpg, .jpeg, or .webp.',
      );
    }
    if (!_supportedStickerMimeTypes.contains(mimeType)) {
      throw StateError('$contextLabel uses an unsupported sticker format.');
    }
    if (!_doesMimeTypeMatchExtension(path: path, mimeType: mimeType)) {
      throw StateError(
        '$contextLabel has mismatched file extension and mime type.',
      );
    }
  }

  bool _doesMimeTypeMatchExtension({
    required String path,
    required String mimeType,
  }) {
    final extension = p.extension(path).toLowerCase();
    switch (mimeType) {
      case 'image/png':
        return extension == '.png';
      case 'image/jpeg':
        return extension == '.jpg' || extension == '.jpeg';
      case 'image/webp':
        return extension == '.webp';
      default:
        return false;
    }
  }

  String? _inferMimeTypeFromPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  String? _normalizedMimeType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (normalized == 'image/jpg') {
      return 'image/jpeg';
    }
    return normalized;
  }

  String _fileExtensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/jpeg':
      default:
        return '.jpg';
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}
