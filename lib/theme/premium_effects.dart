import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Reusable premium visual constants for consistent premium styling.
/// This is the single source of truth for all visual effects used across the app.

// ─────────────────────────────────────────────────────────────────────────────
// Border Radii
// ─────────────────────────────────────────────────────────────────────────────
class PremiumRadius {
  PremiumRadius._();

  static const double small = 12;
  static const double medium = 18;
  static const double large = 24;
  static const double xl = 28;
  static const double pill = 100;

  static BorderRadius get smallBorder => BorderRadius.circular(small);
  static BorderRadius get mediumBorder => BorderRadius.circular(medium);
  static BorderRadius get largeBorder => BorderRadius.circular(large);
  static BorderRadius get xlBorder => BorderRadius.circular(xl);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shadows
// ─────────────────────────────────────────────────────────────────────────────
class PremiumShadows {
  PremiumShadows._();

  // ── Light Theme Shadows ────────────────────────────────────────────────────
  static List<BoxShadow> get cardLight => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 8),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get cardLightPressed => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get elevatedLight => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 30,
          offset: const Offset(0, 12),
          spreadRadius: -2,
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get floatingButtonLight => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  // ── Dark Theme Shadows ─────────────────────────────────────────────────────
  static List<BoxShadow> get cardDark => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 10),
          spreadRadius: -2,
        ),
      ];

  static List<BoxShadow> get cardDarkPressed => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get elevatedDark => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.60),
          blurRadius: 36,
          offset: const Offset(0, 14),
          spreadRadius: -2,
        ),
      ];

  /// Returns appropriate card shadow based on theme and press state
  static List<BoxShadow> card({required bool isDark, bool isPressed = false}) {
    if (isDark) return isPressed ? cardDarkPressed : cardDark;
    return isPressed ? cardLightPressed : cardLight;
  }

  /// Returns elevated shadow based on theme
  static List<BoxShadow> elevated({required bool isDark}) {
    return isDark ? elevatedDark : elevatedLight;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decorations
// ─────────────────────────────────────────────────────────────────────────────
class PremiumDecorations {
  PremiumDecorations._();

  /// Premium card decoration with proper shadow and border
  static BoxDecoration cardDecoration({
    required bool isDark,
    bool isPressed = false,
    double borderRadius = 24,
  }) {
    return BoxDecoration(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(borderRadius),
      border: isDark
          ? Border.all(color: Colors.white.withValues(alpha: 0.07))
          : null,
      boxShadow: PremiumShadows.card(isDark: isDark, isPressed: isPressed),
    );
  }

  /// Glassmorphism container decoration
  static BoxDecoration glassmorphism({
    required bool isDark,
    double borderRadius = 18,
    double opacity = 0.12,
  }) {
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: opacity * 0.6)
          : Colors.white.withValues(alpha: opacity * 3),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.6),
      ),
    );
  }

  /// Frosted glass effect decoration for bottom bars / overlays
  static BoxDecoration frostedGlass({
    required bool isDark,
    double borderRadius = 24,
  }) {
    return BoxDecoration(
      color: isDark
          ? const Color(0xFF1A1A2E).withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.80),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.grey.shade200.withValues(alpha: 0.5),
      ),
    );
  }

  /// Gradient chip/badge decoration
  static BoxDecoration gradientBadge({
    required List<Color> colors,
    double borderRadius = 10,
    bool addShadow = true,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: addShadow
          ? [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.40),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }

  /// Image container gradient background (for product images)
  static BoxDecoration imageContainerBg({required bool isDark}) {
    return BoxDecoration(
      gradient: isDark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF242438), Color(0xFF1A1A2E)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8F9FF), Color(0xFFEEF2FF)],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animation Constants
// ─────────────────────────────────────────────────────────────────────────────
class PremiumAnimations {
  PremiumAnimations._();

  // Durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);
  static const Duration pageTransition = Duration(milliseconds: 350);
  static const Duration staggerDelay = Duration(milliseconds: 60);

  // Curves
  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve smoothCurve = Curves.easeInOutCubic;
  static const Curve snappyCurve = Curves.easeOutBack;

  // Press animation scale
  static const double pressedScale = 0.96;
  static const double normalScale = 1.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper extension for consistent shimmer colors
// ─────────────────────────────────────────────────────────────────────────────
class PremiumShimmer {
  PremiumShimmer._();

  static Color baseColor(bool isDark) =>
      isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE8E8EE);

  static Color highlightColor(bool isDark) =>
      isDark ? const Color(0xFF2A2A3E) : const Color(0xFFF4F4FA);
}
