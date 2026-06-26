import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/premium_effects.dart';

class SheetSkeletonLoader extends StatelessWidget {
  final bool isDark;

  const SheetSkeletonLoader({
    super.key,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 24),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        
        Expanded(
          child: Shimmer.fromColors(
            baseColor: PremiumShimmer.baseColor(isDark),
            highlightColor: PremiumShimmer.highlightColor(isDark),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Big Square + Text Lines
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Square Image Skeleton
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: PremiumRadius.smallBorder,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text Lines Skeleton
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            _buildSkeletonLine(width: double.infinity, height: 14),
                            const SizedBox(height: 12),
                            _buildSkeletonLine(width: 100, height: 14),
                            const SizedBox(height: 12),
                            _buildSkeletonLine(width: double.infinity, height: 14),
                            const SizedBox(height: 12),
                            _buildSkeletonLine(width: 140, height: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Full Width Lines Below
                  _buildSkeletonLine(width: 120, height: 16),
                  const SizedBox(height: 16),
                  _buildSkeletonLine(width: double.infinity, height: 14),
                  const SizedBox(height: 12),
                  _buildSkeletonLine(width: double.infinity, height: 14),
                  const SizedBox(height: 12),
                  _buildSkeletonLine(width: 200, height: 14),
                ],
              ),
            ),
          ),
        ),
      ],
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
