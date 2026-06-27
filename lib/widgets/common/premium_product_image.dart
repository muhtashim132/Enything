import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/premium_effects.dart';

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

    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Blurred Background Image (Frosted Glass Effect)
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 250),
            placeholder: (c, url) => _buildPlaceholder(c, url),
            errorWidget: (c, e, s) => _buildFallback(isDark),
          ),
          
          // 2. Heavy Blur Filter & Overlay Tint
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: isDark 
                    ? Colors.black.withValues(alpha: 0.6) 
                    : Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          
          // 3. Foreground Image (Uncropped)
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: foregroundFit,
            fadeInDuration: const Duration(milliseconds: 300),
            errorWidget: (c, e, s) => const SizedBox(), // Fallback already handled by bg
          ),
        ],
      ),
    );
  }
}
