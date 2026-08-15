import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_colors.dart';
import '../theme/premium_effects.dart';
import '../widgets/product_detail_sheet.dart';
import '../utils/share_utils.dart';
import '../widgets/common/premium_product_image.dart';

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
      duration: PremiumAnimations.normal,
    );
    _addController.forward();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  String _formatWeightUnit() {
    if (product.weightPerUnit != null && product.weightPerUnit! > 0) {
      final weight = product.weightPerUnit!;
      final weightStr =
          weight % 1 == 0 ? weight.toInt().toString() : weight.toString();
      final unit = product.unitType.isNotEmpty ? product.unitType : 'g';
      return '$weightStr $unit';
    } else if (product.unitType.isNotEmpty && product.unitType != 'pieces') {
      return product.unitType;
    }
    return '';
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

    final isShopClosed = shop != null && !shop!.isOpenRightNow;
    final isOutOfStock =
        product.totalQuantity != null && product.totalQuantity! <= 0;
    final isProductUnavailable = !product.isAvailable || isOutOfStock;
    final isLocked = isShopClosed || isProductUnavailable;

    final isLowStock = !isLocked &&
        product.totalQuantity != null &&
        product.totalQuantity! > 0 &&
        product.totalQuantity! <= 5;

    final weightLabel = _formatWeightUnit();
    final hasBrand = product.brand != null && product.brand!.isNotEmpty;

    return GestureDetector(
      onTap:
          isLocked ? null : () => showProductDetailSheet(context, product.id),
      onTapDown: isLocked ? null : (_) => setState(() => _isPressed = true),
      onTapUp: isLocked ? null : (_) => setState(() => _isPressed = false),
      onTapCancel: isLocked ? null : () => setState(() => _isPressed = false),
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
                : Border.all(
                    color: _isPressed
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
            boxShadow:
                PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product Image ────────────────────────────────────────────
              AspectRatio(
                aspectRatio: 1.0,
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
                            ? PremiumProductImage(
                                imageUrl: product.displayImage,
                                isDark: isDark,
                              )
                            : _buildImageError(isDark),
                      ),
                    ),

                    // Subtle inner shadow at bottom of image
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 28,
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
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B35), Color(0xFFFF3366)],
                            ),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(PremiumRadius.large),
                              bottomLeft: Radius.circular(8),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3366)
                                    .withValues(alpha: 0.40),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '${product.discountPercent!.toStringAsFixed(0)}% OFF',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),

                    // Top-Left Badges Stack (Diet / Rx / Bestseller / Low Stock)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Veg / Non-Veg Icon
                              if (product.isVeg != null) ...[
                                _buildDietEmblem(product.isVeg!),
                                const SizedBox(width: 3),
                              ],
                              // Prescription Tag
                              if (product.requiresPrescription) ...[
                                _buildRxBadge(),
                                const SizedBox(width: 3),
                              ],
                              // Bestseller badge
                              if (isBestseller)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2.5),
                                  decoration: PremiumDecorations.gradientBadge(
                                    colors: const [
                                      Color(0xFFFF9F43),
                                      Color(0xFFEE5A24)
                                    ],
                                    borderRadius: 5,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 9,
                                          color: Colors.white),
                                      const SizedBox(width: 2),
                                      Text('BEST',
                                          style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          // Low Stock Alert Badge
                          if (isLowStock) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706),
                                borderRadius: BorderRadius.circular(5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD97706)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt_rounded,
                                      size: 9, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Only ${product.totalQuantity} left',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Favorite button
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (auth.currentUserId != null) {
                            favs.toggleProductFavorite(
                                auth.currentUserId!, product.id);
                          }
                        },
                        child: AnimatedContainer(
                          duration: PremiumAnimations.fast,
                          padding: const EdgeInsets.all(5.5),
                          decoration: BoxDecoration(
                            color: isFav
                                ? Colors.red.withValues(alpha: 0.15)
                                : (isDark
                                    ? Colors.black.withValues(alpha: 0.45)
                                    : Colors.white.withValues(alpha: 0.9)),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 5)
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: PremiumAnimations.fast,
                            child: Icon(
                              key: ValueKey(isFav),
                              isFav
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 13,
                              color: isFav
                                  ? Colors.red
                                  : (isDark
                                      ? Colors.white70
                                      : AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Share button
                    Positioned(
                      bottom: 6,
                      left: 36,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ShareUtils.shareProduct(product, shop: shop);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4.5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 5)
                            ],
                          ),
                          child: Icon(
                            Icons.ios_share_rounded,
                            size: 12,
                            color: isDark ? Colors.white70 : AppColors.primary,
                          ),
                        ),
                      ),
                    ),

                    // Availability / Closed Overlay
                    if (isLocked)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(PremiumRadius.large)),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.65),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: Text(
                                  isShopClosed
                                      ? 'SHOP CLOSED'
                                      : isOutOfStock
                                          ? 'OUT OF STOCK'
                                          : 'UNAVAILABLE',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Info ─────────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Info Stack: Brand/Weight, Name, Rating
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand & Unit/Weight row
                          if (hasBrand || weightLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  if (hasBrand)
                                    Expanded(
                                      child: Text(
                                        product.brand!.toUpperCase(),
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 9,
                                          color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                          letterSpacing: 0.4,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (weightLabel.isNotEmpty) ...[
                                    if (hasBrand) const SizedBox(width: 4),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.08)
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.grey.shade300,
                                            width: 0.7,
                                          ),
                                        ),
                                        child: Text(
                                          weightLabel,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 8.5,
                                            color: isDark
                                                ? Colors.white70
                                                : AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                          // Product name
                          Text(
                            product.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // Rating & Shop Distance row
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: Color(0xFFF6C90E), size: 11),
                                const SizedBox(width: 2),
                                Text(
                                  product.totalReviews > 0
                                      ? product.rating.toStringAsFixed(1)
                                      : 'New',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                if (product.totalReviews > 0)
                                  Text(
                                    product.totalReviews > 99
                                        ? ' (99+)'
                                        : ' (${product.totalReviews})',
                                    style: GoogleFonts.outfit(
                                      fontSize: 9,
                                      color: isDark
                                          ? Colors.white38
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                if (shop != null) ...[
                                  const SizedBox(width: 3),
                                  Container(
                                      width: 2.5,
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white38
                                              : AppColors.textSecondary,
                                          shape: BoxShape.circle)),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      '${context.watch<LocationProvider>().distanceTo(shop!.location).toStringAsFixed(1)}km',
                                      style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white54
                                            : AppColors.textSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Bottom Action Stack: Price, ADD / Stepper Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Price row with 100x responsive formatting
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '₹${product.price.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.primary,
                                    fontSize: 14.5,
                                  ),
                                ),
                                if (hasDiscount) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    '₹${product.originalPrice!.toStringAsFixed(0)}',
                                    style: GoogleFonts.outfit(
                                      color: isDark
                                          ? Colors.white38
                                          : AppColors.textLight,
                                      fontSize: 9.5,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: isDark
                                          ? Colors.white38
                                          : AppColors.textLight,
                                    ),
                                  ),
                                  if (savedAmount > 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3.5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        'Save ₹${savedAmount.toStringAsFixed(0)}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 5),

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
                            child: isLocked
                                ? _buildUnavailableButton(isDark)
                                : product.variants.isNotEmpty
                                    ? _buildVariantAddButton(isDark)
                                    : quantity > 0
                                    ? _buildStepper(cart, quantity, isDark)
                                    : _buildAddButton(cart, isDark),
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
    );
  }

  Widget _buildDietEmblem(bool isVeg) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 5.5,
          height: 5.5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildRxBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
        ),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.30),
            blurRadius: 3,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.medical_services_rounded,
              size: 7.5, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            'Rx',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 7.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
          size: 32,
          color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.30),
        ),
      ),
    );
  }

  Widget _buildVariantAddButton(bool isDark) {
    return GestureDetector(
      key: const ValueKey('variant_add'),
      onTap: () {
        HapticFeedback.lightImpact();
        showProductDetailSheet(context, product.id, highlightVariants: true);
      },
      child: Container(
        width: double.infinity,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    AppColors.secondary.withValues(alpha: 0.22),
                    AppColors.secondaryLight.withValues(alpha: 0.16),
                  ]
                : [
                    AppColors.secondary.withValues(alpha: 0.08),
                    AppColors.secondary.withValues(alpha: 0.12),
                  ],
          ),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color:
                  AppColors.secondary.withValues(alpha: isDark ? 0.50 : 0.45),
              width: 1.1),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ADD',
                style: GoogleFonts.outfit(
                  color:
                      isDark ? AppColors.secondaryLight : AppColors.secondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
              ),
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'OPTIONS',
                  style: GoogleFonts.outfit(
                    color:
                        isDark ? AppColors.secondaryLight : AppColors.secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 7,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(CartProvider cart, bool isDark) {
    return GestureDetector(
      key: const ValueKey('add'),
      onTap: () {
        HapticFeedback.lightImpact();
        if (shop != null) {
          cart.addItemWithFeedback(context, product, shop!);
        }
      },
      child: Container(
        width: double.infinity,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
              color:
                  AppColors.secondary.withValues(alpha: isDark ? 0.40 : 0.35),
              width: 1.1),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded,
                  size: 13,
                  color:
                      isDark ? AppColors.secondaryLight : AppColors.secondary),
              const SizedBox(width: 3),
              Text(
                'ADD',
                style: GoogleFonts.outfit(
                  color:
                      isDark ? AppColors.secondaryLight : AppColors.secondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepper(CartProvider cart, int quantity, bool isDark) {
    return Container(
      key: const ValueKey('stepper'),
      height: 30,
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context
                  .read<CartProvider>()
                  .updateQuantity(product.id, quantity - 1);
            },
            child:
                const Icon(Icons.remove_rounded, size: 14, color: Colors.white),
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
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (product.totalQuantity != null &&
                  quantity >= product.totalQuantity!) {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Only ${product.totalQuantity} items in stock',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              HapticFeedback.lightImpact();
              if (shop != null) {
                context
                    .read<CartProvider>()
                    .addItemWithFeedback(context, product, shop!);
              }
            },
            child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableButton(bool isDark) {
    return Container(
      width: double.infinity,
      height: 30,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Center(
        child: Text(
          'UNAVAILABLE',
          style: GoogleFonts.outfit(
            color: isDark ? Colors.white38 : Colors.grey.shade500,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
