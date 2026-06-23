import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/product_detail_sheet.dart';

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final ShopModel? shop;

  const ProductCard({super.key, required this.product, this.shop});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _addController;

  ProductModel get product => widget.product;
  ShopModel? get shop => widget.shop;

  @override
  void initState() {
    super.initState();
    _addController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isFav = favs.isProductFavorite(product.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasDiscount = product.discountPercent != null &&
        product.discountPercent! > 0;
    final isBestseller = product.rating >= 4.2 && product.totalReviews > 10;

    return GestureDetector(
      onTap: () => showProductDetailSheet(context, product.id),
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                : null,
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.40)
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: _isPressed ? 6 : 18,
                offset: Offset(0, _isPressed ? 2 : 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product Image ──────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    // Image with gradient bg
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: isDark
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF242438),
                                    Color(0xFF1A1A2E)
                                  ],
                                )
                              : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFF8F9FF),
                                    Color(0xFFEEF2FF)
                                  ],
                                ),
                        ),
                        child: product.displayImage.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: product.displayImage,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                fadeInDuration:
                                    const Duration(milliseconds: 250),
                                placeholder: (c, i) => Shimmer.fromColors(
                                  baseColor: isDark
                                      ? const Color(0xFF242438)
                                      : const Color(0xFFEEF2FF),
                                  highlightColor: isDark
                                      ? const Color(0xFF2E2E4A)
                                      : const Color(0xFFF8F9FF),
                                  child: Container(color: Colors.white),
                                ),
                                errorWidget: (c, e, s) => Center(
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 38,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 38,
                                  color:
                                      AppColors.primary.withValues(alpha: 0.4),
                                ),
                              ),
                      ),
                    ),

                    // Discount ribbon — top-right
                    if (hasDiscount)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF6B35),
                                Color(0xFFFF3366)
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(22),
                              bottomLeft: Radius.circular(12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3366)
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '${product.discountPercent!.toStringAsFixed(0)}% OFF',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),

                    // Bestseller badge — top-left
                    if (isBestseller)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF9F43),
                                Color(0xFFEE5A24)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFFEE5A24)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 10,
                                  color: Colors.white),
                              const SizedBox(width: 3),
                              Text('BEST',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),

                    // Favorite button — shown only when not bestseller at top-left
                    Positioned(
                      top: isBestseller ? null : 8,
                      bottom: isBestseller ? 8 : null,
                      left: 8,
                      child: GestureDetector(
                        onTap: () {
                          if (auth.currentUserId != null) {
                            favs.toggleProductFavorite(
                                auth.currentUserId!, product.id);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isFav
                                ? Colors.red.withValues(alpha: 0.12)
                                : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8)
                            ],
                          ),
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 15,
                            color: isFav ? Colors.red : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),

                    // Veg/NonVeg FSSAI-standard indicator — top-right (when no discount)
                    if (product.isVeg != null && !hasDiscount)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ],
                          ),
                          child: Icon(
                            Icons.circle,
                            size: 10,
                            color: product.isVeg!
                                ? AppColors.vegGreen
                                : AppColors.nonVegRed,
                          ),
                        ),
                      ),

                    // Veg/NonVeg when discount badge is present — below it
                    if (product.isVeg != null && hasDiscount)
                      Positioned(
                        top: 38,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ],
                          ),
                          child: Icon(
                            Icons.circle,
                            size: 10,
                            color: product.isVeg!
                                ? AppColors.vegGreen
                                : AppColors.nonVegRed,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Info ────────────────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Name
                      Text(
                        product.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Shop name (if provided)
                      if (shop != null && shop!.name.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          shop!.name,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                            color: isDark
                                ? Colors.white38
                                : AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Rating row
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFF6C90E), size: 13),
                          const SizedBox(width: 2),
                          Text(
                            product.totalReviews > 0
                                ? product.rating.toStringAsFixed(1)
                                : 'New',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (product.totalReviews > 0) ...[
                            Text(
                              ' (${product.totalReviews})',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.white38
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const Spacer(),

                      // Price row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${product.price.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              fontSize: 15,
                            ),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 4),
                            Text(
                              '₹${product.originalPrice!.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                color: isDark
                                    ? Colors.white38
                                    : AppColors.textLight,
                                fontSize: 10,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 8),

                      // ── Add to cart ──────────────────────────────────
                      if (quantity > 0)
                        _buildStepper(cart, quantity)
                      else
                        _buildAddButton(cart),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(CartProvider cart) {
    return GestureDetector(
      onTap: () {
        if (shop != null) {
          cart.addItem(product, shop!);
        }
      },
      child: Container(
        width: double.infinity,
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.primary.withValues(alpha: 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_rounded,
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 3),
            Text(
              'ADD',
              style: GoogleFonts.outfit(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(CartProvider cart, int quantity) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A2A9E), Color(0xFF1E40AF)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () =>
                context.read<CartProvider>().updateQuantity(product.id, quantity - 1),
            child: const Icon(Icons.remove_rounded,
                size: 16, color: Colors.white),
          ),
          Text(
            '$quantity',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          GestureDetector(
            onTap: () {
              if (shop != null) context.read<CartProvider>().addItem(product, shop!);
            },
            child: const Icon(Icons.add_rounded,
                size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
