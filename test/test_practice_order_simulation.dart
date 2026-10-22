import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/services/practice_order_service.dart';
import 'package:enythingmobilenew/services/bell_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x PRACTICE / DUMMY ORDER SIMULATION & AUDIO BELL ALERT TEST SUITE', () {
    setUp(() async {
      BellAlertService.instance.disableAudioForTesting = true;
      await BellAlertService.instance.clearAll();
    });

    tearDown(() async {
      await BellAlertService.instance.clearAll();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. MODEL TAGGING & PRACTICE IDENTIFICATION
    // ─────────────────────────────────────────────────────────────────────────
    test('1. OrderModel accurately detects practice orders across all tagging dimensions', () {
      // Dimension A: deliveryNotes
      final orderWithNotes = OrderModel(
        id: 'order-p1',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 0.0,
        deliveryCharges: 0.0,
        createdAt: DateTime.now(),
        deliveryNotes: '${PracticeOrderService.practiceTag} Merchant rush training',
      );
      expect(orderWithNotes.isPracticeOrder, isTrue);

      // Dimension B: addressLabel
      final orderWithLabel = OrderModel(
        id: 'order-p2',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 0.0,
        deliveryCharges: 0.0,
        createdAt: DateTime.now(),
        addressLabel: PracticeOrderService.practiceAddressLabel,
      );
      expect(orderWithLabel.isPracticeOrder, isTrue);

      // Dimension C: paymentMethod
      final orderWithPaymentMethod = OrderModel(
        id: 'order-p3',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 0.0,
        deliveryCharges: 0.0,
        createdAt: DateTime.now(),
        paymentMethod: PracticeOrderService.practicePaymentMethod,
      );
      expect(orderWithPaymentMethod.isPracticeOrder, isTrue);

      // Standard real order must NOT be marked as practice
      final realOrder = OrderModel(
        id: 'order-real',
        customerId: 'cust-real',
        status: 'confirmed',
        totalAmount: 450.0,
        deliveryCharges: 30.0,
        createdAt: DateTime.now(),
        addressLabel: 'Home',
        deliveryNotes: 'Leave at front gate please',
        paymentMethod: 'upi',
      );
      expect(realOrder.isPracticeOrder, isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. ORDER GROUP PRACTICE DETECTION & PREPAID MODEL ZERO-COD VERIFICATION
    // ─────────────────────────────────────────────────────────────────────────
    test('2. OrderGroup.isPractice correctly reflects sub-order composition and adheres to 100% Prepaid Model', () {
      final practiceOrder = OrderModel(
        id: 'order-practice-sub',
        customerId: 'cust-1',
        status: 'ready_for_pickup',
        totalAmount: 0.0,
        deliveryCharges: 0.0,
        riderEarnings: 0.0,
        createdAt: DateTime.now(),
        deliveryNotes: PracticeOrderService.practiceTag,
        paymentMethod: 'practice',
        paymentStatus: 'captured',
      );

      final groupWithPractice = OrderGroup('group-p1', [practiceOrder]);
      expect(groupWithPractice.isPractice, isTrue);

      // 100% Prepaid Rule: Practice deliveries MUST have ₹0 COD collection and zero financial debt
      expect(groupWithPractice.isCod, isFalse);
      expect(groupWithPractice.isPrepaid, isTrue);
      expect(groupWithPractice.codAmountToCollect, 0.0);
      expect(groupWithPractice.totalEarnings, 0.0);

      // Real order group
      final realOrder = OrderModel(
        id: 'order-real-sub',
        customerId: 'cust-2',
        status: 'confirmed',
        totalAmount: 500.0,
        deliveryCharges: 40.0,
        riderEarnings: 32.0,
        createdAt: DateTime.now(),
        paymentMethod: 'upi',
        paymentStatus: 'captured',
      );
      final realGroup = OrderGroup('group-real', [realOrder]);
      expect(realGroup.isPractice, isFalse);
      expect(realGroup.isPrepaid, isTrue);
      expect(realGroup.codAmountToCollect, 0.0);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. AUDIO BELL ALERT LIFECYCLE FOR PRACTICE ORDERS
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Practice orders trigger BellAlertService and stop on resolution or clear', () async {
      final bell = BellAlertService.instance;
      const practiceOrderId = 'practice-alert-order-101';
      const practiceGroupId = 'practice-alert-group-202';

      expect(bell.hasPendingOrders, isFalse);
      expect(bell.pendingCount, 0);

      // Simulate incoming practice order alert
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      await bell.addPendingOrder(practiceOrderId, expiration: deadline);

      expect(bell.hasPendingOrders, isTrue);
      expect(bell.pendingCount, 1);

      // Rider group alert added
      await bell.addPendingOrder(practiceGroupId, expiration: deadline);
      expect(bell.pendingCount, 2);

      // Merchant accepts order -> order removed from bell
      await bell.removePendingOrder(practiceOrderId);
      expect(bell.pendingCount, 1);
      expect(bell.hasPendingOrders, isTrue);

      // Rider accepts order -> group removed from bell -> all silenced
      await bell.removePendingOrder(practiceGroupId);
      expect(bell.pendingCount, 0);
      expect(bell.hasPendingOrders, isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. APPLE REVIEWER PHONE SAFETY & FRAUD PREVENTION
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Practice orders strictly avoid Apple Reviewer phone triggers (%999999999%)', () {
      // Verify default practice phone does not match %999999999%
      expect(
        PracticeOrderService.defaultPracticePhone.contains('999999999'),
        isFalse,
        reason: 'Practice phone must not match 999999999 to prevent accidental reviewer auto-accept triggers',
      );
      expect(PracticeOrderService.defaultPracticePhone, '+919876500000');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. PRACTICE ORDER SIMULATION LIFECYCLE TRANSITIONS
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Practice order state progression mirrors real production flow safely', () {
      // Initial: awaiting_acceptance (bell rings)
      var order = OrderModel(
        id: 'flow-order-1',
        customerId: 'cust-1',
        status: 'awaiting_acceptance',
        totalAmount: 0.0,
        deliveryCharges: 0.0,
        createdAt: DateTime.now(),
        deliveryNotes: PracticeOrderService.practiceTag,
        paymentMethod: 'practice',
        paymentStatus: 'captured',
      );
      expect(order.status, 'awaiting_acceptance');
      expect(order.isPracticeOrder, isTrue);

      // Step 2: Merchant accepts -> sets prep time (transitions to 'preparing')
      order = order.copyWith(
        status: 'preparing',
        sellerAccepted: true,
      );
      expect(order.status, 'preparing');
      expect(order.sellerAccepted, isTrue);

      // Step 3: Kitchen finishes -> marked ready for pickup
      final readyTime = DateTime.now();
      order = order.copyWith(
        status: 'ready_for_pickup',
        orderReadyTime: readyTime,
      );
      expect(order.status, 'ready_for_pickup');
      expect(order.orderReadyTime, readyTime);

      // Step 4: Rider arrives at shop
      final arrivedTime = DateTime.now();
      order = order.copyWith(
        arrivedAtShopTime: arrivedTime,
      );
      expect(order.arrivedAtShopTime, arrivedTime);

      // Step 5: Rider confirms pickup
      order = order.copyWith(status: 'picked_up');
      expect(order.status, 'picked_up');

      // Step 6: Rider starts journey to customer drop
      order = order.copyWith(status: 'out_for_delivery');
      expect(order.status, 'out_for_delivery');

      // Step 7: Rider delivers parcel (₹0 cash collected)
      order = order.copyWith(status: 'delivered');
      expect(order.status, 'delivered');
      expect(order.totalAmount, 0.0);
    });
  });
}
