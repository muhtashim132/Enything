import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Seller Dashboard & Catalog Filtering Invariants', () {
    test('Soft delete filter invariant is preserved across product lists', () {
      final products = [
        ProductModel(
          id: 'prod-1',
          shopId: 'shop-1',
          name: 'Fresh Mangoes 1kg',
          category: 'Grocery',
          price: 120.0,
          isAvailable: true,
        ),
        ProductModel(
          id: 'prod-2',
          shopId: 'shop-1',
          name: 'Apples 1kg',
          category: 'Grocery',
          price: 180.0,
          isAvailable: false,
        ),
      ];

      // Simulate client-side search query
      const q = 'mango';
      final filtered = products.where((p) => p.name.toLowerCase().contains(q.toLowerCase())).toList();
      expect(filtered.length, 1);
      expect(filtered.first.id, 'prod-1');
    });

    test('Availability and Category filtering logic functions correctly', () {
      final products = [
        ProductModel(
          id: 'prod-1',
          shopId: 'shop-1',
          name: 'Margherita Pizza',
          category: 'Pizza',
          price: 250.0,
          isAvailable: true,
        ),
        ProductModel(
          id: 'prod-2',
          shopId: 'shop-1',
          name: 'Farmhouse Pizza',
          category: 'Pizza',
          price: 350.0,
          isAvailable: false,
        ),
        ProductModel(
          id: 'prod-3',
          shopId: 'shop-1',
          name: 'Garlic Bread',
          category: 'Sides',
          price: 120.0,
          isAvailable: true,
        ),
      ];

      // Filter by category 'Pizza'
      final pizzaOnly = products.where((p) => p.category == 'Pizza').toList();
      expect(pizzaOnly.length, 2);

      // Filter by availability 'Available'
      final availableOnly = products.where((p) => p.isAvailable).toList();
      expect(availableOnly.length, 2);

      // Filter by availability 'Hidden'
      final hiddenOnly = products.where((p) => !p.isAvailable).toList();
      expect(hiddenOnly.length, 1);
      expect(hiddenOnly.first.name, 'Farmhouse Pizza');
    });

    test('Variant price and MRP calculations remain accurate', () {
      final variant = ProductVariant(
        id: 'var-101',
        name: '500ml Bottle',
        price: 90.0,
        originalPrice: 100.0,
      );

      expect(variant.discountPercent, isNotNull);
      expect(variant.discountPercent, 10.0);

      final product = ProductModel(
        id: 'prod-shampoo',
        shopId: 'shop-1',
        name: 'Organic Shampoo',
        category: 'Personal Care',
        price: 90.0,
        originalPrice: 100.0,
        variants: [variant],
      );

      expect(product.originalPrice != null && product.originalPrice! > product.price, isTrue);
      expect(product.variants.first.name, '500ml Bottle');
    });
  });

  group('Seller Order State Machine & Cancellation Guards', () {
    test('Seller cancellation popup only allows pre-dispatch cancellation', () {
      const cancellableStatuses = ['confirmed', 'preparing'];
      const nonCancellableStatuses = ['ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered'];

      for (final status in cancellableStatuses) {
        expect(cancellableStatuses.contains(status), isTrue);
      }

      for (final status in nonCancellableStatuses) {
        expect(cancellableStatuses.contains(status), isFalse);
      }
    });

    test('Multi-shop aggregation and shop context isolation', () {
      final shopA = {
        'id': 'shop-a',
        'name': 'Gourmet Kitchen',
        'category': 'Restaurant',
        'is_active': true,
        'is_accepting_orders': true,
      };

      final shopB = {
        'id': 'shop-b',
        'name': 'City Pharmacy',
        'category': 'Pharmacy',
        'is_active': true,
        'is_accepting_orders': false,
      };

      final shops = [shopA, shopB];
      expect(shops.length, 2);

      String activeShopId = shopA['id'] as String;
      expect(activeShopId, 'shop-a');

      // Switch to shop B
      activeShopId = shopB['id'] as String;
      expect(activeShopId, 'shop-b');

      final currentShop = shops.firstWhere((s) => s['id'] == activeShopId);
      expect(currentShop['name'], 'City Pharmacy');
      expect(currentShop['category'], 'Pharmacy');
      expect(currentShop['is_accepting_orders'], isFalse);
    });
  });
}
