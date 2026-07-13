import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CartProvider cartProvider;
  late PlatformConfigProvider platformProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    platformProvider = PlatformConfigProvider();
    // In test environment, PlatformConfigProvider defaults to values matching PaymentConfig
    cartProvider = CartProvider();
  });

  // Helpers to generate mock data for edge cases
  ProductModel createProduct({
    required String id,
    required double price,
    required double weightPerUnit,
    String category = 'Food',
    double? gstOverride,
  }) {
    return ProductModel(
      id: id,
      shopId: 's1',
      name: 'Test Product $id',
      category: category,
      subCategory: 'Test',
      brand: 'TestBrand',
      price: price,
      originalPrice: price + 10,
      totalQuantity: 999,
      weightPerUnit: weightPerUnit,
      unitType: 'kg',
      description: 'Desc',
      images: ['test.jpg'],
      isVeg: true,
      menuCategory: 'Test',
      prepTimeMinutes: 10,
      specialTags: [],
      isAvailable: true,
      rating: 4.5,
      requiresPrescription: false,
      medicineType: '',
      gstRateOverride: gstOverride,
    );
  }

  ShopModel createShop(String id) {
    return ShopModel(
      id: id,
      sellerId: 'sel_$id',
      name: 'Shop $id',
      shopType: 'restaurant',
      cuisineType: 'Indian',
      fssaiNumber: '12345678901234',
      prepTimeMinutes: 20,
      isVegOnly: false,
      openingHours: '{}',
      address: 'Test Addr',
      location: const LatLng(10.0, 20.0),
      category: 'Food',
      categories: ['Food'],
      isActive: true,
      rating: 4.5,
      totalReviews: 100,
      totalOrders: 500,
      bannerImage: null,
    );
  }

  group('Magic Numbers & Edge Cases Tests', () {
    test('Max Items Limit (${PaymentConfig.maxItemsPerOrder})', () {
      final shop = createShop('s1');
      final product = createProduct(id: 'p1', price: 10.0, weightPerUnit: 0.1);

      // Adding up to max items should succeed
      var err = cartProvider.addItem(product, shop, quantity: PaymentConfig.maxItemsPerOrder);
      expect(err, isNull, reason: 'Adding exactly ${PaymentConfig.maxItemsPerOrder} items should succeed');
      expect(cartProvider.totalItemCount, PaymentConfig.maxItemsPerOrder);

      // Adding one more should fail
      err = cartProvider.addItem(product, shop, quantity: 1);
      expect(err, isNotNull, reason: 'Adding ${PaymentConfig.maxItemsPerOrder + 1} items should fail');
      expect(cartProvider.totalItemCount, PaymentConfig.maxItemsPerOrder);
    });

    test('Max Weight Limit (${PaymentConfig.maxWeightKg} kg)', () {
      final shop = createShop('s1');
      // Product exactly at max weight
      final heavyProduct = createProduct(id: 'p2', price: 100.0, weightPerUnit: PaymentConfig.maxWeightKg);
      
      var err = cartProvider.addItem(heavyProduct, shop, quantity: 1);
      expect(err, isNull, reason: 'Adding exactly ${PaymentConfig.maxWeightKg} kg should succeed');
      expect(cartProvider.totalWeight, PaymentConfig.maxWeightKg);

      // Adding slight excess weight should fail
      cartProvider.clear();
      final extraHeavyProduct = createProduct(id: 'p3', price: 100.0, weightPerUnit: PaymentConfig.maxWeightKg + 0.1);
      err = cartProvider.addItem(extraHeavyProduct, shop, quantity: 1);
      expect(err, isNotNull, reason: 'Adding >${PaymentConfig.maxWeightKg} kg should fail');
      expect(cartProvider.totalItemCount, 0);
    });

    test('Multi-Shop Limit (Max 3 shops)', () {
      // Adding from 3 distinct shops
      for (int i = 1; i <= 3; i++) {
        final shop = createShop('s$i');
        final p = createProduct(id: 'p$i', price: 10.0, weightPerUnit: 0.1);
        final err = cartProvider.addItem(p, shop, quantity: 1);
        expect(err, isNull);
      }
      expect(cartProvider.shops.length, 3);
      expect(cartProvider.isMultiShopOrder, true);

      // Adding 4th shop should fail
      final shop4 = createShop('s4');
      final p4 = createProduct(id: 'p4', price: 10.0, weightPerUnit: 0.1);
      final err = cartProvider.addItem(p4, shop4, quantity: 1);
      expect(err, isNotNull, reason: 'Should not allow adding from a 4th distinct shop');
      expect(cartProvider.shops.length, 3);
    });

    test('Small Cart Fee Threshold (₹${PaymentConfig.smallCartThreshold})', () {
      final shop = createShop('s1');
      
      // Edge case: Just below threshold
      final productBelow = createProduct(id: 'p_below', price: PaymentConfig.smallCartThreshold - 1, weightPerUnit: 1.0);
      cartProvider.addItem(productBelow, shop, quantity: 1);
      expect(cartProvider.subtotal, PaymentConfig.smallCartThreshold - 1);
      expect(cartProvider.smallCartFee, PaymentConfig.smallCartFee, reason: 'Small cart fee should apply when subtotal is < ${PaymentConfig.smallCartThreshold}');

      // Edge case: Exactly at threshold
      cartProvider.clear();
      final productAt = createProduct(id: 'p_at', price: PaymentConfig.smallCartThreshold, weightPerUnit: 1.0);
      cartProvider.addItem(productAt, shop, quantity: 1);
      expect(cartProvider.subtotal, PaymentConfig.smallCartThreshold);
      expect(cartProvider.smallCartFee, 0.0, reason: 'Small cart fee should NOT apply when subtotal is >= ${PaymentConfig.smallCartThreshold}');
    });

    test('Heavy Order Fee Threshold (${PaymentConfig.heavyOrderThreshold} kg)', () {
      final shop = createShop('s1');
      
      // Edge case: Exactly at threshold
      final productAt = createProduct(id: 'h1', price: 100.0, weightPerUnit: PaymentConfig.heavyOrderThreshold);
      cartProvider.addItem(productAt, shop, quantity: 1);
      expect(cartProvider.totalWeight, PaymentConfig.heavyOrderThreshold);
      expect(cartProvider.heavyOrderFee, 0.0, reason: 'Heavy order fee should NOT apply at exactly threshold');

      // Edge case: Just above threshold
      cartProvider.clear();
      final productAbove = createProduct(id: 'h2', price: 100.0, weightPerUnit: PaymentConfig.heavyOrderThreshold + 0.1);
      cartProvider.addItem(productAbove, shop, quantity: 1);
      expect(cartProvider.heavyOrderFee, PaymentConfig.heavyOrderFee, reason: 'Heavy order fee should apply strictly > threshold');
    });

    test('Platform Fee is consistently applied', () {
      final shop = createShop('s1');
      final product = createProduct(id: 'p1', price: 200.0, weightPerUnit: 1.0); // Subtotal 200, so no small cart fee
      cartProvider.addItem(product, shop, quantity: 1);
      
      expect(cartProvider.platformFee, PaymentConfig.platformFee);
    });

    test('Minimum Order Value (₹${PaymentConfig.minimumOrderValue})', () {
      final shop = createShop('s1');
      // Adding item below minimum order value
      final product = createProduct(id: 'p1', price: PaymentConfig.minimumOrderValue - 0.5, weightPerUnit: 0.1);
      cartProvider.addItem(product, shop, quantity: 1);
      
      expect(cartProvider.meetsMinimumOrder, isFalse);

      // Now adding more to meet it
      cartProvider.addItem(product, shop, quantity: 2); // 3 * 0.5 = 1.5
      expect(cartProvider.meetsMinimumOrder, isTrue);
    });
  });
}
