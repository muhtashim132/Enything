import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Helper math and transformation model for Product Photo Alignment Studio
class AlignmentStudioMath {
  static const double minScale = 0.5;
  static const double maxScale = 3.0;
  static const double minAngle = -45.0;
  static const double maxAngle = 45.0;
  static const double snapThreshold = 0.5; // Snap to 0.0 if within 0.5 degrees

  /// Clamps user scale slider between 0.5x and 3.0x
  static double clampScale(double scale) {
    return scale.clamp(minScale, maxScale);
  }

  /// Normalizes angle to [-45.0, 45.0] and snaps to 0.0 if within threshold
  static double normalizeAngle(double angle) {
    if (angle.abs() <= snapThreshold) return 0.0;
    return angle.clamp(minAngle, maxAngle);
  }

  /// Calculates scale factor to fit the entire image inside the frame without cropping
  static double calculateFitScale({
    required double imgWidth,
    required double imgHeight,
    required double frameWidth,
    required double frameHeight,
  }) {
    if (imgWidth <= 0 || imgHeight <= 0 || frameWidth <= 0 || frameHeight <= 0) {
      return 1.0;
    }
    return math.min(frameWidth / imgWidth, frameHeight / imgHeight);
  }

  /// Calculates scale factor so the image completely covers the frame
  static double calculateFillScale({
    required double imgWidth,
    required double imgHeight,
    required double frameWidth,
    required double frameHeight,
  }) {
    if (imgWidth <= 0 || imgHeight <= 0 || frameWidth <= 0 || frameHeight <= 0) {
      return 1.0;
    }
    return math.max(frameWidth / imgWidth, frameHeight / imgHeight);
  }

  /// Calculates target output dimensions given an input size and aspect ratio
  static Size calculateOutputDimensions({
    required int inputWidth,
    required int inputHeight,
    required double? targetAspectRatio,
  }) {
    if (targetAspectRatio == null) {
      return Size(inputWidth.toDouble(), inputHeight.toDouble());
    }

    const int maxDim = 1600;
    const int minDim = 800;

    if ((targetAspectRatio - 1.0).abs() < 0.01) {
      // 1:1 Square
      final side = math.max(inputWidth, inputHeight).clamp(minDim, maxDim).toDouble();
      return Size(side, side);
    } else if (targetAspectRatio > 1.0) {
      // Widescreen (e.g. 16:9)
      final w = math.max(inputWidth, minDim).clamp(minDim, maxDim).toDouble();
      final h = (w / targetAspectRatio).roundToDouble();
      return Size(w, h);
    } else {
      // Portrait / Fashion (e.g. 3:4)
      final h = math.max(inputHeight, minDim).clamp(minDim, maxDim).toDouble();
      final w = (h * targetAspectRatio).roundToDouble();
      return Size(w, h);
    }
  }

  /// Converts a Flutter Color to an Image package ColorRgba8 safely
  static img.ColorRgba8 toImageColor(Color color) {
    return img.ColorRgba8(
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
      (color.a * 255.0).round().clamp(0, 255),
    );
  }
}

/// Standalone pure isolate worker for aligned image export
Uint8List testRenderAlignedImageWorker(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final scale = (params['scale'] as num?)?.toDouble() ?? 1.0;
  final angle = (params['angle'] as num?)?.toDouble() ?? 0.0;
  final normOffsetX = (params['normOffsetX'] as num?)?.toDouble() ?? 0.0;
  final normOffsetY = (params['normOffsetY'] as num?)?.toDouble() ?? 0.0;
  final flipH = params['flipH'] as bool? ?? false;
  final flipV = params['flipV'] as bool? ?? false;
  final bgColorValue = params['bgColorValue'] as int? ?? 0xFFFFFFFF;
  final aspectRatio = (params['aspectRatio'] as num?)?.toDouble();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  var processed = decoded;

  // 1. Flips
  if (flipH) {
    processed = img.flipHorizontal(processed);
  }
  if (flipV) {
    processed = img.flipVertical(processed);
  }

  // 2. Straighten & Tilt
  if (angle.abs() > 0.05) {
    processed = img.copyRotate(processed, angle: angle);
  }

  // 3. Canvas dimensions
  final int canvasWidth;
  final int canvasHeight;
  const int maxDim = 1600;
  const int minDim = 800;

  if (aspectRatio != null) {
    if ((aspectRatio - 1.0).abs() < 0.01) {
      final side = math.max(processed.width, processed.height).clamp(minDim, maxDim);
      canvasWidth = side;
      canvasHeight = side;
    } else if (aspectRatio > 1.0) {
      canvasWidth = math.max(processed.width, minDim).clamp(minDim, maxDim);
      canvasHeight = (canvasWidth / aspectRatio).round();
    } else {
      canvasHeight = math.max(processed.height, minDim).clamp(minDim, maxDim);
      canvasWidth = (canvasHeight * aspectRatio).round();
    }
  } else {
    canvasWidth = processed.width;
    canvasHeight = processed.height;
  }

  // 4. Scaling
  final double baseScale = math.min(
    canvasWidth / processed.width,
    canvasHeight / processed.height,
  );
  final effectiveScale = baseScale * scale;
  final targetW = math.max(1, (processed.width * effectiveScale).round());
  final targetH = math.max(1, (processed.height * effectiveScale).round());

  final scaledImage = img.copyResize(
    processed,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.linear,
  );

  // 5. Canvas with background color
  final canvas = img.Image(width: canvasWidth, height: canvasHeight);
  final bgR = (bgColorValue >> 16) & 0xFF;
  final bgG = (bgColorValue >> 8) & 0xFF;
  final bgB = bgColorValue & 0xFF;
  final bgA = (bgColorValue >> 24) & 0xFF;
  canvas.clear(img.ColorRgba8(bgR, bgG, bgB, bgA));

  // 6. Placement with offset
  final centerX = (canvasWidth - targetW) ~/ 2;
  final centerY = (canvasHeight - targetH) ~/ 2;
  final shiftX = (normOffsetX * canvasWidth).round();
  final shiftY = (normOffsetY * canvasHeight).round();

  img.compositeImage(
    canvas,
    scaledImage,
    dstX: centerX + shiftX,
    dstY: centerY + shiftY,
  );

  // 7. JPEG output
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
}

