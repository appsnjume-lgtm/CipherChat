import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/entities/sticker.dart';

final stickerRepositoryProvider = Provider<StickerRepository>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return StickerRepository(client);
});

final stickerLibraryProvider =
    StateNotifierProvider.autoDispose<
      StickerLibraryController,
      StickerLibraryState
    >((ref) {
      final controller = StickerLibraryController(ref);
      controller.load();
      return controller;
    });

class StickerLibraryState {
  const StickerLibraryState({
    required this.stickersById,
    required this.libraryIds,
    required this.favoriteIds,
    required this.recentIds,
    required this.isLoading,
    required this.isMutating,
    required this.errorMessage,
  });

  factory StickerLibraryState.initial() {
    return const StickerLibraryState(
      stickersById: <String, Sticker>{},
      libraryIds: <String>[],
      favoriteIds: <String>[],
      recentIds: <String>[],
      isLoading: true,
      isMutating: false,
      errorMessage: null,
    );
  }

  final Map<String, Sticker> stickersById;
  final List<String> libraryIds;
  final List<String> favoriteIds;
  final List<String> recentIds;
  final bool isLoading;
  final bool isMutating;
  final String? errorMessage;

  List<Sticker> get stickersTabStickers {
    final seen = <String>{};
    final orderedIds = <String>[];
    for (final stickerId in libraryIds) {
      if (seen.add(stickerId)) {
        orderedIds.add(stickerId);
      }
    }
    for (final stickerId in recentIds) {
      if (seen.add(stickerId)) {
        orderedIds.add(stickerId);
      }
    }
    return orderedIds
        .map((id) => stickersById[id])
        .whereType<Sticker>()
        .toList(growable: false);
  }

  List<Sticker> get favoriteStickers => favoriteIds
      .map((id) => stickersById[id])
      .whereType<Sticker>()
      .toList(growable: false);

  bool isFavorite(String stickerId) => favoriteIds.contains(stickerId);

  bool isInLibrary(String stickerId) => libraryIds.contains(stickerId);

  Sticker? stickerById(String stickerId) => stickersById[stickerId];

