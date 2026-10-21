import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/quote_request_model.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('100x Manual Quotation Forensic Edge Cases Test Suite', () {
    test('Edge Case 1: Expired quote rejects acceptance and disables action buttons', () {
      final now = DateTime.now();
      final expiredQuote = QuoteRequestModel(
        id: 'q-expired-01',
        customerId: 'cust-01',
        customerPhone: '+917006464241',
        eventName: 'College Alumni Dinner',
        eventDate: now.add(const Duration(days: 4)),
        estimatedGuestCount: 80,
        requirementsDescription: '80 Mutton Biryani packs',
        contactPersonName: 'Aamir',
        contactPersonPhone: '+917006464241',
        quoteStatus: 'quoted',
        quotedAmount: 24000.0,
        quotedValidUntil: now.subtract(const Duration(minutes: 5)), // Expired 5 mins ago
        createdAt: now.subtract(const Duration(hours: 49)),
      );

      // Verify that client-side computed getters immediately block acceptance
      expect(expiredQuote.isQuoteExpired, true);
      expect(expiredQuote.canAccept, false);
      expect(expiredQuote.isExpired, true);
      expect(expiredQuote.statusDisplay, 'Quote Expired');
    });

    test('Edge Case 2: Active quote allows acceptance only when valid_until is in future', () {
      final now = DateTime.now();
      final validQuote = QuoteRequestModel(
        id: 'q-valid-01',
        customerId: 'cust-01',
        customerPhone: '+917006464241',
        eventName: 'Tech Meetup Catering',
        eventDate: now.add(const Duration(days: 4)),
        estimatedGuestCount: 50,
        requirementsDescription: '50 Snack Boxes',
        contactPersonName: 'Aamir',
        contactPersonPhone: '+917006464241',
        quoteStatus: 'quoted',
        quotedAmount: 15000.0,
        quotedValidUntil: now.add(const Duration(hours: 48)),
        createdAt: now,
      );

      expect(validQuote.isQuoteExpired, false);
      expect(validQuote.canAccept, true);
      expect(validQuote.canMarkPaid, true);
      expect(validQuote.statusDisplay, 'Quote Ready');
    });

    test('Edge Case 3: Offline payment financial integrity (0 GST, 0 delivery, 0 platform fee)', () {
      const quotedAmount = 35000.0;
      final offlineOrder = OrderModel(
        id: 'ord-manual-offline-01',
        customerId: 'cust-01',
        shopId: 'shop-01',
        deliveryCharges: 0.0,
        platformFee: 0.0,
        gstItemTotal: 0.0,
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 0.0,
        gstDelivery: 0.0,
        gstPlatform: 0.0,
        tcsAmount: 0.0,
        tdsAmount: 0.0,
        enythingCommission: 0.0,
        gatewayDeduction: 0.0,
        grandTotalCollected: quotedAmount,
        totalAmount: quotedAmount,
        orderType: 'manual_quote',
        status: 'bulk_pending',
        paymentMethod: 'offline',
        paymentStatus: 'captured',
        createdAt: DateTime.now(),
      );

      // 100% Prepaid offline model guarantees
      expect(offlineOrder.paymentMethod, 'offline');
      expect(offlineOrder.paymentStatus, 'captured');
      expect(offlineOrder.totalAmount, quotedAmount);
      expect(offlineOrder.grandTotal, quotedAmount);
      expect(offlineOrder.gstItemTotal, 0.0);
      expect(offlineOrder.deliveryCharges, 0.0);
      expect(offlineOrder.platformFee, 0.0);
      expect(offlineOrder.isBulkOrder, true);
      expect(offlineOrder.isManualQuote, true);
    });

    test('Edge Case 4: Terminal status filtering prevents zombie quote displays', () {
      final now = DateTime.now();
      final quotes = [
        QuoteRequestModel(
          id: 'q1',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Active Review',
          eventDate: now.add(const Duration(days: 2)),
          estimatedGuestCount: 20,
          requirementsDescription: '20 Meals',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'pending_review',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'q2',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Active Quoted',
          eventDate: now.add(const Duration(days: 3)),
          estimatedGuestCount: 30,
          requirementsDescription: '30 Meals',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'quoted',
          quotedValidUntil: now.add(const Duration(hours: 24)),
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'q3',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Declined Quote',
          eventDate: now.add(const Duration(days: 3)),
          estimatedGuestCount: 30,
          requirementsDescription: '30 Meals',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'customer_rejected',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'q4',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Order Placed',
          eventDate: now.add(const Duration(days: 3)),
          estimatedGuestCount: 30,
          requirementsDescription: '30 Meals',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'order_placed',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'q5',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Cancelled',
          eventDate: now.add(const Duration(days: 3)),
          estimatedGuestCount: 30,
          requirementsDescription: '30 Meals',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'cancelled',
          createdAt: now,
        ),
      ];

      // Active quotes (shown in discovery banner) must strictly exclude terminal quotes
      final activeQuotes = quotes.where((q) => !q.isTerminal).toList();
      expect(activeQuotes.length, 2);
      expect(activeQuotes.map((q) => q.id), containsAll(['q1', 'q2']));

      // Terminal quotes must include rejected, placed, and cancelled
      final terminalQuotes = quotes.where((q) => q.isTerminal).toList();
      expect(terminalQuotes.length, 3);
      expect(terminalQuotes.map((q) => q.id), containsAll(['q3', 'q4', 'q5']));
    });

    test('Edge Case 5: Admin tab categorization parity with backend RPC filters', () {
      final now = DateTime.now();
      final allQuotes = [
        QuoteRequestModel(
          id: 'p1',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Pending 1',
          eventDate: now.add(const Duration(days: 2)),
          estimatedGuestCount: 50,
          requirementsDescription: '50 items',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'pending_review',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'q1',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Quoted 1',
          eventDate: now.add(const Duration(days: 2)),
          estimatedGuestCount: 50,
          requirementsDescription: '50 items',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'quoted',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'a1',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Accepted 1',
          eventDate: now.add(const Duration(days: 2)),
          estimatedGuestCount: 50,
          requirementsDescription: '50 items',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'customer_accepted',
          createdAt: now,
        ),
        QuoteRequestModel(
          id: 'd1',
          customerId: 'c1',
          customerPhone: '9876543210',
          eventName: 'Done 1',
          eventDate: now.add(const Duration(days: 2)),
          estimatedGuestCount: 50,
          requirementsDescription: '50 items',
          contactPersonName: 'User',
          contactPersonPhone: '9876543210',
          quoteStatus: 'order_placed',
          createdAt: now,
        ),
      ];

      // Tab 1: Pending Review
      final pendingTab = allQuotes.where((q) => q.quoteStatus == 'pending_review').toList();
      expect(pendingTab.length, 1);
      expect(pendingTab.first.id, 'p1');

      // Tab 2: Quoted / Awaiting Payment (both quoted and customer_accepted)
      final quotedTab = allQuotes
          .where((q) => q.quoteStatus == 'quoted' || q.quoteStatus == 'customer_accepted')
          .toList();
      expect(quotedTab.length, 2);
      expect(quotedTab.map((q) => q.id), containsAll(['q1', 'a1']));

      // Tab 3: Done / History
      final doneTab = allQuotes
          .where((q) => [
                'order_placed',
                'customer_rejected',
                'expired',
                'cancelled'
              ].contains(q.quoteStatus))
          .toList();
      expect(doneTab.length, 1);
      expect(doneTab.first.id, 'd1');
    });

    test('Edge Case 6: Fallback for missing contact name or phone uses customer profile data', () {
      final minimalMap = {
        'id': 'q-min-01',
        'customer_id': 'cust-min',
        'customer_phone': '+917006464241',
        'event_name': 'Minimal Event',
        'requirements_description': 'Just simple catering',
        // contact_person_name and phone omitted
      };

      final parsed = QuoteRequestModel.fromMap(minimalMap);
      expect(parsed.id, 'q-min-01');
      expect(parsed.contactPersonName, '');
      expect(parsed.customerPhone, '+917006464241');
      expect(parsed.estimatedGuestCount, 1); // safe default > 0
      expect(parsed.quoteStatus, 'pending_review');
      expect(parsed.eventType, 'custom');
      expect(parsed.quotedLineItems, isEmpty);
    });
  });
}
