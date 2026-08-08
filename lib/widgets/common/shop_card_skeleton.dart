import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';

class ShopCardSkeleton extends StatelessWidget {
  final bool isDark;

  const ShopCardSkeleton({super.key, required this.isDark});

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
            // ── Header Image Skeleton ─────────────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PremiumRadius.large)),
                child: Container(
                  color: Colors.white,
                ),
              ),
            ),

            // ── Info Skeleton ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop Name
                  Row(
                    children: [
                      Expanded(
                        child: _buildSkeletonLine(
                            width: double.infinity, height: 16),
                      ),
                      const SizedBox(width: 8),
                      // Mock arrow icon
                      Container(
                        width: 12,
                        height: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Cuisine / Type
                  _buildSkeletonLine(width: 100, height: 12),
                  const SizedBox(height: 12),

                  // Chips row
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildSkeletonChip(width: 70),
                      _buildSkeletonChip(width: 60),
                      _buildSkeletonChip(width: 90),
                    ],
                  ),
                ],
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

  Widget _buildSkeletonChip({required double width}) {
    return Container(
      width: width,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
