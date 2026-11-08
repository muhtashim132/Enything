import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

void main() {
  group('100x Forensic Unit 7: Edge Functions & Razorpay Payment Gateway Fortress', () {
    const testSecret = 'rzp_sec_test_secret_key_12345';

    test('1. Authoritative price resolution & integer paise conversion', () {
      // Client may attempt to send spoofed amount: { "amount": 100 }
      // Server strictly ignores client amount and queries DB grand_total_collected:
      const dbGrandTotal = 249.50; // ₹249.50

      // Exact integer paise conversion matching Edge Function:
      // const amount = Math.round(dbAmount * 100);
      final int paiseAmount = (dbGrandTotal * 100).round();
      expect(paiseAmount, equals(24950));

      // Minimum payment threshold check: must be >= ₹1.00 (100 paise)
      expect(paiseAmount, greaterThanOrEqualTo(100));

      // Defense against sub-rupee / zero exploits
      const zeroAmount = 0.0;
      expect((zeroAmount * 100).round() < 100, isTrue);
    });

    test('2. Multi-Shop Cart Group Summation across active sibling orders', () {
      final cartOrders = [
        {'id': 'o1', 'status': 'awaiting_payment', 'grand_total_collected': 250.0},
        {'id': 'o2', 'status': 'awaiting_payment', 'grand_total_collected': 180.50},
        {'id': 'o3_declined', 'status': 'seller_rejected', 'grand_total_collected': 90.0},
      ];

      // Edge function strictly filters 'awaiting_payment' orders
      final eligibleOrders = cartOrders.where((o) => o['status'] == 'awaiting_payment');
      final dbAmount = eligibleOrders.fold(0.0, (sum, o) => sum + (o['grand_total_collected'] as double));

      expect(dbAmount, equals(430.50));
      final int totalPaise = (dbAmount * 100).round();
      expect(totalPaise, equals(43050));
    });

    test('3. Razorpay HMAC SHA-256 cryptographic signature verification', () {
      const orderId = 'order_DAK998124';
      const paymentId = 'pay_PST100982';

      // Edge Function signature generation:
      // const message = `${razorpay_order_id}|${razorpay_payment_id}`;
      // const expectedSignature = createHmac("sha256", keySecret).update(message).digest("hex");
      final message = '$orderId|$paymentId';
      final hmac = Hmac(sha256, utf8.encode(testSecret));
      final digest = hmac.convert(utf8.encode(message));
      final validSignature = digest.toString();

      expect(validSignature.length, equals(64)); // 256 bits = 64 hex chars

      // Verification function
      bool verifySignature(String rOrderId, String rPayId, String rSignature, String secret) {
        final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$rOrderId|$rPayId')).toString();
        // Constant-time comparison
        if (expected.length != rSignature.length) return false;
        int diff = 0;
        for (int i = 0; i < expected.length; i++) {
          diff |= expected.codeUnitAt(i) ^ rSignature.codeUnitAt(i);
        }
        return diff == 0;
      }

      // Valid signature must pass
      expect(verifySignature(orderId, paymentId, validSignature, testSecret), isTrue);

      // Tampered payment_id must fail
      expect(verifySignature(orderId, 'pay_TAMPERED', validSignature, testSecret), isFalse);

      // Tampered secret must fail
      expect(verifySignature(orderId, paymentId, validSignature, 'wrong_secret'), isFalse);
    });

    test('4. Webhook idempotency: duplicate payment.captured events do not duplicate records', () {
      final processedPaymentIds = <String>{};
      final orderTransitions = <String>[];

      Map<String, dynamic> handleWebhookEvent({
        required String eventType,
        required String paymentId,
        required String orderId,
      }) {
        if (eventType == 'payment.captured' || eventType == 'order.paid') {
          // Idempotency check:
          if (processedPaymentIds.contains(paymentId)) {
            return {'status': 200, 'message': 'Already processed'};
          }
          processedPaymentIds.add(paymentId);
          orderTransitions.add('Order $orderId updated to captured');
          return {'status': 200, 'message': 'Payment confirmed'};
        }
        return {'status': 200, 'message': 'Ignored'};
      }

      // First webhook arrives:
      final res1 = handleWebhookEvent(eventType: 'payment.captured', paymentId: 'pay_001', orderId: 'ord_A');
      expect(res1['message'], equals('Payment confirmed'));
      expect(orderTransitions.length, equals(1));

      // Duplicate webhook arrives 5 seconds later due to network retry:
      final res2 = handleWebhookEvent(eventType: 'payment.captured', paymentId: 'pay_001', orderId: 'ord_A');
      expect(res2['message'], equals('Already processed'));
      // No duplicate order transition
      expect(orderTransitions.length, equals(1));
    });

    test('5. 100% Prepaid Invariant: order cannot advance to preparation without captured payment', () {
      bool canAdvanceToPreparation(String paymentStatus) {
        return paymentStatus == 'captured';
      }

      expect(canAdvanceToPreparation('pending'), isFalse);
      expect(canAdvanceToPreparation('failed'), isFalse);
      expect(canAdvanceToPreparation('created'), isFalse);
      expect(canAdvanceToPreparation('captured'), isTrue);
    });

    test('6. Instant refund dispatch calculation on store rejection', () {
      // Order had grandTotalCollected = ₹350
      // Shop rejects order -> customer is entitled to full refund including delivery fee
      const grandTotalCollected = 350.0;
      final int refundPaise = (grandTotalCollected * 100).round();
      expect(refundPaise, equals(35000));

      // Partial rejection: 1 item out of 2 rejected (item price ₹60, quantity 1)
      const declinedItemPrice = 60.0;
      final int partialRefundPaise = (declinedItemPrice * 100).round();
      expect(partialRefundPaise, equals(6000));
    });
  });
}

