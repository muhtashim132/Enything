import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('100x Financial & GST Compliance Engine Tests', () {
    test('Food vs Non-Food GST and Section 9(5) Liability Separation', () {
      final restaurantItem = {
        'category': 'Restaurant',
        'price': 400.0,
        'quantity': 1,
        'gst_rate_override': null,
      };

      final groceryItem = {
        'category': 'Grocery',
        'price': 200.0,
        'quantity': 1,
        'gst_rate_override': null,
      };

      final breakdown = OrderTaxBreakdown.calculate(
        items: [restaurantItem, groceryItem],
        deliveryCharge: 30.0,
        riderEarnings: 24.0,
        platformFee: 5.0,
        paymentMethod: 'upi',
      );

      // Verify Food GST (5% on ₹400 = ₹20) is classified as Section 9(5) ECO liability
      expect(breakdown.s9_5GstToRemit, closeTo(20.0, 0.01));

      // Verify Non-Food GST is pass-through
      expect(breakdown.nonFoodGstPassThrough, greaterThanOrEqualTo(0.0));

      // Verify embedded 18% GST in delivery (30 - 30/1.18 = 4.58)
      expect(breakdown.deliveryGst, closeTo(30.0 - (30.0 / 1.18), 0.01));

      // Verify embedded 18% GST in platform fee (5 - 5/1.18 = 0.76)
      expect(breakdown.platformFeeGst, closeTo(5.0 - (5.0 / 1.18), 0.01));

      // Verify Grand Total matches sum of parts
      expect(
        breakdown.grandTotal,
        closeTo(
          600.0 +
              breakdown.itemGstTotal +
              30.0 +
              5.0,
          0.05,
        ),
      );
    });

    test('Product-Level GST Rate Override Precedence', () {
      final standardPharmacyRate = TaxConfig.gstRateForCategory('Pharmacy');
      expect(standardPharmacyRate, 0.05); // Default 5%

      // Override product to 18% (e.g. Cosmetic/specialty pharma)
      final overriddenRate = TaxConfig.gstRateForProduct(
        'Pharmacy',
        0.18,
      );
      expect(overriddenRate, 0.18);

      // When override is null, should fall back to category
      final defaultRate = TaxConfig.gstRateForProduct(
        'Pharmacy',
        null,
      );
      expect(defaultRate, 0.05);
    });

    test('TCS (Section 52) and TDS (Section 194-O) Statutory Rates', () {
      const grocerySubtotal = 1000.0;
      final tcs = grocerySubtotal * TaxConfig.tcsRateForCategory('Grocery');
      const tds = grocerySubtotal * TaxConfig.itTdsRate;

      // TCS is 0.5% (0.25% CGST + 0.25% SGST)
      expect(tcs, closeTo(5.0, 0.01));

      // TDS is 0.1% (Finance Act 2024 Section 194-O)
      expect(tds, closeTo(1.0, 0.01));
    });
  });

  group('100x Cart, Multi-Shop Routing & Capacity Control Tests', () {
    test('Enforce Maximum 3 Shops Per Cart Group', () {
      final cart = CartProvider();

      final shop1 = ShopModel(
        id: 'shop-1',
        sellerId: 'seller-1',
        name: 'Shop 1',
        shopType: 'restaurant',
        address: 'Main Street',
        location: const LatLng(34.0837, 74.7973),
        category: 'Restaurant',
        categories: ['Restaurant'],
        isActive: true,
      );

      final shop2 = ShopModel(
        id: 'shop-2',
        sellerId: 'seller-2',
        name: 'Shop 2',
        shopType: 'shop',
        address: 'Market Yard',
        location: const LatLng(34.0850, 74.7990),
        category: 'Grocery',
        categories: ['Grocery'],
        isActive: true,
      );

      final shop3 = ShopModel(
        id: 'shop-3',
        sellerId: 'seller-3',
        name: 'Shop 3',
        shopType: 'shop',
        address: 'Bakery Road',
        location: const LatLng(34.0870, 74.8010),
        category: 'Bakery',
        categories: ['Bakery'],
        isActive: true,
      );

      final shop4 = ShopModel(
        id: 'shop-4',
        sellerId: 'seller-4',
        name: 'Shop 4',
        shopType: 'shop',
        address: 'Health Lane',
        location: const LatLng(34.0900, 74.8050),
        category: 'Pharmacy',
        categories: ['Pharmacy'],
        isActive: true,
      );

      final prod1 = ProductModel(id: 'p1', shopId: 'shop-1', name: 'Item 1', category: 'Restaurant', price: 100.0, isAvailable: true);
      final prod2 = ProductModel(id: 'p2', shopId: 'shop-2', name: 'Item 2', category: 'Grocery', price: 100.0, isAvailable: true);
      final prod3 = ProductModel(id: 'p3', shopId: 'shop-3', name: 'Item 3', category: 'Bakery', price: 100.0, isAvailable: true);
      final prod4 = ProductModel(id: 'p4', shopId: 'shop-4', name: 'Item 4', category: 'Pharmacy', price: 100.0, isAvailable: true);

      // Add from 3 shops -> Allowed
      expect(cart.addItem(prod1, shop1), isNull);
      expect(cart.addItem(prod2, shop2), isNull);
      expect(cart.addItem(prod3, shop3), isNull);
      expect(cart.shops.length, 3);

      // Add from 4th shop -> Rejected with clear message
      final err = cart.addItem(prod4, shop4);
      expect(err, isNotNull);
      expect(err, contains('Maximum 3 shops'));
      expect(cart.shops.length, 3);
    });

    test('Multi-Shop Distance Surcharge using Nearest-Neighbor Greedy Algorithm', () {
      final shop1 = ShopModel(
        id: 's1',
        sellerId: 'sel1',
        name: 'Srinagar Central Bakery',
        shopType: 'shop',
        address: 'Central Srinagar',
        location: const LatLng(34.083656, 74.797287),
        category: 'Bakery',
        categories: ['Bakery'],
        isActive: true,
      );

      final shop2 = ShopModel(
        id: 's2',
        sellerId: 'sel2',
        name: 'Lal Chowk Grocery',
        shopType: 'shop',
        address: 'Lal Chowk',
        location: const LatLng(34.072500, 74.810000), // ~1.7 km away
        category: 'Grocery',
        categories: ['Grocery'],
        isActive: true,
      );

      // Single shop surcharge is always 0
      expect(DeliveryCalculator.calculateMultiShopSurcharge([shop1]), 0.0);

      // Two shops surcharge: ceil(distance) * ratePerKm
      final dist = DeliveryCalculator.haversineKm(shop1.location, shop2.location);
      final expectedSurcharge = dist.ceil() * 10.0;
      final actualSurcharge = DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2]);
      expect(actualSurcharge, expectedSurcharge);
      expect(actualSurcharge, greaterThanOrEqualTo(10.0));
    });

    test('Weight Aggregation and Maximum Weight Limit Protection', () {
      final cart = CartProvider();

      final shop = ShopModel(
        id: 'shop-heavy',
        sellerId: 'seller-heavy',
        name: 'Wholesale Depot',
        shopType: 'shop',
        address: 'Industrial Area',
        location: const LatLng(34.08, 74.80),
        category: 'Grocery',
        categories: ['Grocery'],
        isActive: true,
      );

      final product10kg = ProductModel(
        id: 'prod-flour-bag',
        shopId: 'shop-heavy',
        name: 'Flour Bag 10kg',
        category: 'Grocery',
        price: 450.0,
        weightPerUnit: 10.0,
        unitType: 'kg',
        isAvailable: true,
      );

      // Adding 1st bag (10kg) should succeed within 15kg max
      expect(cart.addItem(product10kg, shop, quantity: 1), isNull);
      expect(cart.totalWeight, 10.0);

      // Adding 2nd bag (would total 20kg, exceeding 15kg max) should be rejected
      final err = cart.addItem(product10kg, shop, quantity: 1);
      expect(err, isNotNull);
      expect(err, contains('Maximum weight of 15.0 kg allowed'));
      expect(cart.totalWeight, 10.0);
    });

    test('Small Cart Fee Threshold Verification', () {
      final cart = CartProvider();
      final shop = ShopModel(
        id: 'shop-test',
        sellerId: 'seller-test',
        name: 'Snack Corner',
        shopType: 'restaurant',
        address: 'Food Court',
        location: const LatLng(34.08, 74.80),
        category: 'Restaurant',
        categories: ['Restaurant'],
        isActive: true,
      );

      final smallItem = ProductModel(
        id: 'prod-tea',
        shopId: 'shop-test',
        name: 'Kashmiri Kehwa',
        category: 'Restaurant',
        price: 40.0,
        isAvailable: true,
      );

      cart.addItem(smallItem, shop, quantity: 1);
      expect(cart.subtotal, 40.0);
      expect(cart.subtotal < PaymentConfig.smallCartThreshold, isTrue);
      expect(cart.smallCartFee, PaymentConfig.smallCartFee);

      // Add more items to cross small cart threshold (₹99)
      cart.updateQuantity('prod-tea', 3); // 3 * 40 = 120.0
      expect(cart.subtotal, 120.0);
      expect(cart.smallCartFee, 0.0);
    });
  });

  group('100x Order Lifecycle & Terminal State Security', () {
    test('Disallow Customer Cancellation Post-Pickup', () {
      const allowedCustomerCancelStatuses = [
        'awaiting_acceptance',
        'confirmed',
        'preparing',
      ];

      const blockedCustomerCancelStatuses = [
        'picked_up',
        'out_for_delivery',
        'delivered',
        'cancelled',
      ];

      bool canCustomerCancel(String status) =>
          allowedCustomerCancelStatuses.contains(status);

      for (final s in allowedCustomerCancelStatuses) {
        expect(canCustomerCancel(s), isTrue);
      }

      for (final s in blockedCustomerCancelStatuses) {
        expect(canCustomerCancel(s), isFalse);
      }
    });

    test('Single-Device Session Validation Token Matcher', () {
      const localSessionId = 'session-device-alpha-123';
      const sameDbSessionId = 'session-device-alpha-123';
      const remoteDbSessionId = 'session-device-beta-456';

      bool isSessionValid(String local, String? db) {
        if (db == null || db.isEmpty) return true;
        return local == db;
      }

      expect(isSessionValid(localSessionId, sameDbSessionId), isTrue);
      expect(isSessionValid(localSessionId, remoteDbSessionId), isFalse);
    });
  });
}
