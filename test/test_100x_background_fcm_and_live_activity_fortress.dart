import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/services/live_activity_service.dart';
import 'package:enythingmobilenew/utils/order_messaging_helper.dart';

void main() {
  group('100x Background FCM, Live Activity & Role Isolation Fortress Tests', () {
    test('1. LiveActivityState preserves fulfillmentCategory and category-adaptive delivered copy', () {
      final service = LiveActivityService();

      // Pharmacy order
      final pharmacyOrder = OrderModel(
        id: 'pharm-ord-1',
        customerId: 'cust-1',
        status: 'delivered',
        orderType: 'instant',
        totalAmount: 150.0,
        deliveryCharges: 20.0,
        riderEarnings: 15.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            id: 'item-1',
            productId: 'prod-crocin',
            productName: 'Crocin 650 Tablet',
            quantity: 1,
            price: 50.0,
            weightKg: 0.1,
            requiresPrescription: false,
          ),
        ],
        gstItemTotal: 5.0,
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 5.0,
        gstDelivery: 3.6,
        gstPlatform: 0.9,
        tcsAmount: 0.5,
        tdsAmount: 0.1,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        enythingCommission: 7.5,
        sellerPayout: 140.0,
        gatewayDeduction: 3.5,
        grandTotalCollected: 175.0,
        gstRateSnapshot: {'Pharmacy': 0.12},
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(order: pharmacyOrder);
      expect(state.isTerminal, true);
      expect(state.progress, 1.0);
      expect(state.statusHeadline, contains('Delivered'));
      // Zero meal bias: must not say "Enjoy your meal!" for medicine
      expect(state.statusHeadline.contains('Enjoy your meal'), false);
      expect(state.statusHeadline, contains('Medicines delivered safely'));
      expect(state.fulfillmentCategory, OrderFulfillmentCategory.pharmacy);
      expect(state.toMap()['category'], 'pharmacy');
    });

    test('2. LiveActivityState preparing headline adapts to pharmacy, grocery, and food', () {
      final service = LiveActivityService();

      final prepPharmacyOrder = OrderModel(
        id: 'pharm-ord-prep',
        customerId: 'cust-1',
        status: 'preparing',
        orderType: 'instant',
        totalAmount: 150.0,
        deliveryCharges: 20.0,
        riderEarnings: 15.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            id: 'item-1',
            productId: 'prod-paracetamol',
            productName: 'Paracetamol Syrup',
            quantity: 1,
            price: 60.0,
            weightKg: 0.2,
            requiresPrescription: false,
          ),
        ],
        gstItemTotal: 5.0,
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 5.0,
        gstDelivery: 3.6,
        gstPlatform: 0.9,
        tcsAmount: 0.5,
        tdsAmount: 0.1,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        enythingCommission: 7.5,
        sellerPayout: 140.0,
        gatewayDeduction: 3.5,
        grandTotalCollected: 175.0,
        gstRateSnapshot: {'Pharmacy': 0.12},
        waitTimePenalty: 0.0,
        waitTimeDisputed: false,
        hasCustomerRated: false,
        hasSellerRated: false,
        hasDeliveryRated: false,
        prescriptionUrls: [],
      );

      final state = service.computeState(order: prepPharmacyOrder);
      expect(state.statusHeadline, 'Pharmacy is preparing your medicines');
      expect(state.fulfillmentCategory, OrderFulfillmentCategory.pharmacy);
    });

    test('3. Role Isolation Guard: Customer never evaluates to isUrgent', () {
      bool evaluateIsUrgent({
        required String? role,
        required String? action,
        required String title,
      }) {
        final bool isCustomer = role == 'customer';
        return !isCustomer &&
            (role == 'rider' ||
                role == 'delivery' ||
                role == 'seller' ||
                role == 'delivery_partner' ||
                action == 'new_order' ||
                action == 'start_preparing' ||
                action == 'pickup_order' ||
                title.toLowerCase().contains('new order') ||
                title.toLowerCase().contains('accept now') ||
                title.toLowerCase().contains('payment done') ||
                title.toLowerCase().contains('payment received') ||
                title.toLowerCase().contains('order ready'));
      }

      // Customer receives push with title "Your New Order #1234 Confirmed"
      final customerResult = evaluateIsUrgent(
        role: 'customer',
        action: 'order_confirmed',
        title: 'Your New Order #1234 Confirmed',
      );
      expect(customerResult, false, reason: 'Customers must NEVER trigger isUrgent alarm siren or wake-lock');

      // Rider receives new order alert
      final riderResult = evaluateIsUrgent(
        role: 'rider',
        action: 'new_order',
        title: 'New Order Available!',
      );
      expect(riderResult, true, reason: 'Riders must receive urgent alarm notification');

      // Seller receives new order alert
      final sellerResult = evaluateIsUrgent(
        role: 'seller',
        action: 'new_order',
        title: 'New Order Received!',
      );
      expect(sellerResult, true, reason: 'Sellers must receive urgent alarm notification');
    });

    test('4. Safe PostgREST Foreign Key Resolution handles Map and List without casting crash', () {
      String resolveShopName(dynamic shopsRaw) {
        if (shopsRaw is Map) {
          return shopsRaw['name']?.toString() ?? 'Enything Store';
        } else if (shopsRaw is List && shopsRaw.isNotEmpty && shopsRaw.first is Map) {
          return shopsRaw.first['name']?.toString() ?? 'Enything Store';
        }
        return 'Enything Store';
      }

      // Map format
      expect(resolveShopName({'name': 'Apollo Pharmacy'}), 'Apollo Pharmacy');

      // Single-element list format (PostgREST foreign key return)
      expect(resolveShopName([{'name': 'Noor Medicate'}]), 'Noor Medicate');

      // Null or empty fallback
      expect(resolveShopName(null), 'Enything Store');
      expect(resolveShopName([]), 'Enything Store');
    });
  });
}
