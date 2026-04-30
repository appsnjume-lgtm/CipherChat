import 'package:path_provider/path_provider.dart';

class NormalizedCropRect {
  const NormalizedCropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  const NormalizedCropRect.full() : x = 0, y = 0, width = 1, height = 1;

  final double x;
  final double y;
  final double width;
  final double height;

  NormalizedCropRect get normalized {
    final safeX = x.clamp(0.0, 1.0).toDouble();
    final safeY = y.clamp(0.0, 1.0).toDouble();
    final safeWidth = width.clamp(0.0, 1.0 - safeX).toDouble();
    final safeHeight = height.clamp(0.0, 1.0 - safeY).toDouble();
    return NormalizedCropRect(
      x: safeX,
      y: safeY,
      width: safeWidth,
      height: safeHeight,
    );
  }

  bool get isEffectivelyFullFrame {
    final value = normalized;
    return value.x <= 0.001 &&
        value.y <= 0.001 &&
        value.width >= 0.999 &&
        value.height >= 0.999;
  }
}

class StickerCropSelection {
  const StickerCropSelection._({this.crop});

  const StickerCropSelection.useOriginal() : this._();

  const StickerCropSelection.cropped(NormalizedCropRect crop)
    : this._(crop: crop);

  final NormalizedCropRect? crop;
}

class StickerMediaPreprocessor {
  StickerMediaPreprocessor._();

  static Future<String> createTemporaryOutputPath({
    required String prefix,
    required String extension,
  }) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  static String quoteForFfmpeg(String path) {
    return '"${path.replaceAll('\\', '/').replaceAll('"', r'\"')}"';
  }

  static String buildCropFilter(NormalizedCropRect cropRect) {
    final crop = cropRect.normalized;
    return "crop='max(2,floor(iw*${_factor(crop.width)}/2)*2)':'max(2,floor(ih*${_factor(crop.height)}/2)*2)':'max(0,floor(iw*${_factor(crop.x)}/2)*2)':'max(0,floor(ih*${_factor(crop.y)}/2)*2)'";
  }

  static String _factor(double value) =>
      value.clamp(0.0, 1.0).toStringAsFixed(6);
}
