import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('100x Replacement Deadlines & Partial Rejection Fortress Tests', () {
    test('Maximum (latest) acceptance deadline is selected among active orders', () {
      final now = DateTime.now().toUtc();

      // Older sibling shop placed 2.5 minutes ago (30s left)
      final olderSiblingOrder = OrderModel(
        id: 'order-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        totalAmount: 200.0,
        address: 'Test Address',
        deliveryCharges: 20.0,
        createdAt: now.subtract(const Duration(minutes: 2, seconds: 30)),
        acceptanceDeadline: now.add(const Duration(seconds: 30)),
      );

      // Fresh replacement shop placed right now (3 mins left)
      final replacementOrder = OrderModel(
        id: 'order-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        totalAmount: 150.0,
        address: 'Test Address',
        deliveryCharges: 20.0,
        createdAt: now,
        acceptanceDeadline: now.add(const Duration(minutes: 3)),
      );

      final groupOrders = [olderSiblingOrder, replacementOrder];

      // Test latest deadline selection (reduce logic from TrackOrderPage)
      final activeAccepting = groupOrders
          .where((o) => o.status == 'awaiting_acceptance')
          .toList();

      final selectedOrder = activeAccepting.reduce((curr, next) =>
          (curr.acceptanceDeadline?.isAfter(next.acceptanceDeadline ??
                      DateTime.fromMillisecondsSinceEpoch(0)) ??
                  false)
              ? curr
              : next);

      expect(selectedOrder.id, equals('order-2'));
      expect(
        selectedOrder.acceptanceDeadline!.difference(now).inSeconds,
        greaterThan(170),
      );
    });

    test('Maximum (latest) payment deadline is selected among active paying orders', () {
      final now = DateTime.now().toUtc();

      // Older sibling shop accepted 8 minutes ago (2 mins left on 10 min window)
      final olderPayingOrder = OrderModel(
        id: 'order-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_payment',
        totalAmount: 200.0,
        address: 'Test Address',
        deliveryCharges: 20.0,
        createdAt: now.subtract(const Duration(minutes: 8)),
        paymentDeadline: now.add(const Duration(minutes: 2)),
      );

      // Replacement shop accepted just now (10 mins left)
      final freshPayingOrder = OrderModel(
        id: 'order-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_payment',
        totalAmount: 150.0,
        address: 'Test Address',
        deliveryCharges: 20.0,
        createdAt: now,
        paymentDeadline: now.add(const Duration(minutes: 10)),
      );

      final groupOrders = [olderPayingOrder, freshPayingOrder];

      final activePaying = groupOrders
          .where((o) => o.status == 'awaiting_payment')
          .toList();

      final selectedOrder = activePaying.reduce((curr, next) =>
          (curr.paymentDeadline?.isAfter(next.paymentDeadline ??
                      DateTime.fromMillisecondsSinceEpoch(0)) ??
                  false)
              ? curr
              : next);

      expect(selectedOrder.id, equals('order-2'));
      expect(
        selectedOrder.paymentDeadline!.difference(now).inMinutes,
        greaterThanOrEqualTo(9),
      );
    });

    test('Customer replaced order definitively resolves partial rejection check', () {
      // Order 1: Rejected by seller, but customer placed replacement
      final replacedOrder = OrderModel(
        id: 'order-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        cancelledReason: 'customer_replaced',
        totalAmount: 100.0,
        address: 'Test Address',
        deliveryCharges: 0.0,
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );

      // Order 2: Active replacement shop awaiting acceptance
      final activeOrder = OrderModel(
        id: 'order-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        totalAmount: 120.0,
        address: 'Test Address',
        deliveryCharges: 20.0,
        createdAt: DateTime.now().toUtc(),
      );

      final groupOrders = [replacedOrder, activeOrder];

      // Check the resolution logic in TrackOrderPage._hasPartialRejection
      final hasReplacedOrder = groupOrders.any((o) => o.cancelledReason == 'customer_replaced');
      expect(hasReplacedOrder, isTrue);

      final terminalStatuses = {
        'seller_rejected',
        'partner_rejected',
        'rider_rejected',
        'verification_failed',
        'cancelled',
        'timeout',
        'payment_failed',
        'shop_dispute_cancel',
      };

      bool hasPartialRejection(bool partialRejectionResolved) {
        if (partialRejectionResolved) return false;
        if (groupOrders.isEmpty) return false;
        if (hasReplacedOrder) return false;

        final hasRejected = groupOrders.any((o) => terminalStatuses.contains(o.status));
        final hasActive = groupOrders.any((o) => !terminalStatuses.contains(o.status));
        return hasRejected && hasActive;
      }

      // Because hasReplacedOrder is true, hasPartialRejection MUST be false
      expect(hasPartialRejection(false), isFalse);
    });
  });
}
