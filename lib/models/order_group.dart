import 'order_model.dart';

class OrderGroup {
  final String
      groupId; // Usually cart_group_id, or order.id if cart_group_id is null
  final List<OrderModel> orders;

  OrderGroup(this.groupId, this.orders);

  /// Active orders in this group (excluding cancelled and rejected sub-orders).
  List<OrderModel> get activeOrders =>
      orders.where((o) => o.status != 'rejected' && o.status != 'cancelled').toList();

  /// Primary order to read shared metadata from (customer info, delivery coordinates).
  OrderModel get primaryOrder =>
      activeOrders.isNotEmpty ? activeOrders.first : orders.first;

  double get totalGrand =>
      (activeOrders.isNotEmpty ? activeOrders : orders).fold(0.0, (sum, o) => sum + o.grandTotal);

  double get totalEarnings =>
      (activeOrders.isNotEmpty ? activeOrders : orders).fold(0.0, (sum, o) => sum + o.riderEarnings);

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
  String? get customerName => primaryOrder.customerId;

  // Delivery coords (assumed identical for all orders in a group)
  double? get deliveryLat => primaryOrder.deliveryLat;
  double? get deliveryLng => primaryOrder.deliveryLng;

  // Has multi-shop?
  bool get isMultiShop => (activeOrders.isNotEmpty ? activeOrders.length : orders.length) > 1;

  // Lowest status representation (e.g. if one is pending, the group is pending)
  // For rider progress: Arrived -> Picked Up -> Out for Delivery -> Delivered
  bool get allArrived {
    final list = activeOrders.isNotEmpty ? activeOrders : orders;
    return list.isNotEmpty && list.every((o) => o.arrivedAtShopTime != null);
  }

  bool get allPickedUp {
    final list = activeOrders.isNotEmpty ? activeOrders : orders;
    return list.isNotEmpty &&
        list.every((o) =>
            o.status == 'picked_up' ||
            o.status == 'out_for_delivery' ||
            o.status == 'delivered');
  }

  bool get allOutForDelivery {
    final list = activeOrders.isNotEmpty ? activeOrders : orders;
    return list.isNotEmpty &&
        list.every((o) => o.status == 'out_for_delivery' || o.status == 'delivered');
  }

  // The dominant group status for UI display.
  // Priority order (highest → lowest):
  //   delivered > out_for_delivery > picked_up > ready_for_pickup >
  //   preparing > confirmed > awaiting_payment > pending > pickup_in_progress
  String get groupStatus {
    final list = activeOrders.isNotEmpty ? activeOrders : orders;
    if (list.isEmpty) return 'cancelled';

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

    // Check terminal rejection if all orders were rejected
    if (list.every((o) => o.status == 'rejected')) return 'rejected';
    if (list.every((o) => o.status == 'cancelled')) return 'cancelled';

    // Otherwise it's in the pickup phase (e.g. arrived at shop but not yet picked up)
    return 'pickup_in_progress';
  }
}
