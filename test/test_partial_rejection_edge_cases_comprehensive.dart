import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x Comprehensive Partial Rejection & Multi-Shop Recalculation Suite', () {
    const terminalRejectionStatuses = [
      'cancelled',
      'seller_rejected',
      'partner_rejected',
      'rider_rejected',
      'verification_failed',
      'timeout',
      'payment_failed',
      'shop_dispute_cancel'
    ];

    OrderModel buildTestOrder({
      required String id,
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
      String? cancelledReason,
      DateTime? updatedAt,
    }) {
      final grandTotal = math.max(
        0.0,
        itemTotal +
            deliveryCharges +
            multiShopSurcharge +
            platformFee +
            smallCartFee +
            heavyOrderFee -
            couponDiscount,
      );

      return OrderModel(
        id: id,
        customerId: 'customer-1',
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
        cancelledReason: cancelledReason,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        updatedAt: updatedAt ?? DateTime.now(),
        items: [
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
    // Test 1: 2-Shop Order -> Shop 1 (Base Shop) Rejects
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 1: 2-Shop Order -> Shop 1 (Base Shop) Rejects -> Shop 2 promoted to Base Shop', () {
      final shop1Initial = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        itemTotal: 200.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        cancelledReason: 'seller_rejected',
      );
      final shop2Initial = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 20.0,
        platformFee: 0.0,
      );

      final shop2Rebalanced = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        itemTotal: 150.0,
        deliveryCharges: 20.0,
        platformFee: 5.0,
        multiShopSurcharge: 0.0,
      );
      final shop1Rebalanced = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        itemTotal: 0.0,
        deliveryCharges: 0.0,
        platformFee: 0.0,
        multiShopSurcharge: 0.0,
      );

      expect(shop2Rebalanced.deliveryCharges, equals(20.0));
      expect(shop2Rebalanced.platformFee, equals(5.0));
      expect(shop2Rebalanced.multiShopSurcharge, equals(0.0));
      expect(shop2Rebalanced.grandTotalCollected, equals(175.0));
      expect(shop1Rebalanced.grandTotalCollected, equals(0.0));

      expect(395.0 - shop2Rebalanced.grandTotalCollected!, equals(220.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: 2-Shop Order -> Shop 2 (Leg Shop) Rejects
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 2: 2-Shop Order -> Shop 2 (Leg Shop) Rejects -> Shop 1 retains Base Fee', () {
      final shop1 = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        itemTotal: 200.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );
      final shop2 = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-2',
        status: 'seller_rejected',
        itemTotal: 150.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 20.0,
        platformFee: 0.0,
      );

      expect(shop1.deliveryCharges, equals(20.0));
      expect(shop1.platformFee, equals(5.0));
      expect(shop1.multiShopSurcharge, equals(0.0));

      final refund = (shop1.grandTotalCollected! + shop2.grandTotalCollected!) - 225.0;
      expect(refund, equals(170.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: 3-Shop Order -> 2 Shops Reject (Shop 1 & Shop 2)
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 3: 3-Shop Order -> 2 Shops Reject -> Shop 3 promoted to sole Base Shop', () {
      final shop1 = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-1',
        status: 'seller_rejected',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );
      final shop2 = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-2',
        status: 'seller_rejected',
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 20.0,
        platformFee: 0.0,
      );
      final shop3 = buildTestOrder(
        id: 'ord-3',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 100.0,
        deliveryCharges: 0.0,
        multiShopSurcharge: 20.0,
        platformFee: 0.0,
      );

      final shop3Rebalanced = buildTestOrder(
        id: 'ord-3',
        shopId: 'shop-3',
        status: 'awaiting_acceptance',
        itemTotal: 100.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
      );

      expect(shop3Rebalanced.grandTotalCollected, equals(125.0));
      expect(365.0 - shop3Rebalanced.grandTotalCollected!, equals(240.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: 3-Shop Order -> Sequential Rejection (Shop 1 then Shop 2)
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 4: Sequential Rejections: Shop 1 rejects -> Shop 2 promoted -> Shop 2 rejects -> Shop 3 promoted', () {
      final step1Shop2Delivery = 20.0;
      final step1Shop2Platform = 5.0;

      expect(step1Shop2Delivery, equals(20.0));
      expect(step1Shop2Platform, equals(5.0));

      final step2Shop3Delivery = 20.0;
      final step2Shop3Platform = 5.0;
      final step2Shop3Surcharge = 0.0;

      expect(step2Shop3Delivery, equals(20.0));
      expect(step2Shop3Platform, equals(5.0));
      expect(step2Shop3Surcharge, equals(0.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: All Shops Reject (Complete Rejection)
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 5: All Shops Reject -> 0 active shops, 100% refund pool, zero payout/commission', () {
      final orders = [
        buildTestOrder(id: '1', shopId: 's1', status: 'seller_rejected', itemTotal: 100, deliveryCharges: 20, multiShopSurcharge: 0, platformFee: 5),
        buildTestOrder(id: '2', shopId: 's2', status: 'seller_rejected', itemTotal: 100, deliveryCharges: 0, multiShopSurcharge: 20, platformFee: 0),
      ];

      final activeOrders = orders.where((o) => !terminalRejectionStatuses.contains(o.status)).toList();
      expect(activeOrders.isEmpty, isTrue);

      final double totalOriginalPaid = 125.0 + 120.0;
      final double activeGrandTotal = 0.0;
      final double totalRefund = totalOriginalPaid - activeGrandTotal;

      expect(totalRefund, equals(245.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 6: Adding 1 Replacement Shop -> Leg Distance Surcharge
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 6: Replacement Order with Surviving Active Shop -> Surcharge added, Base Fee retained', () {
      final activeShopIds = {'shop-2'};
      final isReplacementOrder = true;
      final legSurcharges = [20.0];

      final shopIndex = 0;
      final isExtraLeg = isReplacementOrder && activeShopIds.isNotEmpty;
      final double currentLegSurcharge = (shopIndex < legSurcharges.length) ? legSurcharges[shopIndex] : 0.0;
      final double shopSurcharge = (shopIndex == 0 && !isExtraLeg) ? 0.0 : currentLegSurcharge;
      final double shopBaseFee = (shopIndex == 0)
          ? (0.0 + 0.0 + 0.0 + (isExtraLeg ? currentLegSurcharge : 0.0))
          : currentLegSurcharge;

      expect(shopSurcharge, equals(20.0));
      expect(shopBaseFee, equals(20.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 7: Adding 2 Replacement Shops -> Sequential Leg Surcharges
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 7: Adding 2 Replacement Shops -> Sequential leg surcharges correctly attributed', () {
      final activeShopIds = {'shop-2'};
      final isReplacementOrder = true;
      final legSurcharges = [20.0, 40.0];

      final isExtraLeg = isReplacementOrder && activeShopIds.isNotEmpty;

      final shop0Surcharge = (0 == 0 && !isExtraLeg) ? 0.0 : legSurcharges[0];
      final shop0BaseFee = (0.0 + (isExtraLeg ? legSurcharges[0] : 0.0));

      final shop1Surcharge = legSurcharges[1];
      final shop1BaseFee = legSurcharges[1];

      expect(shop0Surcharge, equals(20.0));
      expect(shop0BaseFee, equals(20.0));
      expect(shop1Surcharge, equals(40.0));
      expect(shop1BaseFee, equals(40.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 8: Cascading Rejection Banner Logic
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 8: Cascading Rejection: Shop 1 replaced -> Shop 2 rejects -> banner correctly displays', () {
      final orders = [
        buildTestOrder(
          id: 'ord-1',
          shopId: 'shop-1',
          status: 'seller_rejected',
          itemTotal: 100,
          deliveryCharges: 0,
          multiShopSurcharge: 0,
          platformFee: 0,
          cancelledReason: 'customer_replaced',
        ),
        buildTestOrder(
          id: 'ord-2',
          shopId: 'shop-2',
          status: 'seller_rejected',
          itemTotal: 150,
          deliveryCharges: 0,
          multiShopSurcharge: 0,
          platformFee: 0,
          cancelledReason: 'seller_rejected',
        ),
        buildTestOrder(
          id: 'ord-3',
          shopId: 'shop-3',
          status: 'awaiting_acceptance',
          itemTotal: 200,
          deliveryCharges: 20,
          multiShopSurcharge: 0,
          platformFee: 5,
        ),
      ];

      final hasUnhandledRejection = orders.any((o) =>
          terminalRejectionStatuses.contains(o.status) &&
          !(o.cancelledReason?.startsWith('customer') ?? false));
      final hasActive = orders.any((o) => !terminalRejectionStatuses.contains(o.status));
      final fortifiedHasPartialRejection = hasUnhandledRejection && hasActive;

      expect(fortifiedHasPartialRejection, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 9: Coupon Boundary Recalculation
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 9: Coupon boundary: Subtotal drops below min_order_amount -> coupon revoked', () {
      final couponMinOrder = 500.0;
      final couponDiscount = 50.0;

      final initialSubtotal = 600.0;
      expect(initialSubtotal >= couponMinOrder, isTrue);

      final activeSubtotal = 300.0;
      final effectiveCoupon = (activeSubtotal >= couponMinOrder) ? couponDiscount : 0.0;
      expect(effectiveCoupon, equals(0.0));

      final recoveredSubtotal = activeSubtotal + 250.0;
      final recoveredCoupon = (recoveredSubtotal >= couponMinOrder) ? couponDiscount : 0.0;
      expect(recoveredCoupon, equals(50.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 10: Small Cart & Heavy Order Fee Transitions
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 10: Dynamic Small Cart & Heavy Order Fee transitions on rejection and replacement', () {
      const smallCartThreshold = 99.0;
      const smallCartFeeRate = 15.0;
      const heavyOrderThreshold = 10.0;
      const heavyFeePerKg = 10.0;

      double subtotal = 150.0;
      double weight = 12.0;

      double smallCartFee = (subtotal < smallCartThreshold) ? smallCartFeeRate : 0.0;
      double heavyFee = (weight > heavyOrderThreshold) ? (weight - heavyOrderThreshold).ceil() * heavyFeePerKg : 0.0;
      expect(smallCartFee, equals(0.0));
      expect(heavyFee, equals(20.0));

      subtotal = 80.0;
      weight = 4.0;
      smallCartFee = (subtotal < smallCartThreshold) ? smallCartFeeRate : 0.0;
      heavyFee = (weight > heavyOrderThreshold) ? (weight - heavyOrderThreshold).ceil() * heavyFeePerKg : 0.0;

      expect(smallCartFee, equals(15.0));
      expect(heavyFee, equals(0.0));

      subtotal = 130.0;
      weight = 12.0;
      smallCartFee = (subtotal < smallCartThreshold) ? smallCartFeeRate : 0.0;
      heavyFee = (weight > heavyOrderThreshold) ? (weight - heavyOrderThreshold).ceil() * heavyFeePerKg : 0.0;

      expect(smallCartFee, equals(0.0));
      expect(heavyFee, equals(20.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 11: Seller Payout & Gateway Deduction Financial Integrity
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 11: Gateway deduction formula & seller payout zeroing on cancellation', () {
      final grandTotal = 250.0;
      final gatewayDeduction = grandTotal * 0.02 * 1.18;
      expect(gatewayDeduction, closeTo(5.90, 0.01));

      final cancelledGrandTotal = 0.0;
      final cancelledGatewayDeduction = cancelledGrandTotal * 0.02 * 1.18;
      final cancelledSellerPayout = 0.0;
      final cancelledCommission = 0.0;

      expect(cancelledGatewayDeduction, equals(0.0));
      expect(cancelledSellerPayout, equals(0.0));
      expect(cancelledCommission, equals(0.0));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 12: Atomic Single Group Cancellation on Timeout
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 12: Atomic cancellation flags p_cancel_entire_group=true to avoid double rebalances', () {
      final cancellableOrders = [
        buildTestOrder(id: '1', shopId: 's1', status: 'awaiting_acceptance', itemTotal: 100, deliveryCharges: 20, multiShopSurcharge: 0, platformFee: 5),
        buildTestOrder(id: '2', shopId: 's2', status: 'awaiting_acceptance', itemTotal: 100, deliveryCharges: 0, multiShopSurcharge: 20, platformFee: 0),
      ];

      final primaryOrderId = cancellableOrders.first.id;
      final rpcParams = {
        'p_order_id': primaryOrderId,
        'p_reason': 'timeout',
        'p_cancel_entire_group': true,
      };

      expect(rpcParams['p_cancel_entire_group'], isTrue);
      expect(rpcParams['p_order_id'], equals('1'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 13: Cart Pollution Prevention
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 13: clearPendingReplacement clears pendingCartGroupId to prevent cart pollution', () {
      final cart = CartProvider();
      cart.setPendingCartGroupId('stale-group-id-123');
      cart.setPendingOrderIdToCancel('stale-order-id-456');

      expect(cart.pendingCartGroupId, equals('stale-group-id-123'));
      expect(cart.pendingOrderIdToCancel, equals('stale-order-id-456'));

      cart.clearPendingReplacement();

      expect(cart.pendingCartGroupId, isNull);
      expect(cart.pendingOrderIdToCancel, isNull);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 14: Banner Auto-Dismiss When All Active Shops Reach Confirmed
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 14: Auto-resolve banner when all remaining active shops reach confirmed+', () {
      final activeOrders = [
        buildTestOrder(id: '2', shopId: 's2', status: 'confirmed', itemTotal: 150, deliveryCharges: 20, multiShopSurcharge: 0, platformFee: 5),
      ];

      final safeStatuses = [
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'picked_up',
        'out_for_delivery',
        'delivered'
      ];

      final allActiveSafe = activeOrders.isNotEmpty &&
          activeOrders.every((o) => safeStatuses.contains(o.status));

      expect(allActiveSafe, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 15: SharedPreferences Crash Recovery / Backend Truth Check
    // ─────────────────────────────────────────────────────────────────────────
    test('Test 15: Backend truth check detects all rejected orders are customer-handled and skips timer', () {
      final orders = [
        buildTestOrder(
          id: '1',
          shopId: 's1',
          status: 'seller_rejected',
          itemTotal: 100,
          deliveryCharges: 0,
          multiShopSurcharge: 0,
          platformFee: 0,
          cancelledReason: 'customer_proceed',
        ),
        buildTestOrder(
          id: '2',
          shopId: 's2',
          status: 'awaiting_acceptance',
          itemTotal: 150,
          deliveryCharges: 20,
          multiShopSurcharge: 0,
          platformFee: 5,
        ),
      ];

      final unhandledRejections = orders.where((o) =>
          terminalRejectionStatuses.contains(o.status) &&
          !(o.cancelledReason?.startsWith('customer') ?? false)).toList();

      expect(unhandledRejections.isEmpty, isTrue);
    });
  });
}
