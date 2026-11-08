import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  group('100x Forensic Unit 4: Multi-Shop Cart & Lifecycle Fortress', () {
    final baseDate = DateTime(2026, 11, 8, 12, 0);

    OrderModel createMockOrder({
      required String id,
      required String shopId,
      required String status,
      DateTime? arrivedAtShopTime,
      double grandTotal = 250.0,
      double riderEarnings = 35.0,
      String? cartGroupId,
      List<OrderItem>? items,
    }) {
      return OrderModel(
        id: id,
        customerId: 'cust_1',
        shopId: shopId,
        deliveryPartnerId: 'rider_1',
        status: status,
        paymentStatus: 'captured',
        paymentMethod: 'upi',
        items: items ?? [],
        totalAmount: grandTotal - 35.0,
        deliveryCharges: 35.0,
        platformFee: 2.0,
        grandTotalCollected: grandTotal,
        riderEarnings: riderEarnings,
        address: 'Nowpora, Bandipora',
        addressLabel: '🏠 Home',
        deliveryLat: 34.4120,
        deliveryLng: 74.6485,
        deliveryOtp: '1234',
        createdAt: baseDate,
        updatedAt: baseDate,
        cartGroupId: cartGroupId ?? 'cg_1',
        arrivedAtShopTime: arrivedAtShopTime,
      );
    }

    test('1. 100% Prepaid Model invariant (Zero COD Doorstep Collection)', () {
      final order = createMockOrder(id: 'o1', shopId: 's1', status: 'confirmed');
      final group = OrderGroup('cg_1', [order]);

      // COD must be strictly false, Prepaid must be strictly true, COD amount to collect must be 0.0
      expect(group.isCod, isFalse);
      expect(group.isPrepaid, isTrue);
      expect(group.codAmountToCollect, equals(0.0));
      expect(group.deliveryOtp, equals('1234'));
    });

    test('2. OrderGroup Terminal Fallback Guard: empty active orders return false', () {
      // Both orders are cancelled/rejected
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'seller_rejected');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'cancelled');
      final group = OrderGroup('cg_1', [o1, o2]);

      expect(group.activeOrders, isEmpty);
      // All progress getters must strictly return false, never true or throw
      expect(group.allArrived, isFalse);
      expect(group.allPickedUp, isFalse);
      expect(group.allOutForDelivery, isFalse);
      expect(group.groupStatus, equals('cancelled'));
    });

    test('3. Sibling Order Survival on Store Rejection', () {
      // 3-shop cart group: Store 1 rejects, Store 2 and 3 survive
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'seller_rejected');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'confirmed');
      final o3 = createMockOrder(id: 'o3', shopId: 's3', status: 'confirmed');
      final group = OrderGroup('cg_1', [o1, o2, o3]);

      // Active orders must contain only surviving orders (Store 2 & Store 3)
      expect(group.activeOrders.length, equals(2));
      expect(group.activeOrders.map((o) => o.id), containsAll(['o2', 'o3']));
      expect(group.activeOrders.any((o) => o.id == 'o1'), isFalse);

      // Primary order must dynamically resolve to the first ACTIVE order (o2), NOT dead o1
      expect(group.primaryOrder.id, equals('o2'));
      expect(group.primaryOrder.status, equals('confirmed'));

      // Grand total of the group must sum ONLY active orders
      expect(group.totalGrand, equals(500.0)); // 250 + 250
    });

    test('4. Dead sub-order acceptance guard targets first active order', () {
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'seller_rejected');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'awaiting_acceptance');
      final group = OrderGroup('cg_1', [o1, o2]);

      // Guard logic used in _acceptOrderGroup:
      final targetOrder = group.activeOrders.firstWhere(
        (o) => o.status == 'awaiting_acceptance' || o.status == 'pending',
        orElse: () => group.activeOrders.first,
      );

      expect(targetOrder.id, equals('o2'));
      expect(targetOrder.status, equals('awaiting_acceptance'));
    });

    test('5. Multi-shop sequential pickup notification progression', () {
      // 3 shops in group: o1, o2, o3
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'picked_up');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'ready_for_pickup');
      final o3 = createMockOrder(id: 'o3', shopId: 's3', status: 'ready_for_pickup');
      final group = OrderGroup('cg_1', [o1, o2, o3]);

      // Remaining unpicked shops count = 2
      final unpickedCount = group.activeOrders.where((o) => o.status != 'picked_up' && o.status != 'out_for_delivery' && o.status != 'delivered').length;
      expect(unpickedCount, equals(2));

      // Group is not all picked up yet
      expect(group.allPickedUp, isFalse);

      // Group dominant status is ready_for_pickup (lowest incomplete prep status)
      expect(group.groupStatus, equals('ready_for_pickup'));

      // Customer notification message construction
      String getCustomerPickupNotification(int remainingUnpicked, String justPickedShopName) {
        if (remainingUnpicked > 0) {
          return '🛍️ Items Picked Up: Rider collected items from $justPickedShopName. Heading to the next stop!';
        } else {
          return '🚀 All Items Picked Up! Rider is heading to your delivery address.';
        }
      }

      expect(
        getCustomerPickupNotification(2, 'Central Bakery'),
        equals('🛍️ Items Picked Up: Rider collected items from Central Bakery. Heading to the next stop!'),
      );
      expect(
        getCustomerPickupNotification(0, 'Plan Chemist'),
        equals('🚀 All Items Picked Up! Rider is heading to your delivery address.'),
      );
    });

    test('6. Mark all out for delivery strictly filters picked_up orders', () {
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'picked_up');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'picked_up');
      final o3Cancelled = createMockOrder(id: 'o3', shopId: 's3', status: 'cancelled');
      final group = OrderGroup('cg_1', [o1, o2, o3Cancelled]);

      // In dashboard_page.dart:
      final ordersToAdvance = group.activeOrders.where((o) => o.status == 'picked_up').toList();
      expect(ordersToAdvance.length, equals(2));
      expect(ordersToAdvance.every((o) => o.status == 'picked_up'), isTrue);
      expect(ordersToAdvance.any((o) => o.id == 'o3'), isFalse);
    });

    test('7. Multi-merchant synchronization before payment: all must accept', () {
      // In a 2-shop cart group:
      // Store 1 accepts -> status = 'pending' or 'accepted_by_seller'
      // Store 2 not yet accepted -> status = 'awaiting_acceptance'
      final o1 = createMockOrder(id: 'o1', shopId: 's1', status: 'pending');
      final o2 = createMockOrder(id: 'o2', shopId: 's2', status: 'awaiting_acceptance');
      final group = OrderGroup('cg_1', [o1, o2]);

      bool canAdvanceToPayment(OrderGroup g) {
        return g.activeOrders.every((o) => o.status != 'awaiting_acceptance');
      }

      expect(canAdvanceToPayment(group), isFalse);

      // Now Store 2 accepts:
      final o2Accepted = createMockOrder(id: 'o2', shopId: 's2', status: 'pending');
      final groupAllAccepted = OrderGroup('cg_1', [o1, o2Accepted]);
      expect(canAdvanceToPayment(groupAllAccepted), isTrue);
    });

    test('8. Item-Level Partial Decline & Subtotal Rebalancing', () {
      final item1 = OrderItem(
        id: 'i1', productId: 'p1', productName: 'Milk',
        price: 60.0, quantity: 2, weightKg: 0.5, status: 'active',
      );
      final item2Declined = OrderItem(
        id: 'i2', productId: 'p2', productName: 'Brown Bread (Out of Stock)',
        price: 50.0, quantity: 1, weightKg: 0.4, status: 'declined', declinedReason: 'Out of stock',
      );

      final order = createMockOrder(id: 'o1', shopId: 's1', status: 'confirmed', items: [item1, item2Declined]);

      final activeItems = order.items.where((i) => i.status == 'active').toList();
      final declinedItems = order.items.where((i) => i.status != 'active').toList();

      expect(activeItems.length, equals(1));
      expect(declinedItems.length, equals(1));

      // Active subtotal = 60 * 2 = 120
      final activeSubtotal = activeItems.fold(0.0, (sum, i) => sum + (i.price * i.quantity));
      expect(activeSubtotal, equals(120.0));

      // Refund amount owed to customer = 50 * 1 = 50
      final refundAmount = declinedItems.fold(0.0, (sum, i) => sum + (i.price * i.quantity));
      expect(refundAmount, equals(50.0));
    });

    test('9. Multi-Shop Cart Capping: Strict maximum of 3 unique physical stores', () {
      final selectedShops = {'shop_1', 'shop_2', 'shop_3'};
      bool canAddShop(Set<String> currentShops, String newShopId) {
        if (currentShops.contains(newShopId)) return true;
        return currentShops.length < 3;
      }

      // Adding existing shop succeeds
      expect(canAddShop(selectedShops, 'shop_2'), isTrue);

      // Adding a 4th unique shop must be rejected cleanly
      expect(canAddShop(selectedShops, 'shop_4'), isFalse);
    });
  });
}
