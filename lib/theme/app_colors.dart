import 'package:flutter/material.dart';

class AppColors {
  // ── Primary Brand Colors — Cobalt Blue (2026 premium) ──────────────────────
  static const Color primary = Color(0xFF1E3FD8);       // Vivid cobalt — energetic & trustworthy
  static const Color primaryDark = Color(0xFF0F1E80);   // Deep cobalt for dark mode depths
  static const Color primaryLight = Color(0xFF3D6BFF);  // Electric blue for glows/accents

  // ── Secondary — Warm Coral-Orange (CTA) ────────────────────────────────────
  static const Color secondary = Color(0xFFFF6B35);     // Warm coral — more modern than pure orange
  static const Color secondaryLight = Color(0xFFFF8C42);

  // ── Accent — Rich Gold ─────────────────────────────────────────────────────
  static const Color accent = Color(0xFFFFCF40);
  static const Color accentLight = Color(0xFFFFF0B0);

  // ── Semantic Colors ────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00C853);
  static const Color successLight = Color(0xFFB9F6CA);
  static const Color warning = Color(0xFFFF6D00);
  static const Color warningLight = Color(0xFFFFE0B2);
  static const Color danger = Color(0xFFD32F2F);
  static const Color dangerLight = Color(0xFFFFCDD2);
  static const Color info = Color(0xFF0288D1);

  // ── Food / Category Colors ─────────────────────────────────────────────────
  static const Color foodRed = Color(0xFFE53935);
  static const Color groceryGreen = Color(0xFF2E7D32);
  static const Color pharmacyBlue = Color(0xFF1565C0);
  static const Color vegGreen = Color(0xFF388E3C);
  static const Color nonVegRed = Color(0xFFB71C1C);

  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F6FF);     // Slight blue tint — premium light
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color darkBg = Color(0xFF0C0E1A);         // True near-black with blue undertone
  static const Color darkSurface = Color(0xFF141626);    // Richer dark surface
  static const Color darkCard = Color(0xFF1A1D30);       // Dark card background

  // ── Premium Surface Elevations ─────────────────────────────────────────────
  static const Color surfaceElevatedLight = Color(0xFFEEF0FF);
  static const Color surfaceElevatedDark = Color(0xFF1E2236);
  static const Color surfaceOverlayLight = Color(0xFFE4E6F8);
  static const Color surfaceOverlayDark = Color(0xFF252840);

  // ── Text Colors ────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF111827);    // Rich near-black, warm
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Divider & Border ───────────────────────────────────────────────────────
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFD1D5DB);

  // ── Shimmer ────────────────────────────────────────────────────────────────
  static const Color shimmerBase = Color(0xFFE0E0EE);
  static const Color shimmerHighlight = Color(0xFFF5F5FF);

  // ── Premium Trust & Status Colors ──────────────────────────────────────────
  static const Color premiumGold = Color(0xFFD4A017);
  static const Color premiumGoldLight = Color(0xFFFFF8E1);
  static const Color premiumSilver = Color(0xFF9E9E9E);
  static const Color trustGreen = Color(0xFF2E7D32);
  static const Color savingsGreen = Color(0xFF1B5E20);

  // ── Glassmorphism Overlays ─────────────────────────────────────────────────
  static const Color glassLight = Color(0x26FFFFFF);
  static const Color glassDark = Color(0x1AFFFFFF);
  static const Color glassBorderLight = Color(0x40FFFFFF);
  static const Color glassBorderDark = Color(0x14FFFFFF);

  // ══════════════════════════════════════════════════════════════════════════
  //  GRADIENTS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Primary (3-stop depth gradient) ───────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0F1E80), Color(0xFF1E3FD8), Color(0xFF3D6BFF)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Hero / Splash ──────────────────────────────────────────────────────────
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF070F50), Color(0xFF1E3FD8), Color(0xFF2F58FF)],
    stops: [0.0, 0.6, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── CTA Coral-Orange ───────────────────────────────────────────────────────
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient splashGradient = heroGradient;

  // ── Category Gradients ─────────────────────────────────────────────────────
  static const LinearGradient foodGradient = LinearGradient(
    colors: [Color(0xFFE53935), Color(0xFFFF6D00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient groceryGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF0C0E1A), Color(0xFF1A1D30)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sellerGradient = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient deliveryGradient = LinearGradient(
    colors: [Color(0xFF00695C), Color(0xFF26A69A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Semantic Gradients ─────────────────────────────────────────────────────
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFF6D00), Color(0xFFFFAB40)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFD32F2F), Color(0xFFFF5252)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumGoldGradient = LinearGradient(
    colors: [Color(0xFFD4A017), Color(0xFFFFCF40)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shimmer ────────────────────────────────────────────────────────────────
  static const LinearGradient shimmerGradientLight = LinearGradient(
    colors: [Color(0xFFE8E8EE), Color(0xFFF4F4FA), Color(0xFFE8E8EE)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradientDark = LinearGradient(
    colors: [Color(0xFF1A1D30), Color(0xFF252840), Color(0xFF1A1D30)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Royal Blue Glow (profile hero) ────────────────────────────────────────
  static const LinearGradient royalGlowGradient = LinearGradient(
    colors: [Color(0xFF0F1E80), Color(0xFF1E3FD8), Color(0xFF6B8EFF)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  ROLE-SPECIFIC PALETTE MAP
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the gradient for a given role string.
  static LinearGradient roleGradient(String role) {
    switch (role) {
      case 'seller':
        return sellerGradient;
      case 'delivery_partner':
        return deliveryGradient;
      case 'admin':
        return const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFFE91E63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'customer':
      default:
        return primaryGradient;
    }
  }

  /// Returns the solid accent color for a given role string.
  static Color roleColor(String role) {
    switch (role) {
      case 'seller':
        return const Color(0xFF9C27B0);
      case 'delivery_partner':
        return const Color(0xFF00897B);
      case 'admin':
        return const Color(0xFFAD1457);
      case 'customer':
      default:
        return primary;
    }
  }
}
