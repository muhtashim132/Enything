import 'package:flutter/material.dart';

/// Modern 3D Claymorphic surface container.
/// Features dual directional lighting shadows (top-left highlight + bottom-right depth)
/// for a tactile, physical 3D appearance.
class ClaymorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? surfaceColor;
  final double depth; // 1.0 to 10.0
  final bool isDark;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool isConvex;
  final Border? border;

  const ClaymorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.surfaceColor,
    this.depth = 6.0,
    required this.isDark,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.isConvex = true,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = surfaceColor ??
        (isDark ? const Color(0xFF161828) : const Color(0xFFFFFFFF));

    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.90);

    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : const Color(0xFF0F1E80).withValues(alpha: 0.08);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.60),
              width: 1.0,
            ),
        gradient: isConvex
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        baseColor.withValues(alpha: 1.0),
                        baseColor.withValues(alpha: 0.85),
                      ]
                    : [
                        Colors.white,
                        const Color(0xFFF7F8FF),
                      ],
              )
            : null,
        boxShadow: [
          // Top-Left Light Source Highlight
          BoxShadow(
            color: highlightColor,
            offset: Offset(-depth * 0.8, -depth * 0.8),
            blurRadius: depth * 1.5,
            spreadRadius: 0,
          ),
          // Bottom-Right Ambient Depth Shadow
          BoxShadow(
            color: shadowColor,
            offset: Offset(depth, depth * 1.2),
            blurRadius: depth * 2.2,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
