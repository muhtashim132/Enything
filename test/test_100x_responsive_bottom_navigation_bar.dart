import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100x Responsive Bottom Navigation Bar Formula Verification', () {
    double calculateResponsiveBottomMargin({
      required double viewPaddingBottom,
      required double paddingBottom,
      required TargetPlatform platform,
    }) {
      final bottomInset = viewPaddingBottom > paddingBottom
          ? viewPaddingBottom
          : paddingBottom;

      if (bottomInset <= 0) {
        return 10.0;
      } else if (bottomInset >= 36.0) {
        return bottomInset + 4.0;
      } else if (platform == TargetPlatform.iOS) {
        return bottomInset;
      } else {
        return bottomInset + 4.0;
      }
    }

    test('Android 3-Button Navigation (Samsung, Xiaomi: 48dp inset)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 48.0,
        paddingBottom: 48.0,
        platform: TargetPlatform.android,
      );

      // Must be strictly greater than 48dp (0% overlap with system buttons)
      expect(margin, greaterThan(48.0));
      // Must sit cleanly 4dp above the 48dp buttons
      expect(margin, equals(52.0));
      // Must NOT inflate an awkward huge gap (e.g. > 60dp)
      expect(margin, lessThan(60.0));
    });

    test('Android 3-Button Navigation (Dense Display: 54dp inset)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 54.0,
        paddingBottom: 54.0,
        platform: TargetPlatform.android,
      );

      expect(margin, equals(58.0));
      expect(margin, greaterThan(54.0));
    });

    test('Android 2-Button Navigation (Older Android: 40dp inset)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 40.0,
        paddingBottom: 40.0,
        platform: TargetPlatform.android,
      );

      expect(margin, equals(44.0));
      expect(margin, greaterThan(40.0));
    });

    test('Android Gesture Navigation (Pixel, Galaxy Gesture: 20dp inset)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 20.0,
        paddingBottom: 20.0,
        platform: TargetPlatform.android,
      );

      expect(margin, equals(24.0));
      expect(margin, greaterThan(20.0));
      expect(margin, lessThan(30.0));
    });

    test('iOS Home Indicator (iPhone 14/15/16 Pro: 34dp inset)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 34.0,
        paddingBottom: 34.0,
        platform: TargetPlatform.iOS,
      );

      // On iOS, sits flush at safe area boundary (34.0) without inflating huge gap
      expect(margin, equals(34.0));
      expect(margin, lessThan(45.0));
    });

    test('Zero Inset Devices (Capacitive Keys, iPhone SE, Web, Desktop: 0dp)', () {
      final margin = calculateResponsiveBottomMargin(
        viewPaddingBottom: 0.0,
        paddingBottom: 0.0,
        platform: TargetPlatform.android,
      );

      expect(margin, equals(10.0));
    });

    test('Horizontal Margins: Adapts dynamically based on screen width', () {
      double getHorizontalMargin(double screenWidth) {
        final isNarrow = screenWidth < 360;
        return isNarrow ? 12.0 : (screenWidth < 400 ? 16.0 : 20.0);
      }

      // Small compact phone (320dp width)
      expect(getHorizontalMargin(320), equals(12.0));
      // Standard compact phone (360dp width)
      expect(getHorizontalMargin(360), equals(16.0));
      // Modern standard phone (390dp width - iPhone 14)
      expect(getHorizontalMargin(390), equals(16.0));
      // Large phone (412dp - Galaxy S24, 430dp - iPhone Pro Max)
      expect(getHorizontalMargin(412), equals(20.0));
      expect(getHorizontalMargin(430), equals(20.0));
    });
  });
}
