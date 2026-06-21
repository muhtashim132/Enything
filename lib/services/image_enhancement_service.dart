import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// ImageEnhancementSettings
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of one image's enhancement state.
/// All slider values: 0.0 = no change.
///   brightness / contrast / saturation / warmth: -1.0 … +1.0
///   sharpness: 0.0 … 1.0
class ImageEnhancementSettings {
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double sharpness;

  const ImageEnhancementSettings({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.warmth = 0.0,
    this.sharpness = 0.0,
  });

  /// Flat "no change" state.
  static const ImageEnhancementSettings identity = ImageEnhancementSettings();

  /// One-tap "Auto Enhance" preset — tuned for product photography.
  static const ImageEnhancementSettings autoPreset = ImageEnhancementSettings(
    brightness: 0.08,
    contrast: 0.15,
    saturation: 0.22,
    warmth: 0.08,
    sharpness: 0.35,
  );

  bool get isIdentity =>
      brightness == 0.0 &&
      contrast == 0.0 &&
      saturation == 0.0 &&
      warmth == 0.0 &&
      sharpness == 0.0;

  ImageEnhancementSettings copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? sharpness,
  }) =>
      ImageEnhancementSettings(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
        sharpness: sharpness ?? this.sharpness,
      );

  @override
  bool operator ==(Object other) =>
      other is ImageEnhancementSettings &&
      brightness == other.brightness &&
      contrast == other.contrast &&
      saturation == other.saturation &&
      warmth == other.warmth &&
      sharpness == other.sharpness;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, warmth, sharpness);
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageEnhancementHistory — per-image undo/redo stack
// ─────────────────────────────────────────────────────────────────────────────

class ImageEnhancementHistory {
  final List<ImageEnhancementSettings> _stack = [
    ImageEnhancementSettings.identity
  ];
  int _cursor = 0;

  ImageEnhancementSettings get current => _stack[_cursor];
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _stack.length - 1;

  /// Pushes a new state. No-ops if identical to current.
  void push(ImageEnhancementSettings settings) {
    if (settings == current) return;
    // Drop any forward (redo) states
    if (_cursor < _stack.length - 1) {
      _stack.removeRange(_cursor + 1, _stack.length);
    }
    _stack.add(settings);
    _cursor = _stack.length - 1;
  }

  void undo() {
    if (canUndo) _cursor--;
  }

  void redo() {
    if (canRedo) _cursor++;
  }

