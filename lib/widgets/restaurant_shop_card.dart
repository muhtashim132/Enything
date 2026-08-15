import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  ShopModel get shop => widget.shop;
  VoidCallback get onTap => widget.onTap;

  int? _closingInMinutes() {
    if (!shop.isOpenRightNow || shop.closeTime == null) return null;
    try {
      final now = DateTime.now();
      final closeParts = shop.closeTime!.split(':');
      if (closeParts.length < 2) return null;
      final closeH = int.parse(closeParts[0]);
      final closeM = int.parse(closeParts[1]);
      final nowMinutes = now.hour * 60 + now.minute;
      var closeMinutes = closeH * 60 + closeM;
      if (closeMinutes < nowMinutes) {
        closeMinutes += 24 * 60; // Crosses midnight
      }
      final diff = closeMinutes - nowMinutes;
      if (diff > 0 && diff <= 30) return diff;
    } catch (_) {}
    return null;
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

    // Badges & Status
    final isBestseller = shop.rating >= 4.2 && shop.totalReviews > 20;
    final isPromoted = shop.totalOrders > 100;
    final closingInMins = _closingInMinutes();
    final isOpen = shop.isOpenRightNow;

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
        scale: _isPressed
            ? PremiumAnimations.pressedScale
            : PremiumAnimations.normalScale,
        duration: PremiumAnimations.fast,
        curve: PremiumAnimations.defaultCurve,
        child: AnimatedContainer(
          duration: PremiumAnimations.normal,
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
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Banner Image
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      child: shop.bannerImage != null
                          ? CachedNetworkImage(
                              imageUrl: shop.bannerImage!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              memCacheHeight: 320,
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
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.70),
                            ],
                            stops: const [0.0, 0.40, 1.0],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    // CLOSED Overlay with smart recovery time
                    if (!isOpen)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.70),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white38),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'CLOSED',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                  if (shop.openTime != null &&
                                      shop.openTime!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Opens at ${shop.openTime}',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ── TOP-LEFT: Bestseller / Promoted / Closing Soon ────
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (closingInMins != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53E3E),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE53E3E)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 11, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Closes in ${closingInMins}m',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (isBestseller || isPromoted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4.5),
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
                                borderRadius: BorderRadius.circular(8),
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
                        ],
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
                                  horizontal: 8, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFF2E7D32)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 6),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.eco_rounded,
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
                              HapticFeedback.lightImpact();
                              if (auth.currentUserId != null) {
                                favs.toggleShopFavorite(
                                    auth.currentUserId!, shop.id);
                              }
                            },
                            child: AnimatedContainer(
                              duration: PremiumAnimations.fast,
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isFav
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8)
                                ],
                              ),
                              child: AnimatedSwitcher(
                                duration: PremiumAnimations.fast,
                                child: Icon(
                                  key: ValueKey(isFav),
                                  isFav
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 15,
                                  color: isFav
                                      ? Colors.red
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── BOTTOM-LEFT: Rating badge ─────────────────────────
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: _ratingBadge(),
                    ),

                    // ── BOTTOM-RIGHT: Free Delivery / Promo tag ───────────
                    if (isFreeDelivery)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00C853), Color(0xFF009624)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFF00C853)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6),
                            ],
                          ),
                          child: Text('🚴 FREE DELIVERY',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4)),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Info section ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restaurant Name + Orders count
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shop.name,
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (shop.totalOrders > 50) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${shop.totalOrders}+ orders',
                              style: GoogleFonts.outfit(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Cuisine chips + Cost for two indicator
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: cuisineChips.map((c) {
                                return Container(
                                  margin: const EdgeInsets.only(right: 5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : const Color(0xFFD0D9FF),
                                    ),
                                  ),
                                  child: Text(
                                    c,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF3D52A0),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '₹300 for two',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white54
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Divider
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF0F0F5),
                    ),
                    const SizedBox(height: 10),

                    // Meta chips with Wrap to guarantee zero overflow
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
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
                        _metaChip(
                          Icons.location_on_rounded,
                          shop.distanceKm != null
                              ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                              : 'N/A',
                          const Color(0xFF718096),
                          const Color(0xFFF7FAFC),
                          isDark,
                        ),
                        if (shop.fssaiNumber != null &&
                            shop.fssaiNumber!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_user_rounded,
                                    size: 10,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade700),
                                const SizedBox(width: 2),
                                Text(
                                  'FSSAI',
                                  style: GoogleFonts.outfit(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
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
        height: double.infinity,
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
            const Text('🍽️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 6),
            Text(
              shop.name,
              style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasRating
              ? [const Color(0xFF1E6B40), const Color(0xFF2E9D5E)]
              : [const Color(0xFF2D3748), const Color(0xFF3D4A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.white, size: 12),
          const SizedBox(width: 3),
          Text(
            hasRating ? shop.rating.toStringAsFixed(1) : 'New',
            style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Colors.white),
          ),
          if (hasRating) ...[
            Text(
              ' (${shop.totalReviews})',
              style: GoogleFonts.outfit(
                  fontSize: 10, color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(
      IconData icon, String label, Color color, Color bg, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: isDark ? Colors.white54 : color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : color,
            ),
          ),
        ],
      ),
    );
  }
}
