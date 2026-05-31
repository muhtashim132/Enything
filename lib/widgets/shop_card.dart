import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/shop_model.dart';
import '../theme/app_colors.dart';
import '../utils/delivery_calculator.dart';

class ShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const ShopCard({super.key, required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Image with status badge ──────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: shop.bannerImage != null
                      ? CachedNetworkImage(
                          imageUrl: shop.bannerImage!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          placeholder: (c, i) =>
                              Container(color: Colors.grey.shade100),
                          errorWidget: (c, e, s) => _buildImagePlaceholder(),
                        )
                      : _buildImagePlaceholder(),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.accent, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          shop.rating.toStringAsFixed(1),
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (shop.totalReviews > 0) ...[
                          const SizedBox(width: 2),
                          Text(
                            '(${shop.totalReviews})',
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 16),

            // ── Info ────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.name,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shop.cuisineType ?? 'Various items',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildChip(
                        icon: Icons.timer_outlined,
                        label: '${shop.prepTimeMinutes}m',
                        color: Colors.blue.shade50,
                        textColor: Colors.blue.shade700,
                      ),
                      _buildChip(
                        icon: Icons.location_on_outlined,
                        label: shop.distanceKm != null
                            ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                            : 'N/A km',
                        color: Colors.orange.shade50,
                        textColor: Colors.orange.shade700,
                      ),
                      _buildDeliveryChip(shop.distanceKm ?? 0.0),
                    ],
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(
        child: Text('🏪', style: TextStyle(fontSize: 40)),
      ),
    );
  }

  Widget _buildDeliveryChip(double distanceKm) {
    final charge = DeliveryCalculator.calculateDeliveryCharges(distanceKm, 0);
    String label;
    Color bgColor;
    Color textColor;

    if (charge == 0) {
      label = 'Free delivery';
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
    } else if (charge == 25) {
      label = '₹25 delivery';
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade700;
    } else if (charge == 35) {
      label = '₹35 delivery';
      bgColor = Colors.amber.shade50;
      textColor = Colors.amber.shade800;
    } else {
      label = '₹45 delivery';
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
    }

    return _buildChip(
      icon: Icons.delivery_dining_outlined,
      label: label,
      color: bgColor,
      textColor: textColor,
    );
  }

  Widget _buildChip(
      {required IconData icon,
      required String label,
      required Color color,
      required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
