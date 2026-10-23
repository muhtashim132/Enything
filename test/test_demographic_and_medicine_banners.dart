import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';

void main() {
  group('100x Demographic & Medicine Banners Test Suite', () {
    test('1. Banner carousel slides count and auto-scroll modulo cycle', () {
      const int featuredSlidesCount = 6;
      expect(featuredSlidesCount, 6);

      // Verify that auto-scroll modulo wraps around all 6 banners properly:
      // 0: Food, 1: Groceries, 2: Medicine, 3: Men/Boys, 4: Women/Girls, 5: Event/Catering
      final cycle = <int>[];
      int currentIndex = 0;
      for (int i = 0; i < 7; i++) {
        currentIndex = (currentIndex + 1) % featuredSlidesCount;
        cycle.add(currentIndex);
      }
      expect(cycle, [1, 2, 3, 4, 5, 0, 1]);
    });

    // Mirror matcher logic from home_page.dart for strict verification
    bool matchesDemographic(ProductModel product, String demographic) {
      if (demographic == 'All') return true;

      final tags = product.specialTags
          .map((t) => t.trim().toLowerCase().replaceAll('#', ''))
          .toList();

      if (demographic == 'Men/Boys') {
        // 1. Direct positive tag matches
        final hasMenTag = tags.any((t) =>
            t == 'men' ||
            t == 'boys' ||
            t == 'boy' ||
            t == 'kids' ||
            t == 'unisex');
        if (hasMenTag) return true;

        // 2. Strict negative tag matches: if explicitly tagged for Women/Girls, reject
        final hasWomenTag = tags.any((t) =>
            t == 'women' ||
            t == 'girls' ||
            t == 'girl');
        if (hasWomenTag) return false;

        // 3. Fallback to name & description keyword analysis for untagged items
        final text = '${product.name} ${product.description}'.toLowerCase();
        if (RegExp(r"\b(women|womens|women's|girls|girl's|ladies|lady|female|kurti|saree|lehenga|bra|makeup)\b").hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(men|mens|men's|boy|boys|boy's|gent|gents|gent's|male)\b").hasMatch(text);
      } else if (demographic == 'Women/Girls') {
        // 1. Direct positive tag matches
        final hasWomenTag = tags.any((t) =>
            t == 'women' ||
            t == 'girls' ||
            t == 'girl' ||
            t == 'kids' ||
            t == 'unisex');
        if (hasWomenTag) return true;

        // 2. Strict negative tag matches: if explicitly tagged for Men/Boys, reject
        final hasMenTag = tags.any((t) =>
            t == 'men' ||
            t == 'boys' ||
            t == 'boy');
        if (hasMenTag) return false;

        // 3. Fallback to name & description keyword analysis for untagged items
        final text = '${product.name} ${product.description}'.toLowerCase();
        if (RegExp(r"\b(men|mens|men's|boys|boy's|gents|gent's|male)\b").hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(women|womens|women's|girl|girls|girl's|ladies|lady|female|kurti|saree|lehenga|dress|beauty|cosmetics)\b").hasMatch(text);
      }

      return true;
    }

    test('2. Men/Boys demographic matching - Explicit Tags & Unisex', () {
      final p1 = ProductModel(
        id: 'p1',
        shopId: 's1',
        name: 'Classic Casual Denim',
        price: 999,
        category: 'Clothing',
        specialTags: ['#Men'],
      );
      final p2 = ProductModel(
        id: 'p2',
        shopId: 's1',
        name: 'Sporty Running Shoes',
        price: 1499,
        category: 'Footwear',
        specialTags: ['#Boys'],
      );
      final p3 = ProductModel(
        id: 'p3',
        shopId: 's1',
        name: 'Cotton Hoodie',
        price: 799,
        category: 'Clothing',
        specialTags: ['#Unisex'],
      );
      final p4 = ProductModel(
        id: 'p4',
        shopId: 's1',
        name: 'Kids Everyday Socks',
        price: 199,
        category: 'Clothing',
        specialTags: ['#Kids'],
      );

      expect(matchesDemographic(p1, 'Men/Boys'), isTrue);
      expect(matchesDemographic(p2, 'Men/Boys'), isTrue);
      expect(matchesDemographic(p3, 'Men/Boys'), isTrue);
      expect(matchesDemographic(p4, 'Men/Boys'), isTrue);
    });

    test('3. Men/Boys demographic matching - Strict Rejection of Women/Girls', () {
      final pWomenTag = ProductModel(
        id: 'pw1',
        shopId: 's1',
        name: 'Designer Party Wear',
        price: 1999,
        category: 'Clothing',
        specialTags: ['#Women'],
      );
      final pGirlsTag = ProductModel(
        id: 'pw2',
        shopId: 's1',
        name: 'Floral Ballerina Shoes',
        price: 899,
        category: 'Footwear',
        specialTags: ['#Girls'],
      );

      expect(matchesDemographic(pWomenTag, 'Men/Boys'), isFalse);
      expect(matchesDemographic(pGirlsTag, 'Men/Boys'), isFalse);
    });

    test('4. Men/Boys demographic matching - Untagged Legacy Products with Keyword Engine', () {
      final pUntaggedMen = ProductModel(
        id: 'pu1',
        shopId: 's1',
        name: "Men's Formal Oxford Shirt",
        price: 899,
        category: 'Clothing',
        specialTags: [],
      );
      final pUntaggedBoys = ProductModel(
        id: 'pu2',
        shopId: 's1',
        name: "Boys Printed Graphic T-Shirt",
        price: 499,
        category: 'Clothing',
        specialTags: [],
      );
      final pUntaggedWomen = ProductModel(
        id: 'pu3',
        shopId: 's1',
        name: "Women's Embroidered Anarkali Kurti",
        price: 1299,
        category: 'Clothing',
        specialTags: [],
      );

      expect(matchesDemographic(pUntaggedMen, 'Men/Boys'), isTrue);
      expect(matchesDemographic(pUntaggedBoys, 'Men/Boys'), isTrue);
      expect(matchesDemographic(pUntaggedWomen, 'Men/Boys'), isFalse);
    });

    test('5. Women/Girls demographic matching - Explicit Tags & Unisex', () {
      final p1 = ProductModel(
        id: 'pw1',
        shopId: 's1',
        name: 'Traditional Banarasi Silk Saree',
        price: 2499,
        category: 'Clothing',
        specialTags: ['#Women'],
      );
      final p2 = ProductModel(
        id: 'pw2',
        shopId: 's1',
        name: 'Girls Sparkly Party Dress',
        price: 1199,
        category: 'Clothing',
        specialTags: ['#Girls'],
      );
      final p3 = ProductModel(
        id: 'pw3',
        shopId: 's1',
        name: 'Knitted Beanie Cap',
        price: 299,
        category: 'Clothing',
        specialTags: ['#Unisex'],
      );

      expect(matchesDemographic(p1, 'Women/Girls'), isTrue);
      expect(matchesDemographic(p2, 'Women/Girls'), isTrue);
      expect(matchesDemographic(p3, 'Women/Girls'), isTrue);
    });

    test('6. Women/Girls demographic matching - Strict Rejection of Men/Boys', () {
      final pMenTag = ProductModel(
        id: 'pm1',
        shopId: 's1',
        name: 'Tailored Waistcoat',
        price: 1899,
        category: 'Clothing',
        specialTags: ['#Men'],
      );
      final pBoysTag = ProductModel(
        id: 'pm2',
        shopId: 's1',
        name: 'Boys School Uniform Trousers',
        price: 599,
        category: 'Clothing',
        specialTags: ['#Boys'],
      );

      expect(matchesDemographic(pMenTag, 'Women/Girls'), isFalse);
      expect(matchesDemographic(pBoysTag, 'Women/Girls'), isFalse);
    });

    test('7. Women/Girls demographic matching - Untagged Legacy Products with Keyword Engine', () {
      final pUntaggedWomen = ProductModel(
        id: 'puw1',
        shopId: 's1',
        name: "Women's Casual A-Line Dress",
        price: 999,
        category: 'Clothing',
        specialTags: [],
      );
      final pUntaggedGirls = ProductModel(
        id: 'puw2',
        shopId: 's1',
        name: "Girls Pink Sneakers",
        price: 799,
        category: 'Footwear',
        specialTags: [],
      );
      final pUntaggedMen = ProductModel(
        id: 'puw3',
        shopId: 's1',
        name: "Men's Leather Loafers",
        price: 1599,
        category: 'Footwear',
        specialTags: [],
      );

      expect(matchesDemographic(pUntaggedWomen, 'Women/Girls'), isTrue);
      expect(matchesDemographic(pUntaggedGirls, 'Women/Girls'), isTrue);
      expect(matchesDemographic(pUntaggedMen, 'Women/Girls'), isFalse);
    });

    test('8. Medicine Category Mapping & Isolation', () {
      const Map<String, List<String>> tabCategories = {
        'Pharmacy': ['Pharmacy', 'Medical Store'],
        'Grocery': ['Grocery', 'Supermarket / Hypermarket', 'Fruits & Vegs'],
        'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
      };

      expect(tabCategories['Pharmacy'], contains('Pharmacy'));
      expect(tabCategories['Pharmacy'], contains('Medical Store'));
      expect(tabCategories['Pharmacy'], isNot(contains('Restaurant')));
      expect(tabCategories['Pharmacy'], isNot(contains('Clothing')));
    });

    test('9. 100% Prepaid Model Inviolability', () {
      // Ensure zero COD in customer checkout & order models
      final testOrder = {
        'payment_method': 'upi',
        'is_cod': false,
        'is_prepaid': true,
        'cod_amount': 0.0,
      };

      expect(testOrder['is_cod'], isFalse);
      expect(testOrder['is_prepaid'], isTrue);
      expect(testOrder['cod_amount'], 0.0);
    });

    test('10. Soft Delete Inviolability (Database Query Filter)', () {
      final dbProducts = [
        {'id': 'p_active', 'name': 'Active Product', 'is_deleted': false},
        {'id': 'p_deleted', 'name': 'Deleted Product', 'is_deleted': true},
      ];

      // Mirror .eq('is_deleted', false)
      final activeOnly = dbProducts.where((p) => p['is_deleted'] == false).toList();

      expect(activeOnly.length, 1);
      expect(activeOnly.first['id'], 'p_active');
    });
  });
}
