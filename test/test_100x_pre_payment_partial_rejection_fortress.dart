import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  group('100x Pre-Payment Partial Rejection & Replacement Fortress Tests', () {
    test('OrderGroup.groupStatus prioritizes awaiting_acceptance over awaiting_payment', () {
      final now = DateTime.now();

      // Shop A accepted -> awaiting_payment
      final orderA = OrderModel(
        id: 'order-a',
        customerId: 'cust-1',
        status: 'awaiting_payment',
        totalAmount: 250,
        deliveryCharges: 25,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-1',
            productId: 'p-1',
            productName: 'Shampoo',
            quantity: 1,
            price: 250,
            weightKg: 0.3,
            status: 'active',
          ),
        ],
      );

      // Shop B was rejected
      final orderB = OrderModel(
        id: 'order-b',
        customerId: 'cust-1',
        status: 'seller_rejected',
        totalAmount: 180,
        deliveryCharges: 0,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-2',
            productId: 'p-2',
            productName: 'Soap',
            quantity: 1,
            price: 180,
            weightKg: 0.2,
            status: 'declined',
          ),
        ],
      );

      // Replacement Store C added by customer -> awaiting_acceptance
      final orderC = OrderModel(
        id: 'order-c',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 200,
        deliveryCharges: 20,
        createdAt: now,
        items: [
          OrderItem(
            id: 'item-3',
            productId: 'p-3',
            productName: 'Herbal Soap',
            quantity: 1,
            price: 200,
            weightKg: 0.25,
            status: 'active',
          ),
        ],
      );

      final group = OrderGroup('grp-1', [orderA, orderB, orderC]);

      // Active orders are orderA and orderC
      expect(group.activeOrders.length, 2);

      // CRITICAL: groupStatus must report 'awaiting_acceptance' (NOT 'awaiting_payment'),
      // because Shop C has not yet confirmed the order. Rider and UI must NOT claim payment is in progress!
      expect(group.groupStatus, 'awaiting_acceptance');
    });

    test('OrderItem correctly differentiates between active, declined, and swapped statuses', () {
      final activeItem = OrderItem(
        id: 'it-1',
        productId: 'prod-1',
        productName: 'Product 1',
        quantity: 2,
        price: 100,
        weightKg: 0.5,
        status: 'active',
      );
      expect(activeItem.isActive, true);
      expect(activeItem.isDeclined, false);
      expect(activeItem.isSwapped, false);
      expect(activeItem.isDeclinedOrSwapped, false);

      final declinedItem = OrderItem(
        id: 'it-2',
        productId: 'prod-2',
        productName: 'Product 2',
        quantity: 1,
        price: 150,
        weightKg: 0.4,
        status: 'declined',
      );
      expect(declinedItem.isActive, false);
      expect(declinedItem.isDeclined, true);
      expect(declinedItem.isSwapped, false);
      expect(declinedItem.isDeclinedOrSwapped, true);

      final swappedItem = OrderItem(
        id: 'it-3',
        productId: 'prod-3',
        productName: 'Product 3',
        quantity: 1,
        price: 120,
        weightKg: 0.3,
        status: 'swapped',
      );
      expect(swappedItem.isActive, false);
      // isDeclined is false so customer hasDeclinedItems doesn't keep screaming
      expect(swappedItem.isDeclined, false);
      // isSwapped is true so kitchen displays strikethrough & 'Do Not Pack'
      expect(swappedItem.isSwapped, true);
      expect(swappedItem.isDeclinedOrSwapped, true);
    });

    test('OrderGroup.groupStatus transitions to awaiting_payment only when ALL active orders are accepted', () {
      final now = DateTime.now();

      final orderA = OrderModel(
        id: 'order-a',
        customerId: 'cust-1',
        status: 'awaiting_payment',
        totalAmount: 250,
        deliveryCharges: 25,
        createdAt: now,
      );

      final orderC = OrderModel(
        id: 'order-c',
        customerId: 'cust-1',
        status: 'awaiting_payment',
        totalAmount: 200,
        deliveryCharges: 20,
        createdAt: now,
      );

      final group = OrderGroup('grp-1', [orderA, orderC]);

      // When ALL active orders are in awaiting_payment, groupStatus is awaiting_payment
      expect(group.groupStatus, 'awaiting_payment');
    });
  });
}