void main() {
  group('Product Photo Alignment Studio — Math & Logic Suite', () {
    test('Scale clamping strictly constrains between 0.5x and 3.0x', () {
      expect(AlignmentStudioMath.clampScale(0.1), equals(0.5));
      expect(AlignmentStudioMath.clampScale(0.5), equals(0.5));
      expect(AlignmentStudioMath.clampScale(1.0), equals(1.0));
      expect(AlignmentStudioMath.clampScale(1.85), equals(1.85));
      expect(AlignmentStudioMath.clampScale(3.0), equals(3.0));
      expect(AlignmentStudioMath.clampScale(5.2), equals(3.0));
    });

    test('Angle normalization snaps to 0.0 within threshold and clamps to ±45°', () {
      // Snap to 0.0
      expect(AlignmentStudioMath.normalizeAngle(0.2), equals(0.0));
      expect(AlignmentStudioMath.normalizeAngle(-0.4), equals(0.0));
      expect(AlignmentStudioMath.normalizeAngle(0.0), equals(0.0));

      // Regular angles
      expect(AlignmentStudioMath.normalizeAngle(3.5), equals(3.5));
      expect(AlignmentStudioMath.normalizeAngle(-12.8), equals(-12.8));

      // Clamping limits
      expect(AlignmentStudioMath.normalizeAngle(60.0), equals(45.0));
      expect(AlignmentStudioMath.normalizeAngle(-55.0), equals(-45.0));
    });

    test('calculateFitScale ensures complete image visibility inside target frame', () {
      final fitLandscape = AlignmentStudioMath.calculateFitScale(
        imgWidth: 800,
        imgHeight: 400,
        frameWidth: 400,
        frameHeight: 400,
      );
      expect(fitLandscape, equals(0.5));

      final fitPortrait = AlignmentStudioMath.calculateFitScale(
        imgWidth: 300,
        imgHeight: 900,
        frameWidth: 300,
        frameHeight: 300,
      );
      expect(fitPortrait, closeTo(0.333, 0.001));
    });

    test('calculateFillScale ensures frame is completely covered', () {
      final fillLandscape = AlignmentStudioMath.calculateFillScale(
        imgWidth: 800,
        imgHeight: 400,
        frameWidth: 400,
        frameHeight: 400,
      );
      expect(fillLandscape, equals(1.0));
    });

    test('calculateOutputDimensions computes high-resolution dimensions for e-commerce', () {
      final square = AlignmentStudioMath.calculateOutputDimensions(
        inputWidth: 600,
        inputHeight: 400,
        targetAspectRatio: 1.0,
      );
      expect(square.width, equals(800.0));
      expect(square.height, equals(800.0));

      final fashion = AlignmentStudioMath.calculateOutputDimensions(
        inputWidth: 900,
        inputHeight: 1200,
        targetAspectRatio: 3.0 / 4.0,
      );
      expect(fashion.height, equals(1200.0));
      expect(fashion.width, equals(900.0));

      final free = AlignmentStudioMath.calculateOutputDimensions(
        inputWidth: 1050,
        inputHeight: 700,
        targetAspectRatio: null,
      );
      expect(free.width, equals(1050.0));
      expect(free.height, equals(700.0));
    });

    test('Color conversion converts Flutter Colors to Image package ColorRgba8', () {
      final white = AlignmentStudioMath.toImageColor(Colors.white);
      expect(white.r, equals(255));
      expect(white.g, equals(255));
      expect(white.b, equals(255));
      expect(white.a, equals(255));

      final black = AlignmentStudioMath.toImageColor(Colors.black);
      expect(black.r, equals(0));
      expect(black.g, equals(0));
      expect(black.b, equals(0));
    });

    test('testRenderAlignedImageWorker generates valid squared JPEG with 100x transforms', () {
      // Create test raw image
      final rawImg = img.Image(width: 400, height: 300);
      rawImg.clear(img.ColorRgba8(50, 150, 250, 255));
      final rawBytes = Uint8List.fromList(img.encodeJpg(rawImg));

      final exportedBytes = testRenderAlignedImageWorker({
        'bytes': rawBytes,
        'scale': 1.25,
        'angle': 5.0,
        'normOffsetX': 0.05,
        'normOffsetY': -0.02,
        'flipH': true,
        'flipV': false,
        'bgColorValue': 0xFFFFFFFF,
        'aspectRatio': 1.0,
      });

      expect(exportedBytes, isNotEmpty);
      final decodedExport = img.decodeJpg(exportedBytes);
      expect(decodedExport, isNotNull);
      expect(decodedExport!.width, equals(800));
      expect(decodedExport.height, equals(800));
    });
  });
}
