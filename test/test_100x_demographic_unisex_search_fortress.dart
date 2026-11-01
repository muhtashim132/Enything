import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/utils/demographic_utils.dart';
import 'package:enythingmobilenew/models/product_model.dart';

void main() {
  group('100x Demographic & Unisex Omni-Search Fortress Tests', () {
    test('1. Tag Expansion: Gendered/Age demographics MUST include #Unisex', () {
      expect(DemographicUtils.getAllowedTags('Men'), containsAll(['#Men', '#Unisex']));
      expect(DemographicUtils.getAllowedTags('Women'), containsAll(['#Women', '#Unisex']));
      expect(DemographicUtils.getAllowedTags('Boys'), containsAll(['#Boys', '#Kids', '#Unisex']));
      expect(DemographicUtils.getAllowedTags('Girls'), containsAll(['#Girls', '#Kids', '#Unisex']));
      expect(DemographicUtils.getAllowedTags('Kids'), containsAll(['#Kids', '#Boys', '#Girls', '#Unisex']));
      expect(DemographicUtils.getAllowedTags('Unisex'), equals({'#Unisex'}));
      expect(DemographicUtils.getAllowedTags('All'), isNull);
    });

    test('2. Keyword Detection: Identifies demographic tokens and plural/possessive forms', () {
      expect(DemographicUtils.isDemographicKeyword('men'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('mens'), isTrue);
      expect(DemographicUtils.isDemographicKeyword("men's"), isTrue);
      expect(DemographicUtils.isDemographicKeyword('male'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('gents'), isTrue);

      expect(DemographicUtils.isDemographicKeyword('women'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('womens'), isTrue);
      expect(DemographicUtils.isDemographicKeyword("women's"), isTrue);
      expect(DemographicUtils.isDemographicKeyword('female'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('ladies'), isTrue);

      expect(DemographicUtils.isDemographicKeyword('boys'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('boy'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('girls'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('girl'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('kids'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('children'), isTrue);
      expect(DemographicUtils.isDemographicKeyword('unisex'), isTrue);

      // Non-demographic words must NOT be flagged
      expect(DemographicUtils.isDemographicKeyword('shoes'), isFalse);
      expect(DemographicUtils.isDemographicKeyword('cinnamon'), isFalse);
      expect(DemographicUtils.isDemographicKeyword('mentos'), isFalse);
      expect(DemographicUtils.isDemographicKeyword('shirt'), isFalse);
    });

    test('3. Unisex Inclusion in Product Search: #Unisex products match gendered search terms', () {
      final unisexHoodie = ProductModel(
        id: 'p1',
        shopId: 's1',
        name: 'Cotton Fleece Hoodie',
        description: 'Warm everyday oversized hoodie',
        price: 999.0,
        category: 'Clothing',
        isAvailable: true,
        specialTags: ['#Unisex'],
      );

      final menSearchable = '${unisexHoodie.name} ${unisexHoodie.description} ${unisexHoodie.specialTags.join(' ')}'.toLowerCase();

      // Searching 'men' must match unisex hoodie
      expect(
        DemographicUtils.productMatchesTerm(
          product: unisexHoodie,
          term: 'men',
          searchableText: menSearchable,
        ),
        isTrue,
      );

      // Searching 'women' must match unisex hoodie
      expect(
        DemographicUtils.productMatchesTerm(
          product: unisexHoodie,
          term: 'women',
          searchableText: menSearchable,
        ),
        isTrue,
      );

      // Searching 'kids' must match unisex hoodie
      expect(
        DemographicUtils.productMatchesTerm(
          product: unisexHoodie,
          term: 'kids',
          searchableText: menSearchable,
        ),
        isTrue,
      );

      // Searching 'unisex' must match unisex hoodie
      expect(
        DemographicUtils.productMatchesTerm(
          product: unisexHoodie,
          term: 'unisex',
          searchableText: menSearchable,
        ),
        isTrue,
      );
    });

    test('4. Cross-Gender Isolation: Explicit #Women product does NOT match "men"', () {
      final womenKurti = ProductModel(
        id: 'p2',
        shopId: 's1',
        name: 'Silk Embroidered Kurti',
        description: 'Traditional party wear',
        price: 1499.0,
        category: 'Clothing',
        isAvailable: true,
        specialTags: ['#Women'],
      );

      final kurtiSearchable = '${womenKurti.name} ${womenKurti.description} ${womenKurti.specialTags.join(' ')}'.toLowerCase();

      // Searching 'men' must NOT match women kurti
      expect(
        DemographicUtils.productMatchesTerm(
          product: womenKurti,
          term: 'men',
          searchableText: kurtiSearchable,
        ),
        isFalse,
      );

      // Searching 'women' MUST match women kurti
      expect(
        DemographicUtils.productMatchesTerm(
          product: womenKurti,
          term: 'women',
          searchableText: kurtiSearchable,
        ),
        isTrue,
      );
    });

    test('5. Compound Queries: "men shoes" matches unisex running shoes', () {
      final unisexShoes = ProductModel(
        id: 'p3',
        shopId: 's1',
        name: 'Air Flow Running Shoes',
        description: 'Breathable sports footwear',
        price: 2499.0,
        category: 'Footwear',
        isAvailable: true,
        specialTags: ['#Unisex'],
      );

      final shoesSearchable = '${unisexShoes.name} ${unisexShoes.description} ${unisexShoes.specialTags.join(' ')}'.toLowerCase();

      // Query: "men shoes" -> terms: ['men', 'shoes']
      final terms = ['men', 'shoes'];
      final matchesAll = terms.every((t) => DemographicUtils.productMatchesTerm(
        product: unisexShoes,
        term: t,
        searchableText: shoesSearchable,
      ));

      expect(matchesAll, isTrue, reason: 'Unisex running shoes must match "men shoes" query');
    });

    test('6. Filter Selection: matchesDemographic properly reflects all products including unisex', () {
      final unisexWatch = ProductModel(
        id: 'p4',
        shopId: 's1',
        name: 'Minimalist Steel Watch',
        description: 'Classic analog watch',
        price: 3500.0,
        category: 'Jewellery',
        isAvailable: true,
        specialTags: ['#Unisex'],
      );

      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Men'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Women'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Boys'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Girls'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Kids'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'Unisex'), isTrue);
      expect(DemographicUtils.matchesDemographic(unisexWatch, 'All'), isTrue);
    });
  });
}