  StickerLibraryState copyWith({
    Map<String, Sticker>? stickersById,
    List<String>? libraryIds,
    List<String>? favoriteIds,
    List<String>? recentIds,
    bool? isLoading,
    bool? isMutating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return StickerLibraryState(
      stickersById: stickersById ?? this.stickersById,
      libraryIds: libraryIds ?? this.libraryIds,
      favoriteIds: favoriteIds ?? this.favoriteIds,
      recentIds: recentIds ?? this.recentIds,
      isLoading: isLoading ?? this.isLoading,
      isMutating: isMutating ?? this.isMutating,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class StickerLibraryController extends StateNotifier<StickerLibraryState> {
  StickerLibraryController(this._ref) : super(StickerLibraryState.initial());

  final Ref _ref;

  StickerRepository get _repository => _ref.read(stickerRepositoryProvider);

  String get _currentUserId {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }
    return userId;
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait<List<Sticker>>([
        _repository.fetchLibrary(userId: _currentUserId),
        _repository.fetchRecent(userId: _currentUserId),
      ]);
      final library = results[0];
      final recent = results[1];

      final stickersById = <String, Sticker>{
        for (final sticker in library) sticker.id: sticker,
      };
      for (final sticker in recent) {
        stickersById[sticker.id] = _mergeSticker(
          stickersById[sticker.id],
          sticker,
        );
      }

      state = state.copyWith(
        stickersById: stickersById,
        libraryIds: library
            .map((sticker) => sticker.id)
            .toList(growable: false),
        favoriteIds: library
            .where((sticker) => sticker.isFavorite)
            .map((sticker) => sticker.id)
            .toList(growable: false),
        recentIds: recent.map((sticker) => sticker.id).toList(growable: false),
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<void> refresh() => load();

  Future<void> ensureStickersLoaded(Iterable<String> stickerIds) async {
    final missingIds = stickerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && !state.stickersById.containsKey(id))
        .toSet()
        .toList(growable: false);
    if (missingIds.isEmpty) {
      return;
    }

    try {
      final loaded = await _repository.fetchStickersByIds(missingIds);
      if (loaded.isEmpty) {
        return;
      }
      state = state.copyWith(
        stickersById: {...state.stickersById, ...loaded},
        clearError: true,
      );
    } catch (_) {
      // Best-effort hydration for visible message stickers.
    }
  }

  Future<Sticker?> getSticker(String stickerId) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final existing = state.stickersById[trimmed];
    if (existing != null) {
      return existing;
    }

    final sticker = await _repository.fetchStickerById(trimmed);
    if (sticker == null) {
      return null;
    }

    final merged = _mergeSticker(state.stickersById[trimmed], sticker);
    state = state.copyWith(
      stickersById: {...state.stickersById, trimmed: merged},
      clearError: true,
    );
    return merged;
  }

  Future<void> registerStickerUse(String stickerId) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final knownSticker =
        state.stickersById[trimmed] ??
        await _repository.fetchStickerById(trimmed);
    if (knownSticker == null) {
      return;
    }

    final merged = _mergeSticker(
      state.stickersById[trimmed],
      knownSticker.copyWith(lastUsedAt: DateTime.now(), setLastUsedAt: true),
    );

    final recentIds = [
      trimmed,
      ...state.recentIds.where((id) => id != trimmed),
    ];

    state = state.copyWith(
      stickersById: {...state.stickersById, trimmed: merged},
      recentIds: recentIds,
      clearError: true,
    );
  }

  Future<Sticker?> saveToLibrary(String stickerId) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final existing = state.stickersById[trimmed];
    if (state.isInLibrary(trimmed) && existing != null) {
      return existing;
    }

    state = state.copyWith(isMutating: true, clearError: true);
    try {
      await _repository.ensureStickerInLibrary(
        userId: _currentUserId,
        stickerId: trimmed,
      );

      final baseSticker =
          existing ?? await _repository.fetchStickerById(trimmed);
      if (baseSticker == null) {
        state = state.copyWith(isMutating: false);
        return null;
      }

      final merged = _mergeSticker(
        existing,
        baseSticker.copyWith(
          addedAt: existing?.addedAt ?? DateTime.now(),
          setAddedAt: true,
        ),
      );

      state = state.copyWith(
        stickersById: {...state.stickersById, trimmed: merged},
        libraryIds: [trimmed, ...state.libraryIds.where((id) => id != trimmed)],
        isMutating: false,
        clearError: true,
      );
      return merged;
    } catch (error) {
      state = state.copyWith(isMutating: false, errorMessage: error.toString());
      rethrow;
    }
  }

  Future<void> toggleFavorite(String stickerId) async {
    final trimmed = stickerId.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (!state.isInLibrary(trimmed)) {
      throw StateError('Add this sticker to Stickers first.');
    }

    final nextFavorite = !state.isFavorite(trimmed);
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      await _repository.setFavorite(
        userId: _currentUserId,
        stickerId: trimmed,
        isFavorite: nextFavorite,
      );

      final baseSticker =
          state.stickersById[trimmed] ??
          await _repository.fetchStickerById(trimmed);
      if (baseSticker == null) {
        state = state.copyWith(isMutating: false);
        return;
      }

      final merged = _mergeSticker(
        state.stickersById[trimmed],
        baseSticker.copyWith(
          isFavorite: nextFavorite,
          addedAt: state.stickersById[trimmed]?.addedAt ?? baseSticker.addedAt,
          setAddedAt:
              state.stickersById[trimmed]?.addedAt != null ||
              baseSticker.addedAt != null,
        ),
      );
      final favoriteIds = nextFavorite
          ? [trimmed, ...state.favoriteIds.where((id) => id != trimmed)]
          : state.favoriteIds
                .where((id) => id != trimmed)
                .toList(growable: false);

      state = state.copyWith(
        stickersById: {...state.stickersById, trimmed: merged},
        favoriteIds: favoriteIds,
        isMutating: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isMutating: false, errorMessage: error.toString());
      rethrow;
    }
  }

  Future<Sticker> createSticker({
    required String sourcePath,
    bool isPublic = false,
  }) async {
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final sticker = await _repository.createSticker(
        userId: _currentUserId,
        sourcePath: sourcePath,
        isPublic: isPublic,
      );
      final merged = _mergeSticker(state.stickersById[sticker.id], sticker);
      state = state.copyWith(
        stickersById: {...state.stickersById, sticker.id: merged},
        libraryIds: [
          sticker.id,
          ...state.libraryIds.where((id) => id != sticker.id),
        ],
        isMutating: false,
        clearError: true,
      );
      return merged;
    } catch (error) {
      state = state.copyWith(isMutating: false, errorMessage: error.toString());
      rethrow;
    }
  }

  Sticker _mergeSticker(Sticker? existing, Sticker incoming) {
    if (existing == null) {
      return incoming;
    }

    return existing.copyWith(
      userId: incoming.userId ?? existing.userId,
      setUserId: incoming.userId != null || existing.userId != null,
      storagePath: incoming.storagePath,
      imageUrl: incoming.imageUrl,
      mimeType: incoming.mimeType,
      isPublic: incoming.isPublic,
      createdAt: incoming.createdAt,
      isFavorite: incoming.isFavorite,
      addedAt: incoming.addedAt ?? existing.addedAt,
      setAddedAt: incoming.addedAt != null || existing.addedAt != null,
      lastUsedAt: incoming.lastUsedAt ?? existing.lastUsedAt,
      setLastUsedAt: incoming.lastUsedAt != null || existing.lastUsedAt != null,
    );
  }
}
