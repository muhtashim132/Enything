import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Enything Super Admin Design System ─────────────────────────
// Single source of truth for all admin UI tokens.

class AdminColors {
  AdminColors._();

  // Gradient
  static const primary = Color(0xFF6C2BD9);
  static const primaryEnd = Color(0xFF2563EB);

  // Accent
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF06B6D4);

  // Background layers
  static const bg = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);
  static const surfaceHigh = Color(0xFF263448);

  // Card
  static const cardBg = Color(0x12FFFFFF);
  static const cardBorder = Color(0x1FFFFFFF);

  // Text
  static const textPrimary = Color(0xF0FFFFFF);
  static const textSecondary = Color(0x99FFFFFF);
  static const textMuted = Color(0x55FFFFFF);
}

class AdminGradients {
  AdminGradients._();

  static const primary = LinearGradient(
    colors: [AdminColors.primary, AdminColors.primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const success = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const warning = LinearGradient(
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const danger = LinearGradient(
    colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const info = LinearGradient(
    colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const dark = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AdminStyles {
  AdminStyles._();

  static TextStyle heading({double size = 26, Color color = AdminColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w700, color: color);

  static TextStyle title({double size = 18, Color color = AdminColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w600, color: color);

  static TextStyle body({double size = 14, Color color = AdminColors.textPrimary}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w400, color: color);

  static TextStyle caption({double size = 12, Color color = AdminColors.textSecondary}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w400, color: color);

  static TextStyle label({double size = 11, Color color = AdminColors.textMuted}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w500, color: color, letterSpacing: 0.5);
}

// ── Reusable Decoration ──────────────────────────────────────────
class AdminDecorations {
  AdminDecorations._();

  static BoxDecoration glassCard({
    Color? borderColor,
    double radius = 20,
    Color? bgColor,
    List<BoxShadow>? shadows,
  }) =>
      BoxDecoration(
        color: bgColor ?? AdminColors.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AdminColors.cardBorder, width: 1),
        boxShadow: shadows ?? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration gradientCard(LinearGradient gradient, {double radius = 20}) =>
      BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  static BoxDecoration surface({double radius = 20}) => BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AdminColors.cardBorder),
      );
}

// ── Reusable Widgets ─────────────────────────────────────────────

/// Glassmorphism card container
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? bgColor;
  final Color? borderColor;

  const AdminCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.bgColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: AdminDecorations.glassCard(radius: radius, bgColor: bgColor, borderColor: borderColor),
      child: child,
    );
  }
}

/// Gradient filled card
class AdminGradientCard extends StatelessWidget {
  final Widget child;
  final LinearGradient gradient;
  final EdgeInsetsGeometry? padding;
  final double radius;

  const AdminGradientCard({
    super.key,
    required this.child,
    required this.gradient,
    this.padding,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: AdminDecorations.gradientCard(gradient, radius: radius),
      child: child,
    );
  }
}

/// Status badge chip
class AdminBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const AdminBadge({super.key, required this.label, required this.color, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              color: color, fontSize: fontSize, fontWeight: FontWeight.w600)),
    );
  }
}

/// KPI metric card for the dashboard grid
class AdminKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final LinearGradient gradient;
  final bool loading;
  final VoidCallback? onTap;

  const AdminKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.gradient,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AdminColors.cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: loading
          ? const _KpiSkeleton()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                Text(value,
                    style: GoogleFonts.poppins(
                        color: AdminColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(title,
                    style: GoogleFonts.poppins(
                        color: AdminColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: GoogleFonts.poppins(
                          color: AdminColors.textMuted, fontSize: 10)),
              ],
            ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: card,
        ),
      );
    }
    return card;
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: Colors.white12, borderRadius: BorderRadius.circular(12))),
        const Spacer(),
        Container(width: 80, height: 20, color: Colors.white12),
        const SizedBox(height: 6),
        Container(width: 60, height: 11, color: Colors.white12),
      ],
    );
  }
}

/// Section header row
class AdminSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AdminSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AdminStyles.title(size: 15)),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel!,
                  style: AdminStyles.caption(color: AdminColors.primary)),
            ),
        ],
      ),
    );
  }
}

/// Empty state placeholder
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const AdminEmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white12, size: 64),
          const SizedBox(height: 16),
          Text(message, style: AdminStyles.body(color: AdminColors.textMuted)),
        ],
      ),
    );
  }
}

/// Shimmer skeleton box
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
