import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/cart_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
import '../../config/routes.dart';
import '../../config/payment_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../providers/location_provider.dart';
import '../../utils/responsive_layout.dart';
import '../../config/tax_config.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_toast.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CartProvider>().syncLiveShopStatuses();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final config = context.watch<PlatformConfigProvider>();
    final location = context.watch<LocationProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    double distanceKm = 3.0;
    if (location.currentLocation != null && cart.shops.isNotEmpty) {
      distanceKm = location.distanceTo(cart.shops.first.location);
    }
    final baseCharge = cart.calculateDeliveryCharges(distanceKm);
    final surcharge = cart.multiShopSurcharge;
    final heavyFee = cart.heavyOrderFee;
    final effectiveBase = baseCharge >= 0 ? baseCharge : 0.0;
    final totalDelivery = cart.totalDeliveryCharges(distanceKm);
    final riderBase = effectiveBase + surcharge + heavyFee;
    final riderPayoutRatio = (config.riderCommissionPercent) / 100.0;
    final riderEarnings = riderBase * riderPayoutRatio;

    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      riderEarnings: riderEarnings,
      platformFee: cart.platformFee,
      paymentMethod: 'upi',
    );
    final total = gstBreakdown.grandTotal;
    final isOverweight =
        cart.effectiveAggregateWeight > PaymentConfig.maxWeightKg;
    final hasClosedShops = cart.hasClosedShops;
    final canCheckout = cart.meetsMinimumOrder &&
        baseCharge >= 0 &&
        !config.isMaintenanceMode &&
        !isOverweight &&
        !hasClosedShops;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFF0F0F8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: isDark ? Colors.white70 : AppColors.textPrimary),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Cart',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              '${cart.totalItemCount} item${cart.totalItemCount == 1 ? '' : 's'}',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          if (!cart.isEmpty)
            TextButton.icon(
              onPressed: () => _showClearDialog(context, cart),
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: AppColors.danger),
              label: Text('Clear',
                  style: GoogleFonts.outfit(
                      color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: MaxWidthContainer(
        child: cart.isEmpty
            ? _buildEmptyCart(context, isDark)
            : RefreshIndicator(
                onRefresh: () => cart.syncLiveShopStatuses(),
                color: AppColors.primary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    if (cart.hasClosedShops) ...[
                      _buildClosedShopsAlertCard(context, cart, isDark),
                      const SizedBox(height: 12),
                    ],
                    ...cart.items.map(
                        (item) => _buildCartItem(context, item, cart, isDark)),
                    const SizedBox(height: 4),
                    _buildWeightCapacityGauge(context, cart, isDark),
                    const SizedBox(height: 12),
                    _buildBillDetailsCard(
                      context,
                      cart: cart,
                      baseCharge: baseCharge,
                      effectiveBase: effectiveBase,
                      surcharge: surcharge,
                      heavyFee: heavyFee,
                      gstBreakdown: gstBreakdown,
                      total: total,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _buildStickyCheckoutBar(
              context,
              cart: cart,
              config: config,
              total: total,
              canCheckout: canCheckout,
              isOverweight: isOverweight,
              baseCharge: baseCharge,
              isMaintenanceMode: config.isMaintenanceMode,
              isDark: isDark,
            ),
    );
  }

  Widget _buildCartItem(
      BuildContext context, item, CartProvider cart, bool isDark) {
    final isShopClosed = !item.shop.isOpenRightNow;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.productDetails,
        arguments: {'productId': item.product.id},
      ),
      child: AnimatedContainer(
        duration: PremiumAnimations.fast,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: PremiumRadius.mediumBorder,
          border: isShopClosed
              ? Border.all(
                  color: isDark
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  width: 1.2,
                )
              : isDark
                  ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                  : null,
          boxShadow: PremiumShadows.cardLight,
        ),
        child: Opacity(
          opacity: isShopClosed ? 0.78 : 1.0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
                clipBehavior: Clip.antiAlias,
                child: (item.selectedVariant?.imageUrl?.isNotEmpty == true ||
                        item.product.displayImage.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl:
                            item.selectedVariant?.imageUrl?.isNotEmpty == true
                                ? item.selectedVariant!.imageUrl!
                                : item.product.displayImage,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: 150,
                        memCacheHeight: 150,
                        errorWidget: (c, e, s) => const _CartImageFallback(),
                      )
                    : const _CartImageFallback(),
              ),
              const SizedBox(width: 12),

              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.selectedVariant != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Variant: ${item.selectedVariant!.name}',
                        style: GoogleFonts.outfit(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      item.shop.name,
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white38 : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isShopClosed) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF451A03)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFFB45309)
                                : const Color(0xFFF59E0B),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.nightlight_round,
                              size: 11,
                              color: isDark
                                  ? const Color(0xFFFDE68A)
                                  : const Color(0xFFB45309),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.shop.openTime != null &&
                                        item.shop.openTime!.isNotEmpty
                                    ? 'Closed · Opens at ${item.shop.openTime}'
                                    : 'Store Currently Closed',
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFFFDE68A)
                                      : const Color(0xFFB45309),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '₹${item.totalPrice.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            fontSize: 16,
                          ),
                        ),
                        _buildQtyControl(context, cart, item, isDark),
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

  Widget _buildQtyControl(
      BuildContext context, CartProvider cart, item, bool isDark) {
    final canInc = cart.canIncrementItem(item);
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.05),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qtyBtn(Icons.remove, () {
            cart.updateQuantity(item.product.id, item.quantity - 1,
                variantName: item.selectedVariant?.name);
          }, isDark),
          AnimatedSwitcher(
            duration: PremiumAnimations.fast,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Padding(
              key: ValueKey(item.quantity),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${item.quantity}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          _qtyBtn(Icons.add, () {
            if (!canInc) {
              HapticFeedback.heavyImpact();
              AppToast.showWarning(
                context,
                title: 'Weight Limit Reached ⛔',
                message:
                    'Two-wheeler delivery cannot exceed ${PaymentConfig.maxWeightKg.toInt()} kg (${cart.remainingWeightCapacityKg.toStringAsFixed(2)} kg remaining).',
              );
              return;
            }
            final err = cart.addItem(item.product, item.shop,
                selectedVariant: item.selectedVariant);
            if (err != null) {
              AppToast.showWarning(
                context,
                title: 'Cart Notice 🛒',
                message: err,
              );
            }
          }, isDark, enabled: canInc),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, bool isDark,
      {bool enabled = true}) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: !enabled
              ? (isDark ? Colors.white24 : Colors.grey.shade400)
              : (isDark ? AppColors.primaryLight : AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  AppColors.primaryLight
                      .withValues(alpha: isDark ? 0.12 : 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: isDark ? AppColors.primaryLight : AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your cart is empty',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items from nearby shops!',
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white38 : AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () =>
                Navigator.pushReplacementNamed(context, AppRoutes.customerHome),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: PremiumRadius.mediumBorder,
                boxShadow: PremiumShadows.floatingButtonLight,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_bag_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Explore Shops',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillDetailsCard(
    BuildContext context, {
    required CartProvider cart,
    required double baseCharge,
    required double effectiveBase,
    required double surcharge,
    required double heavyFee,
    required OrderTaxBreakdown gstBreakdown,
    required double total,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: PremiumRadius.mediumBorder,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.shade200,
        ),
        boxShadow: PremiumShadows.cardLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bill Details',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),

          // Price breakdown
          _summaryRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(0)}',
              isDark: isDark),
          const SizedBox(height: 8),
          _summaryRow(
            'Delivery Charges',
            baseCharge < 0
                ? 'Out of range'
                : '₹${effectiveBase.toStringAsFixed(0)}',
            valueColor: baseCharge < 0 ? AppColors.textSecondary : null,
            isDark: isDark,
          ),

          if (cart.smallCartFee > 0) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Small Cart Fee',
              '+₹${cart.smallCartFee.toStringAsFixed(0)}',
              hint:
                  'For orders under ₹${(PlatformConfigProvider.instance?.smallCartThreshold ?? PaymentConfig.smallCartThreshold).toInt()}',
              valueColor: Colors.orange.shade700,
              isDark: isDark,
            ),
          ],
          if (heavyFee > 0) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Heavy Order Fee',
              '+₹${heavyFee.toStringAsFixed(0)}',
              hint:
                  'For orders over ${(PlatformConfigProvider.instance?.heavyOrderThresholdKg ?? PaymentConfig.heavyOrderThreshold).toInt()} kg',
              valueColor: Colors.orange.shade700,
              isDark: isDark,
            ),
          ],
          if (surcharge > 0) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Multi-shop fee (${cart.shops.length} shops)',
              '+₹${surcharge.toStringAsFixed(0)}',
              valueColor: Colors.orange.shade700,
              hint:
                  '₹${(PlatformConfigProvider.instance?.deliveryRatePerKm ?? 20).toInt()}/km between shops',
              isDark: isDark,
            ),
          ],
          const SizedBox(height: 8),
          _summaryRow(
            'Handling Fee',
            '+₹${cart.platformFee.toStringAsFixed(2)}',
            hint: 'Covers payment gateway & app operations (incl. GST)',
            isDark: isDark,
          ),
          if ((gstBreakdown.itemGstTotal + gstBreakdown.deliveryGst) > 0) ...[
            const SizedBox(height: 8),
            _summaryRow(
              'Taxes & GST',
              '+₹${(gstBreakdown.itemGstTotal + gstBreakdown.deliveryGst).toStringAsFixed(2)}',
              hint: 'Govt. taxes on items & delivery services',
              isDark: isDark,
            ),
          ],

          Divider(
            height: 24,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),

          _summaryRow(
            'Total',
            '₹${total.toStringAsFixed(0)}',
            isBold: true,
            valueColor: AppColors.primary,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceBanner(PlatformConfigProvider config, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF78350F), const Color(0xFF92400E)]
              : [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ordering Temporarily Paused',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config.maintenanceMessage,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFF78350F),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosedShopsAlertCard(
      BuildContext context, CartProvider cart, bool isDark) {
    final areAllClosed = cart.areAllShopsClosed;
    final closedShops = cart.closedShops;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF271B0B) : const Color(0xFFFFFBEB),
        borderRadius: PremiumRadius.mediumBorder,
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.nightlight_round,
                    color: Color(0xFFF59E0B),
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      areAllClosed
                          ? 'Stores Closed for the Night'
                          : 'Store(s) Closed in Multi-Shop Cart',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      areAllClosed
                          ? 'All stores in your cart are currently closed. Your items will remain safely saved in your cart.'
                          : 'Some stores in your cart are closed. Remove items from closed stores to proceed with open stores.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFF78350F),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!areAllClosed) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0x33F59E0B), height: 1),
            const SizedBox(height: 10),
            ...closedShops.map((shop) {
              final count =
                  cart.items.where((i) => i.shop.id == shop.id).length;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.name,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '$count item${count == 1 ? '' : 's'} · ${shop.openTime != null && shop.openTime!.isNotEmpty ? 'Opens at ${shop.openTime}' : 'Currently closed'}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        cart.removeItemsFromShop(shop.id);
                        AppToast.showInfo(
                          context,
                          title: 'Items Removed 🗑️',
                          message:
                              'Removed $count item${count == 1 ? '' : 's'} from ${shop.name}.',
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              size: 14,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Remove',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStickyCheckoutBar(
    BuildContext context, {
    required CartProvider cart,
    required PlatformConfigProvider config,
    required double total,
    required bool canCheckout,
    required bool isOverweight,
    required double baseCharge,
    required bool isMaintenanceMode,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141422) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: GestureDetector(
            onTap: () {
              if (isMaintenanceMode) {
                HapticFeedback.heavyImpact();
                AppToast.showWarning(
                  context,
                  title: 'Platform Maintenance 🛠️',
                  message: config.maintenanceMessage.isNotEmpty
                      ? config.maintenanceMessage
                      : 'Ordering is temporarily paused for system maintenance. Your items remain saved in your cart.',
                );
                return;
              }

              if (cart.areAllShopsClosed) {
                HapticFeedback.heavyImpact();
                AppToast.showWarning(
                  context,
                  title: 'Stores Closed 🌙',
                  message:
                      'All stores in your cart are closed for the night. Your items remain saved.',
                );
                return;
              }

              if (cart.hasClosedShops) {
                HapticFeedback.heavyImpact();
                final closedNames =
                    cart.closedShops.map((s) => s.name).join(', ');
                AppToast.showWarning(
                  context,
                  title: 'Store Closed ⚠️',
                  message:
                      '$closedNames is closed. Remove its items above to proceed with open stores.',
                );
                return;
              }

              if (isOverweight) {
                HapticFeedback.heavyImpact();
                AppToast.showWarning(
                  context,
                  title: 'Weight Limit Exceeded ⚖️',
                  message:
                      'Your cart exceeds ${PaymentConfig.maxWeightKg.toInt()} kg. Please reduce item quantities.',
                );
                return;
              }

              if (baseCharge < 0) {
                HapticFeedback.heavyImpact();
                AppToast.showWarning(
                  context,
                  title: 'Out of Range 📍',
                  message:
                      'One or more shops in your cart are outside the delivery area.',
                );
                return;
              }

              if (!cart.meetsMinimumOrder) {
                HapticFeedback.heavyImpact();
                AppToast.showWarning(
                  context,
                  title: 'Minimum Order Not Met 🛍️',
                  message:
                      'Please add items worth at least ₹${PaymentConfig.minimumOrderValue.toInt()} to checkout.',
                );
                return;
              }

              final auth = context.read<AuthProvider>();
              final uniqueShops = cart.items.map((i) => i.shop.id).toSet();
              if (uniqueShops.length > 3) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2C),
                    title: const Text('Maximum Shops Exceeded',
                        style: TextStyle(color: Colors.white)),
                    content: const SingleChildScrollView(
                      child: Text(
                          'To ensure fast and reliable delivery, you can order from a maximum of 3 shops at a time. Please remove items from other shops to proceed.',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK',
                            style: TextStyle(color: Color(0xFFF4C542))),
                      )
                    ],
                  ),
                );
                return;
              }

              if (auth.currentUserId == null) {
                Navigator.pushNamed(context, AppRoutes.login);
                AppToast.showInfo(
                  context,
                  title: 'Sign In Required 🔐',
                  message:
                      'Please sign in or create an account to proceed with your order.',
                );
              } else {
                Navigator.pushNamed(context, AppRoutes.checkout);
              }
            },
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: AnimatedContainer(
                duration: PremiumAnimations.normal,
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: canCheckout ? AppColors.ctaGradient : null,
                  color: canCheckout
                      ? null
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                  borderRadius: PremiumRadius.mediumBorder,
                  boxShadow:
                      canCheckout ? PremiumShadows.floatingButtonLight : [],
                ),
                child: Center(
                  child: Text(
                    isMaintenanceMode
                        ? 'Platform Maintenance • Ordering Paused'
                        : cart.areAllShopsClosed
                            ? 'Stores Currently Closed'
                            : cart.hasClosedShops
                                ? 'Remove Closed Store Items to Proceed'
                                : isOverweight
                                    ? 'Weight Limit Exceeded (${cart.effectiveAggregateWeight.toStringAsFixed(1)} kg / ${PaymentConfig.maxWeightKg.toInt()} kg)'
                                    : baseCharge < 0
                                        ? 'Out of delivery range'
                                        : cart.meetsMinimumOrder
                                            ? 'Proceed to Checkout • ₹${total.toStringAsFixed(0)}'
                                            : 'Minimum order ₹${PaymentConfig.minimumOrderValue.toInt()}',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: canCheckout
                          ? Colors.white
                          : (isDark ? Colors.white38 : Colors.grey.shade600),
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false,
      Color? valueColor,
      String? hint,
      required bool isDark}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isBold
                      ? (isDark ? Colors.white : AppColors.textPrimary)
                      : (isDark ? Colors.white54 : AppColors.textSecondary),
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                  fontSize: isBold ? 16 : 14,
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white30 : AppColors.textLight,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            color:
                valueColor ?? (isDark ? Colors.white : AppColors.textPrimary),
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            fontSize: isBold ? 18 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildWeightCapacityGauge(
      BuildContext context, CartProvider cart, bool isDark) {
    final weight = cart.effectiveAggregateWeight;
    const maxWeight = PaymentConfig.maxWeightKg;
    final heavyThreshold =
        PlatformConfigProvider.instance?.heavyOrderThresholdKg ??
            PaymentConfig.heavyOrderThreshold;
    final ratio = (weight / maxWeight).clamp(0.0, 1.0);

    final bool isOverweight = weight > maxWeight;
    final bool isHeavy = weight > heavyThreshold && !isOverweight;

    final Color gaugeColor = isOverweight
        ? AppColors.danger
        : isHeavy
            ? Colors.orange.shade700
            : AppColors.success;

    final String statusText = isOverweight
        ? '⛔ Cart exceeds two-wheeler limit (${maxWeight.toInt()} kg)'
        : isHeavy
            ? '⚖️ Heavy order (+₹${cart.heavyOrderFee.toStringAsFixed(0)} fee applies)'
            : '🛵 Standard bike delivery load';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: gaugeColor.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: PremiumRadius.mediumBorder,
        border: Border.all(
          color: gaugeColor.withValues(alpha: isDark ? 0.3 : 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                statusText,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gaugeColor,
                ),
              ),
              Text(
                '${weight.toStringAsFixed(2)} / ${maxWeight.toInt()} kg',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Cart?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: Text('Remove all items from your cart?',
            style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              cart.clear();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Clear',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _CartImageFallback extends StatelessWidget {
  const _CartImageFallback();
  @override
  Widget build(BuildContext context) => const Icon(
        Icons.shopping_bag_outlined,
        color: AppColors.primary,
        size: 30,
      );
}
