import 'order_model.dart';

class OrderGroup {
  final String groupId; // Usually cart_group_id, or order.id if cart_group_id is null
  final List<OrderModel> orders;

  OrderGroup(this.groupId, this.orders);

  double get totalGrand => orders.fold(0.0, (sum, o) => sum + o.grandTotalCollected);
  double get totalEarnings => orders.fold(0.0, (sum, o) => sum + o.riderEarnings);
  
  /// Full delivery address shown to the rider.
  /// Format: "🏠 Home · A-404, Bandipora, J&K, Near City Mall"
  /// Falls back to raw address for legacy orders without a label.
  String get customerAddress {
    final order = orders.first;
    final addr = order.address ?? 'Address not set';
    final label = order.addressLabel;
    if (label != null && label.isNotEmpty) {
      return '$label · $addr';
    }
    return addr;
  }
  String? get customerPhone => orders.first.customerPhone;
  String? get customerName => orders.first.customerId; // actually we don't store customer name in order model?

  // Delivery coords (assumed identical for all orders in a group)
  double? get deliveryLat => orders.first.deliveryLat;
  double? get deliveryLng => orders.first.deliveryLng;

  // Has multi-shop?
  bool get isMultiShop => orders.length > 1;

  // Lowest status representation (e.g. if one is pending, the group is pending)
  // For rider progress: Arrived -> Picked Up -> Out for Delivery -> Delivered
  bool get allArrived => orders.every((o) => o.arrivedAtShopTime != null);
  bool get allPickedUp => orders.every((o) => o.status == 'picked_up' || o.status == 'out_for_delivery' || o.status == 'delivered');
  bool get allOutForDelivery => orders.every((o) => o.status == 'out_for_delivery' || o.status == 'delivered');

  // The dominant group status for UI display.
  // Priority order (highest → lowest):
  //   delivered > out_for_delivery > picked_up > ready_for_pickup >
  //   preparing > confirmed > awaiting_payment > pending > pickup_in_progress
  String get groupStatus {
    if (orders.every((o) => o.status == 'delivered')) return 'delivered';
    // BUG-OG1 FIX: allow mixed out_for_delivery + delivered (last shop still delivering)
    if (orders.every((o) => o.status == 'out_for_delivery' || o.status == 'delivered')) return 'out_for_delivery';
    if (allPickedUp) return 'picked_up'; // ready to go out for delivery

    // Check if any is still pending/preparing
    if (orders.any((o) => o.status == 'awaiting_payment')) return 'awaiting_payment';
    if (orders.any((o) => o.status == 'pending')) return 'pending';

    // BUG-OG1 FIX: confirmed and ready_for_pickup were missing — fell through to
    // 'pickup_in_progress' which has no UI handler, showing a blank label on the
    // rider dashboard for multi-shop orders in the confirmed/preparing/ready phases.
    if (orders.any((o) => o.status == 'ready_for_pickup')) return 'ready_for_pickup';
    if (orders.any((o) => o.status == 'preparing')) return 'preparing';
    if (orders.any((o) => o.status == 'confirmed')) return 'confirmed';

    // Otherwise it's in the pickup phase (e.g. arrived at shop but not yet picked up)
    return 'pickup_in_progress';
  }
}
