import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/shop_model.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/delivery_calculator.dart';

/// A full-width, Swiggy/Zomato-style restaurant card used exclusively
/// when browsing the Food category.
class RestaurantShopCard extends StatefulWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const RestaurantShopCard({
    super.key,
    required this.shop,
    required this.onTap,
  });

  @override
  State<RestaurantShopCard> createState() => _RestaurantShopCardState();
}

class _RestaurantShopCardState extends State<RestaurantShopCard> {
  bool _isPressed = false;

  ShopModel get shop => widget.shop;
  VoidCallback get onTap => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = favs.isShopFavorite(shop.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final deliveryCharge =
        DeliveryCalculator.calculateDeliveryCharges(shop.distanceKm ?? 3.0, 0);
    final isFreeDelivery = deliveryCharge == 0;
    final isOutOfRange = deliveryCharge < 0;

    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? Border.all(color: Colors.white.withValues(alpha: 0.06)) : null,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner image ────────────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: shop.bannerImage != null
                      ? CachedNetworkImage(
                          imageUrl: shop.bannerImage!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _imgPlaceholder(),
                          errorWidget: (_, __, ___) => _imgPlaceholder(),
                        )
                      : _imgPlaceholder(),
                ),
                // Gradient overlay
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Rating badge
                Positioned(
                  bottom: 10,
                  left: 12,
                  child: _ratingBadge(),
                ),
                // Veg-only badge
                if (shop.isVegOnly)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.eco, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text('PURE VEG',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                // Favorite Button
                Positioned(
                  top: 10,
                  right: shop.isVegOnly ? 90 : 10, // Adjust position if Pure Veg badge is present
                  child: GestureDetector(
                    onTap: () {
                      if (auth.currentUserId != null) {
                        favs.toggleShopFavorite(auth.currentUserId!, shop.id);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)
                        ],
                      ),
                      child: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: isFav ? Colors.red : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                // Free delivery tag
                if (isFreeDelivery)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('FREE DELIVERY',
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4)),
                    ),
                  ),
              ],
            ),

            // ── Info section ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          shop.name,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shop.cuisineType ?? 'Multi-cuisine',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0x1A000000)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                       _metaChip(
                        Icons.timer_outlined,
                        '${shop.prepTimeMinutes} min',
                        const Color(0xFF1976D2), // blue 700
                      ),
                      const SizedBox(width: 10),
                      _metaChip(
                        isOutOfRange ? Icons.block_rounded : Icons.delivery_dining_outlined,
                        isOutOfRange
                            ? 'Out of range'
                            : isFreeDelivery
                                ? 'Free delivery'
                                : '₹${deliveryCharge.toStringAsFixed(0)} delivery',
                        isOutOfRange
                            ? const Color(0xFFE53935) // red 600
                            : isFreeDelivery
                                ? const Color(0xFF43A047) // green 600
                                : const Color(0xFFE65100), // orange 900
                      ),
                      const SizedBox(width: 10),
                      _metaChip(
                        Icons.location_on_outlined,
                        shop.distanceKm != null
                            ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                            : 'N/A km',
                        const Color(0xFF757575), // grey 600
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _imgPlaceholder() => Container(
        height: 160,
        width: double.infinity,
        color: const Color(0xFFFFF3EE),
        child: const Center(
          child: Text('🍽️', style: TextStyle(fontSize: 56)),
        ),
      );

  Widget _ratingBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFF48BB78), size: 14),
            const SizedBox(width: 3),
            Text(
              shop.totalOrders > 0 ? shop.rating.toStringAsFixed(1) : 'New',
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            Text(
              shop.totalReviews > 0 ? ' (${shop.totalReviews})' : ' (New)',
              style: GoogleFonts.outfit(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      );

  Widget _metaChip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );
}
