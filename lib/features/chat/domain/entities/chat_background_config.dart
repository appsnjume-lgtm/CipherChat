class ChatBackgroundConfig {
  const ChatBackgroundConfig({
    required this.imagePath,
    required this.offsetX,
    required this.offsetY,
    required this.brightness,
    required this.overlayColor,
    required this.overlayOpacity,
    required this.bubbleColor,
  });

  factory ChatBackgroundConfig.defaults() {
    return const ChatBackgroundConfig(
      imagePath: null,
      offsetX: 0,
      offsetY: 0,
      brightness: 1,
      overlayColor: null,
      overlayOpacity: 0,
      bubbleColor: null,
    );
  }

  factory ChatBackgroundConfig.fromMap(Map<String, dynamic> map) {
    return ChatBackgroundConfig(
      imagePath: _readString(map['image_path']),
      offsetX: _readDouble(map['offset_x'], fallback: 0, min: -1, max: 1),
      offsetY: _readDouble(map['offset_y'], fallback: 0, min: -1, max: 1),
      brightness: _readDouble(
        map['brightness'],
        fallback: 1,
        min: 0.5,
        max: 1.5,
      ),
      overlayColor: _readInt(map['overlay_color']),
      overlayOpacity: _readDouble(
        map['overlay_opacity'],
        fallback: 0,
        min: 0,
        max: 1,
      ),
      bubbleColor: _readInt(map['bubble_color']),
    );
  }

  final String? imagePath;
  final double offsetX;
  final double offsetY;
  final double brightness;
  final int? overlayColor;
  final double overlayOpacity;
  final int? bubbleColor;

  bool get hasImage => imagePath?.trim().isNotEmpty == true;
  bool get hasOverlay => overlayColor != null && overlayOpacity > 0;

  Map<String, dynamic> toMap() {
    return {
      'image_path': imagePath,
      'offset_x': offsetX,
      'offset_y': offsetY,
      'brightness': brightness,
      'overlay_color': overlayColor,
      'overlay_opacity': overlayOpacity,
      'bubble_color': bubbleColor,
    };
  }

  ChatBackgroundConfig copyWith({
    String? imagePath,
    bool clearImage = false,
    double? offsetX,
    double? offsetY,
    double? brightness,
    int? overlayColor,
    bool clearOverlayColor = false,
    double? overlayOpacity,
    int? bubbleColor,
    bool clearBubbleColor = false,
  }) {
    return ChatBackgroundConfig(
      imagePath: clearImage ? null : imagePath ?? this.imagePath,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      brightness: brightness ?? this.brightness,
      overlayColor: clearOverlayColor
          ? null
          : overlayColor ?? this.overlayColor,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      bubbleColor: clearBubbleColor ? null : bubbleColor ?? this.bubbleColor,
    );
  }

  static String? _readString(dynamic value) {
    final trimmed = value?.toString().trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static double _readDouble(
    dynamic value, {
    required double fallback,
    required double min,
    required double max,
  }) {
    double? resolved;
    if (value is num) {
      resolved = value.toDouble();
    } else if (value is String) {
      resolved = double.tryParse(value.trim());
    }
    return (resolved ?? fallback).clamp(min, max);
  }
}
