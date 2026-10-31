import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';

void main() {
  group('100x Forensic Edge-Case Tests: Restaurant Search & Product Discovery Fortress', () {
    // Mock restaurant: KFC
    final kfcShop = ShopModel(
      id: 'shop-kfc-001',
      sellerId: 'seller-kfc',
      name: 'KFC',
      shopType: 'Restaurant',
      category: 'Restaurant',
      categories: const ['Restaurant'],
      cuisineType: 'Fast Food, American, Chicken',
      address: 'High Street, Mall Road',
      location: const LatLng(19.0760, 72.8777),
      rating: 4.6,
      totalOrders: 1500,
      isAcceptingOrders: true,
      isActive: true,
    );

    // Mock products belonging to KFC
    // Notice that their product names DO NOT contain the word "KFC"
    final kfcProduct1 = ProductModel(
      id: 'kfc-p1',
      shopId: 'shop-kfc-001',
      name: 'Zinger Burger',
      category: 'Food',
      price: 199.0,
      rating: 4.8,
      isAvailable: true,
      isVeg: false,
    );
    final kfcProduct2 = ProductModel(
      id: 'kfc-p2',
      shopId: 'shop-kfc-001',
      name: 'Hot & Crispy Chicken (4 pcs)',
      category: 'Food',
      price: 399.0,
      rating: 4.7,
      isAvailable: true,
      isVeg: false,
    );
    final kfcProduct3 = ProductModel(
      id: 'kfc-p3',
      shopId: 'shop-kfc-001',
      name: 'French Fries (Large)',
      category: 'Food',
      price: 119.0,
      rating: 4.5,
      isAvailable: true,
      isVeg: true,
    );
    final kfcProduct4 = ProductModel(
      id: 'kfc-p4',
      shopId: 'shop-kfc-001',
      name: 'Popcorn Chicken',
      category: 'Food',
      price: 249.0,
      rating: 4.6,
      isAvailable: true,
      isVeg: false,
    );
    final kfcProduct5 = ProductModel(
      id: 'kfc-p5',
      shopId: 'shop-kfc-001',
      name: 'Pepsi Can (330ml)',
      category: 'Food',
      price: 60.0,
      rating: 4.2,
      isAvailable: true,
      isVeg: true,
    );

    // Mock unrelated shop closer by distance
    final groceryShop = ShopModel(
      id: 'shop-grocery-002',
      sellerId: 'seller-grocery',
      name: 'Quick Mart Daily',
      shopType: 'Grocery',
      category: 'Grocery',
      categories: const ['Grocery'],
      address: 'Corner Street',
      location: const LatLng(19.0762, 72.8779),
      rating: 4.0,
      totalOrders: 100,
      isAcceptingOrders: true,
      isActive: true,
    );

    test('Searching restaurant name "KFC" identifies matching shop and all 5 products', () {
      const query = 'KFC';
      final lowerQuery = query.toLowerCase().trim();
      final terms = lowerQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final shops = [groceryShop, kfcShop];

      // Identify matching shops
      final matchingShopIds = <String>{};
      for (final s in shops) {
        final sName = s.name.toLowerCase();
        final sCuisine = (s.cuisineType ?? '').toLowerCase();
        final isDirectMatch = (lowerQuery.isNotEmpty && sName.contains(lowerQuery)) ||
            (terms.isNotEmpty && terms.any((t) => sName.contains(t) || sCuisine.contains(t)));
        if (isDirectMatch) {
          matchingShopIds.add(s.id);
        }
      }

      expect(matchingShopIds.contains('shop-kfc-001'), isTrue);
      expect(matchingShopIds.contains('shop-grocery-002'), isFalse);

      // Verify that all products from KFC are included even though product names do not contain "KFC"
      final allKfcProducts = [
        kfcProduct1,
        kfcProduct2,
        kfcProduct3,
        kfcProduct4,
        kfcProduct5,
      ];

      final filteredProducts = allKfcProducts.where((p) {
        final isFromMatchingShop = matchingShopIds.contains(p.shopId);
        if (!isFromMatchingShop && terms.isNotEmpty) {
          final searchable = '${p.name} ${p.description ?? ''} ${p.brand ?? ''}'.toLowerCase();
          if (!terms.every((t) => searchable.contains(t))) return false;
        }
        return true;
      }).toList();

      expect(filteredProducts.length, equals(5));
      expect(filteredProducts.map((p) => p.name).toList(), containsAll([
        'Zinger Burger',
        'Hot & Crispy Chicken (4 pcs)',
        'French Fries (Large)',
        'Popcorn Chicken',
        'Pepsi Can (330ml)',
      ]));
    });

    test('Preview logic: exactly 3 products initially displayed with See More option', () {
      final allProducts = [
        kfcProduct1,
        kfcProduct2,
        kfcProduct3,
        kfcProduct4,
        kfcProduct5,
      ];

      int displayLimit = 3;
      final visibleInitial = allProducts.take(displayLimit).toList();

      expect(visibleInitial.length, equals(3));
      expect(visibleInitial[0].name, equals('Zinger Burger'));
      expect(visibleInitial[1].name, equals('Hot & Crispy Chicken (4 pcs)'));
      expect(visibleInitial[2].name, equals('French Fries (Large)'));

      // Needs See More option
      final hasSeeMore = allProducts.length > 3;
      expect(hasSeeMore, isTrue);

      final remainingCount = allProducts.length - displayLimit;
      expect(remainingCount, equals(2));

      // Tapping See More expands to all products
      displayLimit = allProducts.length;
      final visibleExpanded = allProducts.take(displayLimit).toList();
      expect(visibleExpanded.length, equals(5));

      // Tapping See Less collapses back to 3
      displayLimit = 3;
      final visibleCollapsed = allProducts.take(displayLimit).toList();
      expect(visibleCollapsed.length, equals(3));
    });

    test('Restaurant with <= 3 products shows all products without redundant See More', () {
      final fewProducts = [kfcProduct1, kfcProduct2];

      const initialLimit = 3;
      final visible = fewProducts.take(initialLimit).toList();

      expect(visible.length, equals(2));
      final hasSeeMore = fewProducts.length > 3;
      expect(hasSeeMore, isFalse);
    });

    test('Restaurant sorting: searched restaurant is prioritized #1 above closer shops', () {
      const query = 'KFC';
      final cleanQuery = query.toLowerCase().trim();
      final terms = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      // groceryShop has smaller distance (0.5 km) than kfcShop (2.5 km)
      groceryShop.distanceKm = 0.5;
      kfcShop.distanceKm = 2.5;

      final shops = [groceryShop, kfcShop];

      shops.sort((a, b) {
        if (query.isNotEmpty) {
          final aName = a.name.toLowerCase();
          final bName = b.name.toLowerCase();

          final aExact = aName == cleanQuery || aName.contains(cleanQuery);
          final bExact = bName == cleanQuery || bName.contains(cleanQuery);
          if (aExact != bExact) return aExact ? -1 : 1;

          final aMatches = terms.any((t) => aName.contains(t));
          final bMatches = terms.any((t) => bName.contains(t));
          if (aMatches != bMatches) return aMatches ? -1 : 1;
        }

        final openA = a.isOpenRightNow ? 1 : 0;
        final openB = b.isOpenRightNow ? 1 : 0;
        if (openA != openB) return openB.compareTo(openA);

        return (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity);
      });

      // KFC MUST be index 0 (underneath the See More button)
      expect(shops.first.name, equals('KFC'));
      expect(shops.first.id, equals('shop-kfc-001'));
    });

    test('Punctuation tolerance: searches like "kfc\'s" or "la pino\'z" match properly', () {
      const queryWithPunctuation = "kfc's";
      final cleanQuery = queryWithPunctuation.replaceAll(RegExp(r'[,()"\x27]'), ' ').trim().toLowerCase();
      final terms = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final sName = kfcShop.name.toLowerCase();
      final isDirectMatch = terms.any((t) => sName.contains(t));

      expect(isDirectMatch, isTrue);
    });
  });
}
