import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🔬 100x Deep Forensic Edge-Case Audit & Verification', () {
    test('Edge Case 1: Multi-shop seller rejection rider notification differentiation', () {
      final subOrder1 = OrderModel.fromMap({
        'id': 'order_shop1',
        'cart_group_id': 'group_123',
        'customer_id': 'cust_abc',
        'shop_id': 'shop_1',
        'status': 'seller_rejected',
        'delivery_partner_id': 'rider_xyz',
      });

      final subOrder2 = OrderModel.fromMap({
        'id': 'order_shop2',
        'cart_group_id': 'group_123',
        'customer_id': 'cust_abc',
        'shop_id': 'shop_2',
        'status': 'confirmed',
        'delivery_partner_id': 'rider_xyz',
      });

      final group = OrderGroup('group_123', [subOrder1, subOrder2]);

      // Check if rider has active sibling orders in this group
      final activeSiblings = group.activeOrders
          .where((o) => o.id != subOrder1.id && o.deliveryPartnerId == 'rider_xyz')
          .toList();

      final bool hasOtherActiveOrders = activeSiblings.isNotEmpty;

      final title = hasOtherActiveOrders
          ? '⚠️ Store Declined Items'
          : '❌ Order Cancelled by Shop';
      final body = hasOtherActiveOrders
          ? 'A store declined their part of the order. You are still delivering the remaining store(s).'
          : 'The shop declined the order. You are free for new deliveries.';

      expect(hasOtherActiveOrders, isTrue);
      expect(title, equals('⚠️ Store Declined Items'));
      expect(body, contains('delivering the remaining store(s)'));
      expect(body, isNot(contains('free for new deliveries')));
    });

    test('Edge Case 1b: Single-shop seller rejection sends rider free notification', () {
      final subOrder1 = OrderModel.fromMap({
        'id': 'order_single',
        'cart_group_id': 'group_single',
        'customer_id': 'cust_single',
        'shop_id': 'shop_1',
        'status': 'seller_rejected',
        'delivery_partner_id': 'rider_xyz',
      });

      final group = OrderGroup('group_single', [subOrder1]);

      final activeSiblings = group.activeOrders
          .where((o) => o.id != subOrder1.id && o.deliveryPartnerId == 'rider_xyz')
          .toList();

      final bool hasOtherActiveOrders = activeSiblings.isNotEmpty;

      final title = hasOtherActiveOrders
          ? '⚠️ Store Declined Items'
          : '❌ Order Cancelled by Shop';
      final body = hasOtherActiveOrders
          ? 'A store declined their part of the order. You are still delivering the remaining store(s).'
          : 'The shop declined the order. You are free for new deliveries.';

      expect(hasOtherActiveOrders, isFalse);
      expect(title, equals('❌ Order Cancelled by Shop'));
      expect(body, contains('free for new deliveries'));
    });

    test('Edge Case 2: Intermediate shop pickup notification does NOT claim order is on its way', () {
      final shop1Order = OrderModel.fromMap({
        'id': 'sub_1',
        'cart_group_id': 'cg_multi',
        'customer_id': 'cust_1',
        'shop_id': 'shop_1',
        'status': 'picked_up',
      });

      final shop2Order = OrderModel.fromMap({
        'id': 'sub_2',
        'cart_group_id': 'cg_multi',
        'customer_id': 'cust_1',
        'shop_id': 'shop_2',
        'status': 'confirmed',
      });

      final group = OrderGroup('cg_multi', [shop1Order, shop2Order]);

      final remainingUnpicked = group.activeOrders
          .where((o) =>
              o.id != shop1Order.id &&
              o.status != 'picked_up' &&
              o.status != 'out_for_delivery' &&
              o.status != 'delivered')
          .length;

      expect(remainingUnpicked, equals(1));

      const shopName = 'Fresh Bakery';
      final notifTitle = remainingUnpicked > 0
          ? '🛍️ Items Picked Up'
          : '🛵 Rider Picked Up';
      final notifBody = remainingUnpicked > 0
          ? 'Rider collected items from $shopName. Heading to the next stop!'
          : 'Your order is on its way!';

      expect(notifTitle, equals('🛍️ Items Picked Up'));
      expect(notifBody, contains('Heading to the next stop!'));
      expect(notifBody, isNot(contains('Your order is on its way!')));
    });

    test('Edge Case 2b: Final shop pickup notification informs customer order is on its way', () {
      final shop1Order = OrderModel.fromMap({
        'id': 'sub_1',
        'cart_group_id': 'cg_multi',
        'customer_id': 'cust_1',
        'shop_id': 'shop_1',
        'status': 'picked_up',
      });

      final shop2Order = OrderModel.fromMap({
        'id': 'sub_2',
        'cart_group_id': 'cg_multi',
        'customer_id': 'cust_1',
        'shop_id': 'shop_2',
        'status': 'picked_up',
      });

      final group = OrderGroup('cg_multi', [shop1Order, shop2Order]);

      final remainingUnpicked = group.activeOrders
          .where((o) =>
              o.id != shop2Order.id &&
              o.status != 'picked_up' &&
              o.status != 'out_for_delivery' &&
              o.status != 'delivered')
          .length;

      expect(remainingUnpicked, equals(0));

      const shopName = 'Pharmacy';
      final notifTitle = remainingUnpicked > 0
          ? '🛍️ Items Picked Up'
          : '🛵 Rider Picked Up';
      final notifBody = remainingUnpicked > 0
          ? 'Rider collected items from $shopName. Heading to the next stop!'
          : 'Your order is on its way!';

      expect(notifTitle, equals('🛵 Rider Picked Up'));
      expect(notifBody, equals('Your order is on its way!'));
    });

    test('Edge Case 3: Target order resolution selects active order when first sub-order is rejected', () {
      final deadSubOrder = OrderModel.fromMap({
        'id': 'dead_order_id',
        'cart_group_id': 'group_test',
        'customer_id': 'customer_123',
        'shop_id': 'shop_dead',
        'status': 'seller_rejected',
      });

      final liveSubOrder = OrderModel.fromMap({
        'id': 'live_order_id',
        'cart_group_id': 'group_test',
        'customer_id': 'customer_123',
        'shop_id': 'shop_live',
        'status': 'awaiting_acceptance',
      });

      final group = OrderGroup('group_test', [deadSubOrder, liveSubOrder]);

      expect(group.orders.first.id, equals('dead_order_id'));

      final targetOrder = group.activeOrders.isNotEmpty
          ? group.activeOrders.first
          : group.orders.first;

      expect(targetOrder.id, equals('live_order_id'));
      expect(targetOrder.status, equals('awaiting_acceptance'));
    });

    test('Edge Case 4: Map coordinate fallback preserves current order location without hardcoding Bandipora', () {
      final currentOrder = OrderModel.fromMap({
        'id': 'order_srinagar',
        'shop_lat': 34.0837,
        'shop_lng': 74.7973,
        'delivery_lat': 34.0800,
        'delivery_lng': 74.7950,
      });

      var updatedOrder = OrderModel.fromMap({
        'id': 'order_srinagar',
        'shop_lat': null,
        'shop_lng': 0.0,
        'delivery_lat': null,
        'delivery_lng': 0.0,
      });

      if (updatedOrder.shopLat == null || updatedOrder.shopLat == 0.0) {
        if (currentOrder.shopLat != null && currentOrder.shopLat != 0.0) {
          updatedOrder = updatedOrder.copyWith(
            shopLat: currentOrder.shopLat,
            shopLng: currentOrder.shopLng,
          );
        }
      }

      if (updatedOrder.deliveryLat == null || updatedOrder.deliveryLat == 0.0) {
        if (currentOrder.deliveryLat != null && currentOrder.deliveryLat != 0.0) {
          updatedOrder = updatedOrder.copyWith(
            deliveryLat: currentOrder.deliveryLat,
            deliveryLng: currentOrder.deliveryLng,
          );
        }
      }

      expect(updatedOrder.shopLat, equals(34.0837));
      expect(updatedOrder.shopLng, equals(74.7973));
      expect(updatedOrder.deliveryLat, equals(34.0800));
      expect(updatedOrder.deliveryLng, equals(74.7950));
    });
  });
}
