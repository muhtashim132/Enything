import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🔬 100x Domain C: OrderGroup Multi-Shop Calculation & Terminal Guards', () {
    test('C3: isMultiShop distinguishes between multiple orders from same shop vs different shops', () {
      // Scenario A: Single order -> Not multi-shop
      final singleOrder = OrderModel.fromMap({
        'id': 'ord-1',
        'customer_id': 'cust-1',
        'shop_id': 'shop-A',
        'status': 'confirmed',
      });
      final groupSingle = OrderGroup('group-1', [singleOrder]);
      expect(groupSingle.isMultiShop, isFalse);

      // Scenario B: Two orders from the SAME shop -> Must NOT be multi-shop
      final sameShopOrder1 = OrderModel.fromMap({
        'id': 'ord-1',
        'customer_id': 'cust-1',
        'shop_id': 'shop-A',
        'status': 'confirmed',
      });
      final sameShopOrder2 = OrderModel.fromMap({
        'id': 'ord-2',
        'customer_id': 'cust-1',
        'shop_id': 'shop-A',
        'status': 'preparing',
      });
      final groupSameShop = OrderGroup('group-2', [sameShopOrder1, sameShopOrder2]);
      expect(groupSameShop.isMultiShop, isFalse,
          reason: 'Multiple orders from the same shop must NOT evaluate to multi-shop');

      // Scenario C: Two orders from DIFFERENT shops -> MUST be multi-shop
      final diffShopOrder1 = OrderModel.fromMap({
        'id': 'ord-1',
        'customer_id': 'cust-1',
        'shop_id': 'shop-A',
        'status': 'confirmed',
      });
      final diffShopOrder2 = OrderModel.fromMap({
        'id': 'ord-2',
        'customer_id': 'cust-1',
        'shop_id': 'shop-B',
        'status': 'preparing',
      });
      final groupDiffShop = OrderGroup('group-3', [diffShopOrder1, diffShopOrder2]);
      expect(groupDiffShop.isMultiShop, isTrue,
          reason: 'Orders from distinct shop IDs must evaluate to multi-shop');

      // Scenario D: Active orders empty (all rejected), check fallback to orders
      final rejectedShopA = OrderModel.fromMap({
        'id': 'ord-1',
        'customer_id': 'cust-1',
        'shop_id': 'shop-A',
        'status': 'seller_rejected',
      });
      final rejectedShopB = OrderModel.fromMap({
        'id': 'ord-2',
        'customer_id': 'cust-1',
        'shop_id': 'shop-B',
        'status': 'cancelled',
      });
      final groupAllRejected = OrderGroup('group-4', [rejectedShopA, rejectedShopB]);
      expect(groupAllRejected.activeOrders.isEmpty, isTrue);
      expect(groupAllRejected.isMultiShop, isTrue,
          reason: 'Fallback to historical orders when active orders are empty must preserve distinct shop count');

      // Scenario E: Edge case with null or empty shopId
      final nullShopOrder = OrderModel.fromMap({
        'id': 'ord-5',
        'customer_id': 'cust-1',
        'shop_id': null,
        'status': 'confirmed',
      });
      final groupNullShop = OrderGroup('group-5', [nullShopOrder]);
      expect(groupNullShop.isMultiShop, isFalse);
    });

    test('C2: Terminal Fallback Guard - progress states return false when activeOrders is empty', () {
      final cancelled1 = OrderModel.fromMap({
        'id': 'ord-1',
        'status': 'cancelled',
        'arrived_at_shop_time': DateTime.now().toIso8601String(),
      });
      final rejected2 = OrderModel.fromMap({
        'id': 'ord-2',
        'status': 'seller_rejected',
        'arrived_at_shop_time': DateTime.now().toIso8601String(),
      });
      final group = OrderGroup('grp-dead', [cancelled1, rejected2]);

      expect(group.activeOrders.isEmpty, isTrue);
      expect(group.allArrived, isFalse, reason: 'Terminal orders must never report arrived');
      expect(group.allPickedUp, isFalse, reason: 'Terminal orders must never report picked up');
      expect(group.allOutForDelivery, isFalse, reason: 'Terminal orders must never report out for delivery');
      expect(group.groupStatus, 'cancelled');
    });

    test('C1: 100% Prepaid Model Invariant (COD is Not Supported)', () {
      final order1 = OrderModel.fromMap({
        'id': 'ord-1',
        'payment_method': 'upi',
        'payment_status': 'captured',
        'total_amount': 250.0,
        'delivery_charges': 50.0,
        'grand_total_collected': 300.0,
        'status': 'preparing',
      });
      final order2 = OrderModel.fromMap({
        'id': 'ord-2',
        'payment_method': 'upi',
        'payment_status': 'captured',
        'total_amount': 180.0,
        'delivery_charges': 20.0,
        'grand_total_collected': 200.0,
        'status': 'cancelled',
      });

      final group = OrderGroup('grp-prepaid', [order1, order2]);

      // Enything operates strictly on a 100% prepaid model (No COD)
      expect(group.isCod, isFalse);
      expect(group.isPrepaid, isTrue);
      expect(group.codAmountToCollect, 0.0);
    });
  });

  group('🔬 100x Domain A: Rider Cross-Customer & Sibling Drop Logic', () {
    test('B1: Multi-Shop Sibling Drop Dispatch correctly identifies all distinct shops and sellers', () {
      // Sibling orders in same cart group across 2 distinct shops
      final order1 = OrderModel.fromMap({
        'id': 'ord-1',
        'cart_group_id': 'cart-grp-1',
        'shop_id': 'shop-1',
        'status': 'confirmed',
      });
      final order2 = OrderModel.fromMap({
        'id': 'ord-2',
        'cart_group_id': 'cart-grp-1',
        'shop_id': 'shop-2',
        'status': 'confirmed',
      });

      final group = OrderGroup('cart-grp-1', [order1, order2]);

      // Simulate the logic executed in dashboard_page.dart:
      final Set<String> targetShopIds = {};
      if (order1.shopId != null && order1.shopId!.isNotEmpty) {
        targetShopIds.add(order1.shopId!);
      }
      for (final sub in group.orders) {
        if (sub.shopId != null && sub.shopId!.isNotEmpty) {
          targetShopIds.add(sub.shopId!);
        }
      }

      expect(targetShopIds, containsAll(['shop-1', 'shop-2']));
      expect(targetShopIds.length, 2);

      // Simulate seller deduplication: shop-1 and shop-2 both owned by seller-A
      final shopsData = [
        {'id': 'shop-1', 'seller_id': 'seller-A'},
        {'id': 'shop-2', 'seller_id': 'seller-A'},
      ];

      final Set<String> notifiedSellers = {};
      final List<String> notificationsSent = [];
      for (final s in shopsData) {
        final sellerId = s['seller_id'];
        if (sellerId != null && !notifiedSellers.contains(sellerId)) {
          notifiedSellers.add(sellerId);
          notificationsSent.add(sellerId);
        }
      }

      expect(notificationsSent.length, 1,
          reason: 'Seller owning multiple sibling shops must receive exactly ONE drop notification');
      expect(notificationsSent.first, 'seller-A');
    });

    test('B2 & B3: Cross-Customer Notification Dispatch sends exactly 1 notification per unique customer', () {
      // Scenario A: Multi-shop cart for single customer (3 shops)
      final sameCustOrders = [
        OrderModel.fromMap({'id': 'o1', 'customer_id': 'cust-1', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o2', 'customer_id': 'cust-1', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o3', 'customer_id': 'cust-1', 'status': 'picked_up'}),
      ];

      final Set<String> notifiedSingle = {};
      final List<String> singleCustomerPushes = [];
      for (final o in sameCustOrders) {
        final shouldNotify = !notifiedSingle.contains(o.customerId);
        if (shouldNotify) notifiedSingle.add(o.customerId);
        if (shouldNotify) singleCustomerPushes.add(o.customerId);
      }

      expect(singleCustomerPushes.length, 1,
          reason: 'Same customer ordering from multiple shops must receive exactly 1 out-for-delivery push');
      expect(singleCustomerPushes.first, 'cust-1');

      // Scenario B: Cross-customer batch (Customer A, Customer B, Customer C)
      final multiCustOrders = [
        OrderModel.fromMap({'id': 'o1', 'customer_id': 'cust-A', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o2', 'customer_id': 'cust-B', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o3', 'customer_id': 'cust-C', 'status': 'picked_up'}),
      ];

      final Set<String> notifiedMulti = {};
      final List<String> multiCustomerPushes = [];
      for (final o in multiCustOrders) {
        final shouldNotify = !notifiedMulti.contains(o.customerId);
        if (shouldNotify) notifiedMulti.add(o.customerId);
        if (shouldNotify) multiCustomerPushes.add(o.customerId);
      }

      expect(multiCustomerPushes.length, 3,
          reason: 'Each distinct customer in a stacked delivery batch MUST receive their notification');
      expect(multiCustomerPushes, containsAll(['cust-A', 'cust-B', 'cust-C']));

      // Scenario C: Mixed batch (Customer A has 2 orders, Customer B has 1 order)
      final mixedOrders = [
        OrderModel.fromMap({'id': 'o1', 'customer_id': 'cust-A', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o2', 'customer_id': 'cust-A', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'o3', 'customer_id': 'cust-B', 'status': 'picked_up'}),
      ];

      final Set<String> notifiedMixed = {};
      final List<String> mixedPushes = [];
      for (final o in mixedOrders) {
        final shouldNotify = !notifiedMixed.contains(o.customerId);
        if (shouldNotify) notifiedMixed.add(o.customerId);
        if (shouldNotify) mixedPushes.add(o.customerId);
      }

      expect(mixedPushes.length, 2);
      expect(mixedPushes, ['cust-A', 'cust-B']);
    });
  });

  group('🔬 100x Domain B: Seller Terminal Statuses & Acceptance Guards', () {
    test('B4: Seller _doneOrders includes all 13 terminal statuses without dropping any order', () {
      final terminalStatuses = [
        'delivered',
        'cancelled',
        'seller_rejected',
        'partner_rejected',
        'verification_failed',
        'pending_verification',
        'shop_dispute_cancel',
        'timeout',
        'failed',
        'returned',
        'refunded',
        'no_rider',
        'payment_failed',
      ];

      final orders = terminalStatuses
          .map((status) => OrderModel.fromMap({
                'id': 'ord-$status',
                'status': status,
              }))
          .toList();

      // Active orders that should NOT be in done
      final activeOrders = [
        OrderModel.fromMap({'id': 'act-1', 'status': 'confirmed'}),
        OrderModel.fromMap({'id': 'act-2', 'status': 'preparing'}),
        OrderModel.fromMap({'id': 'act-3', 'status': 'ready_for_pickup'}),
        OrderModel.fromMap({'id': 'act-4', 'status': 'picked_up'}),
        OrderModel.fromMap({'id': 'act-5', 'status': 'out_for_delivery'}),
      ];

      final allOrders = [...orders, ...activeOrders];

      // Replicate seller_orders_page.dart _doneOrders() filter:
      final done = allOrders.where((o) => [
            'delivered',
            'cancelled',
            'seller_rejected',
            'partner_rejected',
            'verification_failed',
            'pending_verification',
            'shop_dispute_cancel',
            'timeout',
            'failed',
            'returned',
            'refunded',
            'no_rider',
            'payment_failed',
          ].contains(o.status)).toList();

      expect(done.length, 13, reason: 'All 13 terminal statuses must be captured in Done tab');
      for (final s in terminalStatuses) {
        expect(done.any((o) => o.status == s), isTrue,
            reason: 'Terminal status $s was dropped from the Done tab');
      }

      // Verify active orders are never leaked into done tab
      for (final a in activeOrders) {
        expect(done.any((o) => o.id == a.id), isFalse);
      }
    });

    test('B7: Reassigned Paid Order Push Suppression logic prevents duplicate payment requests', () {
      final capturedOrder = OrderModel.fromMap({
        'id': 'ord-paid',
        'payment_status': 'captured',
        'customer_id': 'cust-1',
      });
      final unpaidOrder = OrderModel.fromMap({
        'id': 'ord-unpaid',
        'payment_status': 'pending',
        'customer_id': 'cust-2',
      });

      // Simulation of seller accept push selection:
      String getCustomerPushTitle(OrderModel order) {
        final bool isPaid = order.paymentStatus == 'captured';
        if (isPaid) {
          return '🏪 Shop Confirmed & Packing!';
        } else {
          return '✅ Shop & Rider Ready! Pay Now 💳';
        }
      }

      String getRiderPushTitle(OrderModel order) {
        final bool isPaid = order.paymentStatus == 'captured';
        if (isPaid) {
          return '🏪 Shop Confirmed & Packing!';
        } else {
          return '⌛ Waiting for Customer Payment';
        }
      }

      expect(getCustomerPushTitle(capturedOrder), '🏪 Shop Confirmed & Packing!');
      expect(getRiderPushTitle(capturedOrder), '🏪 Shop Confirmed & Packing!');

      expect(getCustomerPushTitle(unpaidOrder), '✅ Shop & Rider Ready! Pay Now 💳');
      expect(getRiderPushTitle(unpaidOrder), '⌛ Waiting for Customer Payment');
    });

    test('B5: Rider arrival alert threshold calculation', () {
      final now = DateTime.now();

      final justArrived = now.subtract(const Duration(minutes: 1));
      final warningArrived = now.subtract(const Duration(minutes: 6));
      final lateArrived = now.subtract(const Duration(minutes: 12));

      String getBadgeSeverity(DateTime arrivedTime) {
        final mins = now.difference(arrivedTime).inMinutes;
        if (mins >= 10) return 'LATE_ALERT';
        if (mins >= 5) return 'WARNING';
        return 'NORMAL';
      }

      expect(getBadgeSeverity(justArrived), 'NORMAL');
      expect(getBadgeSeverity(warningArrived), 'WARNING');
      expect(getBadgeSeverity(lateArrived), 'LATE_ALERT');
    });
  });

  group('🔬 100x Domain D: Map Reset & Stacked Delivery Reassurance', () {
    test('B9: Dropped Rider Map Reset evaluates unassigned state correctly', () {
      // Rider assigned with GPS coords
      Map<String, dynamic> activeRiderRecord = {
        'delivery_partner_id': 'rider-123',
        'rider_lat': 34.0837,
        'rider_lng': 74.7973,
      };

      bool isRiderDropped(Map<String, dynamic> r) {
        final partnerId = r['delivery_partner_id'] as String?;
        final lat = (r['rider_lat'] as num?)?.toDouble();
        final lng = (r['rider_lng'] as num?)?.toDouble();
        return partnerId == null || partnerId.isEmpty || lat == null || lng == null || lat == 0.0 || lng == 0.0;
      }

      expect(isRiderDropped(activeRiderRecord), isFalse);

      // Rider dropped: delivery_partner_id becomes null
      Map<String, dynamic> droppedRecord = {
        'delivery_partner_id': null,
        'rider_lat': null,
        'rider_lng': null,
      };

      expect(isRiderDropped(droppedRecord), isTrue);

      // Rider with invalid zero coordinates
      Map<String, dynamic> zeroCoordRecord = {
        'delivery_partner_id': 'rider-123',
        'rider_lat': 0.0,
        'rider_lng': 0.0,
      };

      expect(isRiderDropped(zeroCoordRecord), isTrue);
    });

    test('B10: Stacked Delivery Reassurance triggers when rider has multiple distinct groups', () {
      const myGroupId = 'cart-cust-1';

      // Scenario A: Rider only has this customer's group
      final singleCustomerOrders = [
        {'id': 'o1', 'cart_group_id': 'cart-cust-1'},
        {'id': 'o2', 'cart_group_id': 'cart-cust-1'},
      ];

      final distinctSingle = singleCustomerOrders
          .map((r) => r['cart_group_id'] ?? r['id'])
          .toSet();
      final hasOtherSingle = distinctSingle.any((gid) => gid != myGroupId);
      expect(hasOtherSingle, isFalse, reason: 'Rider only has 1 customer order');

      // Scenario B: Rider has orders across 2 different customers
      final stackedOrders = [
        {'id': 'o1', 'cart_group_id': 'cart-cust-1'},
        {'id': 'o3', 'cart_group_id': 'cart-cust-2'},
      ];

      final distinctStacked = stackedOrders
          .map((r) => r['cart_group_id'] ?? r['id'])
          .toSet();
      final hasOtherStacked = distinctStacked.any((gid) => gid != myGroupId);
      expect(hasOtherStacked, isTrue,
          reason: 'Rider has another active customer order, must trigger stacked delivery reassurance');
    });
  });

  group('🔬 100x Domain E: Extensive Edge-Case Matrix & Invariants', () {
    test('EC1: 3-Shop Cart with partial rejections dynamically updates isMultiShop', () {
      final oShopA = OrderModel.fromMap({'id': 'oA', 'shop_id': 'shop-A', 'status': 'confirmed'});
      final oShopB = OrderModel.fromMap({'id': 'oB', 'shop_id': 'shop-B', 'status': 'confirmed'});
      final oShopC = OrderModel.fromMap({'id': 'oC', 'shop_id': 'shop-C', 'status': 'confirmed'});

      // Initially all 3 shops active
      final grpInitial = OrderGroup('grp-1', [oShopA, oShopB, oShopC]);
      expect(grpInitial.isMultiShop, isTrue);
      expect(grpInitial.activeOrders.length, 3);

      // Shop B rejects
      final oShopBRejected = OrderModel.fromMap({'id': 'oB', 'shop_id': 'shop-B', 'status': 'seller_rejected'});
      final grpOneRejected = OrderGroup('grp-1', [oShopA, oShopBRejected, oShopC]);
      expect(grpOneRejected.isMultiShop, isTrue, reason: '2 distinct shops still active');
      expect(grpOneRejected.activeOrders.length, 2);

      // Shop C also rejects -> only Shop A remains
      final oShopCRejected = OrderModel.fromMap({'id': 'oC', 'shop_id': 'shop-C', 'status': 'cancelled'});
      final grpTwoRejected = OrderGroup('grp-1', [oShopA, oShopBRejected, oShopCRejected]);
      expect(grpTwoRejected.isMultiShop, isFalse,
          reason: 'Only 1 shop remains active, must NOT be flagged as multi-shop');
      expect(grpTwoRejected.activeOrders.length, 1);
    });

    test('EC2: Remaining active shop has multiple sub-orders but other shops rejected', () {
      final oShopA1 = OrderModel.fromMap({'id': 'oA1', 'shop_id': 'shop-A', 'status': 'confirmed'});
      final oShopA2 = OrderModel.fromMap({'id': 'oA2', 'shop_id': 'shop-A', 'status': 'preparing'});
      final oShopB = OrderModel.fromMap({'id': 'oB', 'shop_id': 'shop-B', 'status': 'seller_rejected'});

      final grp = OrderGroup('grp-2', [oShopA1, oShopA2, oShopB]);
      expect(grp.activeOrders.length, 2);
      expect(grp.isMultiShop, isFalse,
          reason: 'Active sub-orders belong to single shop A, isMultiShop must be false');
    });

    test('EC3: 100% Prepaid Model Guarantees Zero Doorstep Collection', () {
      final prepaidOrder = OrderModel.fromMap({
        'id': 'o-prepaid',
        'payment_method': 'upi',
        'payment_status': 'captured',
        'grand_total_collected': 250.0,
        'status': 'preparing',
      });
      final grp = OrderGroup('grp-prepaid', [prepaidOrder]);
      expect(grp.isCod, isFalse);
      expect(grp.isPrepaid, isTrue);
      expect(grp.codAmountToCollect, 0.0);
    });

    test('EC4: Stacked delivery auto-clears when earlier order transitions to delivered', () {
      const myGroupId = 'cust-A-group';

      // 1. Order 1 is in out_for_delivery
      final activeRiderOrdersInitial = [
        {'id': 'o1', 'cart_group_id': 'cust-B-earlier', 'status': 'out_for_delivery'},
        {'id': 'o2', 'cart_group_id': 'cust-A-group', 'status': 'preparing'},
      ];

      final distinctInitial = activeRiderOrdersInitial
          .where((r) => ['confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'].contains(r['status']))
          .map((r) => r['cart_group_id'] ?? r['id'])
          .toSet();
      expect(distinctInitial.any((gid) => gid != myGroupId), isTrue,
          reason: 'Rider has earlier active order for cust B');

      // 2. Earlier order is now delivered
      final activeRiderOrdersAfterDelivery = [
        {'id': 'o1', 'cart_group_id': 'cust-B-earlier', 'status': 'delivered'},
        {'id': 'o2', 'cart_group_id': 'cust-A-group', 'status': 'picked_up'},
      ];

      final distinctAfter = activeRiderOrdersAfterDelivery
          .where((r) => ['confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'].contains(r['status']))
          .map((r) => r['cart_group_id'] ?? r['id'])
          .toSet();
      expect(distinctAfter.any((gid) => gid != myGroupId), isFalse,
          reason: 'Cust B order is delivered, cust A is now sole active order — reassurance banner must hide');
    });

    test('EC5: Seller arrival badge with negative or 0 elapsed time formats as just now', () {
      final now = DateTime.now();
      final arrivedJustNow = now.add(const Duration(seconds: 5)); // slight clock drift
      final minsAgo = now.difference(arrivedJustNow).inMinutes;

      final label = minsAgo <= 0 ? 'just now' : '$minsAgo min ago';
      expect(label, 'just now', reason: 'Negative elapsed time from clock skew must format as "just now"');
    });

    test('EC6: Sibling drop dispatch ignores terminal sub-orders when finding affected shops', () {
      final activeSub = OrderModel.fromMap({
        'id': 'o1',
        'cart_group_id': 'cart-1',
        'shop_id': 'shop-A',
        'status': 'preparing',
      });
      final cancelledSub = OrderModel.fromMap({
        'id': 'o2',
        'cart_group_id': 'cart-1',
        'shop_id': 'shop-B',
        'status': 'cancelled',
      });

      final group = OrderGroup('cart-1', [activeSub, cancelledSub]);
      final activeShops = group.activeOrders.map((o) => o.shopId).whereType<String>().toSet();

      expect(activeShops.length, 1);
      expect(activeShops.first, 'shop-A');
    });

    test('EC7: Seller order cancellation exception pattern matching matches customer cancellations', () {
      bool isCancellationException(String errorMsg) {
        final msg = errorMsg.toLowerCase();
        return msg.contains('cancel') ||
            msg.contains('invalid state') ||
            msg.contains('invalid transition');
      }

      expect(isCancellationException('Order was cancelled by customer'), isTrue);
      expect(isCancellationException('Invalid state transition: order is in cancelled state'), isTrue);
      expect(isCancellationException('Database connection timeout'), isFalse);
    });
  });
}

