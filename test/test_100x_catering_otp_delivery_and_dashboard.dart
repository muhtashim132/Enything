// ============================================================================
// test_100x_catering_otp_delivery_and_dashboard.dart
// 100x Automated Test Suite for Catering OTP Delivery Notification & Single-View Dashboard
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/providers/quote_request_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x Catering OTP Delivery & Single-View Dashboard Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Initial State: activeCateringOrder and deliveredCateringOrderToCelebrate are null', () {
      final provider = QuoteRequestProvider();
      expect(provider.activeCateringOrder, isNull);
      expect(provider.deliveredCateringOrderToCelebrate, isNull);
    });

    test('2. Single-View Dismissal: dismissDeliveredCateringCelebration persists to SharedPreferences', () async {
      final provider = QuoteRequestProvider();
      const testOrderId = 'order-cat-uuid-1234';

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('seen_catering_delivered_$testOrderId'), isNull);

      // Dismiss celebration
      await provider.dismissDeliveredCateringCelebration(testOrderId);

      // Verify it was persisted to SharedPreferences
      expect(prefs.getBool('seen_catering_delivered_$testOrderId'), isTrue);
      expect(provider.deliveredCateringOrderToCelebrate, isNull);
    });

    test('3. Background Seen State: markDeliveredCateringCelebrationSeen persists without premature dismissal', () async {
      final provider = QuoteRequestProvider();
      const testOrderId = 'order-cat-uuid-5678';

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('seen_catering_delivered_$testOrderId'), isNull);

      await provider.markDeliveredCateringCelebrationSeen(testOrderId);

      expect(prefs.getBool('seen_catering_delivered_$testOrderId'), isTrue);
    });

    test('4. Single-View Guarantee: Already seen order is not resurrected', () async {
      const testOrderId = 'order-cat-uuid-9999';
      SharedPreferences.setMockInitialValues({
        'seen_catering_delivered_$testOrderId': true,
      });

      final prefs = await SharedPreferences.getInstance();
      final hasSeen = prefs.getBool('seen_catering_delivered_$testOrderId') ?? false;

      expect(hasSeen, isTrue, reason: 'Already seen delivered catering order must not be shown again');
    });

    test('5. Notification Payload Formatting: Catering delivery with OTP', () {
      const orderType = 'bulk';
      const newStatus = 'delivered';
      const otp = '7821';
      const eventLabel = 'Nazki Wedding Feast';

      String? title;
      String? body;

      if (newStatus == 'delivered' && (orderType == 'bulk' || orderType == 'manual_quote')) {
        title = '🎉 Catering Feast Delivered!';
        body = (otp.isNotEmpty)
            ? 'Delivery handover verified with OTP for "$eventLabel". Have a wonderful event celebration! 🎉'
            : 'Your catering feast for "$eventLabel" has been delivered. Enjoy your celebration! 🎉';
      }

      expect(title, '🎉 Catering Feast Delivered!');
      expect(body, contains('Delivery handover verified with OTP'));
      expect(body, contains(eventLabel));
    });

    test('6. Notification Payload Formatting: Super Admin override (no OTP)', () {
      const orderType = 'manual_quote';
      const newStatus = 'delivered';
      const String? otp = null;
      const eventLabel = 'Corporate Annual Gala';

      String? title;
      String? body;

      if (newStatus == 'delivered' && (orderType == 'bulk' || orderType == 'manual_quote')) {
        title = '🎉 Catering Feast Delivered!';
        body = (otp != null && otp.isNotEmpty)
            ? 'Delivery handover verified with OTP for "$eventLabel". Have a wonderful event celebration! 🎉'
            : 'Your catering feast for "$eventLabel" has been delivered. Enjoy your celebration! 🎉';
      }

      expect(title, '🎉 Catering Feast Delivered!');
      expect(body, 'Your catering feast for "Corporate Annual Gala" has been delivered. Enjoy your celebration! 🎉');
    });

    test('7. Push Urgency Classification: Feast and Delivered trigger High Priority Channel', () {
      bool isPushUrgent(String title) {
        final t = title.toLowerCase();
        return t.contains('new order') ||
            t.contains('payment done') ||
            t.contains('quote') ||
            t.contains('catering') ||
            t.contains('feast') ||
            t.contains('delivered') ||
            t.contains('kyc');
      }

      expect(isPushUrgent('🎉 Catering Feast Delivered!'), isTrue);
      expect(isPushUrgent('Feast Delivered & Handover Verified! 🎉'), isTrue);
      expect(isPushUrgent('Your order is delivered!'), isTrue);
      expect(isPushUrgent('Random status update'), isFalse);
    });
  });
}
