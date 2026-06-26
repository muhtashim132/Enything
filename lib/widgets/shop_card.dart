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

class ShopCard extends StatefulWidget {
  final ShopModel shop;
  final VoidCallback onTap;

  const ShopCard({super.key, required this.shop, required this.onTap});

  @override
  State<ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<ShopCard> {
  bool _isPressed = false;

  ShopModel get shop => widget.shop;
  VoidCallback get onTap => widget.onTap;

  // Category-specific accent colors
  static const Map<String, List<Color>> _categoryColors = {
    'Grocery': [Color(0xFF2F9E44), Color(0xFF51CF66)],
    'Supermarket / Hypermarket': [Color(0xFF2F9E44), Color(0xFF51CF66)],
    'Fruits & Vegs': [Color(0xFF2F9E44), Color(0xFF94D82D)],
    'Dairy & Eggs': [Color(0xFF1971C2), Color(0xFF4DABF7)],
    'Butcher': [Color(0xFFC92A2A), Color(0xFFFF6B6B)],
    'Fish & Seafood': [Color(0xFF0C8599), Color(0xFF22B8CF)],
    'Organic': [Color(0xFF2B8A3E), Color(0xFF69DB7C)],
    'Pharmacy': [Color(0xFF1971C2), Color(0xFF339AF0)],
    'Medical Store': [Color(0xFF1971C2), Color(0xFF339AF0)],
    'Clothing': [Color(0xFFAE3EC9), Color(0xFFE599F7)],
    'Footwear': [Color(0xFFD6336C), Color(0xFFF783AC)],
    'Jewellery': [Color(0xFFE67700), Color(0xFFFFD43B)],
    'Electronics': [Color(0xFF7048E8), Color(0xFFB197FC)],
    'Mobile & Repair': [Color(0xFF7048E8), Color(0xFFB197FC)],
    'Hardware Store': [Color(0xFF862E9C), Color(0xFFCC5DE8)],
    'Stationery': [Color(0xFF2F9E44), Color(0xFF8CE99A)],
    'Toys & Games': [Color(0xFFE67700), Color(0xFFFFD43B)],
    'Sports': [Color(0xFF1971C2), Color(0xFF74C0FC)],
    'Cosmetics & Beauty': [Color(0xFFD6336C), Color(0xFFF783AC)],
    'Salon & Beauty': [Color(0xFFAE3EC9), Color(0xFFE599F7)],
    'Flowers': [Color(0xFFD6336C), Color(0xFFF783AC)],
    'Home Decor': [Color(0xFFE67700), Color(0xFFFFD43B)],
    'Pet Supplies': [Color(0xFF2F9E44), Color(0xFF8CE99A)],
  };

  static const Map<String, String> _categoryEmoji = {
    'Grocery': '🛒',
    'Supermarket / Hypermarket': '🏬',
    'Fruits & Vegs': '🥑',
    'Dairy & Eggs': '🥛',
    'Butcher': '🥩',
    'Fish & Seafood': '🐟',
    'Organic': '🌿',
    'Pharmacy': '💊',
    'Medical Store': '💊',
    'Clothing': '👕',
    'Footwear': '👟',
    'Jewellery': '💍',
    'Electronics': '📱',
    'Mobile & Repair': '📱',
    'Hardware Store': '🔧',
    'Stationery': '✏️',
    'Toys & Games': '🧸',
    'Sports': '⚽',
    'Cosmetics & Beauty': '💄',
    'Salon & Beauty': '💅',
    'Flowers': '💐',
    'Home Decor': '🏡',
    'Pet Supplies': '🐾',
    'Auto Parts': '🔩',
    'Other': '🛍️',
  };

  List<Color> get _accentColors =>
      _categoryColors[shop.category] ??
      [const Color(0xFF1E3FD8), const Color(0xFF3D6BFF)];

  String get _emoji => _categoryEmoji[shop.category] ?? '🏪';

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = favs.isShopFavorite(shop.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = _accentColors;

    final deliveryCharge =
        DeliveryCalculator.calculateDeliveryCharges(shop.distanceKm ?? 0.0, 0);
    final isFreeDelivery = deliveryCharge == 0;
    final isOutOfRange = deliveryCharge < 0;

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
            boxShadow: PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header image strip ─────────────────────────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(PremiumRadius.large)),
                    child: shop.bannerImage != null
                        ? CachedNetworkImage(
                            imageUrl: shop.bannerImage!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (c, i) => _headerPlaceholder(colors),
                            errorWidget: (c, e, s) =>
                                _headerPlaceholder(colors),
                          )
                        : _headerPlaceholder(colors),
                  ),