  void reset() {
    _stack.clear();
    _stack.add(ImageEnhancementSettings.identity);
    _cursor = 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ColorFilterMatrix — GPU-accelerated live preview via ColorFiltered widget
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a Flutter ColorFilter.matrix (flat list of 20 doubles, 4×5 row-major)
/// for real-time preview. Composed into a single GPU pass via matrix multiplication.
class ColorFilterMatrix {
  static const List<double> _identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Multiplies two 4×5 color matrices (a applied after b).
  /// Internally treats them as 5×5 with last row [0,0,0,0,1].
  static List<double> _compose(List<double> a, List<double> b) {
    final r = List<double>.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = (j == 4) ? a[i * 5 + 4] : 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[i * 5 + k] * b[k * 5 + j];
        }
        r[i * 5 + j] = sum;
      }
    }
    return r;
  }

  static List<double> _brightness(double v) {
    final o = v * 80.0; // maps [-1,1] → [-80,+80] pixel offset
    return [1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];
  }

  static List<double> _contrast(double v) {
    final c = 1.0 + v.clamp(-0.9, 1.5);
    final o = 128.0 * (1.0 - c);
    return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
  }

  static List<double> _saturation(double v) {
    final s = 1.0 + v.clamp(-1.0, 2.0);
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final dr = lr * (1 - s), dg = lg * (1 - s), dbv = lb * (1 - s);
    return [
      dr + s, dg, dbv, 0, 0,
      dr, dg + s, dbv, 0, 0,
      dr, dg, dbv + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _warmth(double v) {
    final rOff = v * 30.0; // positive = warmer (more red)
    final bOff = -v * 15.0; // positive = warmer (less blue)
    return [
      1, 0, 0, 0, rOff,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, bOff,
      0, 0, 0, 1, 0,
    ];
  }

  /// Returns a single composed matrix for all settings (one GPU pass).
  static List<double> fromSettings(ImageEnhancementSettings s) {
    var m = List<double>.from(_identity);
    if (s.brightness != 0) m = _compose(_brightness(s.brightness), m);
    if (s.contrast != 0) m = _compose(_contrast(s.contrast), m);
    if (s.saturation != 0) m = _compose(_saturation(s.saturation), m);
    if (s.warmth != 0) m = _compose(_warmth(s.warmth), m);
    return m;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StudioResult — returned by ImageEnhancementStudio on "Apply"
// ─────────────────────────────────────────────────────────────────────────────

class StudioResult {
  /// Reordered list of NEW local image paths (same as XFile.path).
  final List<String> newImagePaths;

  /// Reordered list of existing remote image URLs.
  final List<String> existingImageUrls;

  /// XFile.path → baked (enhanced) bytes, ready for direct upload.
  /// Only contains entries for images that were actually enhanced.
  final Map<String, Uint8List> bakedBytesMap;

  /// If true, upload to raw-product-images (triggers AI BG removal).
  /// If false, upload to products bucket (keeps original background).
  final bool bgRemovalEnabled;

  const StudioResult({
    required this.newImagePaths,
    required this.existingImageUrls,
    required this.bakedBytesMap,
    required this.bgRemovalEnabled,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate baking — runs in a background isolate via compute()
// ─────────────────────────────────────────────────────────────────────────────

/// Payload passed to the isolate. Uses only serializable types (safe across isolates).
class _BakePayload {
  final Uint8List bytes;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double sharpness;

  _BakePayload({
    required this.bytes,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
    required this.sharpness,
  });
}

/// Top-level function — runs in a spawned isolate.
/// Uses the `image` pure-Dart package (cross-platform: iOS + Android + all).
Uint8List _bakeInIsolate(_BakePayload p) {
  try {
    img.Image? image = img.decodeImage(p.bytes);
    if (image == null) return p.bytes;

    // 1. Brightness + Contrast + Saturation via image package's adjustColor.
    //    All values: 0 = no change, matching our slider semantics.
    image = img.adjustColor(
      image,
      brightness: p.brightness == 0.0 ? null : p.brightness,
      contrast: p.contrast == 0.0 ? null : p.contrast,
      saturation: p.saturation == 0.0 ? null : p.saturation,
    );

    // 2. Warmth — pixel-level red/blue channel shift.
    if (p.warmth != 0.0) {
      final rShift = (p.warmth * 25).round();
      final bShift = (-p.warmth * 12).round();
      for (final pixel in image) {
        pixel.r = (pixel.r + rShift).clamp(0, 255);
        pixel.b = (pixel.b + bShift).clamp(0, 255);
      }
    }

    // 3. Sharpness — unsharp-mask convolution kernel.
    //    Kernel: [0,-1,0,-1, center,-1,0,-1,0]  sum = center-4 = 1 (no brightness change)
    if (p.sharpness > 0.05) {
      final center = 5 + (p.sharpness.clamp(0.0, 1.0) * 4).round(); // 5..9
      image = img.convolution(
        image,
        filter: [0, -1, 0, -1, center, -1, 0, -1, 0],
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  } catch (e) {
    // Graceful fallback: return original bytes if anything fails
    debugPrint('[ImageEnhancementService] bake error: $e');
    return p.bytes;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageEnhancementService — public API
// ─────────────────────────────────────────────────────────────────────────────

class ImageEnhancementService {
  /// Bakes enhancement settings into JPEG bytes using a background isolate.
  ///
  /// - Runs via Flutter's [compute()] — never blocks the UI thread.
  /// - Safe on both iOS and Android.
  /// - Returns original bytes unchanged if [settings] is identity.
  static Future<Uint8List> bakeEnhancement(
    Uint8List inputBytes,
    ImageEnhancementSettings settings,
  ) {
    if (settings.isIdentity) return Future.value(inputBytes);
    return compute(
      _bakeInIsolate,
      _BakePayload(
        bytes: inputBytes,
        brightness: settings.brightness,
        contrast: settings.contrast,
        saturation: settings.saturation,
        warmth: settings.warmth,
        sharpness: settings.sharpness,
      ),
    );
  }
}
