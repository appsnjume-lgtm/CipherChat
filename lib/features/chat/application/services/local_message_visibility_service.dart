import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/security/secure_storage_service.dart';

final localMessageVisibilityServiceProvider =
    Provider<LocalMessageVisibilityService>((ref) {
      final storage = ref.watch(secureStorageServiceProvider);
      return LocalMessageVisibilityService(storage);
    });

class LocalMessageVisibilityService {
  LocalMessageVisibilityService(this._storage);

  final SecureStorageService _storage;

  Future<Set<String>> readHiddenMessageIds({
    required String userId,
    required String chatId,
  }) async {
    final raw = await _storage.read(
      _storageKey(userId: userId, chatId: chatId),
    );
    if (raw == null || raw.isEmpty) {
      return const <String>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // Corrupt local visibility state should not break chat loading.
    }

    return const <String>{};
  }

  Future<void> hideMessage({
    required String userId,
    required String chatId,
    required String messageId,
  }) async {
    final hiddenIds = await readHiddenMessageIds(
      userId: userId,
      chatId: chatId,
    );
    if (!hiddenIds.add(messageId)) {
      return;
    }

    await _writeHiddenMessageIds(
      userId: userId,
      chatId: chatId,
      hiddenIds: hiddenIds,
    );
  }

  Future<void> _writeHiddenMessageIds({
    required String userId,
    required String chatId,
    required Set<String> hiddenIds,
  }) {
    final sortedIds = hiddenIds.toList()..sort();
    return _storage.write(
      _storageKey(userId: userId, chatId: chatId),
      jsonEncode(sortedIds),
    );
  }

  String _storageKey({required String userId, required String chatId}) {
    return '${AppConstants.hiddenMessagesStoragePrefix}.$userId.$chatId';
  }
}