                  // Premium 3-stop gradient overlay
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(PremiumRadius.large)),
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.50),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Category badge (top-left) — glassmorphism style
                  Positioned(
                    top: 10,
                    left: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: colors.first.withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Text(
                          '$_emoji ${shop.category}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                  // Free delivery badge (top-right)
                  if (isFreeDelivery)
                    Positioned(
                      top: 10,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C853),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF00C853)
                                    .withValues(alpha: 0.45),
                                blurRadius: 8),
                          ],
                        ),
                        child: Text(
                          'FREE DELIVERY',
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3),
                        ),
                      ),
                    ),

                  // Rating badge (bottom-left)
                  Positioned(
                    bottom: 10,
                    left: 12,
                    child: _ratingBadge(),
                  ),

                  // Favorite button (bottom-right)
                  Positioned(
                    bottom: 10,
                    right: 12,
                    child: GestureDetector(
                      onTap: () {
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
                                color: Colors.black.withValues(alpha: 0.18),
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
                            size: 14,
                            color: isFav ? Colors.red : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Info section ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + arrow
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shop.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: isDark
                              ? Colors.white24
                              : Colors.grey.shade400,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Cuisine / item type
                    Text(
                      shop.cuisineType ?? 'Various items',
                      style: GoogleFonts.outfit(
                        color: isDark
                            ? Colors.white54
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 11),

                    // Chips row
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildChip(
                          icon: Icons.access_time_rounded,
                          label: DeliveryCalculator.etaLabel(
                              shop.distanceKm ?? 3.0, shop.prepTimeMinutes),
                          color: const Color(0xFFEBF8FF),
                          textColor: const Color(0xFF2B6CB0),
                          isDark: isDark,
                        ),
                        _buildChip(
                          icon: Icons.location_on_rounded,
                          label: shop.distanceKm != null
                              ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                              : 'N/A',
                          color: const Color(0xFFFFFAF0),
                          textColor: const Color(0xFFDD6B20),
                          isDark: isDark,
                        ),
                        _buildDeliveryChip(shop.distanceKm ?? 0.0,
                            isOutOfRange, isFreeDelivery, deliveryCharge,
                            isDark: isDark),
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

  Widget _headerPlaceholder(List<Color> colors) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _emoji,
          style: const TextStyle(fontSize: 46),
        ),
      ),
    );
  }

  Widget _ratingBadge() {
    final hasRating = shop.totalReviews > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasRating
              ? [const Color(0xFF1E6B40), const Color(0xFF2E9D5E)]
              : [const Color(0xFF2D3748), const Color(0xFF3D4A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25), blurRadius: 8),
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
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white),
          ),
          if (hasRating)
            Text(
              ' (${shop.totalReviews})',
              style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.75)),
            ),
        ],
      ),
    );
  }

  Widget _buildDeliveryChip(
      double distanceKm, bool isOutOfRange, bool isFreeDelivery, double charge,
      {required bool isDark}) {
    if (isOutOfRange) {
      return _buildChip(
        icon: Icons.block_rounded,
        label: 'Out of range',
        color: const Color(0xFFFFF5F5),
        textColor: const Color(0xFFE53E3E),
        isDark: isDark,
      );
    }
    if (isFreeDelivery) {
      return _buildChip(
        icon: Icons.delivery_dining_rounded,
        label: 'Free delivery',
        color: const Color(0xFFF0FFF4),
        textColor: const Color(0xFF38A169),
        isDark: isDark,
      );
    }
    return _buildChip(
      icon: Icons.delivery_dining_rounded,
      label: '₹${charge.toStringAsFixed(0)} delivery',
      color: const Color(0xFFEBF8FF),
      textColor: const Color(0xFF2B6CB0),
      isDark: isDark,
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12, color: isDark ? Colors.white54 : textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : textColor,
            ),
          ),
        ],
      ),
    );
  }
}
