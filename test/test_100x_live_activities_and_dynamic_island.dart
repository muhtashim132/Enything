import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/services/live_activity_service.dart';
import 'package:enythingmobilenew/services/notification_service.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('100x Live Activities & Dynamic Island Forensic Test Suite', () {
    late LiveActivityService service;

    setUp(() {
      service = LiveActivityService();
    });

    test('Edge Case 1: Preparing State matches Swiggy Screenshot 1', () {
      final order = OrderModel(
        id: 'ord-prep-123456',
        customerId: 'cust-1',
        status: 'preparing',
        orderType: 'instant',
        totalAmount: 450.0,
        deliveryCharges: 40.0,
        riderEarnings: 30.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryPartnerId: 'rider-1',
        shopPrepTimeSnapshot: 15,
        estimatedDistanceKm: 2.5,
        gstItemTotal: 22.5,
        s9_5GstAmount: 22.5,
        nonFoodGstAmount: 0.0,
        tcsAmount: 4.5,
        grandTotalCollected: 495.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(
        order: order,
        fallbackShopName: 'Swiggy Bowl',
      );

      expect(state.statusHeadline, 'Your order is being prepared');
      expect(state.progress, 0.35);
      expect(state.etaMinutes, greaterThanOrEqualTo(8));
      expect(state.isTerminal, false);
      expect(state.shopName, 'Swiggy Bowl');
    });

    test('Edge Case 2: Rider Heading to Store matches Swiggy Screenshot 2', () {
      final order = OrderModel(
        id: 'ord-conf-789012',
        customerId: 'cust-1',
        status: 'confirmed',
        orderType: 'instant',
        totalAmount: 320.0,
        deliveryCharges: 35.0,
        riderEarnings: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryPartnerId: 'rider-1',
        shopPrepTimeSnapshot: 10,
        estimatedDistanceKm: 1.8,
        gstItemTotal: 16.0,
        s9_5GstAmount: 16.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 3.2,
        grandTotalCollected: 360.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(
        order: order,
        fallbackShopName: 'Dominos Pizza',
        riderName: 'Aman (4.9★)',
      );

      expect(state.statusHeadline, 'Rider is on the way to pick up');
      expect(state.progress, 0.40);
      expect(state.riderName, 'Aman (4.9★)');
      expect(state.isTerminal, false);
    });

    test('Edge Case 3: Multi-Shop Cart Group Pickup Progression', () {
      final order1 = OrderModel(
        id: 'subord-shop-1',
        cartGroupId: 'cartgroup-multi-99',
        customerId: 'cust-1',
        status: 'picked_up',
        orderType: 'instant',
        totalAmount: 200.0,
        deliveryCharges: 25.0,
        riderEarnings: 20.0,
        multiShopSurcharge: 15.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryPartnerId: 'rider-1',
        gstItemTotal: 10.0,
        s9_5GstAmount: 10.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 2.0,
        grandTotalCollected: 230.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final order2 = OrderModel(
        id: 'subord-shop-2',
        cartGroupId: 'cartgroup-multi-99',
        customerId: 'cust-1',
        status: 'preparing',
        orderType: 'instant',
        totalAmount: 250.0,
        deliveryCharges: 25.0,
        riderEarnings: 20.0,
        multiShopSurcharge: 15.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryPartnerId: 'rider-1',
        gstItemTotal: 12.5,
        s9_5GstAmount: 12.5,
        nonFoodGstAmount: 0.0,
        tcsAmount: 2.5,
        grandTotalCollected: 287.5,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      // Evaluating order1 while order2 is still preparing
      final state = service.computeState(
        order: order1,
        groupOrders: [order1, order2],
      );

      expect(state.isMultiShop, true);
      expect(state.totalShops, 2);
      expect(state.pickedUpShops, 1);
      expect(state.statusHeadline, '🛍️ 1 of 2 stores collected · Next stop');
      expect(state.progress, 0.65);
    });

    test('Edge Case 4: Out For Delivery & Dynamic ETA with Live GPS', () {
      final order = OrderModel(
        id: 'ord-out-111',
        customerId: 'cust-1',
        status: 'out_for_delivery',
        orderType: 'instant',
        totalAmount: 500.0,
        deliveryCharges: 40.0,
        riderEarnings: 35.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryPartnerId: 'rider-1',
        deliveryLat: 12.9716,
        deliveryLng: 77.5946,
        gstItemTotal: 25.0,
        s9_5GstAmount: 25.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 5.0,
        grandTotalCollected: 545.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      // Rider is 500m away
      final riderLocs = {
        'rider-1': const LatLng(12.9730, 77.5960),
      };

      final state = service.computeState(
        order: order,
        riderLocations: riderLocs,
      );

      expect(state.statusHeadline, 'Almost there! Rider is arriving 🛵');
      expect(state.progress, 0.90);
      expect(state.etaMinutes, lessThanOrEqualTo(4));
    });

    test('Edge Case 5: Terminal States (Delivered & Cancelled) Trigger Clean Dismissal', () {
      final deliveredOrder = OrderModel(
        id: 'ord-del-1',
        customerId: 'cust-1',
        status: 'delivered',
        orderType: 'instant',
        totalAmount: 100.0,
        deliveryCharges: 20.0,
        riderEarnings: 15.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        gstItemTotal: 5.0,
        s9_5GstAmount: 5.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 1.0,
        grandTotalCollected: 125.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final delState = service.computeState(order: deliveredOrder);
      expect(delState.isTerminal, true);
      expect(delState.progress, 1.0);
      expect(delState.statusHeadline, contains('Delivered'));

      final cancelledOrder = OrderModel(
        id: 'ord-canc-1',
        customerId: 'cust-1',
        status: 'seller_rejected',
        orderType: 'instant',
        totalAmount: 100.0,
        deliveryCharges: 20.0,
        riderEarnings: 15.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        gstItemTotal: 5.0,
        s9_5GstAmount: 5.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 1.0,
        grandTotalCollected: 125.0,
        sellerAccepted: false,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final cancState = service.computeState(order: cancelledOrder);
      expect(cancState.isTerminal, true);
      expect(cancState.progress, 0.0);
      expect(cancState.statusHeadline, 'Order Cancelled');
    });

    test('Edge Case 6: toMap Payload Conforms to Swift OrderLiveActivityAttributes Schema', () {
      final order = OrderModel(
        id: 'ord-swift-schema-test',
        customerId: 'cust-1',
        status: 'preparing',
        orderType: 'instant',
        totalAmount: 200.0,
        deliveryCharges: 20.0,
        riderEarnings: 15.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        gstItemTotal: 10.0,
        s9_5GstAmount: 10.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 2.0,
        grandTotalCollected: 225.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(order: order, fallbackShopName: 'Burger King');
      final map = state.toMap();

      // Required keys matching Swift Codable model
      expect(map.containsKey('orderId'), true);
      expect(map.containsKey('orderNumber'), true);
      expect(map.containsKey('shopName'), true);
      expect(map.containsKey('statusKey'), true);
      expect(map.containsKey('statusHeadline'), true);
      expect(map.containsKey('etaMinutes'), true);
      expect(map.containsKey('etaTimestamp'), true);
      expect(map.containsKey('progress'), true);
      expect(map.containsKey('isMultiShop'), true);
      expect(map.containsKey('unpickedShopsCount'), true);

      expect(map['shopName'], 'Burger King');
      expect(map['statusHeadline'], 'Your order is being prepared');
      expect(map['progress'], 0.30);
    });

    test('Edge Case 7: TrackOrderPage Active State Suppresses In-App Floating Pill', () {
      service.setTrackOrderPageOpen(true);
      expect(service.isTrackOrderPageOpenNotifier.value, true);

      service.setTrackOrderPageOpen(false);
      expect(service.isTrackOrderPageOpenNotifier.value, false);
    });

    test('Edge Case 8: Corrupt / Zero GPS (0.0, 0.0 or outside India) is safely discarded by coordinate sanity', () {
      expect(LiveActivityService.isValidCoordinate(null), false);
      expect(LiveActivityService.isValidCoordinate(const LatLng(0.0, 0.0)), false);
      expect(LiveActivityService.isValidCoordinate(const LatLng(-33.8688, 151.2093)), false); // Sydney, Australia
      expect(LiveActivityService.isValidCoordinate(const LatLng(12.9716, 77.5946)), true); // Bangalore, India
      expect(LiveActivityService.isValidCoordinate(const LatLng(34.0837, 74.7973)), true); // Srinagar, India

      final order = OrderModel(
        id: 'ord-corrupt-gps',
        customerId: 'cust-1',
        status: 'out_for_delivery',
        orderType: 'instant',
        totalAmount: 300.0,
        deliveryCharges: 30.0,
        riderEarnings: 25.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryLat: 12.9716,
        deliveryLng: 77.5946,
        estimatedDistanceKm: 2.0,
        gstItemTotal: 15.0,
        s9_5GstAmount: 15.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 3.0,
        grandTotalCollected: 330.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      // Rider GPS reports uninitialized (0.0, 0.0)
      final state = service.computeState(
        order: order,
        riderLocations: {'rider-1': const LatLng(0.0, 0.0)},
      );

      // ETA must NOT jump to 16,000 minutes; it gracefully uses estimatedDistanceKm
      expect(state.etaMinutes, lessThanOrEqualTo(10));
    });

    test('Edge Case 9: Out for Delivery displays Delivery OTP prominently', () {
      final orderWithOtp = OrderModel(
        id: 'ord-otp-1234',
        customerId: 'cust-1',
        status: 'out_for_delivery',
        orderType: 'instant',
        totalAmount: 400.0,
        deliveryCharges: 35.0,
        riderEarnings: 30.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryOtp: '7482',
        gstItemTotal: 20.0,
        s9_5GstAmount: 20.0,
        nonFoodGstAmount: 0.0,
        tcsAmount: 4.0,
        grandTotalCollected: 440.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(order: orderWithOtp);
      expect(state.deliveryOtp, '7482');
      expect(state.statusHeadline, contains('7482'));
      expect(state.toMap()['deliveryOtp'], '7482');
    });

    test('Edge Case 10: Monotonic Smoothing Damper prevents traffic light ETA spikes', () {
      final order = OrderModel(
        id: 'ord-damper-test',
        customerId: 'cust-1',
        status: 'out_for_delivery',
        orderType: 'instant',
        totalAmount: 250.0,
        deliveryCharges: 25.0,
        riderEarnings: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [],
        deliveryLat: 12.9716,
        deliveryLng: 77.5946,
        gstItemTotal: 12.5,
        s9_5GstAmount: 12.5,
        nonFoodGstAmount: 0.0,
        tcsAmount: 2.5,
        grandTotalCollected: 275.0,
        sellerAccepted: true,
        partnerAccepted: true,
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      // Rider is 200m away (ETA ~3m)
      final state1 = service.computeState(
        order: order,
        riderLocations: {'rider-1': const LatLng(12.9720, 77.5950)},
      );
      expect(state1.etaMinutes, lessThanOrEqualTo(4));

      // Rider stops at traffic light, raw calculation temporarily spikes, damper clamps it
      final state2 = service.computeState(
        order: order,
        riderLocations: {'rider-1': const LatLng(12.9750, 77.6000)},
      );
      expect(state2.etaMinutes, lessThanOrEqualTo(state1.etaMinutes + 1));
    });

    test('Edge Case 11: Notification ID determinism per order ID avoids collisions for concurrent orders', () {
      final notifService = NotificationService();
      final id1 = notifService.getNotificationIdForOrder('order-uuid-alpha-111');
      final id2 = notifService.getNotificationIdForOrder('order-uuid-beta-222');
      final defaultId = notifService.getNotificationIdForOrder(null);

      expect(id1, isNot(equals(id2)));
      expect(defaultId, 888);
      expect(id1, greaterThanOrEqualTo(10000));
      expect(id2, greaterThanOrEqualTo(10000));
    });
  });
}
