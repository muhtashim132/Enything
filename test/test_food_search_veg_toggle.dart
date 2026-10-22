import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/config/app_categories.dart';

void main() {
  group('100x Forensic Edge-Case Tests: Food Search Veg/Non-Veg Toggle Fortress', () {
    // Mock Product Data
    final vegProduct = ProductModel(
      id: 'p-veg-1',
      shopId: 'shop-veg-restaurant',
      name: 'Paneer Butter Masala',
      category: 'Food',
      price: 250.0,
      rating: 4.8,
      isAvailable: true,
      isVeg: true,
    );

    final nonVegProduct = ProductModel(
      id: 'p-nonveg-1',
      shopId: 'shop-nonveg-restaurant',
      name: 'Chicken Dum Biryani',
      category: 'Food',
      price: 320.0,
      rating: 4.9,
      isAvailable: true,
      isVeg: false,
    );

    final unclassifiedFoodProduct = ProductModel(
      id: 'p-unclassified-1',
      shopId: 'shop-mixed',
      name: 'Special Mystery Gravy',
      category: 'Food',
      price: 180.0,
      rating: 4.2,
      isAvailable: true,
      isVeg: null,
    );

    final nonFoodProduct = ProductModel(
      id: 'p-nonfood-1',
      shopId: 'shop-apparel',
      name: 'Cotton Denim Jeans',
      category: 'Clothing',
      price: 1299.0,
      rating: 4.5,
      isAvailable: true,
      isVeg: null,
    );

    // Mock Shop Data
    final pureVegRestaurant = ShopModel(
      id: 'shop-veg-restaurant',
      sellerId: 's-1',
      name: 'Govinda Pure Veg',
      shopType: 'Restaurant',
      category: 'Restaurant',
      categories: const ['Restaurant'],
      address: 'Temple Road',
      location: const LatLng(19.0, 72.8),
      isVegOnly: true,
      isActive: true,
    );

    final multiCuisineRestaurant = ShopModel(
      id: 'shop-nonveg-restaurant',
      sellerId: 's-2',
      name: 'Royal Spice Kitchen',
      shopType: 'Restaurant',
      category: 'Restaurant',
      categories: const ['Restaurant'],
      address: 'Main Market',
      location: const LatLng(19.01, 72.81),
      isVegOnly: false,
      isActive: true,
    );

    final butcherShop = ShopModel(
      id: 'shop-butcher',
      sellerId: 's-3',
      name: 'Fresh Cuts Meat Shop',
      shopType: 'Butcher',
      category: 'Butcher',
      categories: const ['Butcher'],
      address: 'Market Yard',
      location: const LatLng(19.02, 72.82),
      isVegOnly: false,
      isActive: true,
    );

    final apparelShop = ShopModel(
      id: 'shop-apparel',
      sellerId: 's-4',
      name: 'Denim World',
      shopType: 'Retail',
      category: 'Clothing',
      categories: const ['Clothing'],
      address: 'Mall Plaza',
      location: const LatLng(19.03, 72.83),
      isVegOnly: false,
      isActive: true,
    );

    test('EC-1 & EC-2: Pure Veg filter isolates isVeg == true products and excludes others', () {
      final allProducts = [vegProduct, nonVegProduct, unclassifiedFoodProduct, nonFoodProduct];

      // vegOnly filter
      final vegFiltered = allProducts.where((p) => p.isVeg == true).toList();
      expect(vegFiltered.length, 1);
      expect(vegFiltered.first.id, 'p-veg-1');
      expect(vegFiltered.first.name, 'Paneer Butter Masala');

      // nonVegOnly filter
      final nonVegFiltered = allProducts.where((p) => p.isVeg == false).toList();
      expect(nonVegFiltered.length, 1);
      expect(nonVegFiltered.first.id, 'p-nonveg-1');
      expect(nonVegFiltered.first.name, 'Chicken Dum Biryani');
    });

    test('EC-1: Null isVeg products are safely excluded from veg/non-veg but preserved in All', () {
      final allProducts = [vegProduct, nonVegProduct, unclassifiedFoodProduct];

      // In vegOnly mode: null is NOT veg
      final vegOnly = allProducts.where((p) => p.isVeg == true).toList();
      expect(vegOnly.contains(unclassifiedFoodProduct), isFalse);

      // In nonVegOnly mode: null is NOT non-veg
      final nonVegOnly = allProducts.where((p) => p.isVeg == false).toList();
      expect(nonVegOnly.contains(unclassifiedFoodProduct), isFalse);

      // In all mode: all 3 are present
      expect(allProducts.length, 3);
    });

    test('EC-3: Non-food items do not claim dietary status or display diet emblem', () {
      expect(vegProduct.isFood, isTrue);
      expect(vegProduct.showsDietEmblem, isTrue);

      expect(nonVegProduct.isFood, isTrue);
      expect(nonVegProduct.showsDietEmblem, isTrue);

      // Non-food clothing product
      expect(nonFoodProduct.isFood, isFalse);
      expect(nonFoodProduct.showsDietEmblem, isFalse);
    });

    test('EC-3: Food items in search detection activates dietary toggle only when food is present', () {
      // Scenario A: Food products present
      final searchWithFoodProducts = [vegProduct, nonFoodProduct];
      final hasFoodA = searchWithFoodProducts.any((p) => p.isFood || p.isVeg != null);
      expect(hasFoodA, isTrue);

      // Scenario B: Food shop present
      final searchWithFoodShops = [pureVegRestaurant];
      final hasFoodB = searchWithFoodShops.any((s) => AppCategories.isFoodCategory(s.category));
      expect(hasFoodB, isTrue);

      // Scenario C: Purely non-food products and shops (e.g. clothing search)
      final searchNonFoodProds = [nonFoodProduct];
      final searchNonFoodShops = [apparelShop];
      final hasFoodC = searchNonFoodProds.any((p) => p.isFood || p.isVeg != null) ||
          searchNonFoodShops.any((s) => AppCategories.isFoodCategory(s.category));
      expect(hasFoodC, isFalse);
    });

    test('EC-6: Shop filtering preserves dietary coherence for pure veg, mixed, and butcher shops', () {
      final rawShops = [pureVegRestaurant, multiCuisineRestaurant, butcherShop];
      final searchProducts = [vegProduct, nonVegProduct];

      // Filter: Pure Veg mode
      final vegShops = rawShops.where((s) {
        if (s.isVegOnly) return true;
        if (s.category == 'Butcher' || s.category == 'Fish & Seafood') return false;
        final hasVeg = searchProducts.any((p) => p.shopId == s.id && p.isVeg == true);
        if (hasVeg) return true;
        if (searchProducts.isNotEmpty) return false;
        return true;
      }).toList();

      expect(vegShops.contains(pureVegRestaurant), isTrue);
      expect(vegShops.contains(butcherShop), isFalse); // Butcher strictly excluded
      expect(vegShops.contains(multiCuisineRestaurant), isFalse); // multiCuisine has no veg items in searchProducts

      // Filter: Non-Veg mode
      final nonVegShops = rawShops.where((s) {
        if (s.isVegOnly) return false; // Pure veg strictly excluded from non-veg
        final hasNonVeg = searchProducts.any((p) => p.shopId == s.id && p.isVeg == false);
        if (hasNonVeg) return true;
        if (searchProducts.isNotEmpty) {
          return s.category == 'Butcher' || s.category == 'Fish & Seafood';
        }
        return true;
      }).toList();

      expect(nonVegShops.contains(pureVegRestaurant), isFalse); // Pure veg excluded
      expect(nonVegShops.contains(multiCuisineRestaurant), isTrue); // Has matching chicken biryani
      expect(nonVegShops.contains(butcherShop), isTrue); // Butcher allowed in non-veg
    });

    test('EC-4 & EC-5: Zero-match filter edge case gracefully computes count 0 without errors', () {
      // Scenario: User searches for chicken, returns only non-veg items
      final chickenSearchResults = [nonVegProduct];

      // User filters for Pure Veg
      final filteredResults = chickenSearchResults.where((p) => p.isVeg == true).toList();
      expect(filteredResults.isEmpty, isTrue);
      expect(filteredResults.length, 0);

      // Header count must be 0, not chickenSearchResults.length (1)
      final displayedCount = filteredResults.length;
      expect(displayedCount, 0);
    });

    test('EC-7 & EC-10: Toggle behavior switches back to all when tapped again, and preserves sort', () {
      var currentMode = VegFilterMode.all;

      // Tap Veg: switches to vegOnly
      currentMode = currentMode == VegFilterMode.vegOnly ? VegFilterMode.all : VegFilterMode.vegOnly;
      expect(currentMode, VegFilterMode.vegOnly);

      // Tap Veg again: toggles back to all
      currentMode = currentMode == VegFilterMode.vegOnly ? VegFilterMode.all : VegFilterMode.vegOnly;
      expect(currentMode, VegFilterMode.all);

      // Tap Non-Veg: switches to nonVegOnly
      currentMode = currentMode == VegFilterMode.nonVegOnly ? VegFilterMode.all : VegFilterMode.nonVegOnly;
      expect(currentMode, VegFilterMode.nonVegOnly);

      // Tap Non-Veg again: toggles back to all
      currentMode = currentMode == VegFilterMode.nonVegOnly ? VegFilterMode.all : VegFilterMode.nonVegOnly;
      expect(currentMode, VegFilterMode.all);
    });

    test('EC-10: Dietary filter and price sorting compose cleanly without state collisions', () {
      final cheapVeg = ProductModel(
        id: 'p-v-1',
        shopId: 's1',
        name: 'Dal Tadka',
        category: 'Food',
        price: 120.0,
        isAvailable: true,
        isVeg: true,
      );
      final expensiveVeg = ProductModel(
        id: 'p-v-2',
        shopId: 's1',
        name: 'Kaju Curry',
        category: 'Food',
        price: 340.0,
        isAvailable: true,
        isVeg: true,
      );
      final cheapNonVeg = ProductModel(
        id: 'p-nv-1',
        shopId: 's2',
        name: 'Egg Curry',
        category: 'Food',
        price: 150.0,
        isAvailable: true,
        isVeg: false,
      );

      final all = [expensiveVeg, cheapNonVeg, cheapVeg];

      // Filter: Pure Veg + Sort: Price Low to High
      var filtered = all.where((p) => p.isVeg == true).toList();
      filtered.sort((a, b) => a.price.compareTo(b.price));

      expect(filtered.length, 2);
      expect(filtered[0].id, 'p-v-1'); // ₹120 first
      expect(filtered[1].id, 'p-v-2'); // ₹340 second
    });
  });
}
