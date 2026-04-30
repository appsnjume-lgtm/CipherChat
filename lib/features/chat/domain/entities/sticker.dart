class Sticker {
  const Sticker({
    required this.id,
    required this.storagePath,
    required this.imageUrl,
    required this.mimeType,
    required this.isPublic,
    required this.createdAt,
    this.userId,
    this.isFavorite = false,
    this.addedAt,
    this.lastUsedAt,
  });

  final String id;
  final String? userId;
  final String storagePath;
  final String imageUrl;
  final String mimeType;
  final bool isPublic;
  final DateTime createdAt;
  final bool isFavorite;
  final DateTime? addedAt;
  final DateTime? lastUsedAt;

  bool get isSystem => userId == null;
  bool get isWebp => mimeType == 'image/webp';
  bool get isStaticImage => mimeType == 'image/png' || mimeType == 'image/jpeg';
  bool get usesImageRendering => isStaticImage || isWebp;
  bool get isPrivate => !isPublic;

  bool isOwnedBy(String currentUserId) => userId == currentUserId;

  bool canBeSavedBy(String currentUserId) =>
      isPublic || isOwnedBy(currentUserId);

  Sticker copyWith({
    String? userId,
    bool setUserId = false,
    String? storagePath,
    String? imageUrl,
    String? mimeType,
    bool? isPublic,
    DateTime? createdAt,
    bool? isFavorite,
    DateTime? addedAt,
    bool setAddedAt = false,
    DateTime? lastUsedAt,
    bool setLastUsedAt = false,
  }) {
    return Sticker(
      id: id,
      userId: setUserId ? userId : this.userId,
      storagePath: storagePath ?? this.storagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      mimeType: mimeType ?? this.mimeType,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: setAddedAt ? addedAt : this.addedAt,
      lastUsedAt: setLastUsedAt ? lastUsedAt : this.lastUsedAt,
    );
  }
}
