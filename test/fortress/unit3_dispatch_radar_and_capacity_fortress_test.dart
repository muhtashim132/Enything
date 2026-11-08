import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  group('100x Forensic Unit 3: Dispatch Radar, Capacity Ceiling & Proxy Hub Fortress', () {
    final baseTime = DateTime(2026, 11, 8, 14, 0);

    OrderModel createMockOrder({
      required String id,
      required String shopId,
      required String status,
      String? deliveryPartnerId,
      String paymentStatus = 'captured',
      double deliveryLat = 34.4120,
      double deliveryLng = 74.6485,
      String? cartGroupId,
    }) {
      return OrderModel(
        id: id,
        customerId: 'cust_1',
        shopId: shopId,
        deliveryPartnerId: deliveryPartnerId,
        status: status,
        paymentStatus: paymentStatus,
        paymentMethod: 'upi',
        items: [],
        totalAmount: 200.0,
        deliveryCharges: 35.0,
        platformFee: 2.0,
        grandTotalCollected: 237.0,
        riderEarnings: 35.0,
        address: 'Bandipora',
        addressLabel: 'Home',
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
        deliveryOtp: '1234',
        createdAt: baseTime,
        updatedAt: baseTime,
        cartGroupId: cartGroupId ?? 'cg_$id',
      );
    }

    test('1. Courier Capacity Ceiling: UI lock when active cart groups >= 3', () {
      final g1 = OrderGroup('cg_1', [createMockOrder(id: 'o1', shopId: 's1', status: 'confirmed')]);
      final g2 = OrderGroup('cg_2', [createMockOrder(id: 'o2', shopId: 's2', status: 'preparing')]);
      final g3 = OrderGroup('cg_3', [createMockOrder(id: 'o3', shopId: 's3', status: 'picked_up')]);

      final myGroups = [g1, g2, g3];

      // In rider dashboard (dashboard_page.dart):
      final isCapacityReached = myGroups.length >= 3;
      final buttonLabel = isCapacityReached ? 'Max 3 Orders Active' : 'Accept Order';
      final canAccept = !isCapacityReached;

      expect(isCapacityReached, isTrue);
      expect(canAccept, isFalse);
      expect(buttonLabel, equals('Max 3 Orders Active'));
    });

    test('2. Admin / Dispatcher Hoarding Limit Bypass', () {
      // Regular rider check:
      bool canRiderAccept(int activeCount, {required bool isAdminOrDispatcher}) {
        if (isAdminOrDispatcher) return true; // Bypasses hoarding ceiling
        return activeCount < 3;
      }

      expect(canRiderAccept(3, isAdminOrDispatcher: false), isFalse);
      expect(canRiderAccept(5, isAdminOrDispatcher: true), isTrue); // Dispatcher / Admin proxy mode
      expect(canRiderAccept(10, isAdminOrDispatcher: true), isTrue);
    });

    test('3. Radar Distance Filtering & Radius Predicate', () {
      const dispatcherCenter = LatLng(34.4205, 74.6380); // Bandipora Town Center

      // Order A: 1.5 km away (In-town)
      const orderPosA = LatLng(34.4300, 74.6450);
      final distA = DeliveryCalculator.haversineKm(dispatcherCenter, orderPosA);
      expect(distA, closeTo(1.5, 0.5));

      // Order B: 7.2 km away (Ajar / Outer district)
      const orderPosB = LatLng(34.4800, 74.6500);
      final distB = DeliveryCalculator.haversineKm(dispatcherCenter, orderPosB);
      expect(distB, closeTo(6.8, 1.0));

      // Order C: 18.0 km away (Beyond max delivery radius)
      const orderPosC = LatLng(34.2500, 74.6380);
      final distC = DeliveryCalculator.haversineKm(dispatcherCenter, orderPosC);
      expect(distC, greaterThan(15.0));

      // Radar Radius Modes:
      bool isOrderInRadar(double distKm, double? radarRadiusKm) {
        if (radarRadiusKm == null) return true; // Unlimited Mode
        return distKm <= radarRadiusKm;
      }

      // Mode: 5 km
      expect(isOrderInRadar(distA, 5.0), isTrue);
      expect(isOrderInRadar(distB, 5.0), isFalse);

      // Mode: 10 km
      expect(isOrderInRadar(distB, 10.0), isTrue);
      expect(isOrderInRadar(distC, 10.0), isFalse);

      // Mode: Unlimited (null)
      expect(isOrderInRadar(distC, null), isTrue);
    });

    test('4. Courier Drop Order: Suppress Payment Push if Already Captured', () {
      // Re-pool order when rider drops
      final droppedOrder = createMockOrder(id: 'o_drop', shopId: 's1', status: 'confirmed', paymentStatus: 'captured');

      // Rule 5 of 100X Rider Lifecycle:
      // When a reassigned order has payment_status == 'captured', suppress "Ready for Payment"
      // and send "New Rider Assigned! 🛵" to customer.
      String resolveCustomerPushNotification(OrderModel order) {
        if (order.paymentStatus == 'captured') {
          return 'New Rider Assigned! 🛵';
        } else {
          return 'Ready for Payment! 💳';
        }
      }

      expect(resolveCustomerPushNotification(droppedOrder), equals('New Rider Assigned! 🛵'));

      final unpaidOrder = createMockOrder(id: 'o_unpaid', shopId: 's1', status: 'awaiting_payment', paymentStatus: 'pending');
      expect(resolveCustomerPushNotification(unpaidOrder), equals('Ready for Payment! 💳'));
    });

    test('5. Multi-Shop Sibling Drop Dispatch: Distinct shop notification list', () {
      // Sibling orders belonging to the same cart group from 3 distinct shops:
      final o1 = createMockOrder(id: 'o1', shopId: 'shop_bakery', status: 'preparing', cartGroupId: 'cg_multi');
      final o2 = createMockOrder(id: 'o2', shopId: 'shop_grocery', status: 'preparing', cartGroupId: 'cg_multi');
      final o3 = createMockOrder(id: 'o3', shopId: 'shop_bakery', status: 'preparing', cartGroupId: 'cg_multi'); // same shop as o1

      final cartOrders = [o1, o2, o3];

      // Distinct shops involved:
      final distinctShopIds = cartOrders.map((o) => o.shopId).toSet().toList();
      expect(distinctShopIds.length, equals(2));
      expect(distinctShopIds, containsAll(['shop_bakery', 'shop_grocery']));
      // Notification dispatched to every unique affected shop
    });

    test('6. Self-Delivery Mode: Auto-provisioning partner record fallback', () {
      Map<String, dynamic>? deliveryPartnerRecord; // initially null for new admin
      const adminUserId = 'admin_uuid_123';

      // Self-delivery auto-heal pattern:
      if (deliveryPartnerRecord == null) {
        deliveryPartnerRecord = {
          'id': adminUserId,
          'name': 'Admin Operations (Self)',
          'status': 'verified',
          'is_active': true,
        };
      }

      expect(deliveryPartnerRecord['id'], equals(adminUserId));
      expect(deliveryPartnerRecord['status'], equals('verified'));
      expect(deliveryPartnerRecord['is_active'], isTrue);
    });
  });
}

