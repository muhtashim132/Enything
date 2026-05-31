import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/shop_model.dart';
import '../theme/app_colors.dart';
import '../utils/delivery_calculator.dart';

/// A full-width, Swiggy/Zomato-style restaurant card used exclusively
/// when browsing the Food category.
class RestaurantShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const RestaurantShopCard({
    super.key,
    required this.shop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deliveryCharge =
        DeliveryCalculator.calculateDeliveryCharges(shop.distanceKm ?? 3.0, 0);
    final isFreeDelivery = deliveryCharge == 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
                          const SizedBox(width: 3),
                          Text('Pure Veg',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ],
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
                            color: AppColors.textPrimary,
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
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _metaChip(
                        Icons.timer_outlined,
                        '${shop.prepTimeMinutes} min',
                        Colors.blue.shade600,
                      ),
                      const SizedBox(width: 10),
                      _metaChip(
                        Icons.delivery_dining_outlined,
                        isFreeDelivery
                            ? 'Free delivery'
                            : '₹${deliveryCharge.toStringAsFixed(0)} delivery',
                        isFreeDelivery
                            ? Colors.green.shade600
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 10),
                      _metaChip(
                        Icons.location_on_outlined,
                        shop.distanceKm != null
                            ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                            : 'N/A km',
                        Colors.grey.shade600,
                      ),
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
              shop.rating.toStringAsFixed(1),
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
