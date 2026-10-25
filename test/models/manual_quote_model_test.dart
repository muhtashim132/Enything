import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/quote_request_model.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('Manual Quotation & Offline Event Catering Model Unit Tests', () {
    test('QuoteLineItem serialization and deserialization', () {
      const lineItem = QuoteLineItem(
        item: 'Paneer Butter Masala Handi x10',
        price: 2500.0,
      );

      final map = lineItem.toMap();
      expect(map['item'], 'Paneer Butter Masala Handi x10');
      expect(map['price'], 2500.0);

      final reconstructed = QuoteLineItem.fromMap(map);
      expect(reconstructed.item, lineItem.item);
      expect(reconstructed.price, lineItem.price);

      // Default fallbacks for malformed maps
      final empty = QuoteLineItem.fromMap({});
      expect(empty.item, '');
      expect(empty.price, 0.0);
    });

    test('QuoteRequestModel fromMap and toMap roundtrip with full fields', () {
      final now = DateTime.now();
      final eventDate = now.add(const Duration(days: 5));
      final validUntil = now.add(const Duration(hours: 48));

      final quote = QuoteRequestModel(
        id: 'quote-uuid-1234',
        customerId: 'cust-uuid-5678',
        customerName: 'Aamir Nazki',
        customerPhone: '+917006464241',
        eventName: 'Grand Wedding Reception',
        eventType: 'wedding',
        eventDate: eventDate,
        estimatedGuestCount: 250,
        dietaryPreferences: 'Halal 🌙',
        requirementsDescription: '50 Rogan Josh Handi, 100 Rista Handi, 200 Naan, 50 Pulao',
        venueAddress: 'Heritage Grand Hall, Boulevard Road, Srinagar',
        venueLat: 34.0837,
        venueLng: 74.7973,
        venueDeliveryNotes: 'Use VIP Gate 2 for kitchen loading',
        preferredDeliveryTime: '1:00 PM - 3:00 PM',
        contactPersonName: 'Aamir Nazki',
        contactPersonPhone: '+917006464241',
        secondaryContactPhone: '+919906123456',
        gatePassInstructions: 'Pass already approved by security in charge',
        preferredShopId: 'shop-uuid-9999',
        preferredShopName: 'Ahdoos Heritage Kitchen',
        quoteStatus: 'quoted',
        reviewedBy: 'admin-uuid-0001',
        reviewedAt: now,
        quotedAmount: 48500.0,
        quotedNotes: 'Flat rate including delivery and live warm-boxes. 100% offline payment.',
        quotedValidUntil: validUntil,
        quotedLineItems: const [
          QuoteLineItem(item: 'Rogan Josh Handi x50', price: 25000.0),
          QuoteLineItem(item: 'Rista Handi x100', price: 18000.0),
          QuoteLineItem(item: 'Naan & Pulao x250', price: 5500.0),
        ],
        createdAt: now,
      );

      final map = quote.toMap();
      expect(map['id'], 'quote-uuid-1234');
      expect(map['customer_id'], 'cust-uuid-5678');
      expect(map['customer_name'], 'Aamir Nazki');
      expect(map['customer_phone'], '+917006464241');
      expect(map['event_name'], 'Grand Wedding Reception');
      expect(map['estimated_guest_count'], 250);
      expect(map['quoted_amount'], 48500.0);
      expect((map['quoted_line_items'] as List).length, 3);

      final parsed = QuoteRequestModel.fromMap(map);
      expect(parsed.id, quote.id);
      expect(parsed.customerName, quote.customerName);
      expect(parsed.customerPhone, quote.customerPhone);
      expect(parsed.eventName, quote.eventName);
      expect(parsed.estimatedGuestCount, 250);
      expect(parsed.quotedAmount, 48500.0);
      expect(parsed.quotedLineItems.length, 3);
      expect(parsed.quotedLineItems[0].item, 'Rogan Josh Handi x50');
      expect(parsed.quotedLineItems[0].price, 25000.0);
    });

    test('QuoteRequestModel lifecycle state getters test matrix', () {
      final now = DateTime.now();
      final futureValid = now.add(const Duration(hours: 24));
      final pastValid = now.subtract(const Duration(hours: 2));

      // 1. Pending review
      final pending = QuoteRequestModel(
        id: 'q1',
        customerId: 'c1',
        customerPhone: '+919999999999',
        eventName: 'Birthday Party',
        eventDate: now.add(const Duration(days: 3)),
        estimatedGuestCount: 30,
        requirementsDescription: '30 burgers and 30 milkshakes',
        contactPersonName: 'Host',
        contactPersonPhone: '+919999999999',
        quoteStatus: 'pending_review',
        createdAt: now,
      );

      expect(pending.isPendingReview, true);
      expect(pending.isQuoted, false);
      expect(pending.isAccepted, false);
      expect(pending.isPaid, false);
      expect(pending.isOrderPlaced, false);
      expect(pending.isExpired, false);
      expect(pending.isCancelled, false);
      expect(pending.isTerminal, false);
      expect(pending.canAccept, false);
      expect(pending.statusDisplay, 'Under Review');

      // 2. Quoted (active, unexpired)
      final quotedActive = pending.copyWith(
        quoteStatus: 'quoted',
        quotedAmount: 12000.0,
        quotedValidUntil: futureValid,
      );
      expect(quotedActive.isQuoted, true);
      expect(quotedActive.isQuoteExpired, false);
      expect(quotedActive.canAccept, true);
      expect(quotedActive.canMarkPaid, true);
      expect(quotedActive.statusDisplay, 'Quote Ready');

      // 3. Quoted (expired)
      final quotedExpired = pending.copyWith(
        quoteStatus: 'quoted',
        quotedAmount: 12000.0,
        quotedValidUntil: pastValid,
      );
      expect(quotedExpired.isQuoteExpired, true);
      expect(quotedExpired.canAccept, false);
      expect(quotedExpired.isExpired, true);
      expect(quotedExpired.statusDisplay, 'Quote Expired');

      // 4. Customer Accepted
      final accepted = quotedActive.copyWith(
        quoteStatus: 'customer_accepted',
        customerResponseAt: now,
      );
      expect(accepted.isAccepted, true);
      expect(accepted.canAccept, false);
      expect(accepted.canMarkPaid, true);
      expect(accepted.isTerminal, false);
      expect(accepted.statusDisplay, 'Accepted — Awaiting Payment');

      // 5. Payment Received & Order Placed
      final paid = accepted.copyWith(
        quoteStatus: 'order_placed',
        paymentMethod: 'upi',
        paymentReference: 'UPI-TXN-987654',
        paymentReceivedAt: now,
        resultingOrderId: 'order-12345',
      );
      expect(paid.isPaid, true);
      expect(paid.isOrderPlaced, true);
      expect(paid.isTerminal, true);
      expect(paid.statusDisplay, 'Order Created');

      // 6. Declined
      final rejected = pending.copyWith(
        quoteStatus: 'customer_rejected',
        customerRejectionReason: 'Found cheaper alternative',
      );
      expect(rejected.isRejected, true);
      expect(rejected.isTerminal, true);
      expect(rejected.statusDisplay, 'Declined');

      // 7. Cancelled
      final cancelled = pending.copyWith(quoteStatus: 'cancelled');
      expect(cancelled.isCancelled, true);
      expect(cancelled.isTerminal, true);
      expect(cancelled.statusDisplay, 'Cancelled');
    });

    test('OrderModel manual_quote order_type integration', () {
      final manualQuoteOrder = OrderModel(
        id: 'ord-manual-9999',
        customerId: 'cust-123',
        shopId: 'shop-456',
        deliveryCharges: 0.0,
        orderType: 'manual_quote',
        status: 'bulk_pending',
        paymentStatus: 'captured',
        paymentMethod: 'offline',
        totalAmount: 35000.0,
        createdAt: DateTime.now(),
      );

      // Verify that manual_quote behaves cleanly as a bulk order
      expect(manualQuoteOrder.isBulkOrder, true);
      expect(manualQuoteOrder.isInstantOrder, false);
      expect(manualQuoteOrder.isManualQuote, true);
      expect(manualQuoteOrder.statusDisplay, 'Feast Booked · Scheduling Kitchen');

      // Test lifecycle progression of the manual quote order
      final confirmedOrder = manualQuoteOrder.copyWith(status: 'bulk_confirmed');
      expect(confirmedOrder.statusDisplay, 'Kitchen Confirmed & Cooking');

      final preparingOrder = manualQuoteOrder.copyWith(status: 'bulk_preparing');
      expect(preparingOrder.statusDisplay, 'Kitchen Cooking');

      final readyOrder = manualQuoteOrder.copyWith(status: 'bulk_ready');
      expect(readyOrder.statusDisplay, 'Feast Prepared & Packed');

      final dispatchedOrder = manualQuoteOrder.copyWith(status: 'bulk_dispatched');
      expect(dispatchedOrder.statusDisplay, 'Out for Delivery 🚗');

      final deliveredOrder = manualQuoteOrder.copyWith(status: 'delivered');
      expect(deliveredOrder.statusDisplay, 'Delivered');
    });

    test('QuoteRequestModel copyWith immutability test', () {
      final original = QuoteRequestModel(
        id: 'q-orig',
        customerId: 'c-orig',
        customerPhone: '+919999999999',
        eventName: 'Original Event',
        eventDate: DateTime(2026, 12, 1),
        estimatedGuestCount: 50,
        requirementsDescription: 'Original description',
        contactPersonName: 'Original Contact',
        contactPersonPhone: '+919999999999',
        createdAt: DateTime.now(),
      );

      final modified = original.copyWith(
        eventName: 'Updated Event',
        quotedAmount: 15000.0,
        paymentMethod: 'bank_transfer',
      );

      expect(original.eventName, 'Original Event');
      expect(original.quotedAmount, isNull);
      expect(original.paymentMethod, isNull);

      expect(modified.id, 'q-orig');
      expect(modified.eventName, 'Updated Event');
      expect(modified.quotedAmount, 15000.0);
      expect(modified.paymentMethod, 'bank_transfer');
    });
  });
}
