import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../config/payment_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../providers/location_provider.dart';
import '../../utils/responsive_layout.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final location = context.watch<LocationProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Cart'),
            Text(
              '${cart.totalItemCount} items',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          if (!cart.isEmpty)
            TextButton(
              onPressed: () => _showClearDialog(context, cart),
              child: const Text('Clear All',
                  style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      body: MaxWidthContainer(
        child: cart.isEmpty
            ? _buildEmptyCart(context)
            : Column(
                children: [
                  Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return _buildCartItem(context, item, cart);
                    },
                  ),
                ),
                _buildSummary(context, cart, location),
              ],
            ),
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, item, CartProvider cart) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.productDetails,
          arguments: {'productId': item.product.id},
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.product.displayImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.product.displayImage,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorWidget: (c, e, s) => Container(
                      width: 70,
                      height: 70,
                      color: AppColors.primary.withValues(alpha: 0.08),
                      child: const Icon(Icons.shopping_bag_outlined,
                          color: AppColors.primary, size: 30),
                    ),
                  )
                : Container(
                    width: 70,
                    height: 70,
                    color: AppColors.primary.withValues(alpha: 0.08),
                    child: const Icon(Icons.shopping_bag_outlined,
                        color: AppColors.primary, size: 30),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.shop.name,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${item.totalPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    fontSize: 15,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          _buildQtyControl(context, cart, item),
        ],
      ),
     ),
    );
  }

  Widget _buildQtyControl(BuildContext context, CartProvider cart, item) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _qtyBtn(Icons.remove, () {
            cart.updateQuantity(item.product.id, item.quantity - 1);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '${item.quantity}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          _qtyBtn(Icons.add, () {
            final err = cart.addItem(item.product, item.shop);
            if (err != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(err),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.shopping_cart_outlined,
                  size: 60, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add items from nearby shops!',
            style: TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Poppins'),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, AppRoutes.customerHome),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Explore Shops'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, CartProvider cart, LocationProvider location) {
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
    final discount = cart.calculateDeliveryDiscount(distanceKm);
    final effectiveBase = baseCharge >= 0 ? baseCharge : 0.0;
    final totalDelivery =
        effectiveBase + surcharge + heavyFee + cart.smallCartFee - discount;
    final total = cart.subtotal + totalDelivery + cart.platformFee;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          _summaryRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _summaryRow(
            'Delivery Charges',
            baseCharge < 0
                ? 'Out of range'
                : '₹${effectiveBase.toStringAsFixed(0)}',
            valueColor: baseCharge < 0
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'Delivery Discount',
              '-₹${discount.toStringAsFixed(0)}',
              valueColor: AppColors.success,
            ),
          ],
          if (cart.smallCartFee > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'Small Cart Fee',
              '+₹${cart.smallCartFee.toStringAsFixed(0)}',
              hint:
                  'For orders under ₹${(PlatformConfigProvider.instance?.smallCartThreshold ?? PaymentConfig.smallCartThreshold).toInt()}',
              valueColor: Colors.orange.shade700,
            ),
          ],
          if (heavyFee > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'Heavy Order Fee',
              '+₹${heavyFee.toStringAsFixed(0)}',
              hint:
                  'For orders over ${(PlatformConfigProvider.instance?.heavyOrderThresholdKg ?? PaymentConfig.heavyOrderThreshold).toInt()} kg',
              valueColor: Colors.orange.shade700,
            ),
          ],
          // Multi-shop surcharge row — only visible when ordering from 2+ shops
          if (surcharge > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'Multi-shop fee (${cart.shops.length} shops)',
              '+₹${surcharge.toStringAsFixed(0)}',
              valueColor: Colors.orange.shade700,
              hint: '₹7/km between shops',
            ),
          ],
          const SizedBox(height: 6),
          _summaryRow(
            'Handling/Platform Fee',
            '+₹${cart.platformFee.toStringAsFixed(0)}',
            hint: 'Supports app operations',
          ),
          const Divider(height: 20),
          _summaryRow(
            'Total',
            '₹${total.toStringAsFixed(0)}',
            isBold: true,
            valueColor: AppColors.primary,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: (cart.meetsMinimumOrder && baseCharge >= 0)
                  ? () => Navigator.pushNamed(context, AppRoutes.checkout)
                  : null,
              child: baseCharge < 0
                  ? const Text('Out of range',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, height: 1.2))
                  : cart.meetsMinimumOrder
                      ? Text('Proceed to Checkout • ₹${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, height: 1.2))
                      : Text(
                          'Minimum order ₹${PaymentConfig.minimumOrderValue.toInt()}',
                          style: const TextStyle(fontSize: 14, height: 1.2)),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, Color? valueColor, String? hint}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  color:
                      isBold ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                  fontSize: isBold ? 16 : 14,
                  fontFamily: 'Poppins',
                )),
            if (hint != null)
              Text(hint,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontFamily: 'Poppins',
                  )),
          ],
        ),
        Text(value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: isBold ? 18 : 14,
              fontFamily: 'Poppins',
            )),
      ],
    );
  }

  void _showClearDialog(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title:
            const Text('Clear Cart?', style: TextStyle(fontFamily: 'Poppins')),
        content: const Text('Remove all items from your cart?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              cart.clear();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
