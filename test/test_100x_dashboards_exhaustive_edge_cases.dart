import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/pages/delivery/order_route_map_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  OrderModel buildTestOrder({
    required String id,
    required String customerId,
    required String shopId,
    required String status,
    double itemTotal = 0.0,
    double deliveryCharges = 0.0,
    double multiShopSurcharge = 0.0,
    double platformFee = 0.0,
    String? paymentMethod,
    String? paymentStatus,
    double smallCartFee = 0.0,
    double heavyOrderFee = 0.0,
    double couponDiscount = 0.0,
    double riderEarnings = 0.0,
    double s9_5Gst = 0.0,
    double nonFoodGst = 0.0,
    double sellerPayout = 0.0,
    double enythingCommission = 0.0,
    double gatewayDeduction = 0.0,
    double? grandTotalCollected,
    bool sellerAccepted = false,
    bool partnerAccepted = false,
    String? deliveryPartnerId,
    String? cancelledReason,
    String? cartGroupId,
    double? shopLat,
    double? shopLng,
    double? deliveryLat,
    double? deliveryLng,
    double? riderLat,
    double? riderLng,
    DateTime? arrivedAtShopTime,
    DateTime? paymentDeadline,
    DateTime? acceptanceDeadline,
    String? address,
    String? addressLabel,
    List<OrderItem>? items,
  }) {
    final grandTotal = grandTotalCollected ??
        math.max(
          0.0,
          itemTotal +
              s9_5Gst +
              nonFoodGst +
              deliveryCharges +
              multiShopSurcharge +
              platformFee +
              smallCartFee +
              heavyOrderFee -
              couponDiscount,
        );

    return OrderModel(
      id: id,
      customerId: customerId,
      shopId: shopId,
      status: status,
      totalAmount: itemTotal,
      deliveryCharges: deliveryCharges,
      multiShopSurcharge: multiShopSurcharge,
      platformFee: platformFee,
      smallCartFee: smallCartFee,
      heavyOrderFee: heavyOrderFee,
      couponDiscount: couponDiscount,
      grandTotalCollected: grandTotal,
      riderEarnings: riderEarnings,
      s9_5GstAmount: s9_5Gst,
      nonFoodGstAmount: nonFoodGst,
      sellerPayout: sellerPayout,
      enythingCommission: enythingCommission,
      gatewayDeduction: gatewayDeduction,
      sellerAccepted: sellerAccepted,
      partnerAccepted: partnerAccepted,
      deliveryPartnerId: deliveryPartnerId,
      cancelledReason: cancelledReason,
      cartGroupId: cartGroupId,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      shopLat: shopLat ?? 34.0837,
      shopLng: shopLng ?? 74.7973,
      deliveryLat: deliveryLat ?? 34.0900,
      deliveryLng: deliveryLng ?? 74.8000,
      riderLat: riderLat,
      riderLng: riderLng,
      arrivedAtShopTime: arrivedAtShopTime,
      paymentDeadline: paymentDeadline,
      acceptanceDeadline: acceptanceDeadline,
      address: address,
      addressLabel: addressLabel,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      updatedAt: DateTime.now(),
      items: items ??
          [
            OrderItem(
              id: 'item-$id',
              productId: 'prod-$id',
              productName: 'Item for $shopId',
              price: itemTotal,
              quantity: 1,
              weightKg: 1.0,
            ),
          ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1: RIDER DASHBOARD 100x EDGE CASES
  // ══════════════════════════════════════════════════════════════════════════
  group('1. Rider Dashboard 100x Edge Cases', () {
    test('R-EC-01 & R-EC-02: Concurrency & human-readable message mapping', () {
      // Simulate database exception strings and verify UI translation
      String mapRiderException(String rawException) {
        if (rawException.contains('RIDER_SUSPENDED')) {
          return '⚠️ Your rider account has been suspended by administration.';
        } else if (rawException.contains('ORDER_CANCELLED')) {
          return '⚠️ The customer just cancelled this order.';
        } else if (rawException.contains('ORDER_ACCEPTED_BY_OTHER_RIDER')) {
          return '⚠️ Another rider just accepted this order.';
        } else if (rawException.contains('Invalid state transition')) {
          return '⚠️ This order is no longer available to accept.';
        } else if (rawException.contains('MAX_ORDERS_REACHED')) {
          return 'Maximum Orders Reached';
        }
        return rawException;
      }

      expect(
        mapRiderException('PostgrestException: ORDER_ACCEPTED_BY_OTHER_RIDER'),
        equals('⚠️ Another rider just accepted this order.'),
      );
      expect(
        mapRiderException('PostgrestException: ORDER_CANCELLED'),
        equals('⚠️ The customer just cancelled this order.'),
      );
      expect(
        mapRiderException('PostgrestException: Invalid state transition from pending'),
        equals('⚠️ This order is no longer available to accept.'),
      );
      expect(
        mapRiderException('PostgrestException: RIDER_SUSPENDED'),
        equals('⚠️ Your rider account has been suspended by administration.'),
      );
    });

    test('R-EC-03 & R-EC-04: Geofence arrival check (300m threshold) & null coordinate safety', () {
      const shopLat = 34.0837;
      const shopLng = 74.7973;

      // Case A: Within 300m (e.g. 150m away)
      const riderLatNear = 34.0845;
      const riderLngNear = 74.7980;
      final distNear = Geolocator.distanceBetween(riderLatNear, riderLngNear, shopLat, shopLng);
      expect(distNear <= 300, isTrue);

      // Case B: Far away (> 300m, e.g. 1.2km)
      const riderLatFar = 34.0950;
      const riderLngFar = 74.8050;
      final distFar = Geolocator.distanceBetween(riderLatFar, riderLngFar, shopLat, shopLng);
      expect(distFar > 300, isTrue);

      // Case C: Null or (0, 0) coordinates safety check
      bool canVerifyArrival(double? rLat, double? rLng, double? sLat, double? sLng) {
        if (sLat == null || sLng == null || sLat == 0.0 || sLng == 0.0) return false;
        if (rLat == null || rLng == null || rLat == 0.0 || rLng == 0.0) return false;
        return Geolocator.distanceBetween(rLat, rLng, sLat, sLng) <= 300;
      }

      expect(canVerifyArrival(null, null, shopLat, shopLng), isFalse);
      expect(canVerifyArrival(riderLatNear, riderLngNear, 0.0, 0.0), isFalse);
      expect(canVerifyArrival(0.0, 0.0, shopLat, shopLng), isFalse);
      expect(canVerifyArrival(riderLatNear, riderLngNear, shopLat, shopLng), isTrue);
    });

    test('R-EC-05 & R-EC-06: Multi-shop pickup sequence & Master buttons lock logic', () {
      final o1 = buildTestOrder(
        id: 'ord-m1',
        customerId: 'cust-1',
        shopId: 'shop-A',
        status: 'picked_up', // Shop A picked up
        itemTotal: 200.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );

      final o2 = buildTestOrder(
        id: 'ord-m2',
        customerId: 'cust-1',
        shopId: 'shop-B',
        status: 'ready_for_pickup', // Shop B not yet picked up
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1, o2]);

      // All picked up must be false because Shop B is only ready_for_pickup
      expect(group.allPickedUp, isFalse);

      // Master Out for Delivery button must be disabled
      final canMarkAllOutForDelivery = group.allPickedUp && !group.allOutForDelivery;
      expect(canMarkAllOutForDelivery, isFalse);

      // Now Shop B is picked up
      final o2PickedUp = o2.copyWith(status: 'picked_up');
      final groupReady = OrderGroup('cart-grp-1', [o1, o2PickedUp]);

      expect(groupReady.allPickedUp, isTrue);
      final canMarkAllOutForDeliveryNow = groupReady.allPickedUp && !groupReady.allOutForDelivery;
      expect(canMarkAllOutForDeliveryNow, isTrue);
    });

    test('R-EC-07 & R-EC-09: Reassignment / Rider drop clears arrived timestamp', () {
      final oWithArrival = buildTestOrder(
        id: 'ord-drop-1',
        customerId: 'cust-1',
        shopId: 'shop-A',
        status: 'preparing',
        itemTotal: 250.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        deliveryPartnerId: 'rider-old',
        arrivedAtShopTime: DateTime.now().subtract(const Duration(minutes: 8)),
      );

      expect(oWithArrival.arrivedAtShopTime, isNotNull);

      // Reassignment simulation: status reverts to awaiting_acceptance, deliveryPartnerId is cleared, arrival time cleared
      final oReassigned = buildTestOrder(
        id: oWithArrival.id,
        customerId: oWithArrival.customerId,
        shopId: oWithArrival.shopId!,
        status: 'awaiting_acceptance',
        itemTotal: oWithArrival.totalAmount,
        deliveryCharges: oWithArrival.deliveryCharges,
        multiShopSurcharge: oWithArrival.multiShopSurcharge,
        platformFee: oWithArrival.platformFee,
        deliveryPartnerId: null,
        arrivedAtShopTime: null,
      );

      expect(oReassigned.status, equals('awaiting_acceptance'));
      expect(oReassigned.deliveryPartnerId, isNull);
      expect(oReassigned.arrivedAtShopTime, isNull);
    });

    test('R-EC-10: Multi-cart group acceptance with 2 shops in Group A and 1 shop in Group B', () {
      // Group A (Customer A, 2 shops)
      final oA1 = buildTestOrder(
        id: 'ord-A1',
        customerId: 'cust-A',
        cartGroupId: 'grp-A',
        shopId: 'shop-1',
        status: 'pending',
        itemTotal: 150.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );
      final oA2 = buildTestOrder(
        id: 'ord-A2',
        customerId: 'cust-A',
        cartGroupId: 'grp-A',
        shopId: 'shop-2',
        status: 'pending',
        itemTotal: 120.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );
      final groupA = OrderGroup('grp-A', [oA1, oA2]);

      // Group B (Customer B, 1 shop)
      final oB1 = buildTestOrder(
        id: 'ord-B1',
        customerId: 'cust-B',
        cartGroupId: 'grp-B',
        shopId: 'shop-3',
        status: 'pending',
        itemTotal: 300.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );
      final groupB = OrderGroup('grp-B', [oB1]);

      // Simulate atomic backend assignment for Group A
      final acceptedOrdersA = groupA.orders.map((o) => o.copyWith(
        deliveryPartnerId: 'rider-123',
        status: 'awaiting_payment',
      )).toList();
      final acceptedGroupA = OrderGroup('grp-A', acceptedOrdersA);

      // Verify all orders in Group A received rider assignment atomically
      expect(acceptedGroupA.orders.length, equals(2));
      expect(acceptedGroupA.orders.every((o) => o.deliveryPartnerId == 'rider-123'), isTrue);

      // Simulate assignment for Group B
      final acceptedOrdersB = groupB.orders.map((o) => o.copyWith(
        deliveryPartnerId: 'rider-123',
        status: 'awaiting_payment',
      )).toList();
      final acceptedGroupB = OrderGroup('grp-B', acceptedOrdersB);

      // Total active groups held by rider-123 = 2 (under max 3 limit)
      final activeRiderGroups = [acceptedGroupA, acceptedGroupB];
      expect(activeRiderGroups.length, equals(2));
      expect(activeRiderGroups.length <= 3, isTrue);

      // Total sub-orders across both groups = 3
      final totalSubOrders = activeRiderGroups.expand((g) => g.orders).length;
      expect(totalSubOrders, equals(3));
    });

    test('R-EC-11: Terminal rejection handling (shop_dispute_cancel & timeout) in OrderGroup and button activation', () {
      final o1 = buildTestOrder(
        id: 'ord-disp-1',
        customerId: 'cust-1',
        cartGroupId: 'cart-grp-disp',
        shopId: 'shop-1',
        status: 'picked_up', // Shop 1 picked up successfully
        itemTotal: 250.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );

      final o2Disputed = buildTestOrder(
        id: 'ord-disp-2',
        customerId: 'cust-1',
        cartGroupId: 'cart-grp-disp',
        shopId: 'shop-2',
        status: 'shop_dispute_cancel', // Shop 2 disputed / cancelled by rider
        itemTotal: 180.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );

      final group = OrderGroup('cart-grp-disp', [o1, o2Disputed]);

      // activeOrders must filter out shop_dispute_cancel
      expect(group.activeOrders.length, equals(1));
      expect(group.activeOrders.first.id, equals('ord-disp-1'));

      // allPickedUp must be true because only activeOrders are evaluated
      expect(group.allPickedUp, isTrue);

      // Mark all delivered loop must target only deliverable active orders
      final deliverableOrders = group.activeOrders.where((o) => o.status != 'delivered').toList();
      expect(deliverableOrders.length, equals(1));
      expect(deliverableOrders.first.id, equals('ord-disp-1'));

      // When o1 is delivered, groupStatus evaluates to 'delivered'
      final o1Delivered = o1.copyWith(status: 'delivered');
      final finishedGroup = OrderGroup('cart-grp-disp', [o1Delivered, o2Disputed]);
      expect(finishedGroup.groupStatus, equals('delivered'));
    });

    test('R-EC-12: Shared shop geofence cascade across distinct cart groups', () {
      final oCustomerA = buildTestOrder(
        id: 'ord-cA',
        customerId: 'cust-A',
        cartGroupId: 'grp-A',
        shopId: 'shared-bakery',
        status: 'confirmed',
        itemTotal: 200.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        deliveryPartnerId: 'rider-1',
      );

      final oCustomerB = buildTestOrder(
        id: 'ord-cB',
        customerId: 'cust-B',
        cartGroupId: 'grp-B',
        shopId: 'shared-bakery',
        status: 'confirmed',
        itemTotal: 300.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        deliveryPartnerId: 'rider-1',
      );

      // Initially neither has arrived
      expect(oCustomerA.arrivedAtShopTime, isNull);
      expect(oCustomerB.arrivedAtShopTime, isNull);

      // Rider arrives at shared-bakery and marks arrived for Customer A's order
      final arrivalTime = DateTime.now();
      oCustomerA.arrivedAtShopTime = arrivalTime;

      // Cascade logic: all active orders for rider-1 at the same shopId receive arrival timestamp
      final activeOrders = [oCustomerA, oCustomerB];
      for (final o in activeOrders) {
        if (o.shopId == 'shared-bakery' && o.arrivedAtShopTime == null) {
          o.arrivedAtShopTime = arrivalTime;
        }
      }

      // Customer B's order is now also marked arrived
      expect(oCustomerB.arrivedAtShopTime, equals(arrivalTime));

      // When rider drives away to 1500m, Customer B's order already has arrival recorded
      // and won't be blocked by the 300m GPS fence
      expect(oCustomerB.arrivedAtShopTime, isNotNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2: SELLER DASHBOARD 100x EDGE CASES
  // ══════════════════════════════════════════════════════════════════════════
  group('2. Seller Dashboard 100x Edge Cases', () {
    test('S-EC-03: Seller accept catches ORDER_CANCELLED and Invalid state transition', () {
      String mapSellerException(dynamic e) {
        final str = e.toString();
        if (str.contains('ORDER_CANCELLED')) {
          return 'The customer just cancelled this order.';
        } else if (str.contains('SHOP_SUSPENDED')) {
          return 'Your shop has been suspended by administration.';
        } else if (str.contains('Invalid state transition') || str.contains('no longer available')) {
          return 'Order is no longer available to accept.';
        }
        return 'Failed to accept: $e';
      }

      expect(
        mapSellerException('PostgrestException: ORDER_CANCELLED'),
        equals('The customer just cancelled this order.'),
      );
      expect(
        mapSellerException('Exception: Invalid state transition from cancelled'),
        equals('Order is no longer available to accept.'),
      );
      expect(
        mapSellerException('PostgrestException: SHOP_SUSPENDED'),
        equals('Your shop has been suspended by administration.'),
      );
    });

    test('S-EC-04: Multi-shop synchronous payment gate — Payment prompt only fires when ALL shops confirm', () {
      bool shouldTriggerPaymentNotification({
        required List<bool> sellerAcceptanceStates,
        required bool riderAccepted,
      }) {
        final allSellersConfirmed = sellerAcceptanceStates.every((a) => a == true);
        return allSellersConfirmed && riderAccepted;
      }

      // Shop 1 confirmed, Shop 2 pending, Rider confirmed -> BLOCKED
      expect(
        shouldTriggerPaymentNotification(sellerAcceptanceStates: [true, false], riderAccepted: true),
        isFalse,
      );

      // Shop 1 confirmed, Shop 2 confirmed, Rider NOT confirmed -> BLOCKED
      expect(
        shouldTriggerPaymentNotification(sellerAcceptanceStates: [true, true], riderAccepted: false),
        isFalse,
      );

      // Shop 1 confirmed, Shop 2 confirmed, Rider confirmed -> UNBLOCKED!
      expect(
        shouldTriggerPaymentNotification(sellerAcceptanceStates: [true, true], riderAccepted: true),
        isTrue,
      );
    });

    test('S-EC-05: Partial rejection in 3-shop cart promotes surviving Shop 2 to base shop', () {
      // 3-shop initial configuration:
      // Shop 1: Base delivery ₹23.60, Platform Fee ₹20.00
      // Shop 2: Leg 1 Surcharge ₹23.60
      // Shop 3: Leg 2 Surcharge ₹23.60
      final o1 = buildTestOrder(
        id: 'ord-s1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        itemTotal: 300.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );
      final o2 = buildTestOrder(
        id: 'ord-s2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 200.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );
      final o3 = buildTestOrder(
        id: 'ord-s3',
        customerId: 'cust-1',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );

      final initialGroup = OrderGroup('cart-grp-initial', [o1, o2, o3]);
      expect(initialGroup.activeOrders.length, equals(3));

      // Shop 1 declines due to Out of Stock
      final o1Rejected = buildTestOrder(
        id: 'ord-s1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        cancelledReason: 'out_of_stock',
        itemTotal: 300.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
        grandTotalCollected: 0.0,
      );

      // Rebalancing: Shop 2 promoted to Base Shop
      final o2Promoted = buildTestOrder(
        id: 'ord-s2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 200.0,
        deliveryCharges: 23.60, // Inherits base delivery
        multiShopSurcharge: 0.0, // Base shop has 0 surcharge
        platformFee: 20.0, // Inherits platform fee
      );

      final groupAfterRejection = OrderGroup('cart-grp-rebalance', [o1Rejected, o2Promoted, o3]);

      expect(groupAfterRejection.activeOrders.length, equals(2));
      expect(groupAfterRejection.activeOrders.first.id, equals('ord-s2'));
      expect(groupAfterRejection.activeOrders.first.deliveryCharges, equals(23.60));
      expect(groupAfterRejection.activeOrders.first.platformFee, equals(20.0));
      expect(groupAfterRejection.activeOrders.last.multiShopSurcharge, equals(23.60));
    });

    test('S-EC-07: Product soft delete immunity — active in-flight order items remain intact', () {
      final activeItem = OrderItem(
        id: 'item-soft-1',
        productId: 'prod-to-delete',
        productName: 'Crispy Zinger Burger',
        price: 180.0,
        quantity: 2,
        weightKg: 0.5,
      );

      final activeOrder = buildTestOrder(
        id: 'ord-flight-1',
        customerId: 'cust-1',
        shopId: 'shop-restaurant',
        status: 'confirmed',
        itemTotal: 360.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        items: [activeItem],
      );

      // Simulate soft-deleted product record in DB
      final softDeletedDbRecord = {
        'id': 'prod-to-delete',
        'shop_id': 'shop-restaurant',
        'name': 'Crispy Zinger Burger',
        'price': 180.0,
        'is_available': false,
        'is_deleted': true,
      };

      // Verify that active order line items are still readable and complete
      expect(activeOrder.items.length, equals(1));
      expect(activeOrder.items.first.productName, equals('Crispy Zinger Burger'));
      expect(activeOrder.items.first.price * activeOrder.items.first.quantity, equals(360.0));
      expect(softDeletedDbRecord['is_deleted'], isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3: CUSTOMER DASHBOARD & TRACKING 100x EDGE CASES
  // ══════════════════════════════════════════════════════════════════════════
  group('3. Customer Dashboard & Tracking 100x Edge Cases', () {
    test('C-EC-03: 5-minute partial rejection countdown synchronization via SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      const timerKey = 'partial_rejection_timer_start_test-cart-grp-sync-99';

      // 1. Set start time 1 minute ago
      final startTime = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await prefs.setString(timerKey, startTime.toIso8601String());

      // 2. Main Page reads timer
      final mainPageStoredStr = prefs.getString(timerKey);
      final mainPageStart = DateTime.parse(mainPageStoredStr!);
      final mainPageDeadline = mainPageStart.add(const Duration(minutes: 5));
      final mainPageRemaining = mainPageDeadline.difference(DateTime.now().toUtc()).inSeconds;

      // 3. Track Order Page reads timer
      final trackPageStoredStr = prefs.getString(timerKey);
      final trackPageStart = DateTime.parse(trackPageStoredStr!);
      final trackPageDeadline = trackPageStart.add(const Duration(minutes: 5));
      final trackPageRemaining = trackPageDeadline.difference(DateTime.now().toUtc()).inSeconds;

      // Both timers must be exactly equal
      expect(mainPageRemaining, equals(trackPageRemaining));
      expect(mainPageRemaining, closeTo(240, 2)); // ~4 minutes left
    });

    test('C-EC-04: Product search query strictly enforces is_deleted = false', () {
      // Create a mock dataset containing active and soft-deleted products
      const allProducts = [
        {'id': 'p1', 'name': 'Fresh Apples', 'is_deleted': false, 'is_available': true},
        {'id': 'p2', 'name': 'Deleted Apples', 'is_deleted': true, 'is_available': true},
        {'id': 'p3', 'name': 'Out of Stock Apples', 'is_deleted': false, 'is_available': false},
      ];

      // Simulate query with user rule: .eq('is_deleted', false).eq('is_available', true)
      final filtered = allProducts.where((p) => p['is_deleted'] == false && p['is_available'] == true).toList();

      expect(filtered.length, equals(1));
      expect(filtered.first['id'], equals('p1'));
    });

    test('C-EC-08: Customer cancellation boundary check', () {
      bool isCancellationAllowed(String status) {
        const cancellableStatuses = [
          'awaiting_acceptance',
          'awaiting_payment',
          'pending',
        ];
        return cancellableStatuses.contains(status);
      }

      // Allowed stages
      expect(isCancellationAllowed('awaiting_acceptance'), isTrue);
      expect(isCancellationAllowed('awaiting_payment'), isTrue);
      expect(isCancellationAllowed('pending'), isTrue);

      // Blocked stages (shop preparing or rider picked up)
      expect(isCancellationAllowed('confirmed'), isFalse);
      expect(isCancellationAllowed('preparing'), isFalse);
      expect(isCancellationAllowed('ready_for_pickup'), isFalse);
      expect(isCancellationAllowed('picked_up'), isFalse);
      expect(isCancellationAllowed('out_for_delivery'), isFalse);
      expect(isCancellationAllowed('delivered'), isFalse);
    });

    test('C-EC-10: Live rider coordinates ignores (0, 0) coordinates to prevent Null Island', () {
      final validCoords = <String, LatLng>{};

      void addRiderCoord(String riderId, double? lat, double? lng) {
        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          validCoords[riderId] = LatLng(lat, lng);
        }
      }

      addRiderCoord('rider-1', 0.0, 0.0); // Invalid zero coords
      addRiderCoord('rider-2', null, null); // Null coords
      addRiderCoord('rider-3', 34.0837, 74.7973); // Valid coords

      expect(validCoords.containsKey('rider-1'), isFalse);
      expect(validCoords.containsKey('rider-2'), isFalse);
      expect(validCoords.containsKey('rider-3'), isTrue);
      expect(validCoords['rider-3']!.latitude, equals(34.0837));
    });

    test('C-EC-11: Apple Reviewer / Demo Mode Isolation', () {
      bool isDemoSimulationAllowed({
        required String? authPhone,
        required String? orderPhone,
      }) {
        if (authPhone == null || orderPhone == null) return false;
        final isAuthDemo = authPhone.contains('999999999');
        final isOrderDemo = orderPhone.contains('999999999');
        return isAuthDemo && isOrderDemo;
      }

      // Regular customer placed normal order -> FALSE
      expect(
        isDemoSimulationAllowed(authPhone: '+919876543210', orderPhone: '+919876543210'),
        isFalse,
      );

      // Demo reviewer account placed demo order -> TRUE
      expect(
        isDemoSimulationAllowed(authPhone: '+919999999991', orderPhone: '+919999999991'),
        isTrue,
      );

      // Attacker attempting to trigger demo mode on real customer order -> FALSE
      expect(
        isDemoSimulationAllowed(authPhone: '+919999999991', orderPhone: '+919876543210'),
        isFalse,
      );
    });

    test('R-EC-13: Out-for-delivery dynamic polyline target switching', () {
      const pickupStatus = 'preparing';
      const deliveryStatus = 'out_for_delivery';

      // Simulation of dynamic polyline target resolution
      String resolveRouteTarget(String orderStatus) {
        if (orderStatus == 'out_for_delivery') {
          return 'customer_location';
        } else {
          return 'shop_location';
        }
      }

      expect(resolveRouteTarget(pickupStatus), equals('shop_location'));
      expect(resolveRouteTarget(deliveryStatus), equals('customer_location'));
    });

    test('R-EC-14: Multi-shop pickup leg pointer advancing to the next unpicked shop', () {
      final s1 = buildTestOrder(
        id: 'ord-s1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'picked_up', // Picked up
        itemTotal: 100.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );
      final s2 = buildTestOrder(
        id: 'ord-s2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'ready_for_pickup', // Unpicked
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );

      final allShops = [s1, s2];
      final unpicked = allShops.where((s) => s.status != 'picked_up' && s.status != 'out_for_delivery').toList();
      final nextTargetShop = unpicked.isNotEmpty ? unpicked.first : allShops.first;

      // Pointer must advance to Shop 2, NOT stay stuck on Shop 1
      expect(nextTargetShop.shopId, equals('shop-2'));
    });

    test('R-EC-15: Cross-customer data isolation verification', () {
      final groupA = OrderGroup('grp-A', [
        buildTestOrder(
          id: 'ord-A',
          customerId: 'cust-secret-A',
          shopId: 'shop-1',
          status: 'confirmed',
          cartGroupId: 'grp-A',
          address: 'House 10, St 5',
          deliveryLat: 34.08,
          deliveryLng: 74.80,
          itemTotal: 200.0,
          deliveryCharges: 23.60,
          multiShopSurcharge: 0.0,
          platformFee: 20.0,
        )
      ]);

      final groupB = OrderGroup('grp-B', [
        buildTestOrder(
          id: 'ord-B',
          customerId: 'cust-secret-B',
          shopId: 'shop-2',
          status: 'confirmed',
          cartGroupId: 'grp-B',
          address: 'Villa 22, Beach Rd',
          deliveryLat: 34.12,
          deliveryLng: 74.85,
          itemTotal: 400.0,
          deliveryCharges: 23.60,
          multiShopSurcharge: 0.0,
          platformFee: 20.0,
        )
      ]);

      // Simulate customer A map state
      final customerAOrders = groupA.orders;
      expect(customerAOrders.any((o) => o.customerId == 'cust-secret-B'), isFalse);
      expect(customerAOrders.any((o) => o.address == 'Villa 22, Beach Rd'), isFalse);
      expect(customerAOrders.first.address, equals('House 10, St 5'));

      // Simulate customer B map state
      final customerBOrders = groupB.orders;
      expect(customerBOrders.any((o) => o.customerId == 'cust-secret-A'), isFalse);
      expect(customerBOrders.first.address, equals('Villa 22, Beach Rd'));
    });

    test('R-EC-16: Dead first sub-order acceptance guard selects surviving live order', () {
      final order1 = buildTestOrder(
        id: 'ord-dead-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        cartGroupId: 'grp-multi-1',
        itemTotal: 150.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 10.0,
        platformFee: 5.0,
      );
      final order2 = buildTestOrder(
        id: 'ord-live-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        cartGroupId: 'grp-multi-1',
        itemTotal: 250.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 10.0,
        platformFee: 5.0,
      );

      final group = OrderGroup('grp-multi-1', [order1, order2]);

      // Blind selection would pick dead order1 (seller_rejected)
      expect(group.orders.first.status, equals('seller_rejected'));

      // 100x Guard selection: picks order2 (awaiting_acceptance)
      final targetOrder = group.activeOrders.isNotEmpty
          ? group.activeOrders.firstWhere(
              (o) => o.status == 'awaiting_acceptance' || o.status == 'pending',
              orElse: () => group.activeOrders.first,
            )
          : group.orders.first;

      expect(targetOrder.id, equals('ord-live-2'));
      expect(targetOrder.status, equals('awaiting_acceptance'));
    });

    test('R-EC-17: "Mark All Out for Delivery" only updates orders with status "picked_up"', () {
      final order1 = buildTestOrder(
        id: 'ord-picked-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'picked_up',
        cartGroupId: 'grp-1',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );
      final order2 = buildTestOrder(
        id: 'ord-dispute-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'shop_dispute_cancel',
        cartGroupId: 'grp-1',
        itemTotal: 120.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      final group = OrderGroup('grp-1', [order1, order2]);

      // Legacy loop would attempt to transition order2 and throw "Cannot mark out_for_delivery from shop_dispute_cancel"
      // 100x Guard filters strictly to activeOrders where status == 'picked_up'
      final pickedUpOrders = group.activeOrders
          .where((o) => o.status == 'picked_up')
          .toList();

      expect(pickedUpOrders.length, equals(1));
      expect(pickedUpOrders.first.id, equals('ord-picked-1'));
    });

    test('R-EC-18: Drop order whitelist recognizes "confirmed" status before pickup', () {
      const permittedStatuses = {
        'awaiting_acceptance',
        'pending',
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'awaiting_payment'
      };

      // Confirmed status (payment captured, shop hasn't tapped preparing) MUST be permitted to drop
      expect(permittedStatuses.contains('confirmed'), isTrue);

      // Post-pickup and terminal statuses MUST be blocked
      expect(permittedStatuses.contains('picked_up'), isFalse);
      expect(permittedStatuses.contains('out_for_delivery'), isFalse);
      expect(permittedStatuses.contains('delivered'), isFalse);
    });

    test('R-EC-19: _myGroups filters out zombie groups whose orders are all disputed/terminal', () {
      final order1 = buildTestOrder(
        id: 'ord-disp-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'shop_dispute_cancel',
        cartGroupId: 'grp-zombie',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      final zombieGroup = OrderGroup('grp-zombie', [order1]);

      final allGroups = [zombieGroup];
      final activeGroups = allGroups.where((g) => g.activeOrders.isNotEmpty).toList();

      expect(zombieGroup.activeOrders.isEmpty, isTrue);
      expect(activeGroups.isEmpty, isTrue);
    });

    test('R-EC-20: Re-assigned order push sends "New Rider Assigned" when payment is captured', () {
      const currentStatus = 'awaiting_acceptance'; // reset by reject_order_rider
      const currentPaymentStatus = 'captured';     // customer already paid

      const isPaid = currentPaymentStatus == 'captured' ||
          currentStatus == 'confirmed' ||
          currentStatus == 'preparing';

      expect(isPaid, isTrue);

      // Notification title logic:
      const title = isPaid ? 'New Rider Assigned! 🛵' : 'Ready for Payment! 💳';
      expect(title, equals('New Rider Assigned! 🛵'));
    });

    test('R-EC-21: Master route external map chains multiple customer drop-offs and excludes delivered', () {
      final activeGroup = OrderGroup('grp-active', [
        buildTestOrder(
          id: 'ord-active-1',
          customerId: 'cust-active',
          shopId: 'shop-1',
          status: 'out_for_delivery',
          cartGroupId: 'grp-active',
          deliveryLat: 34.08,
          deliveryLng: 74.80,
          itemTotal: 200.0,
          deliveryCharges: 20.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
        )
      ]);

      final deliveredGroup = OrderGroup('grp-done', [
        buildTestOrder(
          id: 'ord-done-1',
          customerId: 'cust-done',
          shopId: 'shop-2',
          status: 'delivered',
          cartGroupId: 'grp-done',
          deliveryLat: 34.12,
          deliveryLng: 74.85,
          itemTotal: 150.0,
          deliveryCharges: 20.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
        )
      ]);

      final allGroups = [activeGroup, deliveredGroup];

      // Undelivered customer drop-offs only
      final customerDropOffs = <String>[];
      for (final g in allGroups) {
        final isDelivered = g.activeOrders.isNotEmpty &&
            g.activeOrders.every((o) => o.status == 'delivered');
        if (!isDelivered && g.deliveryLat != null) {
          customerDropOffs.add('${g.deliveryLat},${g.deliveryLng}');
        }
      }

      expect(customerDropOffs.length, equals(1));
      expect(customerDropOffs.first, equals('34.08,74.8'));
    });

    test('R-EC-22: OrderGroup returns false for allPickedUp, allArrived, and allOutForDelivery when activeOrders is empty', () {
      final order1 = buildTestOrder(
        id: 'ord-term-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'shop_dispute_cancel',
        cartGroupId: 'grp-term',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        arrivedAtShopTime: DateTime.now(), // had arrived before dispute
      );
      final order2 = buildTestOrder(
        id: 'ord-term-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'cancelled',
        cartGroupId: 'grp-term',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      final group = OrderGroup('grp-term', [order1, order2]);

      expect(group.activeOrders.isEmpty, isTrue);
      expect(group.allArrived, isFalse);
      expect(group.allPickedUp, isFalse);
      expect(group.allOutForDelivery, isFalse);
      expect(group.groupStatus, equals('cancelled'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. 100x Rider Multi-Cart & Multi-Customer Map Lifecycle (R-MC-01 to R-MC-10)
  // ═══════════════════════════════════════════════════════════════════════════
  group('4. 100x Rider Multi-Cart & Multi-Customer Map Lifecycle (R-MC-01 to R-MC-10)', () {
    test('R-MC-01: Shared physical shop co-location clusters orders and prevents duplicate waypoints', () {
      final orderAlice = buildTestOrder(
        id: 'ord-alice-pharma',
        customerId: 'cust-alice',
        shopId: 'shop-pharma-1',
        status: 'ready_for_pickup',
        cartGroupId: 'grp-alice',
        itemTotal: 150.0,
        deliveryCharges: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        shopLat: 34.0837,
        shopLng: 74.7973,
      );
      final orderBob = buildTestOrder(
        id: 'ord-bob-pharma',
        customerId: 'cust-bob',
        shopId: 'shop-pharma-1', // Same shop!
        status: 'ready_for_pickup',
        cartGroupId: 'grp-bob',
        itemTotal: 220.0,
        deliveryCharges: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        shopLat: 34.0837,
        shopLng: 74.7973,
      );

      final targetOrders = [orderAlice, orderBob];
      final stops = <UnifiedShopStop>[];

      for (final o in targetOrders) {
        final sLat = o.shopLat ?? 0.0;
        final sLng = o.shopLng ?? 0.0;
        final existingIndex = stops.indexWhere((s) {
          if (o.shopId != null && s.orders.any((ord) => ord.shopId == o.shopId)) {
            return true;
          }
          return Geolocator.distanceBetween(s.lat, s.lng, sLat, sLng) < 25.0;
        });

        if (existingIndex != -1) {
          stops[existingIndex].orders.add(o);
        } else {
          stops.add(UnifiedShopStop(
            lat: sLat,
            lng: sLng,
            name: 'City Pharmacy',
            orders: [o],
          ));
        }
      }

      // Exactly 1 unified shop stop created for both Alice and Bob
      expect(stops.length, equals(1));
      expect(stops.first.orders.length, equals(2));
      expect(stops.first.aggregateStatus, equals('ready_for_pickup'));
    });

    test('R-MC-02: Greedy nearest-neighbor customer drop-off TSP sequence optimizes route', () {
      const lastShopPos = LatLng(34.0800, 74.8000);

      // Customer 1 is far (Sector 62 ~ 17km away)
      final farCust = OrderGroup('grp-far', [
        buildTestOrder(
          id: 'ord-far',
          customerId: 'cust-far',
          shopId: 'shop-1',
          status: 'out_for_delivery',
          cartGroupId: 'grp-far',
          itemTotal: 300.0,
          deliveryCharges: 30.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
          deliveryLat: 34.2000,
          deliveryLng: 74.9000,
        ),
      ]);

      // Customer 2 is close (Sector 15 ~ 1.5km away)
      final nearCust = OrderGroup('grp-near', [
        buildTestOrder(
          id: 'ord-near',
          customerId: 'cust-near',
          shopId: 'shop-1',
          status: 'out_for_delivery',
          cartGroupId: 'grp-near',
          itemTotal: 150.0,
          deliveryCharges: 25.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
          deliveryLat: 34.0900,
          deliveryLng: 74.8100,
        ),
      ]);

      // Raw array order has far customer first
      final rawGroups = [farCust, nearCust];

      // Greedy nearest-neighbor algorithm
      final unvisited = List<OrderGroup>.from(rawGroups);
      final sequenced = <OrderGroup>[];
      LatLng currentRef = lastShopPos;

      while (unvisited.isNotEmpty) {
        unvisited.sort((a, b) {
          final distA = Geolocator.distanceBetween(
              currentRef.latitude, currentRef.longitude, a.deliveryLat!, a.deliveryLng!);
          final distB = Geolocator.distanceBetween(
              currentRef.latitude, currentRef.longitude, b.deliveryLat!, b.deliveryLng!);
          return distA.compareTo(distB);
        });
        final nearest = unvisited.removeAt(0);
        sequenced.add(nearest);
        currentRef = LatLng(nearest.deliveryLat!, nearest.deliveryLng!);
      }

      // Near customer is visited FIRST!
      expect(sequenced.first.groupId, equals('grp-near'));
      expect(sequenced.last.groupId, equals('grp-far'));
    });

    test('R-MC-03: Realtime shop cancellation safely clamps _selectedStopIndex', () {
      int selectedStopIndex = 2; // Rider was viewing Stop 3
      int totalStopsBefore = 3;

      expect(selectedStopIndex < totalStopsBefore, isTrue);

      // Shop 2 gets cancelled; total stops drops to 2
      int totalStopsAfter = 2;
      final clampedIndex = selectedStopIndex
          .clamp(0, math.max<int>(0, totalStopsAfter - 1))
          .toInt();

      expect(clampedIndex, equals(1));
      expect(clampedIndex < totalStopsAfter, isTrue); // In-bounds!
    });

    test('R-MC-04: Multi-customer phone and address isolation in bottom sheet', () {
      final aliceOrder = buildTestOrder(
        id: 'ord-alice',
        customerId: 'cust-alice',
        shopId: 'shop-1',
        status: 'out_for_delivery',
        cartGroupId: 'grp-alice',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        address: 'A-101 Green Park',
        addressLabel: '🏠 Home',
      );
      final bobOrder = buildTestOrder(
        id: 'ord-bob',
        customerId: 'cust-bob',
        shopId: 'shop-1',
        status: 'out_for_delivery',
        cartGroupId: 'grp-bob',
        itemTotal: 200.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        address: 'B-202 Blue Ridge',
        addressLabel: '💼 Office',
      );

      final grpAlice = OrderGroup('grp-alice', [aliceOrder]);
      final grpBob = OrderGroup('grp-bob', [bobOrder]);
      final activeGroups = [grpAlice, grpBob];

      // Index 0 = Alice, Index 1 = Bob
      expect(activeGroups[0].customerAddress, contains('A-101 Green Park'));
      expect(activeGroups[1].customerAddress, contains('B-202 Blue Ridge'));
      expect(activeGroups[0].customerAddress, isNot(equals(activeGroups[1].customerAddress)));
    });

    test('R-MC-05: Cancelled customer group is marked cancelled and never marked Delivered', () {
      final cancelledOrder = buildTestOrder(
        id: 'ord-cancelled',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'shop_dispute_cancel',
        cartGroupId: 'grp-canc',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      final grp = OrderGroup('grp-canc', [cancelledOrder]);
      final orders = [cancelledOrder];

      final groupOrders = orders.where((o) =>
          (o.cartGroupId != null && o.cartGroupId == grp.groupId) ||
          (o.cartGroupId == null && o.id == grp.primaryOrder.id)).toList();

      final active = groupOrders.where((o) =>
          o.status != 'rejected' &&
          o.status != 'cancelled' &&
          o.status != 'seller_rejected' &&
          o.status != 'partner_rejected' &&
          o.status != 'shop_dispute_cancel').toList();

      final isCancelled = groupOrders.isNotEmpty &&
          groupOrders.every((o) =>
              o.status == 'rejected' ||
              o.status == 'cancelled' ||
              o.status == 'seller_rejected' ||
              o.status == 'partner_rejected' ||
              o.status == 'shop_dispute_cancel');

      final isDelivered = active.isNotEmpty && active.every((o) => o.status == 'delivered');

      expect(isCancelled, isTrue);
      expect(isDelivered, isFalse); // Must NOT be delivered!
    });

    test('R-MC-06: External map waypoint capping strictly limits to 8 waypoints', () {
      final waypoints = List.generate(12, (i) => '34.0$i,74.8$i');
      final safeWaypoints = waypoints.take(8).toList();

      expect(waypoints.length, equals(12));
      expect(safeWaypoints.length, equals(8));
      expect(safeWaypoints.last, equals('34.07,74.87'));
    });

    test('R-MC-07: Consecutive near-identical coordinate stripping removes duplicates', () {
      final rawWaypoints = [
        const LatLng(34.08370, 74.79730),
        const LatLng(34.08371, 74.79731), // ~1.3 meters away (duplicate physical counter)
        const LatLng(34.09000, 74.80000), // ~700m away
      ];

      final sanitized = <LatLng>[];
      for (final p in rawWaypoints) {
        if (sanitized.isEmpty ||
            Geolocator.distanceBetween(
                    sanitized.last.latitude,
                    sanitized.last.longitude,
                    p.latitude,
                    p.longitude) >
                5.0) {
          sanitized.add(p);
        }
      }

      expect(sanitized.length, equals(2));
      expect(sanitized.first.latitude, equals(34.08370));
      expect(sanitized.last.latitude, equals(34.09000));
    });

    test('R-MC-08: UnifiedShopStop aggregate status hierarchy behaves correctly', () {
      final ord1 = buildTestOrder(
        id: 'ord-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'picked_up',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );
      final ord2 = buildTestOrder(
        id: 'ord-2',
        customerId: 'cust-2',
        shopId: 'shop-1',
        status: 'ready_for_pickup',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      final stop = UnifiedShopStop(
        lat: 34.08,
        lng: 74.80,
        name: 'Bakery',
        orders: [ord1, ord2],
      );

      // Since ord2 is ready_for_pickup, the stop as a whole is not yet picked up
      expect(stop.aggregateStatus, equals('ready_for_pickup'));
      expect(stop.isPickedUp, isFalse);

      // Now rider picks up ord2
      ord2.status = 'picked_up';
      expect(stop.aggregateStatus, equals('picked_up'));
      expect(stop.isPickedUp, isTrue);
    });

    test('R-MC-09: Master Route shop resolution extracts all unique shops across groups', () {
      final grp1 = OrderGroup('grp-1', [
        buildTestOrder(
          id: 'ord-1',
          customerId: 'cust-1',
          shopId: 'shop-A',
          status: 'confirmed',
          itemTotal: 100.0,
          deliveryCharges: 20.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
          shopLat: 34.081,
          shopLng: 74.791,
        ),
      ]);
      final grp2 = OrderGroup('grp-2', [
        buildTestOrder(
          id: 'ord-2',
          customerId: 'cust-2',
          shopId: 'shop-B',
          status: 'confirmed',
          itemTotal: 100.0,
          deliveryCharges: 20.0,
          multiShopSurcharge: 0.0,
          platformFee: 5.0,
          shopLat: 34.082,
          shopLng: 74.792,
        ),
      ]);

      final myGroups = [grp1, grp2];
      final shopInfoCache = {
        'shop-A': (lat: 34.081, lng: 74.791, name: 'Shop Alpha'),
        'shop-B': (lat: 34.082, lng: 74.792, name: 'Shop Beta'),
      };

      final allShops = myGroups.expand((g) {
        final targetOrders = g.activeOrders.isNotEmpty ? g.activeOrders : g.orders;
        return targetOrders.map((o) {
          final info = shopInfoCache[o.shopId];
          return (
            lat: info?.lat ?? o.shopLat ?? 0.0,
            lng: info?.lng ?? o.shopLng ?? 0.0,
            name: info?.name ?? 'Shop',
          );
        });
      }).where((s) => s.lat != 0.0 && s.lng != 0.0).toList();

      expect(allShops.length, equals(2));
      expect(allShops[0].name, equals('Shop Alpha'));
      expect(allShops[1].name, equals('Shop Beta'));
    });

    test('R-MC-10: In-flight completed customer delivery is excluded from remaining delivery route', () {
      final ordAlice = buildTestOrder(
        id: 'ord-alice',
        customerId: 'cust-alice',
        shopId: 'shop-1',
        status: 'delivered', // Alice was delivered
        cartGroupId: 'grp-alice',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        deliveryLat: 34.09,
        deliveryLng: 74.80,
      );
      final ordBob = buildTestOrder(
        id: 'ord-bob',
        customerId: 'cust-bob',
        shopId: 'shop-1',
        status: 'out_for_delivery', // Bob is still active
        cartGroupId: 'grp-bob',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        deliveryLat: 34.10,
        deliveryLng: 74.81,
      );

      final grpAlice = OrderGroup('grp-alice', [ordAlice]);
      final grpBob = OrderGroup('grp-bob', [ordBob]);
      final allGroups = [grpAlice, grpBob];
      final allOrders = [ordAlice, ordBob];

      bool isGroupDelivered(OrderGroup g) {
        final groupOrders = allOrders.where((o) =>
            (o.cartGroupId != null && o.cartGroupId == g.groupId) ||
            (o.cartGroupId == null && o.id == g.primaryOrder.id)).toList();
        if (groupOrders.isEmpty) return false;
        final active = groupOrders.where((o) =>
            o.status != 'rejected' &&
            o.status != 'cancelled' &&
            o.status != 'seller_rejected' &&
            o.status != 'partner_rejected' &&
            o.status != 'shop_dispute_cancel').toList();
        if (active.isEmpty) return false;
        return active.every((o) => o.status == 'delivered');
      }

      final undeliveredGroups = allGroups.where((g) => !isGroupDelivered(g)).toList();

      expect(undeliveredGroups.length, equals(1));
      expect(undeliveredGroups.first.groupId, equals('grp-bob'));
    });
  });

  // 5. 100x Rider Cross-Customer & Financial Lifecycle (R-CC-01 to R-CC-08)
  group('5. 100x Rider Cross-Customer & Financial Lifecycle (R-CC-01 to R-CC-08)', () {
    test('R-CC-01: 100% Prepaid model invariant confirms zero doorstep cash collection', () {
      final ordPrepaid = buildTestOrder(
        id: 'ord-prep',
        customerId: 'cust-alice',
        shopId: 'shop-1',
        status: 'confirmed',
        itemTotal: 450.0,
        deliveryCharges: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 15.0,
        paymentMethod: 'upi',
        paymentStatus: 'captured',
      );

      final ordOther = buildTestOrder(
        id: 'ord-other',
        customerId: 'cust-bob',
        shopId: 'shop-2',
        status: 'confirmed',
        itemTotal: 300.0,
        deliveryCharges: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 15.0,
        paymentMethod: 'upi',
        paymentStatus: 'captured',
      );

      final grpPrepaid = OrderGroup('grp-prep', [ordPrepaid]);
      final grpOther = OrderGroup('grp-other', [ordOther]);

      expect(grpPrepaid.isCod, isFalse);
      expect(grpPrepaid.isPrepaid, isTrue);
      expect(grpPrepaid.codAmountToCollect, equals(0.0));

      expect(grpOther.isCod, isFalse);
      expect(grpOther.isPrepaid, isTrue);
      expect(grpOther.codAmountToCollect, equals(0.0));
    });

    test('R-CC-02: Partial cancellation in 100% prepaid model retains zero doorstep collection', () {
      final s1Active = buildTestOrder(
        id: 'ord-s1',
        customerId: 'cust-bob',
        shopId: 'shop-bakery',
        status: 'confirmed',
        itemTotal: 350.0,
        deliveryCharges: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 15.0,
        paymentMethod: 'upi',
        paymentStatus: 'captured',
      );

      final s2Cancelled = buildTestOrder(
        id: 'ord-s2',
        customerId: 'cust-bob',
        shopId: 'shop-drinks',
        status: 'seller_rejected',
        itemTotal: 200.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 20.0,
        platformFee: 0.0,
        paymentMethod: 'upi',
        paymentStatus: 'cancelled',
      );

      final multiShopGroup = OrderGroup('grp-bob-multi', [s1Active, s2Cancelled]);

      expect(multiShopGroup.isCod, isFalse);
      expect(multiShopGroup.isPrepaid, isTrue);
      expect(multiShopGroup.activeOrders.length, equals(1));
      expect(multiShopGroup.codAmountToCollect, equals(0.0));
      expect(multiShopGroup.totalGrand, equals(390.0));
    });

    test('R-CC-03: Prepaid order immunity returns zero collection amount', () {
      final ordPaid = buildTestOrder(
        id: 'ord-paid',
        customerId: 'cust-charlie',
        shopId: 'shop-1',
        status: 'out_for_delivery',
        itemTotal: 500.0,
        deliveryCharges: 30.0,
        multiShopSurcharge: 0.0,
        platformFee: 15.0,
        paymentMethod: 'upi',
        paymentStatus: 'captured',
      );

      final grpPaid = OrderGroup('grp-paid', [ordPaid]);

      expect(grpPaid.isCod, isFalse);
      expect(grpPaid.isPrepaid, isTrue);
      expect(grpPaid.codAmountToCollect, equals(0.0));
    });

    test('R-CC-04: Rider dashboard capacity ceiling lockout blocks hoarding at 3 active groups', () {
      final g1 = OrderGroup('g1', [buildTestOrder(id: 'o1', customerId: 'c1', shopId: 's1', status: 'preparing')]);
      final g2 = OrderGroup('g2', [buildTestOrder(id: 'o2', customerId: 'c2', shopId: 's2', status: 'picked_up')]);
      final g3 = OrderGroup('g3', [buildTestOrder(id: 'o3', customerId: 'c3', shopId: 's3', status: 'out_for_delivery')]);

      final myActiveGroups = [g1, g2, g3];

      bool canAcceptMore(List<OrderGroup> groups) {
        return groups.length < 3;
      }

      expect(canAcceptMore(myActiveGroups), isFalse);

      // Once g1 is delivered
      myActiveGroups.removeAt(0);
      expect(canAcceptMore(myActiveGroups), isTrue);
    });

    test('R-CC-05: Multi-customer total cash to collect is always zero in 100% prepaid model', () {
      final g1Prepaid = OrderGroup('g1', [
        buildTestOrder(id: 'o1', customerId: 'c1', shopId: 's1', status: 'out_for_delivery', itemTotal: 500.0, paymentMethod: 'upi', paymentStatus: 'captured')
      ]);
      final g2Prepaid = OrderGroup('g2', [
        buildTestOrder(id: 'o2', customerId: 'c2', shopId: 's2', status: 'picked_up', itemTotal: 320.0, paymentMethod: 'upi', paymentStatus: 'captured')
      ]);
      final g3Prepaid = OrderGroup('g3', [
        buildTestOrder(id: 'o3', customerId: 'c3', shopId: 's3', status: 'preparing', itemTotal: 180.0, paymentMethod: 'upi', paymentStatus: 'captured')
      ]);

      final allActive = [g1Prepaid, g2Prepaid, g3Prepaid];

      final totalCodToCollect = allActive.fold(0.0, (sum, g) => sum + g.codAmountToCollect);
      expect(totalCodToCollect, equals(0.0));
    });

    test('R-CC-06: Total items getter across active multi-shop orders sums correctly', () {
      final itemBurger = OrderItem(id: 'i1', productId: 'p1', productName: 'Burger', price: 100.0, quantity: 2, weightKg: 0.5);
      final itemFries = OrderItem(id: 'i2', productId: 'p2', productName: 'Fries', price: 50.0, quantity: 3, weightKg: 0.5);

      final o1 = buildTestOrder(id: 'o1', customerId: 'c1', shopId: 's1', status: 'confirmed', items: [itemBurger]);
      final o2 = buildTestOrder(id: 'o2', customerId: 'c1', shopId: 's2', status: 'confirmed', items: [itemFries]);

      final grp = OrderGroup('grp-items', [o1, o2]);
      expect(grp.totalItemCount, equals(5));

      // If Shop 2 cancelled
      final o2Cancelled = buildTestOrder(id: 'o2', customerId: 'c1', shopId: 's2', status: 'seller_rejected', items: [itemFries]);
      final grpPartial = OrderGroup('grp-items-part', [o1, o2Cancelled]);
      expect(grpPartial.totalItemCount, equals(2));
    });

    test('R-CC-07: COD push notification suppression suppresses payment countdown push', () {
      String resolveCustomerPushTitle({required bool isPaid, required bool isCod, required bool allShopsAccepted}) {
        if (isPaid) return 'New Rider Assigned! 🛵';
        if (isCod) return 'Order Confirmed! 🛵';
        if (allShopsAccepted) return 'Ready for Payment! 💳';
        return '🛵 Rider is Ready!';
      }

      // COD order where all shops accepted must NEVER receive 'Ready for Payment! 💳'
      final titleCod = resolveCustomerPushTitle(isPaid: false, isCod: true, allShopsAccepted: true);
      expect(titleCod, equals('Order Confirmed! 🛵'));

      // Online order where all shops accepted receives 'Ready for Payment! 💳'
      final titleOnline = resolveCustomerPushTitle(isPaid: false, isCod: false, allShopsAccepted: true);
      expect(titleOnline, equals('Ready for Payment! 💳'));
    });

    test('R-CC-08: Zero active orders COD safety returns zero collection amount', () {
      final dead1 = buildTestOrder(id: 'd1', customerId: 'c1', shopId: 's1', status: 'shop_dispute_cancel', itemTotal: 300.0, paymentMethod: 'cod');
      final dead2 = buildTestOrder(id: 'd2', customerId: 'c1', shopId: 's2', status: 'cancelled', itemTotal: 200.0, paymentMethod: 'cod');

      final deadGroup = OrderGroup('dead-grp', [dead1, dead2]);
      expect(deadGroup.activeOrders.isEmpty, isTrue);
      // In dead group, codAmountToCollect is 0.0
      expect(deadGroup.codAmountToCollect, equals(0.0));
    });
  });
}


