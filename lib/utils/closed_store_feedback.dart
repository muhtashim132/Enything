import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_toast.dart';

class ClosedStoreFeedback {
  /// Displays a non-intrusive floating feedback informing the customer
  /// that a shop/restaurant is currently closed and not accepting orders.
  /// Uses top-anchored AppToast (rootOverlay: true) so it is NEVER obscured
  /// by floating bottom navigation bars, floating mini-cart bars, or modal sheets.
  static void showClosedStoreNotice(
    BuildContext context, {
    required String shopName,
    String? openTime,
  }) {
    HapticFeedback.lightImpact();

    final timeMsg = (openTime != null && openTime.trim().isNotEmpty)
        ? ' • Opens at ${openTime.trim()}'
        : '';

    AppToast.show(
      context,
      title: '$shopName is Closed 🔒',
      message: 'Store is currently closed and not accepting orders.$timeMsg',
      type: ToastType.warning,
      icon: Icons.lock_clock_outlined,
      duration: const Duration(seconds: 3),
    );
  }

  /// Displays feedback when a product is unavailable, either because the shop
  /// is closed or because the product itself is out of stock.
  static void showProductUnavailableNotice(
    BuildContext context, {
    required String productName,
    bool isShopClosed = false,
    String? shopName,
    String? openTime,
  }) {
    if (isShopClosed && shopName != null && shopName.isNotEmpty) {
      showClosedStoreNotice(context, shopName: shopName, openTime: openTime);
      return;
    }

    HapticFeedback.lightImpact();

    AppToast.show(
      context,
      title: 'Item Unavailable',
      message: '$productName is currently out of stock.',
      type: ToastType.error,
      icon: Icons.remove_shopping_cart_outlined,
      duration: const Duration(seconds: 3),
    );
  }
}
