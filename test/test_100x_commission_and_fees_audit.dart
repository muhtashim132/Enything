import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/bulk_order_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late PlatformConfigProvider configProvider;
  late CartProvider cartProvider;
  late BulkOrderProvider bulkProvider;

  final testShop1 = ShopModel(
    id: 'shop-test-1111',
    sellerId: 'seller-1111',
    name: 'Test Grocery Store',
    shopType: 'Retail',
    category: 'Grocery',
    categories: ['Grocery'],
    isActive: true,
    location: const LatLng(34.0837, 74.7973),
    address: 'Residency Road, Srinagar',
    isAcceptingOrders: true,
    openTime: '00:00',
    closeTime: '23:59',
  );

  final testShop2 = ShopModel(
    id: 'shop-test-2222',
    sellerId: 'seller-2222',
    name: 'Test Bakery',
    shopType: 'Retail',
    category: 'Bakery',
    categories: ['Bakery'],
    isActive: true,
    location: const LatLng(34.0900, 74.8000), // ~0.74 km from Shop 1
    address: 'Lal Chowk, Srinagar',
    isAcceptingOrders: true,
    openTime: '00:00',
    closeTime: '23:59',
  );

  final testProduct1 = ProductModel(
    id: 'prod-test-1111',
    shopId: 'shop-test-1111',
    name: 'Basmati Rice 1kg',
    price: 100.0,
    category: 'Grocery',
    totalQuantity: 50,
    weightPerUnit: 1.0,
    unitType: 'kg',
  );

  final testProduct2 = ProductModel(
    id: 'prod-test-2222',
    shopId: 'shop-test-2222',
    name: 'Chocolate Cake',
    price: 350.0,
    category: 'Bakery',
    totalQuantity: 20,
    weightPerUnit: 0.5,
    unitType: 'kg',
  );

  setUp(() {
    configProvider = PlatformConfigProvider();
    // Simulate live database config rows
    configProvider.updateConfigsFromList([
      {'key': 'platform_fee', 'value': 2.0},
      {'key': 'commission_percent', 'value': 5.0},
      {'key': 'default_commission_percent', 'value': 5.0},
      {'key': 'commission_percent_Bakery', 'value': 7.54},
      {'key': 'commission_percent_Grocery', 'value': 3.04},
      {'key': 'small_cart_threshold', 'value': 199.0},
      {'key': 'small_cart_fee', 'value': 25.0},
      {'key': 'delivery_base_fee', 'value': 20.0},
      {'key': 'delivery_rate_per_km', 'value': 20.0},
      {'key': 'max_delivery_radius_km', 'value': 15.0},
      {'key': 'heavy_order_threshold_kg', 'value': 10.0},
      {'key': 'heavy_order_fee_per_kg', 'value': 20.0},
      {'key': 'rider_commission_percent', 'value': 80.0},
      {'key': 'wait_penalty_per_min', 'value': 2.0},
      {'key': 'wait_penalty_per_min_Restaurant', 'value': 3.0},
      {'key': 'delivery_gst_rate', 'value': 0.18},
      {'key': 'platform_fee_gst_rate', 'value': 0.18},
    ]);

    cartProvider = CartProvider();
    bulkProvider = BulkOrderProvider();
  });

  group('1. Handling Fee (platform_fee) Lifecycle & Parity Tests', () {
    test('PaymentConfig fallback matches live DB value of 2.0', () {
      expect(PaymentConfig.platformFee, equals(2.0),
          reason: 'Default fallback must match live platform_config to prevent spoofing on cold-start');
    });

    test('PlatformConfigProvider getter returns updated platform_fee', () {
      expect(configProvider.platformFee, equals(2.0));
    });

    test('CartProvider dynamically reflects PlatformConfigProvider platformFee', () {
      expect(cartProvider.platformFee, equals(2.0));
    });

    test('BulkOrderProvider dynamically reflects platformFee', () {
      expect(bulkProvider.platformFee, equals(2.0));
    });

    test('Realtime fee update triggers instant propagation across all providers', () {
      // Simulate admin changing platform_fee to 5.0
      configProvider.applyConfigRow('platform_fee', 5.0);

      expect(configProvider.platformFee, equals(5.0));
      expect(cartProvider.platformFee, equals(5.0));
      expect(bulkProvider.platformFee, equals(5.0));
    });

    test('Handling fee of 0.0 (fee waiver promo) is safely handled without errors', () {
      configProvider.applyConfigRow('platform_fee', 0.0);

      expect(cartProvider.platformFee, equals(0.0));
      final breakdown = OrderTaxBreakdown.calculate(
        items: [],
        deliveryCharge: 20.0,
        riderEarnings: 16.0,
        platformFee: cartProvider.platformFee,
        paymentMethod: 'upi',
      );
      expect(breakdown.platformFee, equals(0.0));
      expect(breakdown.platformFeeGst, equals(0.0));
    });
  });

  group('2. Platform Commission & Category Overrides Tests', () {
    test('Default commission percent is 5.0%', () {
      expect(configProvider.commissionPercent, equals(5.0));
    });

    test('Bakery commission override is 7.54%', () {
      expect(configProvider.getCommissionPercentForCategory('Bakery'), equals(7.54));
      expect(configProvider.getCommissionRateForCategory('Bakery'), closeTo(0.0754, 0.0001));
    });

    test('Grocery commission override is 3.04%', () {
      expect(configProvider.getCommissionPercentForCategory('Grocery'), equals(3.04));
      expect(configProvider.getCommissionRateForCategory('Grocery'), closeTo(0.0304, 0.0001));
    });

    test('Non-overridden categories fallback to global default 5.0%', () {
      expect(configProvider.getCommissionPercentForCategory('Pharmacy'), equals(5.0));
    });

    test('OrderTaxBreakdown applies category commission correctly', () {
      final breakdown = OrderTaxBreakdown.calculate(
        items: [
          {'category': 'Bakery', 'price': 100.0, 'quantity': 1},
          {'category': 'Grocery', 'price': 100.0, 'quantity': 1},
        ],
        deliveryCharge: 20.0,
        riderEarnings: 16.0,
        platformFee: 2.0,
        paymentMethod: 'upi',
      );

      // Bakery pure commission: 100 * 0.0754 = 7.54
      // Grocery pure commission: 100 * 0.0304 = 3.04
      // Total pure commission = 10.58
      expect(breakdown.itemBaseSubtotal, equals(200.0));
      expect(breakdown.enythingNetCommission, closeTo(10.58, 0.01));
    });
  });

  group('3. Small Cart Fee & Threshold Tests', () {
    test('Empty cart has smallCartFee = 0', () {
      expect(cartProvider.smallCartFee, equals(0.0));
    });

    test('Cart below threshold attracts smallCartFee of 25.0', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 1, suppressSave: true);
      // Subtotal = 100.0 < 199.0
      expect(cartProvider.subtotal, equals(100.0));
      expect(cartProvider.smallCartFee, equals(25.0));
    });

    test('Cart meeting threshold of 199.0 has smallCartFee = 0', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 2, suppressSave: true);
      // Subtotal = 200.0 >= 199.0
      expect(cartProvider.subtotal, equals(200.0));
      expect(cartProvider.smallCartFee, equals(0.0));
    });
  });

  group('4. Delivery Fee & Rate per Km Tests', () {
    test('Flat base delivery fee is 20.0', () {
      expect(DeliveryCalculator.flatDeliveryFee, equals(20.0));
    });

    test('Delivery charge is max(base_fee, ceil(dist) * rate_per_km)', () {
      // 0.5 km: ceil(0.5) * 20 = 20.0 -> max(20, 20) = 20.0
      expect(DeliveryCalculator.calculateDeliveryCharges(0.5, 500.0), equals(20.0));

      // 1.5 km: ceil(1.5) * 20 = 2 * 20 = 40.0 -> max(20, 40) = 40.0
      expect(DeliveryCalculator.calculateDeliveryCharges(1.5, 500.0), equals(40.0));

      // 5.0 km: 5 * 20 = 100.0
      expect(DeliveryCalculator.calculateDeliveryCharges(5.0, 500.0), equals(100.0));

      // 15.0 km: 15 * 20 = 300.0
      expect(DeliveryCalculator.calculateDeliveryCharges(15.0, 500.0), equals(300.0));

      // Beyond maxRadiusKm (15.1 km): returns -1 (Out of range)
      expect(DeliveryCalculator.calculateDeliveryCharges(15.1, 500.0), equals(-1.0));
    });
  });

  group('5. Multi-Shop Surcharge Tests', () {
    test('Single shop cart has 0 multi-shop surcharge', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 1, suppressSave: true);
      expect(cartProvider.multiShopSurcharge, equals(0.0));
    });

    test('Multi-shop cart calculates distance-based inter-shop surcharge', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 1, suppressSave: true);
      cartProvider.addItem(testProduct2, testShop2, quantity: 1, suppressSave: true);

      expect(cartProvider.shops.length, equals(2));
      // Distance between Shop 1 and Shop 2 is ~0.74 km -> ceil(0.74) = 1 km -> 1 * 20 = 20.0
      expect(cartProvider.multiShopSurcharge, equals(20.0));
    });
  });

  group('6. Heavy Order Fee & Threshold Tests', () {
    test('Cart under 10kg threshold has heavyOrderFee = 0', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 5, suppressSave: true);
      // Total weight = 5kg <= 10kg
      expect(cartProvider.totalWeight, equals(5.0));
      expect(cartProvider.heavyOrderFee, equals(0.0));
    });

    test('Cart over 10kg threshold calculates feePerKg * ceil(extraWeight)', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 13, suppressSave: true);
      // Total weight = 13kg > 10kg. Extra weight = 3kg. Fee = 3 * 20 = 60.0
      expect(cartProvider.totalWeight, equals(13.0));
      expect(cartProvider.heavyOrderFee, equals(60.0));
    });
  });

  group('7. Rider Commission & Payouts Tests', () {
    test('Rider commission is 80%', () {
      expect(configProvider.riderCommissionPercent, equals(80.0));
    });

    test('Rider earnings equals 80% of rider base (delivery + heavy + multi-shop)', () {
      const riderBase = 20.0 + 20.0; // base 20 + surcharge 20
      final riderPayoutRatio = configProvider.riderCommissionPercent / 100.0;
      final earnings = riderBase * riderPayoutRatio;

      expect(earnings, equals(32.0));
    });
  });

  group('8. Bill Breakdown Mathematical Reconciliation Tests', () {
    test('Every component adds up exactly to grandTotal (zero discrepancy)', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 1, suppressSave: true);
      cartProvider.addItem(testProduct2, testShop2, quantity: 1, suppressSave: true);

      const distanceKm = 2.0;
      final baseCharge = cartProvider.calculateDeliveryCharges(distanceKm);
      final surcharge = cartProvider.multiShopSurcharge;
      final heavyFee = cartProvider.heavyOrderFee;
      final smallFee = cartProvider.smallCartFee;
      final effectiveBase = baseCharge >= 0 ? baseCharge : 0.0;
      final totalDelivery = cartProvider.totalDeliveryCharges(distanceKm);
      final riderBase = effectiveBase + surcharge + heavyFee;
      final riderEarnings = riderBase * (configProvider.riderCommissionPercent / 100.0);

      final gstBreakdown = OrderTaxBreakdown.calculate(
        items: cartProvider.taxBreakdownItems,
        deliveryCharge: totalDelivery,
        riderEarnings: riderEarnings,
        platformFee: cartProvider.platformFee,
        paymentMethod: 'upi',
      );

      final grandTotal = gstBreakdown.grandTotal;

      // Mathematical check:
      // itemGrossTotal + totalDelivery + platformFee == grandTotal
      expect(gstBreakdown.itemGrossTotal + totalDelivery + cartProvider.platformFee,
          closeTo(grandTotal, 0.001));

      // Reconciled bill breakdown check:
      // Subtotal + Item GST + Base Delivery + Surcharges + Delivery GST + Platform Fee == grandTotal
      final subtotal = cartProvider.subtotal;
      final itemGst = gstBreakdown.itemGstTotal;
      final deliveryGst = gstBreakdown.deliveryGst;
      final platformFee = cartProvider.platformFee;

      final sumOfRows = subtotal +
          itemGst +
          effectiveBase +
          surcharge +
          heavyFee +
          smallFee +
          deliveryGst +
          platformFee;

      expect(sumOfRows, closeTo(grandTotal, 0.01),
          reason: 'All customer-facing bill rows must sum up to grandTotal with zero penny discrepancy');
      expect(platformFee, equals(2.0),
          reason: 'Handling fee must display exact ₹2.00 as configured in admin panel');
    });
  });
}
