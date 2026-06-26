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
import '../theme/premium_effects.dart';
import '../widgets/product_detail_sheet.dart';
import '../utils/share_utils.dart';

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
  late Animation<double> _addScaleAnim;
  late Animation<double> _addFadeAnim;

  ProductModel get product => widget.product;
  ShopModel? get shop => widget.shop;

  @override
  void initState() {
    super.initState();
    _addController = AnimationController(
      vsync: this,
      duration: PremiumAnimations.normal,
    );
    _addScaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _addController, curve: Curves.elasticOut),
    );
    _addFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _addController, curve: Curves.easeOut),
    );
    _addController.forward();
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

    final hasDiscount =
        product.discountPercent != null && product.discountPercent! > 0;
    final isBestseller = product.rating >= 4.2 && product.totalReviews > 10;
    final savedAmount = hasDiscount && product.originalPrice != null
        ? product.originalPrice! - product.price
        : 0.0;

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
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: PremiumRadius.largeBorder,
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                : Border.all(
                    color: _isPressed
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
            boxShadow: PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product Image ────────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Stack(
                  children: [
                    // Image container with gradient background
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(PremiumRadius.large)),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration:
                            PremiumDecorations.imageContainerBg(isDark: isDark),
                        child: product.displayImage.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: product.displayImage,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                                fadeInDuration:
                                    const Duration(milliseconds: 250),
                                placeholder: (c, i) => Shimmer.fromColors(
                                  baseColor: PremiumShimmer.baseColor(isDark),
                                  highlightColor:
                                      PremiumShimmer.highlightColor(isDark),
                                  child: Container(color: Colors.white),
                                ),
                                errorWidget: (c, e, s) => _buildImageError(isDark),
                              )
                            : _buildImageError(isDark),
                      ),
                    ),

                    // Subtle inner shadow at bottom of image
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.05),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Discount badge — top-right
                    if (hasDiscount)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B35), Color(0xFFFF3366)],
                            ),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(PremiumRadius.large),
                              bottomLeft: Radius.circular(10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3366)
                                    .withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
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

                    // Bestseller badge — top-left (with subtle pulse)
                    if (isBestseller)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: PremiumDecorations.gradientBadge(
                            colors: const [Color(0xFFFF9F43), Color(0xFFEE5A24)],
                            borderRadius: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.local_fire_department_rounded,
                                  size: 10, color: Colors.white),
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

                    // Favorite button
                    Positioned(
                      top: isBestseller ? null : 10,
                      bottom: isBestseller ? 10 : null,
                      left: 10,
                      child: GestureDetector(
                        onTap: () {
                          if (auth.currentUserId != null) {
                            favs.toggleProductFavorite(
                                auth.currentUserId!, product.id);
                          }
                        },
                        child: AnimatedContainer(
                          duration: PremiumAnimations.fast,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isFav
                                ? Colors.red.withValues(alpha: 0.15)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.white),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
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
                                  : (isDark
                                      ? Colors.white60
                                      : AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Share button
                    Positioned(
                      bottom: isBestseller ? 10 : null,
                      top: isBestseller ? null : 42,
                      left: 10,
                      child: GestureDetector(
                        onTap: () =>
                            ShareUtils.shareProduct(product, shop: shop),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 6)
                            ],
                          ),
                          child: Icon(
                            Icons.ios_share_rounded,
                            size: 13,
                            color: isDark
                                ? Colors.white60
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),

                    // Veg / Non-veg indicator
                    if (product.isVeg != null && !hasDiscount)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _buildVegBadge(product.isVeg!),
                      ),
                    if (product.isVeg != null && hasDiscount)
                      Positioned(
                        top: 38,
                        right: 10,
                        child: _buildVegBadge(product.isVeg!),
                      ),
                  ],
                ),
              ),

              // ── Info ─────────────────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Product name
                      Text(
                        product.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Shop name
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
                          if (product.totalReviews > 0)
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
                                decorationColor: isDark
                                    ? Colors.white38
                                    : AppColors.textLight,
                              ),
                            ),
                          ],
                        ],
                      ),

                      // "You save" label
                      if (hasDiscount && savedAmount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Save ₹${savedAmount.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // ── Add to cart / stepper ──────────────────────────
                      AnimatedSwitcher(
                        duration: PremiumAnimations.normal,
                        switchInCurve: Curves.elasticOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                                opacity: animation, child: child),
                          );
                        },
                        child: quantity > 0
                            ? _buildStepper(cart, quantity, isDark)
                            : _buildAddButton(cart, isDark),
                      ),
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

  Widget _buildImageError(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF242438), Color(0xFF1A1A2E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 36,
          color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.30),
        ),
      ),
    );
  }

  Widget _buildVegBadge(bool isVeg) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Icon(
        Icons.circle,
        size: 10,
        color: isVeg ? AppColors.vegGreen : AppColors.nonVegRed,
      ),
    );
  }

  Widget _buildAddButton(CartProvider cart, bool isDark) {
    return GestureDetector(
      key: const ValueKey('add'),
      onTap: () {
        if (shop != null) {
          cart.addItem(product, shop!);
        }
      },
      child: Container(
        width: double.infinity,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    AppColors.secondary.withValues(alpha: 0.18),
                    AppColors.secondaryLight.withValues(alpha: 0.14),
                  ]
                : [
                    AppColors.secondary.withValues(alpha: 0.06),
                    AppColors.secondary.withValues(alpha: 0.10),
                  ],
          ),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: AppColors.secondary.withValues(alpha: isDark ? 0.40 : 0.35),
              width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 15,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary),
            const SizedBox(width: 3),
            Text(
              'ADD',
              style: GoogleFonts.outfit(
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(CartProvider cart, int quantity, bool isDark) {
    return Container(
      key: const ValueKey('stepper'),
      height: 36,
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4)),
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
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
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
            onTap: () {
              if (shop != null) {
                context.read<CartProvider>().addItem(product, shop!);
              }
            },
            child:
                const Icon(Icons.add_rounded, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
