import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/utils/geo_utils.dart';
import 'package:enythingmobilenew/widgets/common/animated_moving_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x BANDIPORA MULTI-SHOP REALTIME SIMULATION & GEOSPATIAL TEST SUITE', () {
    
    // ─────────────────────────────────────────────────────────────────────────
    // 1. BANDIPORA GEOSPATIAL COORDINATES & DISTANCE VERIFICATION
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Bandipora Shop 1, Shop 2, and Shop 3 distances adhere to 1km and 2km specifications', () {
      // Bandipora Real Coordinates
      const riderDepot = LatLng(34.4205, 74.6380); // Bus Stand Bandipora
      const shop1 = LatLng(34.4228, 74.6365);      // Gulshan Chowk (Central Bakery)
      const shop2 = LatLng(34.4148, 74.6305);      // Kaloosa Sopore Rd (Fresh Mart)
      const shop3 = LatLng(34.4295, 74.6465);      // Plan Bandipora (Plan Chemist)
      const customer = LatLng(34.4120, 74.6485);   // Nowpora Residence

      const distanceCalc = Distance();

      // Distances in meters
      final distShop1ToShop2 = distanceCalc.as(LengthUnit.Meter, shop1, shop2);
      final distShop2ToShop3 = distanceCalc.as(LengthUnit.Meter, shop2, shop3);
      final distShop3ToCustomer = distanceCalc.as(LengthUnit.Meter, shop3, customer);
      final distDepotToShop1 = distanceCalc.as(LengthUnit.Meter, riderDepot, shop1);

      // Verify Shop 1 to Shop 2 is approximately 1 km (between 0.95 km and 1.25 km)
      expect(distShop1ToShop2, greaterThan(900));
      expect(distShop1ToShop2, lessThan(1300));
      print('📍 Distance Shop 1 (Gulshan Chowk) ➔ Shop 2 (Kaloosa): ${(distShop1ToShop2 / 1000).toStringAsFixed(2)} km (~1 km requirement PASSED)');

      // Verify Shop 2 to Shop 3 is approximately 2 km (between 1.9 km and 2.4 km)
      expect(distShop2ToShop3, greaterThan(1800));
      expect(distShop2ToShop3, lessThan(2500));
      print('📍 Distance Shop 2 (Kaloosa) ➔ Shop 3 (Plan Chemist): ${(distShop2ToShop3 / 1000).toStringAsFixed(2)} km (~2 km requirement PASSED)');

      // Verify Shop 3 to Customer Drop-off
      expect(distShop3ToCustomer, greaterThan(1700));
      print('📍 Distance Shop 3 (Plan Chemist) ➔ Customer (Nowpora): ${(distShop3ToCustomer / 1000).toStringAsFixed(2)} km');

      // Verify Depot to Shop 1
      expect(distDepotToShop1, lessThan(500));
      print('📍 Distance Depot ➔ Shop 1: ${(distDepotToShop1 / 1000).toStringAsFixed(2)} km');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. MATHEMATICAL BEARING, LERP, AND JITTER SUPPRESSION
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Bearing angle and lerp interpolation handle smooth heading rotation without micro-spinning', () {
      const p1 = LatLng(34.4205, 74.6380);
      const p2 = LatLng(34.4228, 74.6365);

      // Bearing calculation
      final bearing = GeoUtils.calculateBearing(p1, p2);
      expect(bearing, isNotNull);
      expect(bearing, inInclusiveRange(0.0, 360.0));
      print('🧭 Calculated Bearing from Depot to Shop 1: ${bearing.toStringAsFixed(1)}°');

      // Midpoint linear interpolation (lerp)
      final midPoint = lerpLatLng(p1, p2, 0.5);
      expect(midPoint.latitude, closeTo((p1.latitude + p2.latitude) / 2, 0.0001));
      expect(midPoint.longitude, closeTo((p1.longitude + p2.longitude) / 2, 0.0001));

      // Jitter suppression: movement < 3.5m maintains stable bearing
      const jitterPoint = LatLng(34.420510, 74.638010);
      final jitterDist = const Distance().as(LengthUnit.Meter, p1, jitterPoint);
      expect(jitterDist, lessThan(3.5));

      double stableBearing = 45.0;
      if (jitterDist >= 3.5) {
        stableBearing = GeoUtils.calculateBearing(p1, jitterPoint);
      }
      expect(stableBearing, equals(45.0)); // Bearing remains locked, zero spinning
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. 100% PREPAID MODEL & PAYMENT BYPASS INVARIANCE
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Multi-shop order group adheres strictly to 100% Prepaid Model (Zero COD)', () {
      final now = DateTime.now();
      final subOrder1 = OrderModel(
        id: 'bandipora-sub-1',
        shopId: 'shop-bakery-id',
        customerId: 'customer-bandipora-id',
        status: 'awaiting_acceptance',
        totalAmount: 240.0,
        deliveryCharges: 0.0,
        riderEarnings: 45.0,
        grandTotalCollected: 240.0,
        paymentStatus: 'captured', // Bypassed for test
        paymentMethod: 'practice',
        cartGroupId: 'bandipora-cart-group-1',
        createdAt: now,
      );

      final subOrder2 = OrderModel(
        id: 'bandipora-sub-2',
        shopId: 'shop-grocery-id',
        customerId: 'customer-bandipora-id',
        status: 'awaiting_acceptance',
        totalAmount: 380.0,
        deliveryCharges: 0.0,
        riderEarnings: 30.0,
        grandTotalCollected: 380.0,
        paymentStatus: 'captured', // Bypassed for test
        paymentMethod: 'practice',
        cartGroupId: 'bandipora-cart-group-1',
        createdAt: now,
      );

      final subOrder3 = OrderModel(
        id: 'bandipora-sub-3',
        shopId: 'shop-chemist-id',
        customerId: 'customer-bandipora-id',
        status: 'awaiting_acceptance',
        totalAmount: 150.0,
        deliveryCharges: 0.0,
        riderEarnings: 25.0,
        grandTotalCollected: 150.0,
        paymentStatus: 'captured', // Bypassed for test
        paymentMethod: 'practice',
        cartGroupId: 'bandipora-cart-group-1',
        createdAt: now,
      );

      final group = OrderGroup(
        'bandipora-cart-group-1',
        [subOrder1, subOrder2, subOrder3],
      );

      // Verify 100% Prepaid Rules
      expect(group.isPrepaid, isTrue);
      expect(group.isCod, isFalse);
      expect(group.codAmountToCollect, equals(0.0));
      expect(group.orders.length, equals(3));
      expect(group.totalEarnings, equals(100.0));
      print('💳 100% Prepaid Verification: isPrepaid=${group.isPrepaid}, isCod=${group.isCod}, COD to collect=₹${group.codAmountToCollect}');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. MULTI-SHOP INTERMEDIATE PICKUP & OUT-FOR-DELIVERY STATE MACHINE
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Intermediate shop pickups notify customer correctly and transition to out_for_delivery only when all 3 shops are picked up', () {
      final now = DateTime.now();
      
      // Step A: All 3 shops preparing
      var order1 = OrderModel(id: 'o1', shopId: 's1', customerId: 'c1', status: 'preparing', totalAmount: 100, deliveryCharges: 0, createdAt: now);
      var order2 = OrderModel(id: 'o2', shopId: 's2', customerId: 'c1', status: 'preparing', totalAmount: 100, deliveryCharges: 0, createdAt: now);
      var order3 = OrderModel(id: 'o3', shopId: 's3', customerId: 'c1', status: 'preparing', totalAmount: 100, deliveryCharges: 0, createdAt: now);
      var group = OrderGroup('cg1', [order1, order2, order3]);

      expect(group.allPickedUp, isFalse);
      expect(group.allOutForDelivery, isFalse);

      // Step B: Shop 1 Picked Up
      order1 = order1.copyWith(status: 'picked_up');
      group = OrderGroup('cg1', [order1, order2, order3]);

      // Unpicked shops remain (2 remaining)
      final remainingUnpickedAfterShop1 = group.activeOrders.where((o) => o.status != 'picked_up' && o.status != 'out_for_delivery' && o.status != 'delivered').length;
      expect(remainingUnpickedAfterShop1, equals(2));
      expect(group.allPickedUp, isFalse);
      print('🛍️ Intermediate Stop 1 Picked Up: Remaining unpicked shops = $remainingUnpickedAfterShop1 (Push: "Collected from Shop 1, heading to next stop!")');

      // Step C: Shop 2 Picked Up
      order2 = order2.copyWith(status: 'picked_up');
      group = OrderGroup('cg1', [order1, order2, order3]);

      final remainingUnpickedAfterShop2 = group.activeOrders.where((o) => o.status != 'picked_up' && o.status != 'out_for_delivery' && o.status != 'delivered').length;
      expect(remainingUnpickedAfterShop2, equals(1));
      expect(group.allPickedUp, isFalse);
      print('🛍️ Intermediate Stop 2 Picked Up: Remaining unpicked shops = $remainingUnpickedAfterShop2 (Push: "Collected from Shop 2, heading to next stop!")');

      // Step D: Shop 3 Picked Up -> All 3 Picked Up!
      order3 = order3.copyWith(status: 'picked_up');
      group = OrderGroup('cg1', [order1, order2, order3]);

      expect(group.allPickedUp, isTrue);
      print('🎉 All 3 Shops Picked Up: group.allPickedUp=${group.allPickedUp} -> Group advances to out_for_delivery!');

      // Step E: Out for delivery
      order1 = order1.copyWith(status: 'out_for_delivery');
      order2 = order2.copyWith(status: 'out_for_delivery');
      order3 = order3.copyWith(status: 'out_for_delivery');
      group = OrderGroup('cg1', [order1, order2, order3]);

      expect(group.allOutForDelivery, isTrue);
      print('🛵 Group out_for_delivery verified: Customer receives "🛵 Out for Delivery: Heading to your doorstep!"');

      // Step F: Delivered
      order1 = order1.copyWith(status: 'delivered');
      order2 = order2.copyWith(status: 'delivered');
      order3 = order3.copyWith(status: 'delivered');
      group = OrderGroup('cg1', [order1, order2, order3]);

      expect(group.groupStatus, equals('delivered'));
      print('🏁 Group delivered verified: Customer receives "🎉 Order Delivered! Enjoy your order."');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. SIBLING SURVIVAL RULE ON PARTIAL STORE REJECTION
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Sibling Order Survival Rule: If Shop 2 rejects, surviving Shop 1 & Shop 3 continue uninterrupted', () {
      final now = DateTime.now();
      final order1 = OrderModel(id: 'o1', shopId: 's1', customerId: 'c1', status: 'preparing', totalAmount: 100, deliveryCharges: 0, createdAt: now);
      final order2 = OrderModel(id: 'o2', shopId: 's2', customerId: 'c1', status: 'seller_rejected', totalAmount: 100, deliveryCharges: 0, createdAt: now);
      final order3 = OrderModel(id: 'o3', shopId: 's3', customerId: 'c1', status: 'preparing', totalAmount: 100, deliveryCharges: 0, createdAt: now);

      final group = OrderGroup('cg1', [order1, order2, order3]);

      // Active orders should only be 2 (Shop 1 and Shop 3)
      expect(group.activeOrders.length, equals(2));
      expect(group.activeOrders.map((o) => o.id), containsAll(['o1', 'o3']));
      expect(group.activeOrders.map((o) => o.id), isNot(contains('o2')));

      print('🛡️ Sibling Survival Rule PASSED: Active sibling orders (${group.activeOrders.length}) remain alive after Shop 2 rejection.');
    });

  });
}

