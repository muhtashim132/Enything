import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/utils/demographic_utils.dart';
import 'package:enythingmobilenew/utils/search_relevance_engine.dart';

void main() {
  group('100x Semantic Demographic Search Fortress Tests', () {
    ProductModel createProduct({
      required String id,
      required String name,
      String? brand,
      String? description,
      String category = 'Cosmetics & Beauty',
      List<String> specialTags = const [],
      double rating = 4.5,
      double price = 499.0,
      bool isAvailable = true,
    }) {
      return ProductModel(
        id: id,
        shopId: 'shop_maxx',
        name: name,
        category: category,
        price: price,
        isAvailable: isAvailable,
        brand: brand,
        description: description,
        specialTags: specialTags,
        rating: rating,
        images: const ['https://example.com/img.jpg'],
        unitType: 'piece',
      );
    }

    test(
        '1. Demographic Intent Detection: Identifies pure vs compound queries & preserves non-demographic words',
        () {
      final q1 = DemographicUtils.detectDemographicIntent('woman');
      expect(q1.hasDemographicIntent, isTrue);
      expect(q1.canonicalDemographic, 'Women');
      expect(q1.isPureDemographic, isTrue);
      expect(q1.strippedProductQuery, '');

      final q2 = DemographicUtils.detectDemographicIntent('women perfume');
      expect(q2.hasDemographicIntent, isTrue);
      expect(q2.canonicalDemographic, 'Women');
      expect(q2.isPureDemographic, isFalse);
      expect(q2.strippedProductQuery, 'perfume');

      final q3 = DemographicUtils.detectDemographicIntent('shoes for men');
      expect(q3.hasDemographicIntent, isTrue);
      expect(q3.canonicalDemographic, 'Men');
      expect(q3.isPureDemographic, isFalse);
      expect(q3.strippedProductQuery, 'shoes');

      final q4 = DemographicUtils.detectDemographicIntent('dresses for girls');
      expect(q4.hasDemographicIntent, isTrue);
      expect(q4.canonicalDemographic, 'Girls');
      expect(q4.isPureDemographic, isFalse);
      expect(q4.strippedProductQuery, 'dresses');

      // Ambiguous food / brand safeguards
      final q5 = DemographicUtils.detectDemographicIntent('ladyfinger');
      expect(q5.hasDemographicIntent, isFalse);

      final q6 = DemographicUtils.detectDemographicIntent('mother dairy milk');
      expect(q6.hasDemographicIntent, isFalse);

      final q7 = DemographicUtils.detectDemographicIntent('shampoo');
      expect(q7.hasDemographicIntent, isFalse);
    });

    test(
        '2. Semantic Inherent Classification for Untagged Products (Human-Brain Accuracy)',
        () {
      final lipstick = createProduct(
        id: 'p_lip',
        name: 'Maybelline Superstay Matte Ink Liquid Lipstick',
        brand: 'Maybelline',
        category: 'Cosmetics & Beauty',
        specialTags: [], // Untagged!
      );
      expect(DemographicUtils.classifyProduct(lipstick),
          ProductDemographicType.women);

      final kurti = createProduct(
        id: 'p_kurti',
        name: 'Embroidered Anarkali Kurti with Dupatta',
        category: 'Clothing',
        specialTags: [],
      );
      expect(DemographicUtils.classifyProduct(kurti),
          ProductDemographicType.women);

      final pads = createProduct(
        id: 'p_pads',
        name: 'Whisper Ultra Clean Sanitary Pads XL',
        brand: 'Whisper',
        category: 'Cosmetics & Beauty',
        specialTags: [],
      );
      expect(
          DemographicUtils.classifyProduct(pads), ProductDemographicType.women);

      final beardOil = createProduct(
        id: 'p_beard',
        name: 'Beardo Godfather Beard Growth Oil',
        brand: 'Beardo',
        category: 'Salon & Beauty',
        specialTags: [],
      );
      expect(DemographicUtils.classifyProduct(beardOil),
          ProductDemographicType.men);

      final sunscreen = createProduct(
        id: 'p_sun',
        name: 'Neutrogena Ultra Sheer Dry-Touch Sunscreen SPF 50+',
        brand: 'Neutrogena',
        category: 'Cosmetics & Beauty',
        specialTags: [],
      );
      expect(DemographicUtils.classifyProduct(sunscreen),
          ProductDemographicType.unisex);

      final backpack = createProduct(
        id: 'p_bag',
        name: 'Wildcraft Casual Daypack Backpack 25L',
        brand: 'Wildcraft',
        category: 'Stationery',
        specialTags: [],
      );
      expect(DemographicUtils.classifyProduct(backpack),
          ProductDemographicType.unisex);

      final salt = createProduct(
        id: 'p_salt',
        name: 'Tata Salt Vacuum Evaporated Iodised Salt 1kg',
        category: 'Grocerylm',
        specialTags: [],
      );
      expect(
          DemographicUtils.classifyProduct(salt), ProductDemographicType.food);
    });

    test(
        '3. Pure Query "woman" ranks Women items Tier 1, Unisex items Tier 2, and strictly excludes Men and Food items',
        () {
      final lipstick = createProduct(
        id: 'p_lipstick',
        name: 'Lakme Absolute Matte Melt Liquid Lip Color',
        brand: 'Lakme',
        category: 'Cosmetics & Beauty',
      );

      final saree = createProduct(
        id: 'p_saree',
        name: 'Banarasi Silk Saree with Blouse Piece',
        category: 'Clothing',
      );

      final moisturizer = createProduct(
        id: 'p_moist',
        name: 'Nivea Soft Light Moisturizer Cream 100ml',
        brand: 'Nivea',
        category: 'Cosmetics & Beauty',
      );

      final sneakers = createProduct(
        id: 'p_snk',
        name: 'Puma Unisex Smashic Casual Sneakers',
        brand: 'Puma',
        category: 'Footwear',
      );

      final beardOil = createProduct(
        id: 'p_beard',
        name: 'Ustraa Beard Growth Oil 35ml',
        brand: 'Ustraa',
        category: 'Salon & Beauty',
      );

      final boxers = createProduct(
        id: 'p_boxer',
        name: 'Jockey Men Cotton Boxer Shorts',
        brand: 'Jockey',
        category: 'Clothing',
      );

      final chips = createProduct(
        id: 'p_chips',
        name: 'Lay\'s India\'s Magic Masala Potato Chips 50g',
        category: 'Grocerylm',
      );

      final scoreLipstick =
          SearchRelevanceEngine.computeScore(product: lipstick, query: 'woman');
      final scoreSaree =
          SearchRelevanceEngine.computeScore(product: saree, query: 'woman');
      final scoreMoisturizer = SearchRelevanceEngine.computeScore(
          product: moisturizer, query: 'woman');
      final scoreSneakers =
          SearchRelevanceEngine.computeScore(product: sneakers, query: 'woman');
      final scoreBeardOil =
          SearchRelevanceEngine.computeScore(product: beardOil, query: 'woman');
      final scoreBoxers =
          SearchRelevanceEngine.computeScore(product: boxers, query: 'woman');
      final scoreChips =
          SearchRelevanceEngine.computeScore(product: chips, query: 'woman');

      // Tier 1 Women items: score >= 90,000
      expect(scoreLipstick, greaterThanOrEqualTo(90000.0));
      expect(scoreSaree, greaterThanOrEqualTo(90000.0));

      // Tier 2 Unisex items: score between 40,000 and 60,000
      expect(scoreMoisturizer, greaterThanOrEqualTo(45000.0));
      expect(scoreMoisturizer, lessThan(90000.0));
      expect(scoreSneakers, greaterThanOrEqualTo(45000.0));
      expect(scoreSneakers, lessThan(90000.0));

      // Strictly disqualified: score < 0 (-1,000,000)
      expect(scoreBeardOil, lessThan(0.0));
      expect(scoreBoxers, lessThan(0.0));
      expect(scoreChips, lessThan(0.0));

      // Test in sortProducts: Men and Food items are completely removed
      final products = [
        chips,
        beardOil,
        sneakers,
        boxers,
        saree,
        moisturizer,
        lipstick
      ];
      SearchRelevanceEngine.sortProducts(products: products, query: 'woman');

      final resultIds = products.map((p) => p.id).toList();
      // First 2 items must be the Women items (saree & lipstick)
      expect(resultIds.sublist(0, 2), containsAll(['p_saree', 'p_lipstick']));
      // Next 2 items must be the Unisex items (moisturizer & sneakers)
      expect(resultIds.sublist(2, 4), containsAll(['p_moist', 'p_snk']));
      // Men and Food items are completely purged
      expect(products.any((p) => p.id == 'p_beard'), isFalse);
      expect(products.any((p) => p.id == 'p_boxer'), isFalse);
      expect(products.any((p) => p.id == 'p_chips'), isFalse);
    });

    test(
        '4. Compound Query "women perfume": Prioritizes Women perfume, includes Unisex perfume, excludes Men cologne',
        () {
      final womenPerfume = createProduct(
        id: 'p_w_perfume',
        name: 'Plum BodyLovin Vanilla Vibes Eau De Parfum for Women',
        brand: 'Plum',
        category: 'Cosmetics & Beauty',
      );

      final unisexPerfume = createProduct(
        id: 'p_u_perfume',
        name: 'Fastrack Unisex Perfume Pulse EDP 100ml',
        brand: 'Fastrack',
        category: 'Cosmetics & Beauty',
      );

      final menCologne = createProduct(
        id: 'p_m_cologne',
        name: 'Beardo Godfather Perfume EDP for Men',
        brand: 'Beardo',
        category: 'Cosmetics & Beauty',
      );

      final scoreWomen = SearchRelevanceEngine.computeScore(
          product: womenPerfume, query: 'women perfume');
      final scoreUnisex = SearchRelevanceEngine.computeScore(
          product: unisexPerfume, query: 'women perfume');
      final scoreMen = SearchRelevanceEngine.computeScore(
          product: menCologne, query: 'women perfume');

      expect(scoreWomen, greaterThan(scoreUnisex));
      expect(scoreUnisex, greaterThan(0.0));
      expect(scoreMen, lessThan(0.0)); // Strictly excluded
    });

    test(
        '5. Pure Query "men": Ranks Men items top, Unisex next, excludes Women items and Food',
        () {
      final trimmer = createProduct(
        id: 'p_trimmer',
        name: 'Bombay Shaving Company Beard Trimmer for Men',
        brand: 'Bombay Shaving Company',
        category: 'Salon & Beauty',
      );

      final shampoo = createProduct(
        id: 'p_shampoo',
        name: 'Head & Shoulders Anti-Dandruff Shampoo Cool Menthol',
        brand: 'Head & Shoulders',
        category: 'Cosmetics & Beauty',
      );

      final lipstick = createProduct(
        id: 'p_lip',
        name: 'Maybelline Superstay Matte Ink Lipstick',
        brand: 'Maybelline',
        category: 'Cosmetics & Beauty',
      );

      final biscuits = createProduct(
        id: 'p_bisc',
        name: 'Parle-G Gold Biscuits 1kg',
        category: 'Grocerylm',
      );

      final scoreTrimmer =
          SearchRelevanceEngine.computeScore(product: trimmer, query: 'men');
      final scoreShampoo =
          SearchRelevanceEngine.computeScore(product: shampoo, query: 'men');
      final scoreLipstick =
          SearchRelevanceEngine.computeScore(product: lipstick, query: 'men');
      final scoreBiscuits =
          SearchRelevanceEngine.computeScore(product: biscuits, query: 'men');

      expect(scoreTrimmer, greaterThanOrEqualTo(90000.0));
      expect(scoreShampoo, greaterThanOrEqualTo(45000.0));
      expect(scoreShampoo, lessThan(90000.0));
      expect(scoreLipstick, lessThan(0.0)); // Incompatible opposite gender
      expect(scoreBiscuits, lessThan(0.0)); // Food excluded
    });
  });
}
