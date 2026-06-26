import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Colors - Royal Blue
  static const Color primary = Color(0xFF0A2A9E);
  static const Color primaryDark = Color(0xFF071D6B);
  static const Color primaryLight = Color(0xFF1E40AF);

  // Secondary - Orange (used mostly for CTA)
  static const Color secondary = Color(0xFFFF8A00);
  static const Color secondaryLight = Color(0xFFFF9900);

  // Accent - Gold
  static const Color accent = Color(0xFFF4C542);
  static const Color accentLight = Color(0xFFFDE68A);

  // Semantic Colors
  static const Color success = Color(0xFF00C853);
  static const Color successLight = Color(0xFFB9F6CA);
  static const Color warning = Color(0xFFFF6D00);
  static const Color warningLight = Color(0xFFFFE0B2);
  static const Color danger = Color(0xFFD32F2F);
  static const Color dangerLight = Color(0xFFFFCDD2);
  static const Color info = Color(0xFF0288D1);

  // Food / Category Colors
  static const Color foodRed = Color(0xFFE53935);
  static const Color groceryGreen = Color(0xFF2E7D32);
  static const Color pharmacyBlue = Color(0xFF1565C0);
  static const Color vegGreen = Color(0xFF388E3C);
  static const Color nonVegRed = Color(0xFFB71C1C);

  // Backgrounds
  static const Color background = Color(0xFFF8F9FA);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color darkBg = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkCard = Color(0xFF16213E);

  // Premium Surface Elevations (for layered cards / sheets)
  static const Color surfaceElevatedLight = Color(0xFFF0F2F8);
  static const Color surfaceElevatedDark = Color(0xFF222236);
  static const Color surfaceOverlayLight = Color(0xFFE8EAF0);
  static const Color surfaceOverlayDark = Color(0xFF2A2A40);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Divider & Border
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFD1D5DB);

  // Shimmer
  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);

  // Premium Trust & Status Colors
  static const Color premiumGold = Color(0xFFD4A017);
  static const Color premiumGoldLight = Color(0xFFFFF8E1);
  static const Color premiumSilver = Color(0xFF9E9E9E);
  static const Color trustGreen = Color(0xFF2E7D32);
  static const Color savingsGreen = Color(0xFF1B5E20);

  // Glassmorphism Overlays
  static const Color glassLight = Color(0x26FFFFFF);
  static const Color glassDark = Color(0x1AFFFFFF);
  static const Color glassBorderLight = Color(0x40FFFFFF);
  static const Color glassBorderDark = Color(0x14FFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0A2A9E), Color(0xFF071D6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF0A2A9E), Color(0xFF071D6B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient ctaGradient = LinearGradient(
    colors: [Color(0xFFFF8A00), Color(0xFFFF6B00)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient splashGradient = heroGradient;

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
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
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

  // Premium Additional Gradients
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
    colors: [Color(0xFFD4A017), Color(0xFFF4C542)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradientLight = LinearGradient(
    colors: [Color(0xFFE8E8EE), Color(0xFFF4F4FA), Color(0xFFE8E8EE)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradientDark = LinearGradient(
    colors: [Color(0xFF1E1E2E), Color(0xFF2A2A3E), Color(0xFF1E1E2E)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
