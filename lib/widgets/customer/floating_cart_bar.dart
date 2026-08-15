import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/currency_utils.dart';
import '../../utils/haptic_utils.dart';

/// 100x Modern Quick-Commerce Floating Mini-Cart Bar (Blinkit / Zepto Style)
///
/// Automatically floats above the bottom navigation bar when items are in cart.
class FloatingCartBar extends StatelessWidget {
  final double bottomOffset;
  final VoidCallback? onCustomTap;

  const FloatingCartBar({
    super.key,
    this.bottomOffset = 16,
    this.onCustomTap,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (cart.totalItemCount == 0) {
      return const SizedBox.shrink();
    }

    final totalItems = cart.totalItemCount;
    final subtotal = cart.subtotal;
    final itemThumbnails = cart.items
        .map((i) => i.product.displayImage)
        .where((img) => img.isNotEmpty)
        .take(3)
        .toList();

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomOffset,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, (1.0 - value) * 40),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onTap: () {
            HapticUtils.selection();
            if (onCustomTap != null) {
              onCustomTap!();
            } else {
              Navigator.pushNamed(context, AppRoutes.cart);
            }
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E3A8A), const Color(0xFF2563EB)]
                    : [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF2563EB) : AppColors.primary)
                      .withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Thumbnails preview stack or Cart icon
                if (itemThumbnails.isNotEmpty)
                  SizedBox(
                    width: 20.0 + (itemThumbnails.length - 1) * 14.0,
                    height: 28,
                    child: Stack(
                      children: [
                        for (int i = 0; i < itemThumbnails.length; i++)
                          Positioned(
                            left: i * 14.0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                image: DecorationImage(
                                  image: NetworkImage(itemThumbnails[i]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),

                const SizedBox(width: 12),

                // Item count & subtotal
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalItems ${totalItems == 1 ? 'ITEM' : 'ITEMS'} ADDED',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        CurrencyUtils.format(subtotal),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // View Cart CTA
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Cart',
                        style: GoogleFonts.outfit(
                          color: isDark ? const Color(0xFF1E3A8A) : AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: isDark ? const Color(0xFF1E3A8A) : AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
