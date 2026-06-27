import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../theme/app_colors.dart';
import '../theme/premium_effects.dart';
import '../widgets/product_detail_sheet.dart';

class ProductSearchCard extends StatefulWidget {
  final ProductModel product;
  final ShopModel shop;

  const ProductSearchCard(
      {super.key, required this.product, required this.shop});

  @override
  State<ProductSearchCard> createState() => _ProductSearchCardState();
}

class _ProductSearchCardState extends State<ProductSearchCard> {
  bool _isPressed = false;

  ProductModel get product => widget.product;
  ShopModel get shop => widget.shop;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDiscount =
        product.discountPercent != null && product.discountPercent! > 0;

    return GestureDetector(
      onTap: () => showProductDetailSheet(context, product.id),
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? PremiumAnimations.pressedScale : PremiumAnimations.normalScale,
        duration: PremiumAnimations.fast,
        curve: PremiumAnimations.defaultCurve,
        child: AnimatedContainer(
          duration: PremiumAnimations.normal,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: PremiumRadius.largeBorder,
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                : null,
            boxShadow: PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image ────────────────────────────────────────────────
                SizedBox(
                  width: 115,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(22)),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF242438),
                                      Color(0xFF1A1A2E)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFFF8F9FF),
                                      Color(0xFFEEF2FF)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                          ),
                          width: double.infinity,
                          height: double.infinity,
                          child: product.displayImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: product.displayImage,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.contain,
                                  fadeInDuration: const Duration(milliseconds: 200),
                                  placeholder: (c, i) => Shimmer.fromColors(
                                    baseColor: PremiumShimmer.baseColor(isDark),
                                    highlightColor: PremiumShimmer.highlightColor(isDark),
                                    child: Container(color: Colors.white),
                                  ),
                                  errorWidget: (c, e, s) => Center(
                                    child: Icon(
                                      Icons.shopping_bag_outlined,
                                      size: 28,
                                      color: AppColors.primary
                                          .withValues(alpha: isDark ? 0.35 : 0.35),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 28,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                        ),
                      ),
                      // Discount badge
                      if (hasDiscount)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF6B35), Color(0xFFFF3366)],
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(22),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Text(
                              '${product.discountPercent!.toStringAsFixed(0)}% OFF',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),

                    ],
                  ),
                ),

                // ── Info ──────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + Rating
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: Color(0xFFF6C90E), size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  product.totalReviews > 0
                                      ? product.rating.toStringAsFixed(1)
                                      : 'New',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Shop row with avatar
                        Row(
                          children: [
                            if (shop.bannerImage != null &&
                                shop.bannerImage!.isNotEmpty) ...[
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: shop.bannerImage!,
                                    fit: BoxFit.cover,
                                    errorWidget: (c, e, s) => Container(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                          Icons.storefront_rounded,
                                          size: 10,
                                          color: AppColors.primary),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                            ] else ...[
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary
                                      .withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(Icons.storefront_rounded,
                                    size: 10, color: AppColors.primary),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                shop.name,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white54
                                      : AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // Price + ADD button row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Price column
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₹${product.price.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    fontSize: 16,
                                  ),
                                ),
                                if (hasDiscount) ...
                                  [
                                    Text(
                                      '₹${product.originalPrice!.toStringAsFixed(0)}',
                                      style: GoogleFonts.outfit(
                                        color: isDark
                                            ? Colors.white38
                                            : AppColors.textLight,
                                        fontSize: 11,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: isDark
                                            ? Colors.white38
                                            : AppColors.textLight,
                                      ),
                                    ),
                                    Text(
                                      'Save ₹${(product.originalPrice! - product.price).toStringAsFixed(0)}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ],
                              ],
                            ),

                            // ADD / Stepper with AnimatedSwitcher
                            AnimatedSwitcher(
                              duration: PremiumAnimations.normal,
                              switchInCurve: Curves.elasticOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(opacity: animation, child: child),
                                ),
                              child: product.variants.isNotEmpty
                                ? _buildAddButton(context, isDark)
                                : quantity > 0
                                  ? _buildStepper(context, quantity)
                                  : _buildAddButton(context, isDark),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildStepper(BuildContext context, int quantity) {
    return Container(
      key: const ValueKey('stepper'),
      height: 34,
      width: 88,
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => context
                .read<CartProvider>()
                .updateQuantity(product.id, quantity - 1),
            child: const Icon(Icons.remove_rounded,
                size: 16, color: Colors.white),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Text(
              '$quantity',
              key: ValueKey(quantity),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context
                .read<CartProvider>()
                .addItem(product, shop),
            child: const Icon(Icons.add_rounded,
                size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, bool isDark) {
    return GestureDetector(
      key: const ValueKey('add'),
      onTap: () {
        if (product.variants.isNotEmpty) {
          showProductDetailSheet(context, product.id, highlightVariants: true);
        } else {
          context.read<CartProvider>().addItem(product, shop);
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: isDark ? 0.5 : 0.8),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(11),
          gradient: LinearGradient(
            colors: [
              AppColors.secondary.withValues(alpha: isDark ? 0.15 : 0.06),
              AppColors.secondary.withValues(alpha: isDark ? 0.10 : 0.10),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ADD TO CART',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
