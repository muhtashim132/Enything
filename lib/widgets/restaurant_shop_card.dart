import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/shop_model.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/premium_effects.dart';
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

class _RestaurantShopCardState extends State<RestaurantShopCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _shimmerController;

  ShopModel get shop => widget.shop;
  VoidCallback get onTap => widget.onTap;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

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

    // Determine badges
    final isBestseller = shop.rating >= 4.2 && shop.totalReviews > 20;
    final isPromoted = shop.totalOrders > 100;

    // Parse cuisine types into chips
    final cuisineChips = (shop.cuisineType ?? 'Multi-cuisine')
        .split(RegExp(r'[,•·|/]'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .take(3)
        .toList();

    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? PremiumAnimations.pressedScale : PremiumAnimations.normalScale,
        duration: PremiumAnimations.fast,
        curve: PremiumAnimations.defaultCurve,
        child: AnimatedContainer(
          duration: PremiumAnimations.normal,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: PremiumRadius.largeBorder,
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                : null,
            boxShadow:
                PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero banner image ─────────────────────────────────────
              Stack(
                children: [
                  // Banner
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    child: shop.bannerImage != null
                        ? CachedNetworkImage(
                            imageUrl: shop.bannerImage!,
                            height: 185,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _imgPlaceholder(),
                            errorWidget: (_, __, ___) => _imgPlaceholder(),
                          )
                        : _imgPlaceholder(),
                  ),
                  // Gradient overlay — stronger at bottom
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Container(
                      height: 185,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  // ── TOP-LEFT: Bestseller OR Promoted tag ──────────────
                  if (isBestseller || isPromoted)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isBestseller
                                ? [
                                    const Color(0xFFFF9F43),
                                    const Color(0xFFEE5A24)
                                  ]
                                : [
                                    const Color(0xFF6C5CE7),
                                    const Color(0xFFA29BFE)
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: (isBestseller
                                        ? const Color(0xFFEE5A24)
                                        : const Color(0xFF6C5CE7))
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBestseller
                                  ? Icons.local_fire_department_rounded
                                  : Icons.rocket_launch_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isBestseller ? 'BESTSELLER' : 'PROMOTED',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── TOP-RIGHT: Pure Veg + Favorite ───────────────────
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (shop.isVegOnly) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                    color:
                                        Colors.green.withValues(alpha: 0.35),
                                    blurRadius: 8),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.eco,
                                    color: Colors.white, size: 11),
                                const SizedBox(width: 3),
                                Text('PURE VEG',
                                    style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Favorite button
                        GestureDetector(
                          onTap: () {
                            if (auth.currentUserId != null) {
                              favs.toggleShopFavorite(
                                  auth.currentUserId!, shop.id);
                            }
                          },
                          child: AnimatedContainer(
                            duration: PremiumAnimations.fast,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isFav
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 10)
                              ],
                            ),
                            child: AnimatedSwitcher(
                              duration: PremiumAnimations.fast,
                              child: Icon(
                                key: ValueKey(isFav),
                                isFav
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 16,
                                color: isFav ? Colors.red : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── BOTTOM-LEFT: Rating badge (Zomato-style green) ────
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: _ratingBadge(),
                  ),

                  // ── BOTTOM-RIGHT: Free delivery tag ───────────────────
                  if (isFreeDelivery)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C853),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF00C853)
                                    .withValues(alpha: 0.4),
                                blurRadius: 8),
                          ],
                        ),
                        child: Text('🚴 FREE DELIVERY',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4)),
                      ),
                    ),
                ],
              ),

              // ── Info section ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Text(
                      shop.name,
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Cuisine chips row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: cuisineChips.map((c) {
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : const Color(0xFFD0D9FF),
                              ),
                            ),
                            child: Text(
                              c,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF3D52A0),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Divider
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF0F0F5),
                    ),
                    const SizedBox(height: 12),

                    // Meta chips row
                    Row(
                      children: [
                        _metaChip(
                          Icons.access_time_rounded,
                          DeliveryCalculator.etaLabel(
                            shop.distanceKm ?? 3.0,
                            shop.prepTimeMinutes,
                          ),
                          const Color(0xFF4299E1),
                          const Color(0xFFEBF8FF),
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _metaChip(
                          isOutOfRange
                              ? Icons.block_rounded
                              : Icons.delivery_dining_rounded,
                          isOutOfRange
                              ? 'Out of range'
                              : isFreeDelivery
                                  ? 'Free delivery'
                                  : '₹${deliveryCharge.toStringAsFixed(0)} delivery',
                          isOutOfRange
                              ? const Color(0xFFE53E3E)
                              : isFreeDelivery
                                  ? const Color(0xFF38A169)
                                  : const Color(0xFFDD6B20),
                          isOutOfRange
                              ? const Color(0xFFFFF5F5)
                              : isFreeDelivery
                                  ? const Color(0xFFF0FFF4)
                                  : const Color(0xFFFFFAF0),
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _metaChip(
                          Icons.location_on_rounded,
                          shop.distanceKm != null
                              ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                              : 'N/A',
                          const Color(0xFF718096),
                          const Color(0xFFF7FAFC),
                          isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        height: 185,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🍽️', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            Text(
              shop.name,
              style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );

  Widget _ratingBadge() {
    final hasRating = shop.totalReviews > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasRating
              ? [const Color(0xFF1E6B40), const Color(0xFF2E9D5E)]
              : [const Color(0xFF2D3748), const Color(0xFF3D4A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28), blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            hasRating ? shop.rating.toStringAsFixed(1) : 'New',
            style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white),
          ),
          if (hasRating) ...[
            Text(
              ' (${shop.totalReviews})',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(
      IconData icon, String label, Color color, Color bg, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: isDark ? Colors.white54 : color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : color,
            ),
          ),
        ],
      ),
    );
  }
}
