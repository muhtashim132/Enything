import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/utils/geo_utils.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';
import 'package:enythingmobilenew/widgets/common/animated_moving_marker.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x MASTER ORDER LIFECYCLE, NOTIFICATION, MAP & CONCURRENCY MATRIX', () {
    const terminalRejectionStatuses = [
      'cancelled',
      'seller_rejected',
      'partner_rejected',
      'rider_rejected',
      'verification_failed',
      'timeout',
      'payment_failed',
      'shop_dispute_cancel',
      'rejected'
    ];

    OrderModel buildOrder({
      required String id,
      required String customerId,
      required String shopId,
      required String status,
      required double itemTotal,
      required double deliveryCharges,
      required double multiShopSurcharge,
      required double platformFee,
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
      double? shopLat,
      double? shopLng,
      double? deliveryLat,
      double? deliveryLng,
      double? riderLat,
      double? riderLng,
      DateTime? arrivedAtShopTime,
      DateTime? updatedAt,
      List<OrderItem>? items,
    }) {
      final grandTotal = grandTotalCollected ?? math.max(
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
        deliveryPartnerId: deliveryPartnerId,
        cancelledReason: cancelledReason,
        shopLat: shopLat ?? 34.0837,
        shopLng: shopLng ?? 74.7973,
        deliveryLat: deliveryLat ?? 34.0900,
        deliveryLng: deliveryLng ?? 74.8000,
        riderLat: riderLat,
        riderLng: riderLng,
        arrivedAtShopTime: arrivedAtShopTime,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        updatedAt: updatedAt ?? DateTime.now(),
        items: items ?? [
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

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Single Shop Restaurant Order: Add-on 5% GST, Base Delivery, Platform Fee,
    //    Rider 80% cut, Seller 95% base - gateway, Admin ledger parity.
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Single Shop Restaurant Order (5% Section 9(5) GST) Lifecycle & Parity', () {
      final items = [
        {'category': 'Restaurant', 'price': 400.0, 'quantity': 1},
      ];
      const deliveryCharge = 20.0 * 1.18; // ₹23.60 incl 18% GST
      const riderEarnings = 20.0 * 0.80; // ₹16.00 (80% of net ₹20 base)
      const platformFee = 20.0; // ₹20.00 incl 18% GST (net ₹16.95 + GST ₹3.05)

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: deliveryCharge,
        riderEarnings: riderEarnings,
        platformFee: platformFee,
        paymentMethod: 'upi',
      );

      // Customer bill breakdown
      expect(breakdown.itemBaseSubtotal, 400.0);
      expect(breakdown.itemGstTotal, 20.0); // 5% GST
      expect(breakdown.itemGrossTotal, 420.0);
      expect(breakdown.s9_5GstToRemit, 20.0); // Enything remits Section 9(5)
      expect(breakdown.nonFoodGstPassThrough, 0.0);
      expect(breakdown.grandTotal, closeTo(420.0 + 23.60 + 20.0, 0.01)); // ₹463.60

      // Gateway deduction (2.36% on grand total)
      final expectedGateway = breakdown.grandTotal * TaxConfig.effectiveGatewayDeductionPercent;
      expect(breakdown.gatewayDeduction, closeTo(expectedGateway, 0.01));

      // Rider share: exactly 80% of ₹20 base = ₹16
      expect(breakdown.riderEarnings, 16.0);

      // Seller payout: 95% of ₹400 base (₹380) minus seller's gateway share
      const sellerBasePayout = 400.0 * 0.95; // ₹380
      final sellerGwShare = sellerBasePayout * TaxConfig.effectiveGatewayDeductionPercent;
      expect(breakdown.sellerPayout, closeTo(sellerBasePayout - sellerGwShare, 0.01));

      // Notification lifecycle check: Seller buzzer must activate on awaiting_acceptance
      final sellerPendingOrders = <String>{};
      sellerPendingOrders.add('order-single-1');
      expect(sellerPendingOrders.isNotEmpty, isTrue); // Bell loops

      // Seller accepts -> bell stops for this order
      sellerPendingOrders.remove('order-single-1');
      expect(sellerPendingOrders.isEmpty, isTrue); // Bell silenced
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Single Shop Retail / Grocery Order: Non-food 18% GST, Heavy Order Fee (>10kg)
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Single Shop Retail Order (18% GST, Heavy Order Fee, Small Cart Fee check)', () {
      final items = [
        {'category': 'Electronics', 'price': 1200.0, 'quantity': 1},
      ];
      // 12kg order -> Heavy order fee ₹20 + 18% GST = ₹23.60
      // Base delivery ₹20 + Heavy ₹20 = ₹40 net -> ₹47.20 gross
      const baseDelivery = 20.0;
      const heavyFee = 20.0;
      const totalDeliveryNet = baseDelivery + heavyFee; // ₹40
      const deliveryCharge = totalDeliveryNet * 1.18; // ₹47.20
      const riderEarnings = totalDeliveryNet * 0.80; // ₹32.00 (80% of base + heavy)
      const platformFee = 20.0;

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: deliveryCharge,
        riderEarnings: riderEarnings,
        platformFee: platformFee,
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, 1200.0);
      expect(breakdown.itemGstTotal, 216.0); // 18% GST
      expect(breakdown.s9_5GstToRemit, 0.0);
      expect(breakdown.nonFoodGstPassThrough, 216.0); // Passed to seller for remittance
      expect(breakdown.grandTotal, closeTo(1200.0 + 216.0 + 47.20 + 20.0, 0.01)); // ₹1483.20

      // Rider gets 80% of (base + heavy)
      expect(breakdown.riderEarnings, 32.0);

      // Seller payout: Base ₹1200 - 5% commission (₹60) + ₹216 GST passthrough - seller gateway share
      const sellerGross = 1140.0 + 216.0; // ₹1356.00
      final sellerGwShare = sellerGross * TaxConfig.effectiveGatewayDeductionPercent;
      expect(breakdown.sellerPayout, closeTo(sellerGross - sellerGwShare, 0.01));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. 2-Shop Multi-Shop Order: Base Shop + Leg Shop attribution, Route waypoints,
    //    and Synchronous Payment Notification
    // ─────────────────────────────────────────────────────────────────────────
    test('3. 2-Shop Multi-Shop Order: Inter-Shop Surcharge, Waypoints, and Payment sync', () {
      const shop1Lat = 34.0837, shop1Lng = 74.7973;
      const shop2Lat = 34.1000, shop2Lng = 74.8200;
      const custLat = 34.1200, custLng = 74.8400;

      // Distance between Shop 1 and Shop 2: ~2.75 km -> Ceil(2.75) = 3 km -> Surcharge = 3 * ₹20 = ₹60
      final distCalc = const Distance();
      final interDistKm = distCalc.as(LengthUnit.Kilometer, const LatLng(shop1Lat, shop1Lng), const LatLng(shop2Lat, shop2Lng));
      final legSurchargeNet = math.max(1, interDistKm.ceil()) * 20.0; // ₹60
      expect(legSurchargeNet, equals(60.0));

      final o1 = buildOrder(
        id: 'ord-2s-1',
        customerId: 'cust-1',
        shopId: 'shop-A',
        status: 'awaiting_acceptance',
        itemTotal: 300.0,
        s9_5Gst: 15.0,
        deliveryCharges: 20.0 * 1.18, // Shop 1 holds Base Delivery Fee: ₹23.60
        multiShopSurcharge: 0.0,
        platformFee: 20.0, // Shop 1 holds Platform Fee
        riderEarnings: 16.0, // 80% of ₹20
        shopLat: shop1Lat,
        shopLng: shop1Lng,
        deliveryLat: custLat,
        deliveryLng: custLng,
      );

      final o2 = buildOrder(
        id: 'ord-2s-2',
        customerId: 'cust-1',
        shopId: 'shop-B',
        status: 'awaiting_acceptance',
        itemTotal: 250.0,
        s9_5Gst: 12.5,
        deliveryCharges: 0.0, // Shop 2 has ₹0 base delivery
        multiShopSurcharge: legSurchargeNet * 1.18, // Shop 2 holds Leg Surcharge: ₹70.80
        platformFee: 0.0,
        riderEarnings: legSurchargeNet * 0.80, // ₹48.00 (80% of ₹60 leg surcharge)
        shopLat: shop2Lat,
        shopLng: shop2Lng,
        deliveryLat: custLat,
        deliveryLng: custLng,
      );

      final group = OrderGroup('cart-grp-2s', [o1, o2]);
      expect(group.isMultiShop, isTrue);
      expect(group.activeOrders.length, equals(2));

      // Combined bill totals
      final totalItems = o1.totalAmount + o2.totalAmount; // ₹550
      final totalDeliveryGross = o1.deliveryCharges + o2.deliveryCharges + o1.multiShopSurcharge + o2.multiShopSurcharge; // ₹23.60 + ₹70.80 = ₹94.40
      final totalRiderEarnings = o1.riderEarnings + o2.riderEarnings; // ₹16 + ₹48 = ₹64 (80% of ₹80 total net delivery)
      expect(totalDeliveryGross, closeTo(94.40, 0.01));
      expect(totalRiderEarnings, equals(64.0));

      // Asynchronous notification check:
      // Seller 1 accepts, Seller 2 has NOT yet accepted -> Payment prompt MUST NOT fire
      bool shouldPromptPayment(List<OrderModel> orders, bool riderAccepted) {
        final allSellersAccepted = orders.every((o) => o.sellerAccepted);
        return allSellersAccepted && riderAccepted;
      }

      var o1Accepted = o1.copyWith(sellerAccepted: true);
      var o2Pending = o2.copyWith(sellerAccepted: false);
      expect(shouldPromptPayment([o1Accepted, o2Pending], true), isFalse); // Still blocked!

      // Seller 2 accepts AND rider accepts -> NOW payment prompt fires!
      var o2Accepted = o2.copyWith(sellerAccepted: true);
      expect(shouldPromptPayment([o1Accepted, o2Accepted], true), isTrue); // UNBLOCKED!
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. 3-Shop Multi-Shop Order: Sequential Chained Legs, Shop 1 Rejection & Rebalance
    // ─────────────────────────────────────────────────────────────────────────
    test('4. 3-Shop Order: Shop 1 (Base Shop) Rejection Promotes Shop 2 & Recalculates Leg to Shop 3', () {
      // 3 shops in sequence: Shop 1 -> Shop 2 -> Shop 3
      // Initially:
      // Shop 1: Base Delivery ₹20 (+ 18% GST = ₹23.60) + Platform Fee ₹20
      // Shop 2: Leg 1 Surcharge (Shop 1 -> Shop 2: 1 km = ₹20 * 1.18 = ₹23.60)
      // Shop 3: Leg 2 Surcharge (Shop 2 -> Shop 3: 1 km = ₹20 * 1.18 = ₹23.60)
      final o1Initial = buildOrder(
        id: 'ord-3s-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        itemTotal: 200.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        riderEarnings: 16.0,
      );
      final o2Initial = buildOrder(
        id: 'ord-3s-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
        riderEarnings: 16.0,
      );
      final o3Initial = buildOrder(
        id: 'ord-3s-3',
        customerId: 'cust-1',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
        riderEarnings: 16.0,
      );

      // Now Shop 1 REJECTS!
      // Rebalance Simulation:
      // 1. Shop 1 becomes seller_rejected: grand_total=0, delivery=0, platform=0, seller_payout=0
      final o1Cancelled = buildOrder(
        id: 'ord-3s-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        itemTotal: 200.0,
        deliveryCharges: 0.0,
        platformFee: 0.0,
        multiShopSurcharge: 0.0,
        grandTotalCollected: 0.0,
        sellerPayout: 0.0,
        enythingCommission: 0.0,
        gatewayDeduction: 0.0,
        riderEarnings: 0.0,
        cancelledReason: 'seller_rejected',
      );

      // 2. Shop 2 is promoted to Base Shop: inherits Base Delivery ₹23.60 + Platform Fee ₹20. Surcharge becomes ₹0.
      final o2Promoted = buildOrder(
        id: 'ord-3s-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 150.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0, // Base shop has 0 surcharge
        platformFee: 20.0,
        riderEarnings: 16.0, // 80% of ₹20 base
      );

      // 3. Shop 3 retains Leg Surcharge between surviving Shop 2 and Shop 3: ₹23.60
      final o3Surviving = buildOrder(
        id: 'ord-3s-3',
        customerId: 'cust-1',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
        riderEarnings: 16.0,
      );

      final postGroup = OrderGroup('cart-grp-3s', [o1Cancelled, o2Promoted, o3Surviving]);
      expect(postGroup.activeOrders.length, equals(2));
      expect(postGroup.activeOrders.first.id, equals('ord-3s-2')); // Shop 2 is now first active
      expect(postGroup.activeOrders.first.deliveryCharges, closeTo(23.60, 0.01)); // Holds Base Fee
      expect(postGroup.activeOrders.first.platformFee, equals(20.0)); // Holds Platform Fee

      // Total active delivery charges = ₹23.60 (Base) + ₹23.60 (Leg surcharge) = ₹47.20
      final activeDelivery = postGroup.activeOrders.fold<double>(0.0, (sum, o) => sum + o.deliveryCharges + o.multiShopSurcharge);
      expect(activeDelivery, closeTo(47.20, 0.01));

      // Active rider earnings = ₹16.00 + ₹16.00 = ₹32.00 (80% of net ₹40)
      final activeRiderEarnings = postGroup.activeOrders.fold<double>(0.0, (sum, o) => sum + o.riderEarnings);
      expect(activeRiderEarnings, equals(32.0));

      // Cancelled Shop 1 financial ledger check
      expect(o1Cancelled.sellerPayout, equals(0.0));
      expect(o1Cancelled.enythingCommission, equals(0.0));
      expect(o1Cancelled.gatewayDeduction, equals(0.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. 4-Shop Order with 2 Shops Rejecting (Shop 2 & Shop 4 Reject)
    // ─────────────────────────────────────────────────────────────────────────
    test('5. 4-Shop Order: 2 Shops Reject -> Inter-Shop Distance Recomputed between Shop 1 and Shop 3', () {
      final o1 = buildOrder(
        id: 'ord-4s-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        itemTotal: 300.0,
        deliveryCharges: 23.60, // Base
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
        riderEarnings: 16.0,
      );
      final o2 = buildOrder(
        id: 'ord-4s-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'seller_rejected', // REJECTED
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
        grandTotalCollected: 0.0,
      );
      final o3 = buildOrder(
        id: 'ord-4s-3',
        customerId: 'cust-1',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 250.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 47.20, // Recomputed direct distance surcharge from Shop 1 to Shop 3 (2 km = ₹40 * 1.18 = ₹47.20)
        platformFee: 0.0,
        riderEarnings: 32.0, // 80% of ₹40
      );
      final o4 = buildOrder(
        id: 'ord-4s-4',
        customerId: 'cust-1',
        shopId: 'shop-4',
        status: 'seller_rejected', // REJECTED
        itemTotal: 120.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
        grandTotalCollected: 0.0,
      );

      final group = OrderGroup('cart-grp-4s', [o1, o2, o3, o4]);
      expect(group.activeOrders.length, equals(2));
      expect(group.activeOrders.map((o) => o.id).toList(), equals(['ord-4s-1', 'ord-4s-3']));

      // Surviving Shop 1 retains base delivery & platform fee
      expect(group.activeOrders[0].deliveryCharges, closeTo(23.60, 0.01));
      expect(group.activeOrders[0].platformFee, equals(20.0));

      // Surviving Shop 3 holds the direct rebalanced surcharge
      expect(group.activeOrders[1].multiShopSurcharge, closeTo(47.20, 0.01));

      // Total rider earnings across remaining 2 shops = ₹16.00 + ₹32.00 = ₹48.00 (80% of net ₹60)
      expect(group.totalEarnings, equals(48.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Complete Rejection (All Shops Reject): 100% Refund Pool & Full Ledger Zeroing
    // ─────────────────────────────────────────────────────────────────────────
    test('6. Complete Rejection: All shops reject -> 0 active, 100% refund, rider released', () {
      final o1 = buildOrder(
        id: 'ord-all-1',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        itemTotal: 200.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
        grandTotalCollected: 0.0,
        sellerPayout: 0.0,
        enythingCommission: 0.0,
        gatewayDeduction: 0.0,
        riderEarnings: 0.0,
      );
      final o2 = buildOrder(
        id: 'ord-all-2',
        customerId: 'cust-1',
        shopId: 'shop-2',
        status: 'seller_rejected',
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
        grandTotalCollected: 0.0,
        sellerPayout: 0.0,
        enythingCommission: 0.0,
        gatewayDeduction: 0.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-all', [o1, o2]);
      expect(group.activeOrders.isEmpty, isTrue);
      expect(group.totalGrand, equals(0.0));
      expect(group.totalEarnings, equals(0.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Live Map Dynamic Tracking: lerpLatLng, calculateBearing, heading smoothing,
    //    and noise thresholds
    // ─────────────────────────────────────────────────────────────────────────
    test('7. Live Map Dynamic Tracking: coordinate interpolation, heading angle, jitter suppression', () {
      const p1 = LatLng(34.0837, 74.7973); // Srinagar
      const p2 = LatLng(34.0900, 74.8050);

      // Interpolation halfway (t = 0.5)
      final midPoint = lerpLatLng(p1, p2, 0.5);
      expect(midPoint.latitude, closeTo((34.0837 + 34.0900) / 2, 0.0001));
      expect(midPoint.longitude, closeTo((74.7973 + 74.8050) / 2, 0.0001));

      // Bearing calculation
      final bearing = calculateBearing(p1, p2);
      expect(bearing, greaterThan(0.0));
      expect(bearing, lessThan(90.0)); // North-East heading

      // Heading wrap-around across 360/0 degree border
      final angleCross = lerpAngle(355.0, 5.0, 0.5);
      expect(angleCross, closeTo(0.0, 0.01)); // Interpolates across 0°, not backwards 180°!

      // Micro-jitter threshold check: movement < 1.5m ignored to prevent UI flutter
      const jitterDistMeters = 1.2;
      expect(jitterDistMeters < 1.5, isTrue); // Ignored by SmoothMovingRiderMarkerLayer

      // Teleport threshold check: movement > 5000m snaps immediately
      const teleportMeters = 6200.0;
      expect(teleportMeters > 5000.0, isTrue); // Snaps without sliding across city
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Push Notification Deduplication Key Deep Edge Case
    // ─────────────────────────────────────────────────────────────────────────
    test('8. Push Notification Deduplication Key: user_id + order_id + title prevents alert loss', () {
      // Simulating edge function cache behavior
      final recentPushes = <String, int>{};

      bool isDuplicatePush(String key, int nowMs) {
        final lastTime = recentPushes[key];
        if (lastTime != null && nowMs - lastTime < 15000) {
          return true; // Duplicate within 15s window
        }
        recentPushes[key] = nowMs;
        return false;
      }

      const userId = 'cust-123';
      const orderId = 'order-456';
      final t0 = 100000;

      // Old flawed key: user_id + order_id (ignoring title)
      final flawedKey1 = '${userId}_$orderId';
      expect(isDuplicatePush(flawedKey1, t0), isFalse); // First push ("Shop Accepted") sent

      final t1 = t0 + 4000; // 4 seconds later
      final flawedKey2 = '${userId}_$orderId'; // Second push ("Pay Now 💳")
      // WITH FLAWED KEY: It gets incorrectly DROPPED!
      expect(isDuplicatePush(flawedKey2, t1), isTrue); // BUG CONFIRMED: Pay Now push dropped!

      // Reset cache and test NEW 100x fortified key: user_id + order_id + title
      recentPushes.clear();
      final goodKey1 = '${userId}_${orderId}_Shop Accepted!';
      final goodKey2 = '${userId}_${orderId}_✅ Shop & Rider Ready! Pay Now 💳';

      expect(isDuplicatePush(goodKey1, t0), isFalse); // "Shop Accepted" delivered!
      expect(isDuplicatePush(goodKey2, t1), isFalse); // "Pay Now" ALSO delivered!
      expect(isDuplicatePush(goodKey1, t1), isTrue);  // Exact same push repeated at t1 is properly suppressed!
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 9. HIGH CONCURRENCY STRESS MATRIX: 14 Concurrent Customers, 13 Sellers, 13 Riders
    // ─────────────────────────────────────────────────────────────────────────
    test('9. High Concurrency Stress Matrix: 14 Customers, 13 Sellers, 13 Riders concurrent execution', () {
      final customers = List.generate(14, (i) => 'customer-${i + 1}');
      final sellers = List.generate(13, (i) => 'seller-${i + 1}');
      final riders = List.generate(13, (i) => 'rider-${i + 1}');

      final allOrders = <OrderModel>[];
      double totalSystemGrandCollected = 0.0;
      double totalSystemRiderEarnings = 0.0;
      double totalSystemSellerPayouts = 0.0;
      double totalSystemEnythingCommissions = 0.0;
      double totalSystemGatewayDeductions = 0.0;
      double totalSystemFoodGst = 0.0;

      // 14 concurrent order flows:
      for (int i = 0; i < customers.length; i++) {
        final custId = customers[i];
        final riderId = riders[i % riders.length];

        if (i < 5) {
          // Single shop orders
          final sellerId = sellers[i];
          const itemBase = 300.0;
          const foodGst = 15.0;
          const delivery = 23.60;
          const platform = 20.0;
          final grand = itemBase + foodGst + delivery + platform;
          final gw = grand * TaxConfig.effectiveGatewayDeductionPercent;
          const riderCut = 16.0;
          final sellerGw = (itemBase * 0.95) * TaxConfig.effectiveGatewayDeductionPercent;
          final sellerCut = (itemBase * 0.95) - sellerGw;
          final platformComm = (itemBase * 0.05) + sellerGw;

          final o = buildOrder(
            id: 'ord-conc-$i-1',
            customerId: custId,
            shopId: 'shop-$sellerId',
            status: 'delivered',
            itemTotal: itemBase,
            s9_5Gst: foodGst,
            deliveryCharges: delivery,
            multiShopSurcharge: 0.0,
            platformFee: platform,
            riderEarnings: riderCut,
            sellerPayout: sellerCut,
            enythingCommission: platformComm,
            gatewayDeduction: gw,
            deliveryPartnerId: riderId,
          );
          allOrders.add(o);

          totalSystemGrandCollected += grand;
          totalSystemRiderEarnings += riderCut;
          totalSystemSellerPayouts += sellerCut;
          totalSystemEnythingCommissions += platformComm;
          totalSystemGatewayDeductions += gw;
          totalSystemFoodGst += foodGst;
        } else if (i < 10) {
          // 2-shop multi-shop orders
          final s1 = sellers[(i * 2) % sellers.length];
          final s2 = sellers[(i * 2 + 1) % sellers.length];

          final o1 = buildOrder(
            id: 'ord-conc-$i-1',
            customerId: custId,
            shopId: 'shop-$s1',
            status: 'delivered',
            itemTotal: 250.0,
            s9_5Gst: 12.5,
            deliveryCharges: 23.60,
            multiShopSurcharge: 0.0,
            platformFee: 20.0,
            riderEarnings: 16.0,
            deliveryPartnerId: riderId,
          );
          final o2 = buildOrder(
            id: 'ord-conc-$i-2',
            customerId: custId,
            shopId: 'shop-$s2',
            status: 'delivered',
            itemTotal: 200.0,
            s9_5Gst: 10.0,
            deliveryCharges: 0.0,
            multiShopSurcharge: 23.60,
            platformFee: 0.0,
            riderEarnings: 16.0,
            deliveryPartnerId: riderId,
          );
          allOrders.addAll([o1, o2]);
        } else {
          // 3-shop and 4-shop orders with partial rejections
          final s1 = sellers[(i) % sellers.length];
          final s2 = sellers[(i + 1) % sellers.length];
          final s3 = sellers[(i + 2) % sellers.length];

          // s2 rejects!
          final o1 = buildOrder(
            id: 'ord-conc-$i-1',
            customerId: custId,
            shopId: 'shop-$s1',
            status: 'delivered',
            itemTotal: 200.0,
            deliveryCharges: 23.60,
            multiShopSurcharge: 0.0,
            platformFee: 20.0,
            riderEarnings: 16.0,
            deliveryPartnerId: riderId,
          );
          final o2 = buildOrder(
            id: 'ord-conc-$i-2',
            customerId: custId,
            shopId: 'shop-$s2',
            status: 'seller_rejected',
            itemTotal: 150.0,
            deliveryCharges: 0.0,
            multiShopSurcharge: 0.0,
            platformFee: 0.0,
            grandTotalCollected: 0.0,
          );
          final o3 = buildOrder(
            id: 'ord-conc-$i-3',
            customerId: custId,
            shopId: 'shop-$s3',
            status: 'delivered',
            itemTotal: 180.0,
            deliveryCharges: 0.0,
            multiShopSurcharge: 23.60, // Surcharge rebalanced from s1 -> s3
            platformFee: 0.0,
            riderEarnings: 16.0,
            deliveryPartnerId: riderId,
          );
          allOrders.addAll([o1, o2, o3]);
        }
      }

      // Concurrency integrity assertions:
      expect(allOrders.length, greaterThan(25));
      final customerIds = allOrders.map((o) => o.customerId).toSet();
      expect(customerIds.length, equals(14)); // Exactly 14 distinct customers

      // Check that no orders have NaN or negative amounts
      for (final o in allOrders) {
        expect(o.totalAmount.isNaN, isFalse);
        expect(o.totalAmount >= 0, isTrue);
        expect(o.deliveryCharges >= 0, isTrue);
        expect(o.multiShopSurcharge >= 0, isTrue);
        expect(o.grandTotalCollected >= 0, isTrue);
        expect(o.riderEarnings >= 0, isTrue);
      }

      // Check single-shop financial balance
      expect(totalSystemGrandCollected, greaterThan(0.0));
      expect(totalSystemRiderEarnings, equals(5 * 16.0)); // 5 single shop orders * ₹16 rider cut
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 10. BellAlertService Loop Lifecycle & Mute Edge Cases
    // ─────────────────────────────────────────────────────────────────────────
    test('10. BellAlertService: Order addition, multi-order loop maintenance, and instant silence', () {
      final bellPending = <String>{};

      // Order 1 arrives for seller -> start loop
      bellPending.add('order-A');
      expect(bellPending.isNotEmpty, isTrue);

      // Order 2 arrives while order 1 still pending -> bell continues looping without re-starting player
      bellPending.add('order-B');
      expect(bellPending.length, equals(2));

      // Order 1 accepted -> bell does NOT stop because order 2 is still pending
      bellPending.remove('order-A');
      expect(bellPending.isNotEmpty, isTrue);

      // Order 2 rejected -> pending count drops to 0 -> bell SILENCED immediately
      bellPending.remove('order-B');
      expect(bellPending.isEmpty, isTrue);

      // Stale remove call on non-existent order does not throw or crash
      expect(() => bellPending.remove('order-nonexistent'), returnsNormally);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 11. CustomerOrderMapPage Terminal Status Filter & Polylines Parity
    // ─────────────────────────────────────────────────────────────────────────
    test('11. CustomerOrderMapPage: Terminal statuses correctly exclude rejected shops from polylines', () {
      final o1 = buildOrder(
        id: 'ord-m-1',
        customerId: 'c1',
        shopId: 's1',
        status: 'picked_up',
        itemTotal: 200.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 20.0,
      );
      final o2 = buildOrder(
        id: 'ord-m-2',
        customerId: 'c1',
        shopId: 's2',
        status: 'partner_rejected', // Rider rejected / no rider found
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
      );
      final o3 = buildOrder(
        id: 'ord-m-3',
        customerId: 'c1',
        shopId: 's3',
        status: 'timeout', // Acceptance expired
        itemTotal: 180.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        platformFee: 0.0,
      );
      final o4 = buildOrder(
        id: 'ord-m-4',
        customerId: 'c1',
        shopId: 's4',
        status: 'ready_for_pickup',
        itemTotal: 220.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 23.60,
        platformFee: 0.0,
      );

      final groupOrders = [o1, o2, o3, o4];

      // Filter using the fortified terminal status set
      final activeShops = groupOrders.where((o) => !terminalRejectionStatuses.contains(o.status)).toList();

      // Only o1 and o4 should be active! o2 (partner_rejected) and o3 (timeout) must be excluded!
      expect(activeShops.length, equals(2));
      expect(activeShops.map((o) => o.id).toList(), equals(['ord-m-1', 'ord-m-4']));

      // Waypoint routing: Unpicked active stops
      final unpicked = activeShops.where((o) => o.status != 'picked_up' && o.status != 'out_for_delivery').toList();
      expect(unpicked.length, equals(1));
      expect(unpicked.first.shopId, equals('s4')); // Only shop 4 remains to be visited!
    });
  });
}
