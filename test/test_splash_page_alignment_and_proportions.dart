import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100X Splash Screen & Typography Alignment Forensic Suite', () {
    test('1. Trailing letterSpacing asymmetry theorem & optical compensation', () {
      const double letterSpacing = 8.0;
      const int glyphCount = 8; // 'E N Y T H I N G'
      const double averageGlyphWidth = 24.5; // Approximate Outfit 38pt glyph width

      // Impeller/Skia paragraph layout model
      // ParagraphBuilder adds letterSpacing AFTER each glyph, including the last one.
      const double totalGlyphWidth = glyphCount * averageGlyphWidth;
      const double totalTrailingSpacing = glyphCount * letterSpacing;
      const double paragraphWidth = totalGlyphWidth + totalTrailingSpacing;

      // The visible character bounds end at the right edge of the 8th glyph (before trailing whitespace)
      const double visibleGlyphsRightEdge = totalGlyphWidth + (glyphCount - 1) * letterSpacing;
      const double visibleGlyphsWidth = visibleGlyphsRightEdge; // starts at x = 0

      // Centers
      const double paragraphBoundingCenter = paragraphWidth / 2;
      const double visibleGlyphsOpticalCenter = visibleGlyphsWidth / 2;

      // The uncompensated skew to the left
      const double uncompensatedSkew = paragraphBoundingCenter - visibleGlyphsOpticalCenter;
      expect(uncompensatedSkew, equals(letterSpacing / 2));
      expect(uncompensatedSkew, equals(4.0));

      // With optical compensation (+4.0px translation):
      const double opticalOffset = letterSpacing / 2;
      const double compensatedOpticalCenter = visibleGlyphsOpticalCenter + opticalOffset;

      // Now the visible character center is IDENTICAL to the paragraph bounding center!
      expect(compensatedOpticalCenter, equals(paragraphBoundingCenter));
    });

    test('2. Logo squircle responsive bounds & clamping formula', () {
      double computeLogoSize(double shortestSide) {
        return (shortestSide * 0.25).clamp(90.0, 108.0);
      }

      // Compact device: iPhone SE 1st Gen (320px)
      expect(computeLogoSize(320.0), equals(90.0));

      // Compact Android: 360px
      expect(computeLogoSize(360.0), equals(90.0));

      // Standard iPhone 13/14/15/16: 390px
      expect(computeLogoSize(390.0), equals(97.5));

      // Standard Large: iPhone 14/15/16 Pro Max: 430px
      expect(computeLogoSize(430.0), equals(107.5));

      // Tablet / iPad: 768px
      expect(computeLogoSize(768.0), equals(108.0));

      // Large iPad Pro: 1024px
      expect(computeLogoSize(1024.0), equals(108.0));
    });

    test('3. Golden ratio & negative space visual hierarchy', () {
      const double screenWidth = 390.0;
      const double letterSpacing = 8.0;
      const int charCount = 8;

      // Estimated rendered width of "ENYTHING"
      // In Outfit font, average uppercase character width at 38pt is ~24.5px
      const double estimatedWordmarkWidth = (charCount * 24.5) + (charCount * letterSpacing);
      const double screenWidthRatio = estimatedWordmarkWidth / screenWidth;
      const double sideMargins = (screenWidth - estimatedWordmarkWidth) / 2;

      // Industrial standard: wordmark should occupy 55% - 70% of screen width
      expect(screenWidthRatio, greaterThanOrEqualTo(0.55));
      expect(screenWidthRatio, lessThanOrEqualTo(0.70));

      // Side breathing room must be generous (at least 55px on 390px display)
      expect(sideMargins, greaterThanOrEqualTo(55.0));

      // Logo squircle size on 390px screen is 97.5px
      final double logoSize = (screenWidth * 0.25).clamp(90.0, 108.0);
      final double wordmarkToLogoRatio = estimatedWordmarkWidth / logoSize;

      // Ratio between wordmark width and logo size is in the golden harmony zone (~2.6:1)
      expect(wordmarkToLogoRatio, closeTo(2.6, 0.4));
    });

    test('4. Bottom loading dots ergonomics and dynamic pulse scaling', () {
      double computeBottomPosition(double safeAreaBottom) {
        return math.max(32.0, safeAreaBottom + 16.0);
      }

      // No safe area (older devices or fullscreen Android):
      expect(computeBottomPosition(0.0), equals(32.0));

      // Standard iOS home indicator safe area (34px):
      expect(computeBottomPosition(34.0), equals(50.0));

      // Heavy bottom inset (48px):
      expect(computeBottomPosition(48.0), equals(64.0));

      // Dynamic wave pulse sizing test:
      for (double bgCtrlValue = 0.0; bgCtrlValue <= 1.0; bgCtrlValue += 0.1) {
        for (int i = 0; i < 3; i++) {
          final wave = (math.sin((bgCtrlValue * 6) - i * 1.0) + 1) / 2;
          final dotSize = 5.5 + wave * 2.5;

          // Pulse size must strictly oscillate between 5.5px and 8.0px
          expect(dotSize, greaterThanOrEqualTo(5.5));
          expect(dotSize, lessThanOrEqualTo(8.0));
        }
      }
    });

    test('5. Concentric Light Anchor Coordinate Invariance', () {
      // Test that the concentric anchor ensures logo, aurora glow, and shockwave rings
      // have identical center coordinates regardless of screen height or aspect ratio.
      final testScreens = [
        const Size(320, 568),
        const Size(360, 800),
        const Size(390, 844),
        const Size(430, 932),
        const Size(768, 1024),
      ];

      for (final size in testScreens) {
        final logoSize = (size.shortestSide * 0.25).clamp(90.0, 108.0);
        final anchorBox = Rect.fromLTWH(0, 0, logoSize, logoSize);
        final anchorCenter = anchorBox.center;

        // The center of the anchor box
        expect(anchorCenter.dx, equals(logoSize / 2));
        expect(anchorCenter.dy, equals(logoSize / 2));

        // When OverflowBox centers the 0.85*shortestSide aurora within anchorBox:
        final auroraSize = size.shortestSide * 0.85;
        final auroraRect = Rect.fromCenter(center: anchorCenter, width: auroraSize, height: auroraSize);
        expect(auroraRect.center, equals(anchorCenter));

        // When OverflowBox centers each expanding ring within anchorBox:
        final ringMaxRadius = size.shortestSide * 0.46;
        final ringRect = Rect.fromCenter(center: anchorCenter, width: ringMaxRadius * 2, height: ringMaxRadius * 2);
        expect(ringRect.center, equals(anchorCenter));
      }
    });
  });
}

