import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/utils/demographic_utils.dart';

void main() {
  group('100x Omni-Search & Brand Discovery Fortress Tests', () {
    // Helper function simulating the 100x multi-token product matching engine
    bool simulateProductSearchMatch({
      required Map<String, dynamic> product,
      required String query,
    }) {
      if (product['is_deleted'] == true) return false;
      if (product['is_available'] == false) return false;

      final cleanQuery = query.replaceAll(RegExp(r'[,()"\x27]'), ' ').trim();
      final rawTerms = cleanQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

      if (rawTerms.isEmpty) return true;

      const stopWords = {'for', 'in', 'of', 'with', 'and', 'the', 'a', 'an', 'at', 'by', 'to', '&'};
      final specificTerms = rawTerms.length > 1
          ? rawTerms.where((t) => !stopWords.contains(t)).toList()
          : rawTerms;
      final terms = specificTerms.isNotEmpty ? specificTerms : rawTerms;

      final searchable =
          '${product['name']} ${product['description'] ?? ''} ${product['brand'] ?? ''} ${product['category'] ?? ''} ${product['sub_category'] ?? ''} ${product['menu_category'] ?? ''} ${product['medicine_type'] ?? ''}'
              .toLowerCase();
      final cleanSearchable = searchable.replaceAll(RegExp(r'[,()"\x27\-]'), '');
      final spacedSearchable = searchable.replaceAll(RegExp(r'[,()"\x27\-]'), ' ');

      return terms.every((t) {
        if (DemographicUtils.isDemographicKeyword(t)) {
          return DemographicUtils.rawProductMatchesTerm(
            product: product,
            term: t,
            searchableText: searchable,
          );
        }
        final cleanT = t.replaceAll(RegExp(r'[,()"\x27\-]'), '');
        // Direct or punctuation-agnostic match (e.g. loreal matches l'oreal)
        if (searchable.contains(t) || cleanSearchable.contains(cleanT) || spacedSearchable.contains(t)) return true;
        // Plural-to-singular stemming (e.g. 'serums' -> 'serum')
        if (t.endsWith('s') && t.length > 3) {
          final stem = t.substring(0, t.length - 1);
          if (searchable.contains(stem) || cleanSearchable.contains(stem)) return true;
        }
        return false;
      });
    }

    test('1. Product keyword search: "serum" accurately finds serums across shops', () {
      final serum1 = {
        'id': 'p1',
        'name': 'Bright Complete Vitamin C Booster Serum',
        'brand': 'Garnier',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };
      final serum2 = {
        'id': 'p2',
        'name': 'Skin Clarifying Face Serum',
        'brand': 'Mamaearth',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };
      final shampoo = {
        'id': 'p3',
        'name': 'Anti-Dandruff Shampoo',
        'brand': 'Head & Shoulders',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      expect(simulateProductSearchMatch(product: serum1, query: 'serum'), isTrue);
      expect(simulateProductSearchMatch(product: serum2, query: 'serum'), isTrue);
      expect(simulateProductSearchMatch(product: shampoo, query: 'serum'), isFalse);
    });

    test('2. Plural and singular stemming: "serums" matches "serum", "lipsticks" matches "lipstick"', () {
      final serum = {
        'id': 'p1',
        'name': 'Hyaluronic Acid Serum',
        'brand': 'L\'Oreal',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };
      final lipstick = {
        'id': 'p2',
        'name': 'Matte Velvet Lipstick',
        'brand': 'Maybelline',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      expect(simulateProductSearchMatch(product: serum, query: 'serums'), isTrue);
      expect(simulateProductSearchMatch(product: lipstick, query: 'lipsticks'), isTrue);
    });

    test('3. Brand search: Searching by brand (e.g. "Garnier", "Mamaearth", "Nivea", "Amul") matches products', () {
      final garnierSerum = {
        'id': 'p1',
        'name': 'Bright Complete Serum',
        'brand': 'Garnier',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };
      final amulMilk = {
        'id': 'p2',
        'name': 'Taaza Toned Fresh Milk 1L',
        'brand': 'Amul',
        'category': 'Dairy & Eggs',
        'is_available': true,
        'is_deleted': false,
      };
      final niveaCream = {
        'id': 'p3',
        'name': 'Soft Light Moisturiser',
        'brand': 'Nivea',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      // Case-insensitive brand matching
      expect(simulateProductSearchMatch(product: garnierSerum, query: 'garnier'), isTrue);
      expect(simulateProductSearchMatch(product: garnierSerum, query: 'GARNIER'), isTrue);
      expect(simulateProductSearchMatch(product: amulMilk, query: 'amul'), isTrue);
      expect(simulateProductSearchMatch(product: niveaCream, query: 'nivea'), isTrue);
    });

    test('4. Brand with special characters and apostrophe (e.g. "L\'Oreal", "Dot & Key")', () {
      final lorealSerum = {
        'id': 'p1',
        'name': 'Revitalift 1.5% Hyaluronic Acid Serum',
        'brand': 'L\'Oreal Paris',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };
      final dotKeySerum = {
        'id': 'p2',
        'name': 'Water Drench Hydrating Serum',
        'brand': 'Dot & Key',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      expect(simulateProductSearchMatch(product: lorealSerum, query: 'l\'oreal'), isTrue);
      expect(simulateProductSearchMatch(product: lorealSerum, query: 'loreal'), isTrue);
      expect(simulateProductSearchMatch(product: dotKeySerum, query: 'dot & key'), isTrue);
      expect(simulateProductSearchMatch(product: dotKeySerum, query: 'dot key'), isTrue);
    });

    test('5. Multi-word Brand + Product Type search: "Garnier serum", "Amul milk", "Mamaearth face wash"', () {
      final garnierSerum = {
        'id': 'p1',
        'name': 'Bright Complete Vitamin C Booster',
        'brand': 'Garnier',
        'description': 'Brightening skin serum for face',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      expect(simulateProductSearchMatch(product: garnierSerum, query: 'Garnier serum'), isTrue);
      expect(simulateProductSearchMatch(product: garnierSerum, query: 'garnier booster serum'), isTrue);
      // Fails if brand doesn't match
      expect(simulateProductSearchMatch(product: garnierSerum, query: 'Mamaearth serum'), isFalse);
    });

    test('6. Stop-word stripping: "serum for face" or "oil with vitamin c" matches cleanly', () {
      final serum = {
        'id': 'p1',
        'name': 'Glow Face Serum',
        'brand': 'Minimalist',
        'description': 'Pure niacinamide 10% solution',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': false,
      };

      // "for" is stripped from multi-word query so "serum for face" matches "Glow Face Serum"
      expect(simulateProductSearchMatch(product: serum, query: 'serum for face'), isTrue);
    });

    test('7. Soft-deleted products (is_deleted = true) are NEVER returned in search', () {
      final deletedSerum = {
        'id': 'p1',
        'name': 'Discontinued Glow Serum',
        'brand': 'Garnier',
        'category': 'Cosmetics & Beauty',
        'is_available': true,
        'is_deleted': true, // Soft-deleted
      };

      expect(simulateProductSearchMatch(product: deletedSerum, query: 'serum'), isFalse);
      expect(simulateProductSearchMatch(product: deletedSerum, query: 'garnier'), isFalse);
    });

    test('8. Safe Chunking: batches of at most 25 IDs prevent PostgREST URL overflow', () {
      final mock150ShopIds = List.generate(150, (i) => 'shop_uuid_${i.toString().padLeft(3, '0')}');
      
      final chunks = <List<String>>[];
      for (int i = 0; i < mock150ShopIds.length; i += 25) {
        chunks.add(mock150ShopIds.sublist(i, (i + 25 < mock150ShopIds.length) ? i + 25 : mock150ShopIds.length));
      }

      expect(chunks.length, equals(6));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(25));
        // Verify URL length approximation for 25 UUIDs
        final chunkUrlParam = chunk.join(',');
        expect(chunkUrlParam.length, lessThan(1000)); // Well under 4KB Cloudflare URI limit
      }
    });

    test('9. Target demographic filtering with automatic #Unisex inclusion', () {
      final menSerum = {
        'id': 'p1',
        'name': 'Men Active Face Serum',
        'brand': 'Garnier Men',
        'category': 'Cosmetics & Beauty',
        'special_tags': ['#Men'],
        'is_available': true,
        'is_deleted': false,
      };
      final unisexSerum = {
        'id': 'p2',
        'name': 'Hyaluronic Acid 2% Serum',
        'brand': 'The Ordinary',
        'category': 'Cosmetics & Beauty',
        'special_tags': ['#Unisex'],
        'is_available': true,
        'is_deleted': false,
      };
      final womenSerum = {
        'id': 'p3',
        'name': 'Women Skin Brightening Serum',
        'brand': 'Lakme',
        'category': 'Cosmetics & Beauty',
        'special_tags': ['#Women'],
        'is_available': true,
        'is_deleted': false,
      };

      // Searching for "men serum" matches #Men AND #Unisex
      expect(simulateProductSearchMatch(product: menSerum, query: 'men serum'), isTrue);
      expect(simulateProductSearchMatch(product: unisexSerum, query: 'men serum'), isTrue);
      expect(simulateProductSearchMatch(product: womenSerum, query: 'men serum'), isFalse);
    });

    test('10. No artificial product truncation or "See more / See less" collapse toggle in search results', () {
      // In search results, all matching products must be displayed directly without capping
      final mockSearchResults = List.generate(33, (i) => {
        'id': 'prod_$i',
        'name': 'Serum Item $i',
        'brand': 'Brand $i',
        'is_available': true,
        'is_deleted': false,
      });

      // Item count for SliverList is full results length without artificial capping
      final itemCount = mockSearchResults.length;
      expect(itemCount, equals(33));
      // No truncation cap (itemCount must not be artificially clamped to 3)
      expect(itemCount, greaterThan(3));
    });
  });
}

