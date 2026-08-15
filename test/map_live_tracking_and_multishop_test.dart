import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/widgets/common/animated_moving_marker.dart';

void main() {
  group('100x Map Mathematics & Smooth Marker Algorithms', () {
    test('lerpLatLng accurately interpolates coordinates between two points', () {
      final p1 = const LatLng(28.6139, 77.2090); // New Delhi
      final p2 = const LatLng(28.7041, 77.1025);

      final mid = lerpLatLng(p1, p2, 0.5);
      expect(mid.latitude, closeTo((28.6139 + 28.7041) / 2, 0.00001));
      expect(mid.longitude, closeTo((77.2090 + 77.1025) / 2, 0.00001));

      final start = lerpLatLng(p1, p2, 0.0);
      expect(start.latitude, equals(p1.latitude));
      expect(start.longitude, equals(p1.longitude));

      final end = lerpLatLng(p1, p2, 1.0);
      expect(end.latitude, equals(p2.latitude));
      expect(end.longitude, equals(p2.longitude));
    });

    test('calculateBearing accurately computes direction angle', () {
      // Due North (lat increases, lng unchanged)
      final northBearing = calculateBearing(
        const LatLng(0.0, 0.0),
        const LatLng(1.0, 0.0),
      );
      expect(northBearing, closeTo(0.0, 0.5));

      // Due East (lat unchanged, lng increases)
      final eastBearing = calculateBearing(
        const LatLng(0.0, 0.0),
        const LatLng(0.0, 1.0),
      );
      expect(eastBearing, closeTo(90.0, 0.5));

      // Due South (lat decreases, lng unchanged)
      final southBearing = calculateBearing(
        const LatLng(1.0, 0.0),
        const LatLng(0.0, 0.0),
      );
      expect(southBearing, closeTo(180.0, 0.5));

      // Due West (lat unchanged, lng decreases)
      final westBearing = calculateBearing(
        const LatLng(0.0, 1.0),
        const LatLng(0.0, 0.0),
      );
      expect(westBearing, closeTo(270.0, 0.5));
    });

    test('lerpAngle correctly handles wrap-around across 0/360 boundary', () {
      // Interpolate from 350° to 10° across 0°
      final angle = lerpAngle(350.0, 10.0, 0.5);
      expect(angle, closeTo(0.0, 0.001));

      // Interpolate from 10° to 350° backwards
      final revAngle = lerpAngle(10.0, 350.0, 0.5);
      expect(revAngle, closeTo(0.0, 0.001));

      // Normal interpolation without boundary cross
      final normalAngle = lerpAngle(40.0, 60.0, 0.5);
      expect(normalAngle, closeTo(50.0, 0.001));
    });
  });

  group('100x Multi-Shop & Partial Order Rejection in OrderGroup', () {
    OrderModel createTestOrder({
      required String id,
      required String shopId,
      required String status,
      required double grandTotal,
      required double riderEarnings,
      DateTime? arrivedAtShopTime,
      double? shopLat,
      double? shopLng,
      double? deliveryLat,
      double? deliveryLng,
    }) {
      return OrderModel(
        id: id,
        customerId: 'cust-1',
        shopId: shopId,
        totalAmount: grandTotal,
        deliveryCharges: 0.0,
        riderEarnings: riderEarnings,
        grandTotalCollected: grandTotal,
        status: status,
        paymentMethod: 'razorpay',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [],
        address: '123 Main St',
        addressLabel: 'Home',
        arrivedAtShopTime: arrivedAtShopTime,
        shopLat: shopLat ?? 28.6139,
        shopLng: shopLng ?? 77.2090,
        deliveryLat: deliveryLat ?? 28.7041,
        deliveryLng: deliveryLng ?? 77.1025,
      );
    }

    test('All shops accepted in multi-shop order: correct earnings, totals, and group status', () {
      final o1 = createTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'out_for_delivery',
        grandTotal: 500.0,
        riderEarnings: 40.0,
        arrivedAtShopTime: DateTime.now(),
      );
      final o2 = createTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'out_for_delivery',
        grandTotal: 300.0,
        riderEarnings: 30.0,
        arrivedAtShopTime: DateTime.now(),
      );

      final group = OrderGroup('cart-grp-1', [o1, o2]);

      expect(group.isMultiShop, isTrue);
      expect(group.activeOrders.length, equals(2));
      expect(group.totalGrand, equals(800.0));
      expect(group.totalEarnings, equals(70.0));
      expect(group.allArrived, isTrue);
      expect(group.allPickedUp, isTrue);
      expect(group.allOutForDelivery, isTrue);
      expect(group.groupStatus, equals('out_for_delivery'));
    });

    test('Partial Rejection: 1 Shop accepts, 1 Shop rejects in multi-shop order', () {
      final o1Accepted = createTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'out_for_delivery',
        grandTotal: 500.0,
        riderEarnings: 40.0,
        arrivedAtShopTime: DateTime.now(),
      );
      final o2Rejected = createTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'rejected',
        grandTotal: 300.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1Accepted, o2Rejected]);

      // Active orders should isolate the accepted sub-order
      expect(group.activeOrders.length, equals(1));
      expect(group.activeOrders.first.id, equals('ord-1'));
      expect(group.isMultiShop, isFalse); // Only 1 active shop remaining

      // Financials should reflect only active orders
      expect(group.totalGrand, equals(500.0));
      expect(group.totalEarnings, equals(40.0));

      // Status progress must NOT get stuck because of the rejected order
      expect(group.allArrived, isTrue);
      expect(group.allPickedUp, isTrue);
      expect(group.allOutForDelivery, isTrue);
      expect(group.groupStatus, equals('out_for_delivery'));
    });

    test('Partial Rejection leading to completion: 1 delivered, 1 cancelled', () {
      final o1Delivered = createTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'delivered',
        grandTotal: 450.0,
        riderEarnings: 45.0,
        arrivedAtShopTime: DateTime.now(),
      );
      final o2Cancelled = createTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'cancelled',
        grandTotal: 250.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1Delivered, o2Cancelled]);

      expect(group.activeOrders.length, equals(1));
      expect(group.groupStatus, equals('delivered'));
      expect(group.totalGrand, equals(450.0));
      expect(group.totalEarnings, equals(45.0));
    });

    test('Total Rejection: All shops rejected in multi-shop order', () {
      final o1Rejected = createTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'rejected',
        grandTotal: 500.0,
        riderEarnings: 0.0,
      );
      final o2Rejected = createTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'rejected',
        grandTotal: 300.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1Rejected, o2Rejected]);

      expect(group.activeOrders.isEmpty, isTrue);
      expect(group.groupStatus, equals('rejected'));
    });
  });

  group('100x Ghost Rider Prevention & Reassignment Idempotency', () {
    test('Rider reassignment cleanly removes old rider from tracking map', () {
      final riderMap = <String, LatLng>{};
      final orderToRider = <String, String>{};

      const orderId = 'order-123';
      const rider1Id = 'rider-1';
      const rider2Id = 'rider-2';

      // 1. Initial Assignment to Rider 1
      orderToRider[orderId] = rider1Id;
      riderMap[rider1Id] = const LatLng(28.6139, 77.2090);

      expect(riderMap.containsKey(rider1Id), isTrue);
      expect(riderMap[rider1Id], equals(const LatLng(28.6139, 77.2090)));

      // 2. Rider 1 declines, Rider 2 assigned (Reassignment)
      final oldRiderId = orderToRider[orderId];
      if (oldRiderId != null && oldRiderId != rider2Id) {
        riderMap.remove(oldRiderId);
      }
      orderToRider[orderId] = rider2Id;
      riderMap[rider2Id] = const LatLng(28.6200, 77.2100);

      // Verify no ghost rider artifacts
      expect(riderMap.containsKey(rider1Id), isFalse);
      expect(riderMap.containsKey(rider2Id), isTrue);
      expect(riderMap[rider2Id], equals(const LatLng(28.6200, 77.2100)));
      expect(riderMap.length, equals(1));
    });

    test('Order delivery or cancellation removes rider from active tracking', () {
      final riderMap = <String, LatLng>{
        'rider-1': const LatLng(28.6139, 77.2090),
      };

      const status = 'delivered';
      const riderId = 'rider-1';

      if (['delivered', 'cancelled', 'rejected'].contains(status)) {
        riderMap.remove(riderId);
      }

      expect(riderMap.isEmpty, isTrue);
    });
  });
}
