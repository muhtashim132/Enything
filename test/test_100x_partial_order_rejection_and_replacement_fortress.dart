import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  group('100x Partial Order Rejection & Replacement Fortress Tests', () {
    test('OrderGroup.groupStatus prevents regression when in-flight progress exists', () {
      final now = DateTime.now();

      final orderA = OrderModel(
        id: 'order-a',
        customerId: 'cust-1',
        status: 'picked_up',
        totalAmount: 300,
        deliveryCharges: 25,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-1',
            productId: 'p-1',
            productName: 'Burger',
            quantity: 1,
            price: 300,
            weightKg: 0.5,
            status: 'active',
          ),
        ],
      );

      final orderBReplaced = OrderModel(
        id: 'order-b',
        customerId: 'cust-1',
        status: 'seller_rejected',
        totalAmount: 150,
        deliveryCharges: 0,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-2',
            productId: 'p-2',
            productName: 'Fries',
            quantity: 1,
            price: 150,
            weightKg: 0.2,
            status: 'declined',
          ),
        ],
      );

      // Replacement Store C added in awaiting_acceptance
      final orderCReplacement = OrderModel(
        id: 'order-c',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 160,
        deliveryCharges: 0,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-3',
            productId: 'p-3',
            productName: 'Curly Fries',
            quantity: 1,
            price: 160,
            weightKg: 0.25,
            status: 'active',
          ),
        ],
      );

      final group = OrderGroup(
        'grp-1',
        [orderA, orderBReplaced, orderCReplacement],
      );

      // Active orders are orderA (picked_up) and orderC (awaiting_acceptance)
      expect(group.activeOrders.length, 2);

      // Group status must NOT regress to 'awaiting_acceptance'; it must report 'pickup_in_progress'
      expect(group.groupStatus, 'pickup_in_progress');
    });

    test('OrderModel correctly captures pendingRefundAmount and refundStatus', () {
      final now = DateTime.now();
      final map = {
        'id': 'ord-123',
        'customer_id': 'cust-456',
        'status': 'confirmed',
        'total_amount': 450.0,
        'delivery_charges': 30.0,
        'created_at': now.toIso8601String(),
        'pending_refund_amount': 150.0,
        'refund_status': 'processing',
      };

      final order = OrderModel.fromMap(map);
      expect(order.pendingRefundAmount, 150.0);
      expect(order.refundStatus, 'processing');

      final copied = order.copyWith(pendingRefundAmount: 50.0, refundStatus: 'completed');
      expect(copied.pendingRefundAmount, 50.0);
      expect(copied.refundStatus, 'completed');
    });

    test('OrderGroup.allPickedUp strictly accounts for active replacement orders', () {
      final now = DateTime.now();
      final order1 = OrderModel(
        id: 'o-1',
        customerId: 'c-1',
        status: 'picked_up',
        totalAmount: 200,
        deliveryCharges: 25,
        createdAt: now,
      );
      final order2 = OrderModel(
        id: 'o-2',
        customerId: 'c-1',
        status: 'preparing',
        totalAmount: 180,
        deliveryCharges: 0,
        createdAt: now,
      );

      final group = OrderGroup(
        'grp-2',
        [order1, order2],
      );

      expect(group.allPickedUp, false);
      expect(group.groupStatus, 'pickup_in_progress');
    });
  });
}
