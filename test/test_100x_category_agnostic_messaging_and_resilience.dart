import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/utils/order_messaging_helper.dart';

void main() {
  group('100x Category-Agnostic Messaging & Resilience Tests', () {
    test('1. Pure Food Order delivers restaurant celebration copy', () {
      final foodOrder = OrderModel(
        id: 'ord-food-1',
        customerId: 'cust-1',
        totalAmount: 400.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 20.0, // §9(5) restaurant food GST
        nonFoodGstAmount: 0.0,
        gstRateSnapshot: {'Restaurant': 0.05},
        items: [
          OrderItem(
            id: 'item-1',
            productId: 'p-1',
            productName: 'Chicken Biryani Full',
            quantity: 1,
            price: 400.0,
            weightKg: 0.8,
          ),
        ],
      );

      final notif = OrderMessagingHelper.getDeliveredNotification(foodOrder, [foodOrder]);
      final subtitle = OrderMessagingHelper.getDeliveredSubtitle(foodOrder, [foodOrder]);

      expect(notif.title, contains('🍽️'));
      expect(notif.body, contains('Enjoy your meal!'));
      expect(subtitle, contains('Enjoy your meal!'));
    });

    test('2. Pharmacy / Medicine Order delivers health and recovery copy (Zero "meal" bias)', () {
      final pharmaOrder = OrderModel(
        id: 'ord-pharma-1',
        customerId: 'cust-1',
        totalAmount: 120.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 14.4,
        gstRateSnapshot: {'Pharmacy': 0.12},
        items: [
          OrderItem(
            id: 'item-med-1',
            productId: 'p-med-1',
            productName: 'Paracetamol 650mg Tablets',
            quantity: 2,
            price: 60.0,
            weightKg: 0.05,
            requiresPrescription: true,
          ),
        ],
      );

      final notif = OrderMessagingHelper.getDeliveredNotification(pharmaOrder, [pharmaOrder]);
      final subtitle = OrderMessagingHelper.getDeliveredSubtitle(pharmaOrder, [pharmaOrder]);

      expect(notif.title, contains('Medicines Delivered! 💊'));
      expect(notif.body, contains('Take care and get well soon!'));
      expect(notif.body, isNot(contains('meal')));
      expect(subtitle, contains('Medicines delivered safely. Take care! 💊'));
      expect(subtitle, isNot(contains('meal')));
    });

    test('3. General Retail / Electronics / Fashion delivers delightful package copy (Zero "meal" bias)', () {
      final retailOrder = OrderModel(
        id: 'ord-retail-1',
        customerId: 'cust-1',
        totalAmount: 1499.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 269.82,
        gstRateSnapshot: {'Electronics': 0.18},
        items: [
          OrderItem(
            id: 'item-usb-1',
            productId: 'p-usb-1',
            productName: 'USB-C Fast Charging Cable 65W',
            quantity: 1,
            price: 1499.0,
            weightKg: 0.1,
          ),
        ],
      );

      final notif = OrderMessagingHelper.getDeliveredNotification(retailOrder, [retailOrder]);
      final subtitle = OrderMessagingHelper.getDeliveredSubtitle(retailOrder, [retailOrder]);

      expect(notif.title, contains('Order Delivered! 🛍️'));
      expect(notif.body, contains('Hope you love it!'));
      expect(notif.body, isNot(contains('meal')));
      expect(subtitle, contains('Enjoy your order! Thank you 🛍️'));
      expect(subtitle, isNot(contains('meal')));
    });

    test('4. Mixed Multi-Shop Cart (Food + Pharmacy) delivers unified multi-shop copy', () {
      final foodSubOrder = OrderModel(
        id: 'ord-food-sub',
        customerId: 'cust-1',
        cartGroupId: 'group-multi-1',
        totalAmount: 350.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 17.5,
        nonFoodGstAmount: 0.0,
        gstRateSnapshot: {'Restaurant': 0.05},
        items: [
          OrderItem(
            id: 'item-f1',
            productId: 'p-f1',
            productName: 'Mutton Kebab Roll',
            quantity: 1,
            price: 350.0,
            weightKg: 0.4,
          ),
        ],
      );

      final pharmaSubOrder = OrderModel(
        id: 'ord-pharma-sub',
        customerId: 'cust-1',
        cartGroupId: 'group-multi-1',
        totalAmount: 150.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 18.0,
        gstRateSnapshot: {'Pharmacy': 0.12},
        items: [
          OrderItem(
            id: 'item-p1',
            productId: 'p-p1',
            productName: 'Antiseptic Cream 50g',
            quantity: 1,
            price: 150.0,
            weightKg: 0.08,
          ),
        ],
      );

      final notif = OrderMessagingHelper.getDeliveredNotification(
        foodSubOrder,
        [foodSubOrder, pharmaSubOrder],
      );
      final subtitle = OrderMessagingHelper.getDeliveredSubtitle(
        foodSubOrder,
        [foodSubOrder, pharmaSubOrder],
      );

      expect(notif.title, contains('🎉'));
      expect(notif.body, contains('All items from your order have been delivered safely'));
      expect(notif.body, isNot(contains('meal')));
      expect(subtitle, contains('Enjoy your order! Thank you 🎉'));
    });

    test('5. Dynamic Category Shift: Surviving sub-order after food rejection becomes pure pharmacy', () {
      final cancelledFoodSubOrder = OrderModel(
        id: 'ord-food-sub-dead',
        customerId: 'cust-1',
        cartGroupId: 'group-shift-1',
        totalAmount: 350.0,
        deliveryCharges: 30.0,
        status: 'seller_rejected', // Store declined!
        createdAt: DateTime.now(),
        s9_5GstAmount: 17.5,
        nonFoodGstAmount: 0.0,
        gstRateSnapshot: {'Restaurant': 0.05},
        items: [],
      );

      final activePharmaSubOrder = OrderModel(
        id: 'ord-pharma-sub-alive',
        customerId: 'cust-1',
        cartGroupId: 'group-shift-1',
        totalAmount: 150.0,
        deliveryCharges: 30.0,
        status: 'delivered',
        createdAt: DateTime.now(),
        s9_5GstAmount: 0.0,
        nonFoodGstAmount: 18.0,
        gstRateSnapshot: {'Pharmacy': 0.12},
        items: [
          OrderItem(
            id: 'item-p1',
            productId: 'p-p1',
            productName: 'Bandage Strip Pack',
            quantity: 1,
            price: 150.0,
            weightKg: 0.08,
          ),
        ],
      );

      final notif = OrderMessagingHelper.getDeliveredNotification(
        activePharmaSubOrder,
        [cancelledFoodSubOrder, activePharmaSubOrder],
      );

      // Dead food store is ignored by activeOrders filter; resolves to pure Pharmacy!
      expect(notif.title, contains('Medicines Delivered! 💊'));
      expect(notif.body, contains('Take care and get well soon!'));
    });

    test('6. Event Catering: Food Feast vs Event Equipment Supplies', () {
      // 6A. Food Feast
      final feastInfo = OrderMessagingHelper.getCateringBannerInfo(
        status: 'bulk_confirmed',
        deliveryOtp: '1234',
        activeOrder: {'event_name': 'Grand Wedding Dinner Banquet'},
      );
      expect(feastInfo.emoji, equals('👨‍🍳'));
      expect(feastInfo.label, equals('Kitchen Cooking Feast'));

      // 6B. Event Equipment / Rentals
      final suppliesInfo = OrderMessagingHelper.getCateringBannerInfo(
        status: 'bulk_confirmed',
        deliveryOtp: '5678',
        activeOrder: {'event_name': 'Party Equipment & Chairs Rental'},
      );
      expect(suppliesInfo.emoji, equals('📦'));
      expect(suppliesInfo.label, equals('Preparing Event Supplies'));

      // 6C. Dispatched
      final dispatchedSupplies = OrderMessagingHelper.getCateringBannerInfo(
        status: 'bulk_dispatched',
        deliveryOtp: '9988',
        activeOrder: {'event_name': 'Audio Visual & Tent Supplies Rental'},
      );
      expect(dispatchedSupplies.label, equals('Supplies Out for Delivery (OTP: 9988)'));
    });
  });
}
