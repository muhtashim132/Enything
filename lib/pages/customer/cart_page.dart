import 'package:flutter/material.dart';
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

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final location = context.watch<LocationProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF0F0F8),
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
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
              label: Text('Clear',
                  style: GoogleFonts.outfit(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: MaxWidthContainer(
        child: cart.isEmpty
            ? _buildEmptyCart(context, isDark)
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: cart.items.length,
                      itemBuilder: (context, index) {
                        final item = cart.items[index];
                        return _buildCartItem(context, item, cart, isDark);
                      },
                    ),
                  ),
                  _buildSummary(context, cart, location, isDark),
                ],
              ),
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, item, CartProvider cart, bool isDark) {
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
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.07))
              : null,
          boxShadow: PremiumShadows.cardLight,
        ),
        child: Row(
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
              child: item.product.displayImage.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.product.displayImage,
                      fit: BoxFit.cover,
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
                  const SizedBox(height: 6),
                  Text(
                    '₹${item.totalPrice.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Qty controls
            _buildQtyControl(context, cart, item, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyControl(BuildContext context, CartProvider cart, item, bool isDark) {
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qtyBtn(Icons.remove, () {
            cart.updateQuantity(item.product.id, item.quantity - 1, variantName: item.selectedVariant?.name);
          }, isDark),
          AnimatedSwitcher(
            duration: PremiumAnimations.fast,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Padding(
              key: ValueKey(item.quantity),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${item.quantity}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          _qtyBtn(Icons.add, () {
            final err = cart.addItem(item.product, item.shop, selectedVariant: item.selectedVariant);
            if (err != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(err),
                backgroundColor: AppColors.danger,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ));
            }
          }, isDark),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon,
            size: 18,
            color: isDark ? AppColors.primaryLight : AppColors.primary),
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
                  AppColors.primaryLight.withValues(alpha: isDark ? 0.12 : 0.06),
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
            onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.customerHome),
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
                  const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 18),
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

  Widget _buildSummary(BuildContext context, CartProvider cart, LocationProvider location, bool isDark) {
    double distanceKm = 3.0;
    if (location.currentLocation != null && cart.shops.isNotEmpty) {
      distanceKm = 0.0;
      for (var s in cart.shops) {
        final d = location.distanceTo(s.location);
        if (d > distanceKm) distanceKm = d;
      }
    }
    final baseCharge = cart.calculateDeliveryCharges(distanceKm);
    final surcharge = cart.multiShopSurcharge;
    final heavyFee = cart.heavyOrderFee;
    final effectiveBase = baseCharge >= 0 ? baseCharge : 0.0;
    final totalDelivery = cart.totalDeliveryCharges(distanceKm);
    final riderBase = effectiveBase + surcharge + heavyFee;
    final riderEarnings = riderBase * TaxConfig.riderPayoutRatio;

    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      riderEarnings: riderEarnings,
      platformFee: cart.platformFee,
      paymentMethod: 'upi',
    );
    final total = gstBreakdown.grandTotal;
    final canCheckout = cart.meetsMinimumOrder && baseCharge >= 0;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1A1A2E).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.97),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.grey.shade100,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Price breakdown
            _summaryRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(0)}', isDark: isDark),
            const SizedBox(height: 6),
            _summaryRow(
              'Delivery Charges',
              baseCharge < 0
                  ? 'Out of range'
                  : '₹${effectiveBase.toStringAsFixed(0)}',
              valueColor: baseCharge < 0 ? AppColors.textSecondary : null,
              isDark: isDark,
            ),

            if (cart.smallCartFee > 0) ...[
              const SizedBox(height: 6),
              _summaryRow(
                'Small Cart Fee',
                '+₹${cart.smallCartFee.toStringAsFixed(0)}',
                hint: 'For orders under ₹${(PlatformConfigProvider.instance?.smallCartThreshold ?? PaymentConfig.smallCartThreshold).toInt()}',
                valueColor: Colors.orange.shade700,
                isDark: isDark,
              ),
            ],
            if (heavyFee > 0) ...[
              const SizedBox(height: 6),
              _summaryRow(
                'Heavy Order Fee',
                '+₹${heavyFee.toStringAsFixed(0)}',
                hint: 'For orders over ${(PlatformConfigProvider.instance?.heavyOrderThresholdKg ?? PaymentConfig.heavyOrderThreshold).toInt()} kg',
                valueColor: Colors.orange.shade700,
                isDark: isDark,
              ),
            ],
            if (surcharge > 0) ...[
              const SizedBox(height: 6),
              _summaryRow(
                'Multi-shop fee (${cart.shops.length} shops)',
                '+₹${surcharge.toStringAsFixed(0)}',
                valueColor: Colors.orange.shade700,
                hint: '₹${(PlatformConfigProvider.instance?.deliveryRatePerKm ?? 10).toInt()}/km between shops',
                isDark: isDark,
              ),
            ],
            const SizedBox(height: 6),
            _summaryRow(
              'Handling/Platform Fee',
              '+₹${(cart.platformFee - gstBreakdown.platformFeeGst).toStringAsFixed(2)}',
              hint: 'Supports app operations',
              isDark: isDark,
            ),
            if (gstBreakdown.totalGst > 0) ...[
              const SizedBox(height: 6),
              _summaryRow(
                'TOTAL GST',
                '+₹${gstBreakdown.totalGst.toStringAsFixed(2)}',
                hint: 'Govt. taxes on items & services',
                valueColor: const Color(0xFF1565C0), // Consistent with checkout
                isDark: isDark,
              ),
            ],

            Divider(
              height: 20,
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
            ),

            _summaryRow(
              'Total',
              '₹${total.toStringAsFixed(0)}',
              isBold: true,
              valueColor: AppColors.primary,
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // Checkout button
            GestureDetector(
              onTap: canCheckout
                  ? () {
                      final auth = context.read<AuthProvider>();
                      final uniqueShops = cart.items.map((i) => i.shop.id).toSet();
                      if (uniqueShops.length > 1) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2C),
                            title: const Text('Multiple Shops Detected', style: TextStyle(color: Colors.white)),
                            content: const SingleChildScrollView(
                              child: Text('To ensure fast and reliable delivery, you can only order from one shop at a time. Please remove items from other shops to proceed.', style: TextStyle(color: Colors.white70)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK', style: TextStyle(color: Color(0xFFF4C542))),
                              )
                            ],
                          ),
                        );
                        return;
                      }

                      if (auth.currentUserId == null) {
                        Navigator.pushNamed(context, AppRoutes.login);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please login to continue checkout.', style: GoogleFonts.outfit(color: Colors.white)),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      } else {
                        Navigator.pushNamed(context, AppRoutes.checkout);
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: PremiumAnimations.normal,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: canCheckout ? AppColors.ctaGradient : null,
                  color: canCheckout ? null : Colors.grey.shade300,
                  borderRadius: PremiumRadius.mediumBorder,
                  boxShadow: canCheckout ? PremiumShadows.floatingButtonLight : [],
                ),
                child: Center(
                  child: Text(
                    baseCharge < 0
                        ? 'Out of range'
                        : cart.meetsMinimumOrder
                            ? 'Proceed to Checkout • ₹${total.toStringAsFixed(0)}'
                            : 'Minimum order ₹${PaymentConfig.minimumOrderValue.toInt()}',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: canCheckout ? Colors.white : Colors.grey.shade600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, Color? valueColor, String? hint, required bool isDark}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
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
        Text(
          value,
          style: GoogleFonts.outfit(
            color: valueColor ?? (isDark ? Colors.white : AppColors.textPrimary),
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            fontSize: isBold ? 18 : 14,
          ),
        ),
      ],
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
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              cart.clear();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Clear', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
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
