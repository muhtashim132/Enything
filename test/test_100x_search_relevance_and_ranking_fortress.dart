import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/utils/search_relevance_engine.dart';

void main() {
  group('100x Search Relevance & Exact Name Ranking Fortress', () {
    ProductModel createTestProduct({
      required String id,
      required String name,
      String? brand,
      String? description,
      String category = 'Beverages',
      String medicineType = '',
      double rating = 0.0,
      double price = 100.0,
      bool isAvailable = true,
    }) {
      return ProductModel(
        id: id,
        shopId: 'shop_1',
        name: name,
        category: category,
        price: price,
        isAvailable: isAvailable,
        brand: brand,
        description: description,
        medicineType: medicineType,
        rating: rating,
        images: const ['https://example.com/img.jpg'],
        unitType: 'piece',
      );
    }

    test('User Screenshot Forensic Case: "dew" ranks "dew 250" and "Dew 750 ml" at index 0 and 1', () {
      final p1 = createTestProduct(
        id: 'p_vaseline',
        name: 'Vaseline Healthy Bright Gluta-Hya Dewy Radiance',
        brand: 'Vaseline',
        description: 'Serum burst lotion with dewy finish',
        category: 'Cosmetics & Beauty',
        rating: 5.0, // High rating, was #1 in legacy rating sort!
      );

      final p2 = createTestProduct(
        id: 'p_dermadew',
        name: 'Dermadew | Baby Cream | 80g',
        brand: 'Dermadew',
        description: 'Moisturizing baby cream for delicate skin',
        category: 'Pharmacy',
        rating: 5.0, // High rating, was #2 in legacy rating sort!
      );

      final p3 = createTestProduct(
        id: 'p_dew_750',
        name: 'Dew 750 ml',
        description: 'Mountain Dew carbonated soft drink bottle',
        category: 'Beverages',
        rating: 0.0, // New product, was #3 or #7 in legacy rating sort!
      );

      final p4 = createTestProduct(
        id: 'p_dew_250',
        name: 'dew 250',
        description: 'Mountain Dew can 250ml',
        category: 'Beverages',
        rating: 0.0, // New product, was #4 or #8 in legacy rating sort!
      );

      final p5 = createTestProduct(
        id: 'p_mountain_dew',
        name: 'Mountain Dew Soft Drink 1.25L',
        brand: 'Mountain Dew',
        description: 'Citrus flavoured soft drink',
        category: 'Beverages',
        rating: 4.5,
      );

      final products = [p1, p2, p3, p4, p5];

      // Sort with 100x SearchRelevanceEngine
      SearchRelevanceEngine.sortProducts(
        products: products,
        query: 'dew',
      );

      // Verify exact name prefix matches are at index 0 and 1
      final topTwoIds = [products[0].id, products[1].id];
      expect(topTwoIds, contains('p_dew_250'));
      expect(topTwoIds, contains('p_dew_750'));

      // Mountain Dew has distinct word "Dew" in title -> index 2
      expect(products[2].id, 'p_mountain_dew');

      // Vaseline has word "Dewy" starting with "dew" -> index 3
      expect(products[3].id, 'p_vaseline');

      // Dermadew has "dew" as substring inside "dermadew" -> index 4
      expect(products[4].id, 'p_dermadew');
    });

    test('Exact product name match scores highest possible tier', () {
      final exactMatch = createTestProduct(id: '1', name: 'Dew');
      final prefixMatch = createTestProduct(id: '2', name: 'Dew 750 ml');
      final containsWord = createTestProduct(id: '3', name: 'Mountain Dew');
      final containsSubstring = createTestProduct(id: '4', name: 'Dermadew');

      final scoreExact = SearchRelevanceEngine.computeScore(product: exactMatch, query: 'dew');
      final scorePrefix = SearchRelevanceEngine.computeScore(product: prefixMatch, query: 'dew');
      final scoreWord = SearchRelevanceEngine.computeScore(product: containsWord, query: 'dew');
      final scoreSub = SearchRelevanceEngine.computeScore(product: containsSubstring, query: 'dew');

      expect(scoreExact > scorePrefix, isTrue, reason: 'Exact match must score higher than prefix');
      expect(scorePrefix > scoreWord, isTrue, reason: 'Prefix match must score higher than word match');
      expect(scoreWord > scoreSub, isTrue, reason: 'Word match must score higher than substring match');
    });

    test('Cosmetics category: "serum" query ranks actual serums ahead of creams with serum in description', () {
      final serum1 = createTestProduct(
        id: 's1',
        name: 'Dot & Key Water Drench Hyaluronic Serum',
        category: 'Cosmetics & Beauty',
        rating: 0.0,
      );
      final serum2 = createTestProduct(
        id: 's2',
        name: 'Minimalist 10% Niacinamide Serum',
        category: 'Cosmetics & Beauty',
        rating: 0.0,
      );
      final creamWithSerumInDesc = createTestProduct(
        id: 'c1',
        name: 'Ponds Super Light Gel Face Moisturizer',
        description: 'Infused with hyaluronic serum booster for plump skin',
        category: 'Cosmetics & Beauty',
        rating: 5.0, // High rating
      );

      final list = [creamWithSerumInDesc, serum1, serum2];
      SearchRelevanceEngine.sortProducts(products: list, query: 'serum');

      expect(list[0].name.toLowerCase(), contains('serum'));
      expect(list[1].name.toLowerCase(), contains('serum'));
      expect(list[2].id, 'c1', reason: 'Cream with serum in description must rank after actual serums');
    });

    test('Medicine & Pharmacy category: "paracetamol" query ranks tablets and composition matches at top', () {
      final tablet = createTestProduct(
        id: 'm1',
        name: 'Paracetamol 650mg Tablets',
        category: 'Pharmacy',
        rating: 0.0,
      );
      final compositionMatch = createTestProduct(
        id: 'm2',
        name: 'Dolo 650',
        medicineType: 'Paracetamol',
        category: 'Pharmacy',
        rating: 4.0,
      );
      final kit = createTestProduct(
        id: 'm3',
        name: 'Family First Aid Medical Kit',
        description: 'Contains antiseptic, bandages, paracetamol tablets, and cotton',
        category: 'Pharmacy',
        rating: 5.0,
      );

      final list = [kit, compositionMatch, tablet];
      SearchRelevanceEngine.sortProducts(products: list, query: 'paracetamol');

      expect(list[0].id, 'm1', reason: 'Exact name prefix must rank #1');
      expect(list[1].id, 'm2', reason: 'Medicine composition match must rank #2');
      expect(list[2].id, 'm3', reason: 'First aid kit with paracetamol in desc must rank last');
    });

    test('Brand search: "amul" ranks Amul products above items mentioning Amul in description', () {
      final butter = createTestProduct(
        id: 'a1',
        name: 'Amul Butter 500g',
        brand: 'Amul',
        category: 'Dairy & Eggs',
      );
      final milk = createTestProduct(
        id: 'a2',
        name: 'Amul Taaza Homogenised Toned Milk 1L',
        brand: 'Amul',
        category: 'Dairy & Eggs',
      );
      final bread = createTestProduct(
        id: 'b1',
        name: 'Harvest Gold White Bread',
        description: 'Tastes amazing toasted with Amul butter',
        category: 'Bakery',
      );

      final list = [bread, butter, milk];
      SearchRelevanceEngine.sortProducts(products: list, query: 'amul');

      expect(list[0].brand, 'Amul');
      expect(list[1].brand, 'Amul');
      expect(list[2].id, 'b1');
    });

    test('Multi-token queries: "mountain dew" matches full phrase over partial tokens', () {
      final mountainDew = createTestProduct(
        id: 'md',
        name: 'Mountain Dew 750ml',
        category: 'Beverages',
      );
      final regularDew = createTestProduct(
        id: 'rd',
        name: 'dew 250',
        category: 'Beverages',
      );
      final mountainApple = createTestProduct(
        id: 'ma',
        name: 'Mountain Fresh Apple Juice',
        category: 'Beverages',
      );

      final list = [mountainApple, regularDew, mountainDew];
      SearchRelevanceEngine.sortProducts(products: list, query: 'mountain dew');

      expect(list[0].id, 'md', reason: 'Product with all tokens in phrase must rank #1');
    });

    test('Compactness bonus: concise titles matching query rank above bloated titles', () {
      final concise = createTestProduct(
        id: 'c',
        name: 'Dew 250ml',
      );
      final bloated = createTestProduct(
        id: 'b',
        name: 'Dew Refreshing Carbonated Drink with High Caffeine Extra Lime Flavor Party Pack',
      );

      final list = [bloated, concise];
      SearchRelevanceEngine.sortProducts(products: list, query: 'dew');

      expect(list[0].id, 'c', reason: 'Concise title closer to query length must rank higher');
      expect(list[1].id, 'b');
    });
  });
}
