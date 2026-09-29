import 'order_model.dart';

class OrderGroup {
  final String
      groupId; // Usually cart_group_id, or order.id if cart_group_id is null
  final List<OrderModel> orders;

  OrderGroup(this.groupId, this.orders);

  static const Set<String> _terminalRejectionStatuses = {
    'seller_rejected',
    'partner_rejected',
    'cancelled',
    'rejected',
    'shop_dispute_cancel',
    'timeout',
    'failed',
    'returned',
    'refunded',
    'verification_failed',
    'no_rider',
    'payment_failed',
  };

  /// Active orders in this group (excluding cancelled and rejected sub-orders).
  List<OrderModel> get activeOrders => orders
      .where((o) => !_terminalRejectionStatuses.contains(o.status))
      .toList();

  /// Primary order to read shared metadata from (customer info, delivery coordinates).
  OrderModel get primaryOrder =>
      activeOrders.isNotEmpty ? activeOrders.first : orders.first;

  double get totalGrand => (activeOrders.isNotEmpty ? activeOrders : orders)
      .fold(0.0, (sum, o) => sum + o.grandTotal);

  double get totalEarnings => (activeOrders.isNotEmpty ? activeOrders : orders)
      .fold(0.0, (sum, o) => sum + o.riderEarnings);

  /// Enything operates strictly on a 100% prepaid model (online payment only).
  /// Cash on Delivery (COD) is not available in this model.
  bool get isCod => false;

  /// True for all orders since Enything is 100% prepaid online.
  bool get isPrepaid => true;

  /// Since COD is not available in Enything, doorstep collection is always 0.0.
  double get codAmountToCollect => 0.0;

  /// Total items across all active orders in this group.
  int get totalItemCount => activeOrders
      .fold<int>(0, (sum, o) => sum + o.items.fold<int>(0, (s, i) => s + i.quantity));

  /// Full delivery address shown to the rider.
  /// Format: "🏠 Home · A-404, Bandipora, J&K, Near City Mall"
  /// Falls back to raw address for legacy orders without a label.
  String get customerAddress {
    final order = primaryOrder;
    final addr = order.address ?? 'Address not set';
    final label = order.addressLabel;
    if (label != null && label.isNotEmpty) {
      return '$label · $addr';
    }
    return addr;
  }

  String? get customerPhone => primaryOrder.customerPhone;
  /// Customer name is not stored on the order model — returns null.
  /// The rider dashboard should resolve names from profiles if needed.
  String? get customerName => null;

  // Delivery coords (assumed identical for all orders in a group)
  double? get deliveryLat => primaryOrder.deliveryLat;
  double? get deliveryLng => primaryOrder.deliveryLng;

  // Has multi-shop?
  bool get isMultiShop {
    final list = activeOrders.isNotEmpty ? activeOrders : orders;
    return list.map((o) => o.shopId).where((id) => id != null && id.isNotEmpty).toSet().length > 1;
  }

  // Lowest status representation (e.g. if one is pending, the group is pending)
  // For rider progress: Arrived -> Picked Up -> Out for Delivery -> Delivered
  bool get allArrived {
    // 100x FIX (Edge Case 7): If all sub-orders are terminal, return false.
    // Never fall back to dead `orders` list for progress checks.
    final list = activeOrders;
    if (list.isEmpty) return false;
    return list.every((o) => o.arrivedAtShopTime != null);
  }

  bool get allPickedUp {
    // 100x FIX (Edge Case 7): If all sub-orders are terminal, return false.
    final list = activeOrders;
    if (list.isEmpty) return false;
    return list.every((o) =>
        o.status == 'picked_up' ||
        o.status == 'out_for_delivery' ||
        o.status == 'delivered');
  }

  bool get allOutForDelivery {
    // 100x FIX (Edge Case 7): If all sub-orders are terminal, return false.
    final list = activeOrders;
    if (list.isEmpty) return false;
    return list.every(
        (o) => o.status == 'out_for_delivery' || o.status == 'delivered');
  }

  // The dominant group status for UI display.
  // Priority order (highest → lowest):
  //   delivered > out_for_delivery > picked_up > ready_for_pickup >
  //   preparing > confirmed > awaiting_payment > pending > pickup_in_progress
  String get groupStatus {
    if (orders.isEmpty) return 'cancelled';
    if (activeOrders.isEmpty) {
      if (orders.every((o) => o.status == 'shop_dispute_cancel')) {
        return 'shop_dispute_cancel';
      }
      if (orders.every((o) =>
          o.status == 'rejected' ||
          o.status == 'seller_rejected' ||
          o.status == 'partner_rejected')) {
        return 'rejected';
      }
      return 'cancelled';
    }

    final list = activeOrders;

    if (list.every((o) => o.status == 'delivered')) return 'delivered';
    // BUG-OG1 FIX: allow mixed out_for_delivery + delivered (last shop still delivering)
    if (list.every(
        (o) => o.status == 'out_for_delivery' || o.status == 'delivered')) {
      return 'out_for_delivery';
    }
    if (allPickedUp) return 'picked_up'; // ready to go out for delivery

    // Check if any is still pending/preparing
    if (list.any((o) => o.status == 'awaiting_payment')) {
      return 'awaiting_payment';
    }
    if (list.any((o) => o.status == 'pending')) return 'pending';

    // BUG-OG1 FIX: confirmed and ready_for_pickup were missing — fell through to
    // 'pickup_in_progress' which has no UI handler, showing a blank label on the
    // rider dashboard for multi-shop orders in the confirmed/preparing/ready phases.
    if (list.any((o) => o.status == 'ready_for_pickup')) {
      return 'ready_for_pickup';
    }
    if (list.any((o) => o.status == 'preparing')) return 'preparing';
    if (list.any((o) => o.status == 'confirmed')) return 'confirmed';

    // 100x FIX: Handle payment_failed status to prevent falling through
    // to 'pickup_in_progress' which has no UI handler.
    if (list.any((o) => o.status == 'payment_failed')) return 'payment_failed';

    // Otherwise it's in the pickup phase (e.g. arrived at shop but not yet picked up)
    return 'pickup_in_progress';
  }
}
