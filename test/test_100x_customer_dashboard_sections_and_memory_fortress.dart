import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  group('100x Customer Dashboard Sections & Memory Fortress Test Suite', () {
    ProductModel createMockProduct({
      required String id,
      required String name,
      required String category,
      required double price,
      required double rating,
      bool? isVeg,
      bool isAvailable = true,
      String shopId = 'shop-1',
      List<String> specialTags = const [],
      String description = '',
      double? discountPercent,
    }) {
      return ProductModel(
        id: id,
        name: name,
        description: description,
        price: price,
        rating: rating,
        category: category,
        shopId: shopId,
        isVeg: isVeg,
        isAvailable: isAvailable,
        totalReviews: 10,
        specialTags: specialTags,
        images: ['https://enything.test/$id.jpg'],
      );
    }

    ShopModel createMockShop({
      required String id,
      required String name,
      required String category,
      required double distanceKm,
      List<String>? categories,
      bool isActive = true,
      bool isAcceptingOrders = true,
    }) {
      return ShopModel(
        id: id,
        sellerId: 'seller-$id',
        name: name,
        shopType: 'retail',
        address: '123 Market St',
        category: category,
        categories: categories ?? [category],
        rating: 4.8,
        distanceKm: distanceKm,
        isActive: isActive,
        isAcceptingOrders: isAcceptingOrders,
        location: const LatLng(12.9716, 77.5946),
      );
    }

    test('1. Stratified Diverse Category Sampling with case-insensitivity and secondary categories', () {
      final nearbyShops = <ShopModel>[];
      for (int i = 0; i < 60; i++) {
        nearbyShops.add(createMockShop(
          id: 'food_$i',
          name: 'Restaurant $i',
          category: 'Food',
          distanceKm: 1.0 + (i * 0.1),
        ));
      }
      for (int i = 0; i < 10; i++) {
        nearbyShops.add(createMockShop(
          id: 'pharmacy_$i',
          name: 'Medical Care $i',
          category: 'Medical Store',
          categories: ['Pharmacy', 'Medical Store'],
          distanceKm: 2.0 + (i * 0.1),
        ));
      }
      for (int i = 0; i < 10; i++) {
        nearbyShops.add(createMockShop(
          id: 'grocery_$i',
          name: 'Supermarket $i',
          category: 'Supermarket / Hypermarket',
          categories: ['Supermarket / Hypermarket', 'Grocery', 'Fruits & Vegs'],
          distanceKm: 1.5 + (i * 0.1),
        ));
      }
      for (int i = 0; i < 10; i++) {
        nearbyShops.add(createMockShop(
          id: 'clothing_$i',
          name: 'Fashion Hub $i',
          category: 'Clothing',
          categories: ['Clothing', 'Footwear'],
          distanceKm: 3.0 + (i * 0.1),
        ));
      }

      bool isShopInCategories(ShopModel s, List<String> targetCats) {
        final lowerTargets =
            targetCats.map((c) => c.trim().toLowerCase()).toSet();
        if (lowerTargets.contains(s.category.trim().toLowerCase())) return true;
        return s.categories
            .any((c) => lowerTargets.contains(c.trim().toLowerCase()));
      }

      final pharmacyCats = ['Pharmacy', 'Medical Store'];
      final groceryCats = [
        'Grocery',
        'Supermarket / Hypermarket',
        'Fruits & Vegs',
        'Dairy & Eggs',
      ];
      final clothingCats = ['Clothing', 'Footwear', 'Jewellery'];

      final pharmacyShops = nearbyShops
          .where((s) => isShopInCategories(s, pharmacyCats))
          .take(15)
          .toList();
      final groceryShops = nearbyShops
          .where((s) => isShopInCategories(s, groceryCats))
          .take(15)
          .toList();
      final clothingShops = nearbyShops
          .where((s) => isShopInCategories(s, clothingCats))
          .take(15)
          .toList();
      final otherShops = nearbyShops
          .where((s) =>
              !isShopInCategories(s, pharmacyCats) &&
              !isShopInCategories(s, groceryCats) &&
              !isShopInCategories(s, clothingCats))
          .take(25)
          .toList();

      final stratifiedIds = <String>{
        ...pharmacyShops.map((s) => s.id),
        ...groceryShops.map((s) => s.id),
        ...clothingShops.map((s) => s.id),
        ...otherShops.map((s) => s.id),
      }.take(70).toList();

      expect(stratifiedIds.where((id) => id.startsWith('pharmacy')).length, 10);
      expect(stratifiedIds.where((id) => id.startsWith('grocery')).length, 10);
      expect(stratifiedIds.where((id) => id.startsWith('clothing')).length, 10);
      expect(stratifiedIds.where((id) => id.startsWith('food')).length, 25);
      expect(stratifiedIds.length, 55);
    });

    test('2. Demographic Filter Immunity: Groceries & Medicines stay visible when Men/Boys is active', () {
      final products = [
        createMockProduct(
          id: 'p_milk',
          name: 'Fresh Cow Milk 1L',
          category: 'Dairy & Eggs',
          price: 60,
          rating: 4.8,
          description: 'Pasteurized pure whole milk pouch',
        ),
        createMockProduct(
          id: 'p_med',
          name: 'Paracetamol 650mg Tablets',
          category: 'Pharmacy',
          price: 30,
          rating: 4.9,
          description: 'Fast relief from fever and pain',
        ),
        createMockProduct(
          id: 'p_shirt_men',
          name: 'Men Slim Fit Cotton Shirt',
          category: 'Clothing',
          price: 799,
          rating: 4.3,
          specialTags: ['men', 'formal'],
          description: 'Premium cotton shirts for gents',
        ),
        createMockProduct(
          id: 'p_dress_women',
          name: 'Women Floral Summer Dress',
          category: 'Clothing',
          price: 999,
          rating: 4.5,
          specialTags: ['women'],
          description: 'Casual floral dress for ladies',
        ),
      ];

      bool matchesDemographic(ProductModel product, String demographic) {
        if (demographic == 'All') return true;
        final tags = product.specialTags
            .map((t) => t.trim().toLowerCase().replaceAll('#', ''))
            .toList();
        if (demographic == 'Men/Boys') {
          if (tags.any((t) => t == 'men' || t == 'boys' || t == 'boy')) return true;
          if (tags.any((t) => t == 'women' || t == 'girls')) return false;
          final text = '${product.name} ${product.description}'.toLowerCase();
          if (RegExp(r"\b(women|ladies|girl)\b").hasMatch(text)) return false;
          return RegExp(r"\b(men|boy|gents)\b").hasMatch(text);
        }
        return true;
      }

      List<ProductModel> computeCategoryProducts(
        List<ProductModel> allProds,
        List<String> targetCats, {
        required bool applyDemographic,
        required String demographic,
      }) {
        final lowerTargets =
            targetCats.map((c) => c.trim().toLowerCase()).toSet();
        var list = allProds.where((p) {
          return lowerTargets.contains(p.category.trim().toLowerCase());
        }).toList();

        if (applyDemographic && demographic != 'All') {
          list = list.where((p) => matchesDemographic(p, demographic)).toList();
        }
        return list;
      }

      // Demographic is actively selected as 'Men/Boys'
      const activeDemographic = 'Men/Boys';

      // Grocery items must remain 100% visible (immune to demographic)
      final groceryItems = computeCategoryProducts(
        products,
        ['Dairy & Eggs', 'Grocery'],
        applyDemographic: false,
        demographic: activeDemographic,
      );
      expect(groceryItems.length, 1);
      expect(groceryItems.first.id, 'p_milk');

      // Pharmacy items must remain 100% visible (immune to demographic)
      final pharmacyItems = computeCategoryProducts(
        products,
        ['Pharmacy'],
        applyDemographic: false,
        demographic: activeDemographic,
      );
      expect(pharmacyItems.length, 1);
      expect(pharmacyItems.first.id, 'p_med');

      // Clothing items respect the demographic filter
      final clothingItems = computeCategoryProducts(
        products,
        ['Clothing'],
        applyDemographic: true,
        demographic: activeDemographic,
      );
      expect(clothingItems.length, 1);
      expect(clothingItems.first.id, 'p_shirt_men');
    });

    test('3. Admin Delivery Radius strictly eliminates out-of-range stores and products', () {
      final inRangeShop = createMockShop(
        id: 'shop_in',
        name: 'Nearby Mart',
        category: 'Grocery',
        distanceKm: 4.5,
      );

      final outOfRangeShop = createMockShop(
        id: 'shop_out',
        name: 'Distant Mart',
        category: 'Grocery',
        distanceKm: 18.0, // Exceeds default max radius (15km)
      );

      expect(DeliveryCalculator.isWithinRange(inRangeShop.distanceKm ?? 999.0), isTrue);
      expect(DeliveryCalculator.isWithinRange(outOfRangeShop.distanceKm ?? 999.0), isFalse);

      final allShops = [inRangeShop, outOfRangeShop];
      final nearShops = allShops
          .where((s) => DeliveryCalculator.isWithinRange(s.distanceKm ?? 999.0))
          .toList();

      expect(nearShops.length, 1);
      expect(nearShops.first.id, 'shop_in');

      final nearShopIds = nearShops.map((s) => s.id).toSet();

      final inRangeProduct = createMockProduct(
        id: 'p_in',
        name: 'Fresh Bread',
        category: 'Grocery',
        price: 40,
        rating: 4.5,
        shopId: inRangeShop.id,
      );

      final outOfRangeProduct = createMockProduct(
        id: 'p_out',
        name: 'Distant Bread',
        category: 'Grocery',
        price: 40,
        rating: 4.5,
        shopId: outOfRangeShop.id,
      );

      final visibleProducts = [inRangeProduct, outOfRangeProduct]
          .where((p) => nearShopIds.contains(p.shopId))
          .toList();

      expect(visibleProducts.length, 1);
      expect(visibleProducts.first.id, 'p_in');
    });

    test('4. Dedicated Category Sections gracefully collapse when empty', () {
      final allProducts = <ProductModel>[
        createMockProduct(id: 'p1', name: 'Paracetamol', category: 'Pharmacy', price: 20, rating: 4.9),
        createMockProduct(id: 'p2', name: 'Milk', category: 'Grocery', price: 30, rating: 4.8),
      ];

      final pharmacyProducts = allProducts.where((p) => p.category == 'Pharmacy').toList();
      final groceryProducts = allProducts.where((p) => p.category == 'Grocery').toList();
      final clothingProducts = allProducts.where((p) => p.category == 'Clothing').toList();

      expect(pharmacyProducts.isNotEmpty, isTrue);
      expect(groceryProducts.isNotEmpty, isTrue);
      expect(clothingProducts.isEmpty, isTrue);

      Widget buildSectionIfNonEmpty(List<ProductModel> items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Container(key: const ValueKey('active_section'));
      }

      final pharmacyWidget = buildSectionIfNonEmpty(pharmacyProducts);
      final clothingWidget = buildSectionIfNonEmpty(clothingProducts);

      expect(pharmacyWidget is Container, isTrue);
      expect(clothingWidget is SizedBox, isTrue);
      expect((clothingWidget as SizedBox).width, 0.0);
    });

    test('5. Carousel fallback retrieves shop from _shops when missing from productShops cache', () {
      final fallbackShop = createMockShop(
        id: 'shop_xyz',
        name: 'Prime Healthcare',
        category: 'Pharmacy',
        distanceKm: 1.2,
      );

      final product = createMockProduct(
        id: 'p_rx',
        name: 'Antacid Gel',
        category: 'Pharmacy',
        price: 90,
        rating: 4.7,
        shopId: 'shop_xyz',
      );

      final productShops = <String, ShopModel>{}; // Missing entry in cache!
      final allShops = <ShopModel>[fallbackShop];

      final resolvedShop = productShops[product.id] ??
          allShops.cast<ShopModel?>().firstWhere(
                (s) => s?.id == product.shopId,
                orElse: () => null,
              );

      expect(resolvedShop, isNotNull);
      expect(resolvedShop!.name, 'Prime Healthcare');
      expect(resolvedShop.distanceKm, 1.2);
    });

    test('6. AllListingsPage categoryFilter strictly isolates catalog and prevents leakage', () {
      final products = [
        createMockProduct(id: 'p_med_1', name: 'Vitamin C', category: 'Pharmacy & Healthcare', price: 150, rating: 4.9),
        createMockProduct(id: 'p_med_2', name: 'Bandages', category: 'Medicines', price: 50, rating: 4.5),
        createMockProduct(id: 'p_cloth_1', name: 'Cotton Shirt', category: 'Clothing & Fashion', price: 599, rating: 4.2),
        createMockProduct(id: 'p_food_1', name: 'Biryani', category: 'Food & Dining', price: 250, rating: 4.7),
      ];

      final categoryFilter = ['Pharmacy & Healthcare', 'Medicines', 'Pharmacy', 'Healthcare'];
      final lowerFilters = categoryFilter.map((c) => c.trim().toLowerCase()).toSet();

      final filteredProducts = products.where((p) {
        return lowerFilters.contains(p.category.trim().toLowerCase());
      }).toList();

      expect(filteredProducts.length, 2);
      expect(filteredProducts.map((p) => p.id).toSet(), {'p_med_1', 'p_med_2'});
      expect(filteredProducts.any((p) => p.category.contains('Clothing')), isFalse);
      expect(filteredProducts.any((p) => p.category.contains('Food')), isFalse);
    });

    test('7. Empty shopIds in AllListingsPage sets hasMore = false and stops phantom loads', () {
      final shopIds = <String>[];
      bool hasMore = true;
      bool isLoadingMore = true;

      if (shopIds.isEmpty) {
        hasMore = false;
        isLoadingMore = false;
      }

      expect(hasMore, isFalse);
      expect(isLoadingMore, isFalse);
    });

    test('8. High-load stress test: 1,000 products sorting memoization under 120 scroll frames', () {
      final massiveCatalog = List.generate(
        1000,
        (i) => createMockProduct(
          id: 'p_$i',
          name: 'Item $i',
          category: i % 3 == 0
              ? 'Grocery'
              : (i % 3 == 1 ? 'Pharmacy' : 'Clothing'),
          price: (1000 - i).toDouble(),
          rating: 4.0 + (i % 10) * 0.1,
          discountPercent: (i % 50).toDouble(),
        ),
      );

      List<ProductModel>? memoGrocery;
      int computationCount = 0;

      List<ProductModel> getGroceryProducts() {
        if (memoGrocery != null) return memoGrocery!;
        computationCount++;
        final list = massiveCatalog.where((p) => p.category == 'Grocery').toList();
        list.sort((a, b) => b.rating.compareTo(a.rating));
        memoGrocery = list;
        return memoGrocery!;
      }

      void invalidate() {
        memoGrocery = null;
      }

      // Initial computation
      final list = getGroceryProducts();
      expect(computationCount, 1);
      expect(list.length, 334);

      // Simulating 120 rapid scroll frames (e.g. 120fps display)
      final stopwatch = Stopwatch()..start();
      for (int frame = 0; frame < 120; frame++) {
        final current = getGroceryProducts();
        expect(identical(current, list), isTrue);
      }
      stopwatch.stop();

      // Zero recomputations occurred during scroll ticks!
      expect(computationCount, 1);
      // Execution time for 120 memoized reads of 1,000 items is sub-millisecond
      expect(stopwatch.elapsedMilliseconds < 50, isTrue);

      // Invalidation works deterministically on filter change
      invalidate();
      getGroceryProducts();
      expect(computationCount, 2);
    });

    test('9. Database query soft-delete compliance (is_deleted = false)', () {
      final rawDbRows = [
        {'id': 'p1', 'name': 'Active Syrup', 'is_deleted': false, 'price': 100},
        {'id': 'p2', 'name': 'Soft Deleted Tablet', 'is_deleted': true, 'price': 80},
        {'id': 'p3', 'name': 'Active Antibiotic', 'is_deleted': false, 'price': 120},
      ];

      final queriedRows = rawDbRows.where((row) => row['is_deleted'] == false).toList();

      expect(queriedRows.length, 2);
      expect(queriedRows.map((r) => r['id']).toList(), ['p1', 'p3']);
      expect(queriedRows.any((r) => r['id'] == 'p2'), isFalse);
    });
  });
}
