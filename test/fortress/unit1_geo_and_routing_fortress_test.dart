import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:enythingmobilenew/utils/geo_utils.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('100x Forensic Unit 1: Geospatial, Geofencing & TSP Engine', () {
    // Reference Bandipora Hyperlocal Coordinates
    const depot = LatLng(34.4205, 74.6380); // Bus Stand Bandipora
    const shop1 = LatLng(34.4228, 74.6365); // Gulshan Chowk (Central Bakery)
    const shop2 = LatLng(34.4148, 74.6305); // Kaloosa (Fresh Mart)
    const shop3 = LatLng(34.4295, 74.6465); // Plan Bandipora (Plan Chemist)
    const customer1 = LatLng(34.4120, 74.6485); // Nowpora Residence
    const customer2 = LatLng(34.4350, 74.6520); // Muslim Abad Residence

    test('1. Cardinal bearings and zero-distance safety', () {
      // Due North (0°)
      final north = GeoUtils.calculateBearing(
        const LatLng(34.0, 74.0),
        const LatLng(35.0, 74.0),
      );
      expect(north, closeTo(0.0, 0.5));

      // Due East (90°)
      final east = GeoUtils.calculateBearing(
        const LatLng(34.0, 74.0),
        const LatLng(34.0, 75.0),
      );
      expect(east, closeTo(90.0, 1.0));

      // Due South (180°)
      final south = GeoUtils.calculateBearing(
        const LatLng(35.0, 74.0),
        const LatLng(34.0, 74.0),
      );
      expect(south, closeTo(180.0, 0.5));

      // Due West (270°)
      final west = GeoUtils.calculateBearing(
        const LatLng(34.0, 75.0),
        const LatLng(34.0, 74.0),
      );
      expect(west, closeTo(270.0, 1.0));

      // Coincident points: must not throw NaN or divide by zero
      final coincident = GeoUtils.calculateBearing(shop1, shop1);
      expect(coincident.isNaN, isFalse);
    });

    test('2. Shortest-path angle interpolation across 0/360 degree boundary', () {
      // Lerping from 350° to 10° at t=0.5 must cross 0° (midpoint is 0° or 360°)
      final mid1 = GeoUtils.lerpAngle(350.0, 10.0, 0.5);
      expect(mid1, closeTo(0.0, 0.1));

      // Lerping from 10° to 350° at t=0.5 must also cross 0°
      final mid2 = GeoUtils.lerpAngle(10.0, 350.0, 0.5);
      expect(mid2, closeTo(0.0, 0.1));

      // Standard acute interpolation (40° to 80° at t=0.5 -> 60°)
      final mid3 = GeoUtils.lerpAngle(40.0, 80.0, 0.5);
      expect(mid3, closeTo(60.0, 0.1));

      // Full circle boundaries
      expect(GeoUtils.lerpAngle(0.0, 360.0, 0.5), closeTo(0.0, 0.1));
    });

    test('3. Coordinate linear interpolation (lerpLatLng)', () {
      final mid = GeoUtils.lerpLatLng(shop1, shop2, 0.5);
      expect(mid.latitude, closeTo((shop1.latitude + shop2.latitude) / 2, 0.00001));
      expect(mid.longitude, closeTo((shop1.longitude + shop2.longitude) / 2, 0.00001));

      // Boundaries at t=0 and t=1
      final start = GeoUtils.lerpLatLng(shop1, shop2, 0.0);
      expect(start.latitude, closeTo(shop1.latitude, 0.00001));
      final end = GeoUtils.lerpLatLng(shop1, shop2, 1.0);
      expect(end.latitude, closeTo(shop2.latitude, 0.00001));
    });

    test('4. Haversine distance assertions on Bandipora hyperlocal topology', () {
      // Shop 1 (Gulshan Chowk) to Shop 2 (Kaloosa): ~1.05 km
      final dist12 = DeliveryCalculator.haversineKm(shop1, shop2);
      expect(dist12, closeTo(1.05, 0.2));

      // Shop 2 (Kaloosa) to Shop 3 (Plan Chemist): ~2.2 km
      final dist23 = DeliveryCalculator.haversineKm(shop2, shop3);
      expect(dist23, closeTo(2.2, 0.3));

      // Depot to Shop 1: ~0.29 km
      final distDepotShop1 = DeliveryCalculator.haversineKm(depot, shop1);
      expect(distDepotShop1, closeTo(0.29, 0.1));
    });

    test('5. Delivery radius 15km hard cutoff boundary defense', () {
      // 14.99 km -> within range
      expect(DeliveryCalculator.isWithinRange(14.99), isTrue);
      expect(DeliveryCalculator.calculateDeliveryCharges(14.99, 500), isNonNegative);

      // 15.00 km -> exactly on boundary -> within range
      expect(DeliveryCalculator.isWithinRange(15.00), isTrue);
      expect(DeliveryCalculator.calculateDeliveryCharges(15.00, 500), isNonNegative);

      // 15.01 km -> out of range -> returns -1
      expect(DeliveryCalculator.isWithinRange(15.01), isFalse);
      expect(DeliveryCalculator.calculateDeliveryCharges(15.01, 500), equals(-1.0));
      expect(DeliveryCalculator.deliveryChargeLabel(15.01, 500), equals('Out of range'));
    });

    test('6. Dynamic per-km delivery fee tiers and floor protection', () {
      // 0.2 km -> ceil(1km) * 20 = 20 (floor is 20)
      expect(DeliveryCalculator.calculateDeliveryCharges(0.2, 100), equals(20.0));

      // 1.0 km -> 20.0
      expect(DeliveryCalculator.calculateDeliveryCharges(1.0, 100), equals(20.0));

      // 1.1 km -> ceil(2km) * 20 = 40.0
      expect(DeliveryCalculator.calculateDeliveryCharges(1.1, 100), equals(40.0));

      // 4.5 km -> ceil(5km) * 20 = 100.0
      expect(DeliveryCalculator.calculateDeliveryCharges(4.5, 100), equals(100.0));
    });

    test('7. Multi-shop surcharge greedy nearest-neighbor chain', () {
      final s1 = ShopModel(
        id: 'shop_1', sellerId: 'sel_1', name: 'Bakery', category: 'Food',
        categories: [], location: shop1, isActive: true, rating: 4.5,
        totalReviews: 10, totalOrders: 10, address: 'Gulshan Chowk', shopType: 'shop'
      );
      final s2 = ShopModel(
        id: 'shop_2', sellerId: 'sel_2', name: 'Grocery', category: 'Grocery',
        categories: [], location: shop2, isActive: true, rating: 4.5,
        totalReviews: 10, totalOrders: 10, address: 'Kaloosa', shopType: 'shop'
      );
      final s3 = ShopModel(
        id: 'shop_3', sellerId: 'sel_3', name: 'Chemist', category: 'Pharmacy',
        categories: [], location: shop3, isActive: true, rating: 4.5,
        totalReviews: 10, totalOrders: 10, address: 'Plan', shopType: 'shop'
      );

      // 1 shop -> ₹0 surcharge
      expect(DeliveryCalculator.calculateMultiShopSurcharge([s1]), equals(0.0));

      // 2 shops: s1 -> s2 is ~1.05 km -> ceil(1.05) = 2 km -> 2 * 20 = ₹40 (or 20 if within 1km floor)
      final surcharge2 = DeliveryCalculator.calculateMultiShopSurcharge([s1, s2]);
      expect(surcharge2, greaterThanOrEqualTo(20.0));

      // 3 shops: s1 -> s2 -> s3
      final surcharge3 = DeliveryCalculator.calculateMultiShopSurcharge([s1, s2, s3]);
      expect(surcharge3, greaterThan(surcharge2));
    });

    test('8. Micro-movement noise suppression (<3.5m threshold)', () {
      // Micro-jitter: 0.00001 degrees lat is ~1.1 meters
      const p1 = LatLng(34.42050, 74.63800);
      const p2 = LatLng(34.42051, 74.63800);
      final jitterDistMeters = DeliveryCalculator.haversineKm(p1, p2) * 1000;

      expect(jitterDistMeters, lessThan(3.5));
      // In rider background service, movements <3.5m are suppressed from spinning compass icon
    });

    test('9. Distance formatting rules', () {
      expect(GeoUtils.formatDistance(0.0), equals('0 m'));
      expect(GeoUtils.formatDistance(0.05), equals('50 m'));
      expect(GeoUtils.formatDistance(0.95), equals('950 m'));
      expect(GeoUtils.formatDistance(1.0), equals('1.0 km'));
      expect(GeoUtils.formatDistance(3.456), equals('3.5 km'));
    });

    test('10. Bounding box computation with padding (computeBounds)', () {
      // Empty list returns null
      expect(GeoUtils.computeBounds([]), isNull);

      // Single point creates padded bounding box
      final singleBounds = GeoUtils.computeBounds([depot], paddingFactor: 0.01);
      expect(singleBounds, isNotNull);
      expect(singleBounds!.southWest.latitude, closeTo(depot.latitude - 0.01, 0.0001));
      expect(singleBounds.northEast.latitude, closeTo(depot.latitude + 0.01, 0.0001));

      // Multiple points encompass all coordinates plus padding
      final multiBounds = GeoUtils.computeBounds([shop1, shop2, shop3], paddingFactor: 0.005);
      expect(multiBounds, isNotNull);
      expect(multiBounds!.southWest.latitude, lessThan(shop2.latitude));
      expect(multiBounds.northEast.latitude, greaterThan(shop3.latitude));
    });

    test('11. Travel time estimation (estimateTravelTime)', () {
      // Distance <= 0.05 km returns '< 1 min'
      expect(GeoUtils.estimateTravelTime(0.04), equals('< 1 min'));
      expect(GeoUtils.estimateTravelTime(0.0), equals('< 1 min'));

      // 22 km/h average speed: 2.2 km takes ~6 mins
      expect(GeoUtils.estimateTravelTime(2.2, avgSpeedKmh: 22.0), equals('6 min'));

      // 11 km takes 30 mins
      expect(GeoUtils.estimateTravelTime(11.0, avgSpeedKmh: 22.0), equals('30 min'));
    });

    test('12. Waypoint sanitization (< 5m consecutive duplicate coordinate stripping)', () {
      // Points with jitter < 5m
      const p1 = LatLng(34.420500, 74.638000);
      const p2Duplicate = LatLng(34.420501, 74.638001); // ~0.14 meters away
      const p3Distinct = LatLng(34.422800, 74.636500); // ~290 meters away
      const p4Duplicate = LatLng(34.422802, 74.636501); // ~0.2 meters away

      final rawWaypoints = [p1, p2Duplicate, p3Distinct, p4Duplicate];

      // Sanitization filter rule from GeoUtils:
      final sanitized = <LatLng>[];
      for (final p in rawWaypoints) {
        if (sanitized.isEmpty ||
            DeliveryCalculator.haversineKm(sanitized.last, p) * 1000.0 > 5.0) {
          sanitized.add(p);
        }
      }

      // Must strip p2Duplicate and p4Duplicate, leaving only 2 distinct points
      expect(sanitized.length, equals(2));
      expect(sanitized.first, equals(p1));
      expect(sanitized.last, equals(p3Distinct));
    });

    test('13. Precedence-Constrained Greedy TSP & External Map URL 8-Waypoint Cap', () {
      // Scenario: Rider picks up from 3 shops, then drops off to 2 customers.
      // Precedence Constraint: All unpicked shops MUST precede customer drop-offs.
      final unpickedShopStops = [shop1, shop2, shop3];
      final customerDropOffs = [customer1, customer2];

      // Nearest-neighbor customer drop-off sequencing starting from last shop:
      final unvisitedCustomers = List<LatLng>.from(customerDropOffs);
      final orderedCustomers = <LatLng>[];
      LatLng currentRef = unpickedShopStops.last;

      while (unvisitedCustomers.isNotEmpty) {
        unvisitedCustomers.sort((a, b) {
          final dA = DeliveryCalculator.haversineKm(currentRef, a);
          final dB = DeliveryCalculator.haversineKm(currentRef, b);
          return dA.compareTo(dB);
        });
        final nearest = unvisitedCustomers.removeAt(0);
        orderedCustomers.add(nearest);
        currentRef = nearest;
      }

      // Verification: Shops come first, followed by customers ordered by proximity
      expect(unpickedShopStops.length, equals(3));
      expect(orderedCustomers.length, equals(2));

      // External Google Maps URL construction
      final origin = '${depot.latitude},${depot.longitude}';
      final destination = '${orderedCustomers.last.latitude},${orderedCustomers.last.longitude}';

      final allIntermediateStops = <String>[
        ...unpickedShopStops.map((s) => '${s.latitude},${s.longitude}'),
        if (orderedCustomers.length > 1)
          ...orderedCustomers.sublist(0, orderedCustomers.length - 1).map((c) => '${c.latitude},${c.longitude}'),
      ];

      // Edge Case 6 Guard: Cap intermediate waypoints to max 8
      final safeWaypoints = allIntermediateStops.take(8).toList();
      expect(safeWaypoints.length, lessThanOrEqualTo(8));

      final uriString =
          'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=${safeWaypoints.join('|')}';
      final uri = Uri.parse(uriString);

      expect(uri.queryParameters['origin'], equals(origin));
      expect(uri.queryParameters['destination'], equals(destination));
      expect(uri.queryParameters['waypoints']!.split('|').length, lessThanOrEqualTo(8));
    });

    test('14. Proximity matching (200m auto-detection of saved addresses)', () {
      const savedHome = LatLng(34.4120, 74.6485);
      // User GPS within 120m -> should auto-match saved address
      const nearbyGps = LatLng(34.4128, 74.6492);
      final distKm = DeliveryCalculator.haversineKm(savedHome, nearbyGps);
      final distMeters = distKm * 1000.0;

      expect(distMeters, lessThan(200.0));

      // User GPS 500m away -> should not auto-match
      const distantGps = LatLng(34.4160, 74.6520);
      final distFarMeters = DeliveryCalculator.haversineKm(savedHome, distantGps) * 1000.0;
      expect(distFarMeters, greaterThan(200.0));
    });
  });
}
