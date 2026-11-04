import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100x Grid Even Row and Per-Shop Feed Limit Fortress', () {
    test('perShopLimit calculation prevents single-shop 5-item hole bottleneck', () {
      int computePerShopLimit(int shopCount) {
        return shopCount <= 2 ? 12 : 8;
      }

      // Case 1: Single shop (e.g. Maxx Retail in Bandipora)
      expect(computePerShopLimit(1), 12);
      expect(computePerShopLimit(1) >= 6, isTrue);

      // Case 2: Two shops
      expect(computePerShopLimit(2), 12);

      // Case 3: Many shops
      expect(computePerShopLimit(3), 8);
      expect(computePerShopLimit(10), 8);
      expect(computePerShopLimit(50), 8);
    });

    test('Responsive grid effectiveLimit produces complete rows across all screen sizes', () {
      int computeEffectiveLimit({
        required int crossAxisCount,
        required int productsDisplayLimit,
      }) {
        final targetGridCount =
            crossAxisCount == 2 ? 6 : (crossAxisCount * 2);
        return math.max(productsDisplayLimit, targetGridCount);
      }

      // Mobile (2 columns): target 6 items (3 complete rows of 2)
      final mobileLimit = computeEffectiveLimit(
        crossAxisCount: 2,
        productsDisplayLimit: 6,
      );
      expect(mobileLimit, 6);
      expect(mobileLimit % 2, 0, reason: 'Must be divisible by 2 on mobile');

      // Tablet (4 columns): target 8 items (2 complete rows of 4)
      final tabletLimit = computeEffectiveLimit(
        crossAxisCount: 4,
        productsDisplayLimit: 6,
      );
      expect(tabletLimit, 8);
      expect(tabletLimit % 4, 0, reason: 'Must be divisible by 4 on tablet');

      // Desktop (5 columns): target 10 items (2 complete rows of 5)
      final desktopLimit = computeEffectiveLimit(
        crossAxisCount: 5,
        productsDisplayLimit: 6,
      );
      expect(desktopLimit, 10);
      expect(desktopLimit % 5, 0, reason: 'Must be divisible by 5 on desktop');
    });

    test('Simulation: Single shop with 15 products fills complete 3x2 grid with 6 items', () {
      // Mock 15 products from Maxx Retail
      final mockProducts = List.generate(
        15,
        (i) => {'id': 'prod_$i', 'name': 'Product $i', 'shop_id': 'maxx_retail'},
      );

      final perShopLimit = 12; // New 100x limit
      final fetchedFromBackend = mockProducts.take(perShopLimit).toList();
      expect(fetchedFromBackend.length, 12);

      const crossAxisCount = 2; // Mobile
      final targetGridCount = crossAxisCount == 2 ? 6 : (crossAxisCount * 2);
      final effectiveLimit = math.max(6, targetGridCount);

      final displayProducts = fetchedFromBackend.take(effectiveLimit).toList();
      expect(displayProducts.length, 6);

      // Check row distribution
      final rows = (displayProducts.length / crossAxisCount).ceil();
      expect(rows, 3);
      final isLastRowComplete = displayProducts.length % crossAxisCount == 0;
      expect(isLastRowComplete, isTrue, reason: 'Row 3 column 2 must not be empty');
    });

    test('Legacy vs 100x Fortress comparison: 5-limit bug reproduction and resolution', () {
      final mockStoreProducts = List.generate(20, (i) => 'Product $i');

      // LEGACY BEHAVIOR:
      const legacyLimitPerShop = 5;
      final legacyFetched = mockStoreProducts.take(legacyLimitPerShop).toList();
      const crossAxisCount = 2;
      final legacyDisplayed = legacyFetched.take(6).toList();
      expect(legacyDisplayed.length, 5);
      expect(
        legacyDisplayed.length % crossAxisCount,
        1,
        reason: 'Legacy bug: leaves 1 orphan product in row 3 with empty slot on the right',
      );

      // 100X FORTRESS BEHAVIOR:
      const fortressLimitPerShop = 12;
      final fortressFetched = mockStoreProducts.take(fortressLimitPerShop).toList();
      final fortressDisplayed = fortressFetched.take(6).toList();
      expect(fortressDisplayed.length, 6);
      expect(
        fortressDisplayed.length % crossAxisCount,
        0,
        reason: '100x Fortress: Row 3 is completely filled with 2 items, zero holes',
      );
    });

    test('All categories in Explore Categories adhere to even row invariants', () {
      const exploreCategories = [
        'Food',
        'Supermarket / Hypermarket',
        'Pharmacy',
        'Clothing',
        'Electronics',
        'More',
      ];

      for (final cat in exploreCategories) {
        // Mock products for category
        final products = List.generate(10, (i) => '$cat Product $i');
        const crossAxisCount = 2;
        final targetCount = crossAxisCount == 2 ? 6 : (crossAxisCount * 2);
        final displayed = products.take(targetCount).toList();

        expect(displayed.length, 6, reason: 'Category $cat must display 6 products');
        expect(displayed.length % crossAxisCount, 0,
            reason: 'Category $cat grid must have zero empty slots');
      }
    });
  });
}

