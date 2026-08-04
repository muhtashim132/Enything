import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';

class ProductCardSkeleton extends StatelessWidget {
  final bool isDark;

  const ProductCardSkeleton({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: PremiumRadius.largeBorder,
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
        boxShadow: PremiumShadows.card(isDark: isDark, isPressed: false),
      ),
      child: Shimmer.fromColors(
        baseColor: PremiumShimmer.baseColor(isDark),
        highlightColor: PremiumShimmer.highlightColor(isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product Image Skeleton ────────────────────────────────────────────
            AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PremiumRadius.large)),
                child: Container(
                  color: Colors.white, // Color is controlled by Shimmer
                ),
              ),
            ),

            // ── Info Skeleton ─────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Product name skeleton (2 lines)
                    _buildSkeletonLine(width: double.infinity, height: 12),
                    const SizedBox(height: 6),
                    _buildSkeletonLine(width: 100, height: 12),
                    const SizedBox(height: 12),

                    // Shop name skeleton
                    _buildSkeletonLine(width: 80, height: 10),
                    const SizedBox(height: 12),

                    // Rating skeleton
                    _buildSkeletonLine(width: 60, height: 12),

                    const Spacer(),

                    // Price row skeleton
                    _buildSkeletonLine(width: 70, height: 16),
                    const SizedBox(height: 14),

                    // Add button skeleton
                    Container(
                      width: double.infinity,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLine({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
