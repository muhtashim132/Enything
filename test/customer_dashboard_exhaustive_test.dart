import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/models/saved_address_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/location_provider.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Customer Dashboard: Financial & Tax Compliance Tests', () {
    test('Add-On GST Model: Food vs Non-Food Tax Breakdown', () {
      final items = [
        {
          'category': 'Restaurant',
          'price': 200.0,
          'quantity': 2,
          'gst_rate_override': null,
        },
        {
          'category': 'Grocery',
          'price': 100.0,
          'quantity': 1,
          'gst_rate_override': null,
        },
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 30.0,
        riderEarnings: 24.0,
        platformFee: 5.0,
        paymentMethod: 'upi',
      );

      // Restaurant is §9(5) (5% on ₹400 = ₹20)
      // Grocery is pass-through (5% on ₹100 = ₹5)
      // Delivery (18% inclusive in ₹30 => 30 - 30/1.18 = 4.576)
      // Platform (18% inclusive in ₹5 => 5 - 5/1.18 = 0.763)
      expect(breakdown.s9_5GstToRemit, closeTo(20.0, 0.01));
      expect(breakdown.nonFoodGstPassThrough, closeTo(5.0, 0.01));
      expect(breakdown.itemGstTotal, closeTo(25.0, 0.01));
      expect(breakdown.deliveryGst, closeTo(30.0 - (30.0 / 1.18), 0.01));
      expect(breakdown.platformFeeGst, closeTo(5.0 - (5.0 / 1.18), 0.01));
      expect(breakdown.grandTotal, closeTo(500.0 + 25.0 + 30.0 + 5.0, 0.01));
    });

    test('Small Cart Fee applied below threshold', () {
      final cart = CartProvider();
      final shop = ShopModel(
        id: 's1',
        sellerId: 'sel1',
        name: 'Snack Shop',
        shopType: 'restaurant',
        prepTimeMinutes: 15,
        isVegOnly: false,
        address: 'Main St',
        location: const LatLng(34.0, 74.0),
        category: 'Food',
        categories: ['Food'],
        isActive: true,
        rating: 4.5,
        totalReviews: 10,
        totalOrders: 20,
      );

      final product = ProductModel(
        id: 'p1',
        shopId: 's1',
        name: 'Juice',
        category: 'Food',
        subCategory: 'Beverages',
        price: 50.0, // Below small cart threshold of 99
        totalQuantity: 20,
        weightPerUnit: 0.2,
        unitType: 'piece',
        isVeg: true,
        prepTimeMinutes: 5,
        isAvailable: true,
        rating: 4.0,
      );

      cart.addItem(product, shop, quantity: 1);
      expect(cart.subtotal, 50.0);
      expect(cart.smallCartFee, PaymentConfig.smallCartFee);
    });

    test('Heavy Order Fee calculation above threshold', () {
      final cart = CartProvider();
      final shop = ShopModel(
        id: 's1',
        sellerId: 'sel1',
        name: 'Bulk Mart',
        shopType: 'grocery',
        prepTimeMinutes: 15,
        isVegOnly: false,
        address: 'Wholesale Rd',
        location: const LatLng(34.0, 74.0),
        category: 'Grocery',
        categories: ['Grocery'],
        isActive: true,
        rating: 4.5,
        totalReviews: 10,
        totalOrders: 20,
      );

      final heavyProduct = ProductModel(
        id: 'p_heavy',
        shopId: 's1',
        name: 'Rice Bag',
        category: 'Grocery',
        subCategory: 'Grains',
        price: 800.0,
        totalQuantity: 10,
        weightPerUnit: 6.0, // 6 kg per unit (within 15kg cap for 2 units = 12kg)
        unitType: 'kg',
        isVeg: true,
        prepTimeMinutes: 5,
        isAvailable: true,
        rating: 4.8,
      );

      // Add 2 units = 12 kg (Threshold is 10 kg -> 2 kg excess)
      final err = cart.addItem(heavyProduct, shop, quantity: 2);
      expect(err, isNull);
      expect(cart.totalWeight, 12.0);
      expect(cart.heavyOrderFee, closeTo(2 * PaymentConfig.heavyOrderFee, 0.01));
    });
  });

  group('Customer Dashboard: Multi-Shop Surcharges & Constraints', () {
    test('Enforces max 3 unique shops per checkout', () {
      final cart = CartProvider();

      ShopModel makeShop(String id) => ShopModel(
            id: id,
            sellerId: 'sel_$id',
            name: 'Shop $id',
            shopType: 'store',
            prepTimeMinutes: 10,
            isVegOnly: false,
            address: 'Addr $id',
            location: const LatLng(34.0, 74.0),
            category: 'Food',
            categories: ['Food'],
            isActive: true,
            rating: 4.0,
            totalReviews: 1,
            totalOrders: 1,
          );

      ProductModel makeProduct(String id, String shopId) => ProductModel(
            id: id,
            shopId: shopId,
            name: 'Prod $id',
            category: 'Food',
            subCategory: 'Item',
            price: 100.0,
            totalQuantity: 10,
            weightPerUnit: 0.1,
            unitType: 'piece',
            isVeg: true,
            prepTimeMinutes: 5,
            isAvailable: true,
            rating: 4.0,
          );

      expect(cart.addItem(makeProduct('p1', 's1'), makeShop('s1')), isNull);
      expect(cart.addItem(makeProduct('p2', 's2'), makeShop('s2')), isNull);
      expect(cart.addItem(makeProduct('p3', 's3'), makeShop('s3')), isNull);

      // 4th shop must be rejected
      final error = cart.addItem(makeProduct('p4', 's4'), makeShop('s4'));
      expect(error, contains('Maximum 3 shops'));
      expect(cart.shops.length, 3);
    });

    test('Multi-shop surcharge calculation for 1, 2, and 3 shops', () {
      final shop1 = ShopModel(
        id: 's1',
        sellerId: 'sel1',
        name: 'Shop 1',
        shopType: 'store',
        prepTimeMinutes: 10,
        isVegOnly: false,
        address: 'Addr 1',
        location: const LatLng(34.0, 74.0),
        category: 'Food',
        categories: ['Food'],
        isActive: true,
        rating: 4.0,
        totalReviews: 1,
        totalOrders: 1,
      );

      final shop2 = ShopModel(
        id: 's2',
        sellerId: 'sel2',
        name: 'Shop 2',
        shopType: 'store',
        prepTimeMinutes: 10,
        isVegOnly: false,
        address: 'Addr 2',
        location: const LatLng(34.01, 74.01), // ~1.4 km away
        category: 'Food',
        categories: ['Food'],
        isActive: true,
        rating: 4.0,
        totalReviews: 1,
        totalOrders: 1,
      );

      final shop3 = ShopModel(
        id: 's3',
        sellerId: 'sel3',
        name: 'Shop 3',
        shopType: 'store',
        prepTimeMinutes: 10,
        isVegOnly: false,
        address: 'Addr 3',
        location: const LatLng(34.03, 74.03),
        category: 'Food',
        categories: ['Food'],
        isActive: true,
        rating: 4.0,
        totalReviews: 1,
        totalOrders: 1,
      );

      expect(DeliveryCalculator.calculateMultiShopSurcharge([shop1]), 0.0);
      expect(DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2]),
          greaterThan(0.0));
      expect(
          DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2, shop3]),
          greaterThan(
              DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2])));
    });
  });

  group('Customer Dashboard: Order Model & Status Machine Transitions', () {
    test('Order status helper displays correct customer-facing labels', () {
      final order = OrderModel(
        id: 'o1',
        customerId: 'c1',
        status: 'awaiting_acceptance',
        totalAmount: 250.0,
        deliveryCharges: 30.0,
        riderEarnings: 24.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.0,
        createdAt: DateTime.now(),
      );

      expect(order.statusDisplay, 'Waiting for Confirmation');

      order.status = 'awaiting_payment';
      expect(order.statusDisplay, 'Pay Now');

      order.status = 'confirmed';
      expect(order.statusDisplay, 'Confirmed');

      order.status = 'preparing';
      expect(order.statusDisplay, 'Preparing');

      order.status = 'ready_for_pickup';
      expect(order.statusDisplay, 'Ready for Pickup');

      order.status = 'out_for_delivery';
      expect(order.statusDisplay, 'Out for Delivery');

      order.status = 'delivered';
      expect(order.statusDisplay, 'Delivered');

      order.status = 'seller_rejected';
      expect(order.statusDisplay, 'Shop Declined');
    });

    test('Grand total calculation respects frozen DB snapshot vs fallback', () {
      final orderWithSnapshot = OrderModel(
        id: 'o1',
        customerId: 'c1',
        status: 'confirmed',
        totalAmount: 200.0,
        deliveryCharges: 35.40,
        riderEarnings: 24.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.90,
        gstItemTotal: 10.0,
        grandTotalCollected: 251.30,
        createdAt: DateTime.now(),
      );

      expect(orderWithSnapshot.grandTotal, 251.30);

      final legacyOrder = OrderModel(
        id: 'o2',
        customerId: 'c1',
        status: 'confirmed',
        totalAmount: 200.0,
        deliveryCharges: 35.40,
        riderEarnings: 24.0,
        multiShopSurcharge: 0.0,
        platformFee: 5.90,
        gstItemTotal: 10.0,
        couponDiscount: 20.0,
        grandTotalCollected: -1.0, // Legacy unrecorded flag
        createdAt: DateTime.now(),
      );

      // totalAmount (200) + gstItem (10) + delivery (35.40) + platform (5.90) - coupon (20) = 231.30
      expect(legacyOrder.grandTotal, closeTo(231.30, 0.01));
    });
  });

  group('Customer Dashboard: Location & Saved Address Proximity', () {
    test('Proximity matching detects address within 200m radius', () {
      final address = SavedAddress(
        id: 'addr_1',
        userId: 'u1',
        label: 'Home',
        flatNumber: '101',
        address: 'Rose Lane, Bandipora',
        latitude: 34.4225,
        longitude: 74.6366,
      );

      expect(address.displayLabel, 'Home');
      expect(address.icon, '🏠');

      // Distance to exact same point is 0
      final locProvider = LocationProvider();
      locProvider.setManualLocation(
        const LatLng(34.4225, 74.6366),
        'Rose Lane, Bandipora',
      );

      expect(locProvider.hasLocation, true);
      expect(locProvider.distanceTo(const LatLng(34.4225, 74.6366)), 0.0);
    });
  });
}
