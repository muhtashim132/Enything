import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/premium_effects.dart';

/// Ultra-high-performance product image renderer.
/// Uses native hardware-accelerated gradients and optimized memory caching
/// without expensive live GPU BackdropFilters that cause frame drops or OOM crashes.
class PremiumProductImage extends StatelessWidget {
  final String imageUrl;
  final bool isDark;
  final double? width;
  final double? height;
  final BoxFit foregroundFit;

  const PremiumProductImage({
    super.key,
    required this.imageUrl,
    required this.isDark,
    this.width,
    this.height,
    this.foregroundFit = BoxFit.contain,
  });

  Widget _buildFallback(bool isDark) {
    return Container(
      width: width,
      height: height,
      color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F9),
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: isDark ? Colors.white30 : Colors.black26,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, String url) {
    return Shimmer.fromColors(
      baseColor: PremiumShimmer.baseColor(isDark),
      highlightColor: PremiumShimmer.highlightColor(isDark),
      child: Container(
        width: width,
        height: height,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildFallback(isDark);
    }

    // High performance memory cache bounds (optimal 2x device pixel ratio for mobile)
    final cacheW = (width != null ? (width! * 2).toInt() : 340).clamp(180, 600);
    final cacheH = (height != null ? (height! * 2).toInt() : 340).clamp(180, 600);

    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF222332), Color(0xFF171824)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFFAFBFE), Color(0xFFEFF2F8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: foregroundFit,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        maxWidthDiskCache: 800,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (c, url) => _buildPlaceholder(c, url),
        errorWidget: (c, e, s) => _buildFallback(isDark),
      ),
    );
  }
}
