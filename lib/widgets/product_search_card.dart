import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../theme/app_colors.dart';
import '../theme/premium_effects.dart';
import '../widgets/product_detail_sheet.dart';
import 'common/premium_product_image.dart';
import '../utils/closed_store_feedback.dart';
import '../config/app_categories.dart';

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
    final totalQuantity = cart.getProductTotalQuantity(product.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDiscount =
        product.discountPercent != null && product.discountPercent! > 0;

    final isShopClosed = !shop.isOpenRightNow;
    final isOutOfStock =
        product.totalQuantity != null && product.totalQuantity! <= 0;
    final isProductUnavailable = !product.isAvailable || isOutOfStock;
    final isLocked = isShopClosed || isProductUnavailable;

    final isLowStock = !isLocked &&
        product.totalQuantity != null &&
        product.totalQuantity! > 0 &&
        product.totalQuantity! <= 5;

    final weightLabel = _formatWeightUnit();

    return GestureDetector(
      onTap: isShopClosed
          ? () => ClosedStoreFeedback.showClosedStoreNotice(
                context,
                shopName: shop.name,
                openTime: shop.openTime,
              )
          : (isProductUnavailable
              ? () => ClosedStoreFeedback.showProductUnavailableNotice(
                    context,
                    productName: product.name,
                  )
              : () => showProductDetailSheet(context, product.id)),
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
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: PremiumRadius.largeBorder,
            border: totalQuantity > 0
                ? Border.all(
                    color: AppColors.secondary
                        .withValues(alpha: isDark ? 0.45 : 0.40),
                    width: 1.2,
                  )
                : isDark
                    ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                    : null,
            boxShadow:
                PremiumShadows.card(isDark: isDark, isPressed: _isPressed),
          ),
          child: SizedBox(
            height: 144,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image ────────────────────────────────────────────────
                AspectRatio(
                  aspectRatio: 1.0,
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
                              ? PremiumProductImage(
                                  imageUrl: product.displayImage,
                                  isDark: isDark,
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

                      // Top-Left Badges Stack (Discount / Diet / Rx)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasDiscount)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 4),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFFF6B35),
                                      Color(0xFFFF3366)
                                    ],
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
                          ],
                        ),
                      ),

                      // Dietary & Rx Markers top-right
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (product.showsDietEmblem)
                              _buildDietEmblem(product.isVeg!),
                            if (product.requiresPrescription) ...[
                              const SizedBox(width: 3),
                              _buildRxBadge(),
                            ],
                          ],
                        ),
                      ),

                      // Low Stock Badge bottom-left
                      if (isLowStock)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFD97706)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              'Only ${product.totalQuantity} left',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),

                      // Availability / Closed Overlay
                      if (isLocked)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(22)),
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
                                        ? 'CLOSED'
                                        : isOutOfStock
                                            ? 'OUT OF STOCK'
                                            : 'UNAVAILABLE',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 9.5,
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

                // ── Info ──────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand & Unit/Weight row
                        if ((product.brand != null &&
                                product.brand!.isNotEmpty) ||
                            weightLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                if (product.brand != null &&
                                    product.brand!.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      product.brand!.toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9.5,
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
                                  if (product.brand != null &&
                                      product.brand!.isNotEmpty)
                                    const SizedBox(width: 4),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.08)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white12
                                              : Colors.grey.shade300,
                                          width: 0.8,
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

                        // Name + Rating
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Salt / Composition for medicines
                        if ((product.category == 'Pharmacy' ||
                                AppCategories.isPharmacyCategory(product.category)) &&
                            product.description != null &&
                            product.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.science_outlined,
                                size: 10,
                                color: isDark
                                    ? const Color(0xFF6EE7B7)
                                    : const Color(0xFF059669),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  product.description!.trim(),
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 9.5,
                                    color: isDark
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFF059669),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 3),

                        // Shop row with avatar
                        Row(
                          children: [
                            if (shop.bannerImage != null &&
                                shop.bannerImage!.isNotEmpty) ...[
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    width: 1.2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: shop.bannerImage!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 64,
                                    memCacheHeight: 64,
                                    errorWidget: (c, e, s) => Container(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                          Icons.storefront_rounded,
                                          size: 9,
                                          color: AppColors.primary),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ] else ...[
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    width: 1.2,
                                  ),
                                ),
                                child: const Icon(Icons.storefront_rounded,
                                    size: 9, color: AppColors.primary),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                shop.name,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
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
                            // Price column with zero overflow FittedBox
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '₹${product.price.toStringAsFixed(0)}',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w900,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.primary,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (hasDiscount) ...[
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '₹${product.originalPrice!.toStringAsFixed(0)}',
                                            style: GoogleFonts.outfit(
                                              color: isDark
                                                  ? Colors.white38
                                                  : AppColors.textLight,
                                              fontSize: 10,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                              decorationColor: isDark
                                                  ? Colors.white38
                                                  : AppColors.textLight,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Save ₹${(product.originalPrice! - product.price).toStringAsFixed(0)}',
                                            style: GoogleFonts.outfit(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // ADD / Stepper with AnimatedSwitcher
                            AnimatedSwitcher(
                              duration: PremiumAnimations.normal,
                              switchInCurve: Curves.elasticOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                    opacity: animation, child: child),
                              ),
                              child: isLocked
                                  ? _buildUnavailableButton(context, isDark,
                                      isShopClosed: isShopClosed)
                                  : product.variants.isNotEmpty
                                      ? (totalQuantity > 0
                                          ? _buildVariantStepper(
                                              context, totalQuantity, isDark)
                                          : _buildVariantAddButton(
                                              context, isDark))
                                      : totalQuantity > 0
                                          ? _buildStepper(
                                              context, totalQuantity)
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

  Widget _buildDietEmblem(bool isVeg) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
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
            color: const Color(0xFF0284C7).withValues(alpha: 0.35),
            blurRadius: 3,
          ),
        ],
      ),
      child: Text(
        'Rx',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildVariantAddButton(BuildContext context, bool isDark) {
    return GestureDetector(
      key: const ValueKey('variant_add'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        showProductDetailSheet(context, product.id, highlightVariants: true);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: isDark ? 0.5 : 0.8),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              AppColors.secondary.withValues(alpha: isDark ? 0.18 : 0.08),
              AppColors.secondary.withValues(alpha: isDark ? 0.12 : 0.12),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'ADD',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
                letterSpacing: 0.3,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 3),
            Transform.translate(
              offset: const Offset(0, 0.5),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantStepper(
      BuildContext context, int totalQuantity, bool isDark) {
    final cart = context.read<CartProvider>();
    final productItems = cart.getItemsForProduct(product.id);
    final hasSingleVariant = productItems.length == 1;
    final singleItem = hasSingleVariant ? productItems.first : null;

    return Container(
      key: const ValueKey('variant_stepper'),
      height: 32,
      constraints: const BoxConstraints(minWidth: 84),
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left touch zone: Decrement or open sheet
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (hasSingleVariant && singleItem != null) {
                  cart.updateQuantity(
                    product.id,
                    singleItem.quantity - 1,
                    variantName: singleItem.selectedVariant?.name,
                  );
                } else {
                  showProductDetailSheet(context, product.id,
                      highlightVariants: true);
                }
              },
              child: Container(
                width: 28,
                height: double.infinity,
                alignment: Alignment.center,
                child: const Icon(Icons.remove_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
            // Center info area
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                showProductDetailSheet(context, product.id,
                    highlightVariants: true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$totalQuantity',
                        key: ValueKey(totalQuantity),
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2.5, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'OPT',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 6.5,
                          letterSpacing: 0.3,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Right touch zone: Increment or open sheet
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (product.totalQuantity != null &&
                    totalQuantity >= product.totalQuantity!) {
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
                if (hasSingleVariant && singleItem != null) {
                  cart.addItemWithFeedback(
                    context,
                    product,
                    shop,
                    selectedVariant: singleItem.selectedVariant,
                  );
                } else {
                  showProductDetailSheet(context, product.id,
                      highlightVariants: true);
                }
              },
              child: Container(
                width: 28,
                height: double.infinity,
                alignment: Alignment.center,
                child: const Icon(Icons.add_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(BuildContext context, int quantity) {
    return Container(
      key: const ValueKey('stepper'),
      height: 32,
      width: 88,
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            // Left touch zone: Decrement / Remove
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  context
                      .read<CartProvider>()
                      .updateQuantity(product.id, quantity - 1);
                },
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(left: 2),
                  child: const Icon(Icons.remove_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ),
            // Center quantity
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Text(
                  '$quantity',
                  key: ValueKey(quantity),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            // Right touch zone: Increment / Add
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
                  context
                      .read<CartProvider>()
                      .addItemWithFeedback(context, product, shop);
                },
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(right: 2),
                  child: const Icon(Icons.add_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, bool isDark) {
    return GestureDetector(
      key: const ValueKey('add'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        context
            .read<CartProvider>()
            .addItemWithFeedback(context, product, shop);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: isDark ? 0.5 : 0.8),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              AppColors.secondary.withValues(alpha: isDark ? 0.15 : 0.06),
              AppColors.secondary.withValues(alpha: isDark ? 0.10 : 0.10),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, 0.6),
              child: Icon(
                Icons.add_rounded,
                size: 13,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
              ),
            ),
            const SizedBox(width: 3.5),
            Text(
              'ADD',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                color: isDark ? AppColors.secondaryLight : AppColors.secondary,
                letterSpacing: 0.4,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableButton(BuildContext context, bool isDark,
      {bool isShopClosed = false}) {
    final label = isShopClosed ? 'STORE CLOSED' : 'UNAVAILABLE';
    return GestureDetector(
      onTap: () {
        if (isShopClosed) {
          ClosedStoreFeedback.showClosedStoreNotice(
            context,
            shopName: shop.name,
            openTime: shop.openTime,
          );
        } else {
          ClosedStoreFeedback.showProductUnavailableNotice(
            context,
            productName: product.name,
          );
        }
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isShopClosed
              ? (isDark ? const Color(0xFF2D2418) : const Color(0xFFFFFBEB))
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          border: isShopClosed
              ? Border.all(
                  color: isDark
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                      : const Color(0xFFFDE68A),
                  width: 0.8,
                )
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isShopClosed) ...[
              Icon(
                Icons.lock_clock_outlined,
                size: 11,
                color:
                    isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 10,
                color: isShopClosed
                    ? (isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706))
                    : (isDark ? Colors.white38 : Colors.grey.shade500),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
