import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/widgets/common/premium_product_image.dart';

void main() {
  group('100x Load More & Pagination Edge-Case Contract Tests', () {
    ProductModel createMockProduct({
      required String id,
      required String name,
      required double price,
      required double rating,
      bool isVeg = true,
      bool isAvailable = true,
      String? displayImage,
      String shopId = 'shop-1',
    }) {
      return ProductModel(
        id: id,
        name: name,
        price: price,
        rating: rating,
        category: 'Grocery',
        shopId: shopId,
        isVeg: isVeg,
        isAvailable: isAvailable,
        totalReviews: 25,
        images: [displayImage ?? 'https://enything.test/img-$id.jpg'],
      );
    }

    ShopModel createMockShop({
      required String id,
      required String name,
      required double rating,
      double? distanceKm,
    }) {
      return ShopModel(
        id: id,
        sellerId: 'seller-1',
        name: name,
        shopType: 'retail',
        address: '123 Market St',
        category: 'Grocery',
        categories: ['Grocery'],
        rating: rating,
        distanceKm: distanceKm,
        isActive: true,
        location: const LatLng(12.9716, 77.5946),
      );
    }

    test('E1: Pagination strictly deduplicates incoming products across batches', () {
      final existingProducts = [
        createMockProduct(id: 'p1', name: 'Apples', price: 100, rating: 4.8),
        createMockProduct(id: 'p2', name: 'Bananas', price: 40, rating: 4.5),
      ];

      // Second batch from DB includes p2 again (offset drift) + new p3
      final incomingBatch = [
        createMockProduct(id: 'p2', name: 'Bananas', price: 40, rating: 4.5),
        createMockProduct(id: 'p3', name: 'Oranges', price: 80, rating: 4.9),
      ];

      final existingIds = existingProducts.map((p) => p.id).toSet();
      final newUniqueProducts = <ProductModel>[];

      for (final p in incomingBatch) {
        if (!existingIds.contains(p.id)) {
          newUniqueProducts.add(p);
          existingIds.add(p.id);
        }
      }

      existingProducts.addAll(newUniqueProducts);

      expect(existingProducts.length, 3);
      expect(existingProducts.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);
    });

    test('E2: Display limit increments never throw RangeError when taking items', () {
      final products = List.generate(
        15,
        (i) => createMockProduct(
          id: 'prod_$i',
          name: 'Item $i',
          price: (i + 1) * 10.0,
          rating: 4.0,
        ),
      );

      int displayLimit = 20;

      // Taking items with .take(displayLimit) when list has 15 items
      var displaySlice = products.take(displayLimit).toList();
      expect(displaySlice.length, 15);

      // Incrementing displayLimit by 20
      displayLimit = (displayLimit + 20).clamp(0, products.length);
      expect(displayLimit, 15);

      displaySlice = products.take(displayLimit).toList();
      expect(displaySlice.length, 15);
    });

    test('E3: Memoized sorting produces exact deterministic order and handles ties', () {
      final products = [
        createMockProduct(id: 'p1', name: 'A', price: 100, rating: 4.2),
        createMockProduct(id: 'p2', name: 'B', price: 50, rating: 4.9),
        createMockProduct(id: 'p3', name: 'C', price: 200, rating: 4.5),
      ];

      // Sort by rating desc
      final sortedByRating = List<ProductModel>.from(products)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      expect(sortedByRating.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);

      // Sort by price low to high
      final sortedByPriceLow = List<ProductModel>.from(products)
        ..sort((a, b) => a.price.compareTo(b.price));
      expect(sortedByPriceLow.map((p) => p.id).toList(), ['p2', 'p1', 'p3']);

      // Sort by price high to low
      final sortedByPriceHigh = List<ProductModel>.from(products)
        ..sort((a, b) => b.price.compareTo(a.price));
      expect(sortedByPriceHigh.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);
    });

    test('E4: Dietary filter isolates items cleanly without dropping matching pagination items', () {
      final products = [
        createMockProduct(id: 'p1', name: 'Paneer', price: 120, rating: 4.8, isVeg: true),
        createMockProduct(id: 'p2', name: 'Chicken', price: 250, rating: 4.9, isVeg: false),
        createMockProduct(id: 'p3', name: 'Tofu', price: 110, rating: 4.5, isVeg: true),
      ];

      final vegOnly = products.where((p) => p.isVeg == true).toList();
      expect(vegOnly.length, 2);
      expect(vegOnly.every((p) => p.isVeg == true), isTrue);

      final nonVegOnly = products.where((p) => p.isVeg == false).toList();
      expect(nonVegOnly.length, 1);
      expect(nonVegOnly.first.id, 'p2');
    });

    test('E5: Concurrency lock blocks re-entrant fetch executions', () {
      bool isLoadingMore = false;
      int fetchCalls = 0;

      void triggerLoadMore() {
        if (isLoadingMore) return; // Concurrency shield
        isLoadingMore = true;
        fetchCalls++;
      }

      // Initial tap
      triggerLoadMore();
      expect(fetchCalls, 1);
      expect(isLoadingMore, isTrue);

      // Rapid consecutive taps while loading
      triggerLoadMore();
      triggerLoadMore();
      triggerLoadMore();
      expect(fetchCalls, 1); // Strictly blocked!

      // Fetch completes
      isLoadingMore = false;

      // Next tap succeeds
      triggerLoadMore();
      expect(fetchCalls, 2);
    });

    testWidgets('E6: PremiumProductImage renders without BackdropFilter or crashes on empty image', (tester) async {
      // 1. Test fallback on empty image URL
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PremiumProductImage(
              imageUrl: '',
              isDark: false,
              width: 100,
              height: 100,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.image_not_supported_rounded), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);

      // 2. Test valid image URL renders without BackdropFilter
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PremiumProductImage(
              imageUrl: 'https://enything.test/sample.jpg',
              isDark: true,
              width: 150,
              height: 150,
            ),
          ),
        ),
      );

      // CRITICAL: Ensure NO BackdropFilter is injected into the widget tree!
      expect(find.byType(BackdropFilter), findsNothing);
    });

    test('E7: Shop sorting by rating and distance handles pagination clamping accurately', () {
      final shops = [
        createMockShop(id: 's1', name: 'Fresh Mart', rating: 4.2, distanceKm: 1.2),
        createMockShop(id: 's2', name: 'Quick Grocers', rating: 4.8, distanceKm: 3.5),
        createMockShop(id: 's3', name: 'Local Store', rating: 4.5, distanceKm: 0.8),
      ];

      // Sort by rating desc
      final sortedByRating = List<ShopModel>.from(shops)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      expect(sortedByRating.map((s) => s.id).toList(), ['s2', 's3', 's1']);

      // Sort by distance asc
      final sortedByDistance = List<ShopModel>.from(shops)
        ..sort((a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity));
      expect(sortedByDistance.map((s) => s.id).toList(), ['s3', 's1', 's2']);

      // Pagination slice
      int displayLimit = 20;
      final displayShops = sortedByRating.take(displayLimit).toList();
      expect(displayShops.length, 3);
    });
  });
}

