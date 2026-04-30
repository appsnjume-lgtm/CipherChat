import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/chat/domain/entities/chat_background_config.dart';

final chatBackgroundStorageServiceProvider =
    Provider<ChatBackgroundStorageService>((ref) {
      return ChatBackgroundStorageService.instance;
    });

class ChatBackgroundStorageService {
  ChatBackgroundStorageService._();

  static final ChatBackgroundStorageService instance =
      ChatBackgroundStorageService._();

  Future<ChatBackgroundConfig?> readGlobalConfig() async {
    return _readConfig(await _globalConfigFile());
  }

  Future<ChatBackgroundConfig?> readChatConfig(String chatId) async {
    return _readConfig(await _chatConfigFile(chatId));
  }

  Future<ChatBackgroundConfig> saveGlobalConfig({
    required ChatBackgroundConfig config,
    String? replacementImageSourcePath,
    ChatBackgroundConfig? previousConfig,
  }) {
    return _persistConfig(
      configFileFuture: _globalConfigFile(),
      config: config,
      replacementImageSourcePath: replacementImageSourcePath,
      previousConfig: previousConfig,
      imageScopePrefix: 'global_background_',
    );
  }

  Future<ChatBackgroundConfig> saveChatConfig({
    required String chatId,
    required ChatBackgroundConfig config,
    String? replacementImageSourcePath,
    ChatBackgroundConfig? previousConfig,
  }) {
    return _persistConfig(
      configFileFuture: _chatConfigFile(chatId),
      config: config,
      replacementImageSourcePath: replacementImageSourcePath,
      previousConfig: previousConfig,
      imageScopePrefix: _chatImageScopePrefix(chatId),
    );
  }

  Future<void> deleteGlobalConfig({
    ChatBackgroundConfig? previousConfig,
  }) async {
    final file = await _globalConfigFile();
    if (previousConfig != null) {
      await _deleteManagedScopeImage(
        previousConfig.imagePath,
        imageScopePrefix: 'global_background_',
      );
    }
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteChatConfig(
    String chatId, {
    ChatBackgroundConfig? previousConfig,
  }) async {
    final file = await _chatConfigFile(chatId);
    if (previousConfig != null) {
      await _deleteManagedScopeImage(
        previousConfig.imagePath,
        imageScopePrefix: _chatImageScopePrefix(chatId),
      );
    }
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<ChatBackgroundConfig?> _readConfig(File file) async {
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = jsonDecode(await file.readAsString());
      final map = raw is Map<String, dynamic>
          ? raw
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : null;
      if (map == null) {
        return null;
      }
      return _sanitizeConfig(ChatBackgroundConfig.fromMap(map));
    } catch (_) {
      return null;
    }
  }

  Future<ChatBackgroundConfig> _persistConfig({
    required Future<File> configFileFuture,
    required ChatBackgroundConfig config,
    required String imageScopePrefix,
    String? replacementImageSourcePath,
    ChatBackgroundConfig? previousConfig,
  }) async {
    final configFile = await configFileFuture;
    await configFile.parent.create(recursive: true);

    final sanitizedConfig = await _sanitizeConfig(config);
    String? resolvedImagePath = sanitizedConfig.imagePath;

    if (replacementImageSourcePath != null &&
        replacementImageSourcePath.trim().isNotEmpty) {
      resolvedImagePath = await _importBackgroundImage(
        sourcePath: replacementImageSourcePath,
        imageScopePrefix: imageScopePrefix,
      );
      await _deleteManagedScopeImage(
        previousConfig?.imagePath,
        imageScopePrefix: imageScopePrefix,
      );
    } else if (resolvedImagePath == null) {
      await _deleteManagedScopeImage(
        previousConfig?.imagePath,
        imageScopePrefix: imageScopePrefix,
      );
    }

    final storedConfig = sanitizedConfig.copyWith(
      imagePath: resolvedImagePath,
      clearImage: resolvedImagePath == null,
    );

    await configFile.writeAsString(
      jsonEncode(storedConfig.toMap()),
      flush: true,
    );
    return storedConfig;
  }

  Future<ChatBackgroundConfig> _sanitizeConfig(
    ChatBackgroundConfig config,
  ) async {
    final imagePath = config.imagePath;
    if (imagePath == null || imagePath.trim().isEmpty) {
      return config.copyWith(clearImage: true);
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      return config.copyWith(clearImage: true);
    }

    return config;
  }

  Future<String> _importBackgroundImage({
    required String sourcePath,
    required String imageScopePrefix,
  }) async {
    final bytes = await _compressBackgroundImage(sourcePath);
    final imagesDirectory = await _imagesDirectory();
    await imagesDirectory.create(recursive: true);

    final filename =
        '$imageScopePrefix${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(p.join(imagesDirectory.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _deleteManagedScopeImage(
    String? path, {
    required String imageScopePrefix,
  }) async {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }

    final basename = p.basename(trimmed);
    if (!basename.startsWith(imageScopePrefix)) {
      return;
    }

    final file = File(trimmed);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List> _compressBackgroundImage(String sourcePath) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      sourcePath,
      format: CompressFormat.jpeg,
      quality: 82,
      minWidth: 1440,
      minHeight: 1440,
    );

    if (compressed == null || compressed.isEmpty) {
      throw Exception('Unable to prepare chat background image.');
    }

    return compressed;
  }

  Future<File> _globalConfigFile() async {
    final directory = await _storageDirectory();
    return File(p.join(directory.path, 'global_chat_background.json'));
  }

  Future<File> _chatConfigFile(String chatId) async {
    final directory = await _storageDirectory();
    return File(
      p.join(
        directory.path,
        'chat_backgrounds',
        '${_sanitizeForFilename(chatId)}.json',
      ),
    );
  }

  Future<Directory> _imagesDirectory() async {
    final directory = await _storageDirectory();
    return Directory(p.join(directory.path, 'chat_background_images'));
  }

  Future<Directory> _storageDirectory() async {
    final directory = await getApplicationSupportDirectory();
    return Directory(
      p.join(directory.path, 'cipherchat_local_cache', 'storage'),
    );
  }

  String _chatImageScopePrefix(String chatId) {
    return 'chat_${_sanitizeForFilename(chatId)}_';
  }

  String _sanitizeForFilename(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'chat' : sanitized;
  }
}
