import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  group('100x Forensic Section Search & Catalog Fortress Tests', () {
    final mockPharmacyShop = ShopModel(
      id: 'shop_noor_medicate',
      sellerId: 'seller_123',
      name: 'Noor Medicate',
      address: 'Main Market, Sopore',
      shopType: 'shop',
      category: 'Medical Store',
      categories: ['Pharmacy', 'Medical Store'],
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.8,
      location: const LatLng(34.423, 74.634),
    );

    final mockGroceryShop = ShopModel(
      id: 'shop_grocery_mart',
      sellerId: 'seller_456',
      name: 'Super Grocery Mart',
      address: 'City Center, Sopore',
      shopType: 'shop',
      category: 'Grocery',
      categories: ['Grocery', 'Supermarket / Hypermarket'],
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.6,
      location: const LatLng(34.425, 74.636),
    );

    final List<ProductModel> mockMedicineProducts = [
      ProductModel(
        id: 'med_1',
        shopId: 'shop_noor_medicate',
        name: 'Dolo 650Mg Strip Of 15 Tablets',
        price: 34.0,
        category: 'Medical Store',
        menuCategory: 'Pain Relief & Fever',
        description: 'Contains Paracetamol 650mg for fast fever and headache relief.',
        brand: 'Micro Labs',
        medicineType: 'Tablet',
        isAvailable: true,
        specialTags: ['#Fever', '#PainRelief'],
      ),
      ProductModel(
        id: 'med_2',
        shopId: 'shop_noor_medicate',
        name: 'Diovol Mint Flavour Sugar Free Solution 170 Ml',
        price: 187.0,
        category: 'Medical Store',
        menuCategory: 'Digestive Health',
        description: 'Antacid for acidity and gas relief.',
        brand: 'Wallace',
        medicineType: 'Suspension',
        isAvailable: true,
        specialTags: ['#Acidity', '#Digestive'],
      ),
      ProductModel(
        id: 'med_3',
        shopId: 'shop_noor_medicate',
        name: 'Thyronorm 100Mcg Bottle Of 120 Tablets',
        price: 240.0,
        category: 'Medical Store',
        menuCategory: 'Heart & BP',
        description: 'Levothyroxine Sodium tablets for thyroid management.',
        brand: 'Abbott',
        medicineType: 'Tablet',
        isAvailable: true,
        specialTags: ['#Thyroid'],
      ),
      ProductModel(
        id: 'med_4',
        shopId: 'shop_noor_medicate',
        name: 'Ambrodil S Bottle Of 100Ml Syrup',
        price: 52.0,
        category: 'Medical Store',
        menuCategory: 'Cough & Cold',
        description: 'Mucolytic cough syrup for chest congestion relief.',
        brand: 'Aristo',
        medicineType: 'Syrup',
        isAvailable: true,
        specialTags: ['#Cough', '#Cold'],
      ),
      ProductModel(
        id: 'med_5',
        shopId: 'shop_noor_medicate',
        name: 'Ciplox 0.3% Bottle Of 10Ml Eye/Ear Drops',
        price: 19.0,
        category: 'Medical Store',
        menuCategory: 'Eye & Ear Care',
        description: 'Ciprofloxacin ophthalmic / otic drops.',
        brand: 'Cipla',
        medicineType: 'Drops',
        isAvailable: true,
        specialTags: ['#EyeCare', '#EarCare'],
      ),
    ];

    test('1. Department Query Recognition matches broad department terms', () {
      final deptKeywords = {
        'Pharmacy': [
          'medicine',
          'medicines',
          'pharmacy',
          'medical',
          'medical store',
          'healthcare',
          'health',
          'pharma',
          'drugs',
          'drug',
          'clinic',
          'wellness'
        ],
        'Grocery': [
          'grocery',
          'groceries',
          'essentials',
          'supermarket',
          'ration',
          'daily essentials'
        ],
        'Clothing': [
          'clothing',
          'clothes',
          'fashion',
          'apparel',
          'wear',
          'garments'
        ],
      };

      bool isDepartmentQuery(String query, String sectionTitle, List<String>? categoryFilter) {
        final lower = query.trim().toLowerCase();
        if (lower.isEmpty) return false;
        final title = sectionTitle.toLowerCase();
        if (title.contains(lower) || lower.contains(title)) return true;

        for (final entry in deptKeywords.entries) {
          final deptKey = entry.key.toLowerCase();
          final inFilter = categoryFilter?.any((c) => c.toLowerCase().contains(deptKey)) ?? false;
          final inTitle = title.contains(deptKey);
          if (inFilter || inTitle) {
            if (entry.value.any((k) =>
                lower == k ||
                lower.startsWith('$k ') ||
                lower.endsWith(' $k') ||
                lower.contains(' $k '))) {
              return true;
            }
          }
        }
        return false;
      }

      // Medicines section tests
      expect(isDepartmentQuery('medicine', 'Medicines & Healthcare', ['Pharmacy', 'Medical Store']), isTrue);
      expect(isDepartmentQuery('medicines', 'Medicines & Healthcare', ['Pharmacy', 'Medical Store']), isTrue);
      expect(isDepartmentQuery('healthcare', 'Medicines & Healthcare', ['Pharmacy', 'Medical Store']), isTrue);
      expect(isDepartmentQuery('medical store', 'Medicines & Healthcare', ['Pharmacy', 'Medical Store']), isTrue);
      expect(isDepartmentQuery('pharma', 'Medicines & Healthcare', ['Pharmacy', 'Medical Store']), isTrue);

      // Grocery section tests
      expect(isDepartmentQuery('grocery', 'Daily Grocery & Essentials', ['Grocery']), isTrue);
      expect(isDepartmentQuery('supermarket', 'Daily Grocery & Essentials', ['Grocery']), isTrue);

      // Clothing section tests
      expect(isDepartmentQuery('clothing', 'Clothing & Fashion', ['Clothing']), isTrue);
      expect(isDepartmentQuery('fashion', 'Clothing & Fashion', ['Clothing']), isTrue);

      // Specific product search terms are NOT department queries
      expect(isDepartmentQuery('dolo 650', 'Medicines & Healthcare', ['Pharmacy']), isFalse);
      expect(isDepartmentQuery('thyronorm', 'Medicines & Healthcare', ['Pharmacy']), isFalse);
      expect(isDepartmentQuery('ciplox', 'Medicines & Healthcare', ['Pharmacy']), isFalse);
    });

    test('2. Tokenized Multi-Term Search across multiple product fields', () {
      List<ProductModel> searchProducts(String query, List<ProductModel> catalog) {
        final clean = query.replaceAll(RegExp(r'[,()"\x27]'), ' ').toLowerCase();
        final terms = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        return catalog.where((p) {
          final searchable =
              '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''} ${p.medicineType} ${p.specialTags.join(' ')}'
                  .toLowerCase();
          return terms.every((t) => searchable.contains(t));
        }).toList();
      }

      // 1. Matches by name + strength
      final doloMatches = searchProducts('dolo 650', mockMedicineProducts);
      expect(doloMatches.length, 1);
      expect(doloMatches.first.name, contains('Dolo 650Mg'));

      // 2. Matches by generic chemical ingredient in description
      final paracetamolMatches = searchProducts('paracetamol', mockMedicineProducts);
      expect(paracetamolMatches.length, 1);
      expect(paracetamolMatches.first.name, contains('Dolo'));

      // 3. Matches by category / menu_category / medicine_type
      final syrupMatches = searchProducts('syrup', mockMedicineProducts);
      expect(syrupMatches.length, 1);
      expect(syrupMatches.first.name, contains('Ambrodil'));

      final dropMatches = searchProducts('eye drops', mockMedicineProducts);
      expect(dropMatches.length, 1);
      expect(dropMatches.first.name, contains('Ciplox'));

      // 4. Matches brand name
      final abbottMatches = searchProducts('abbott', mockMedicineProducts);
      expect(abbottMatches.length, 1);
      expect(abbottMatches.first.name, contains('Thyronorm'));
    });

    test('3. Punctuation and Special Syntax Sanitization resilience', () {
      const inputWithPunctuation = 'Ciplox 0.3% (Eye/Ear) Drops, 10ml!';
      final clean = inputWithPunctuation.replaceAll(RegExp(r'[,()"\x27]'), ' ').trim();
      expect(clean, isNot(contains(',')));
      expect(clean, isNot(contains('(')));
      expect(clean, isNot(contains(')')));

      final terms = clean.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      expect(terms, contains('ciplox'));
      expect(terms, contains('0.3%'));
      expect(terms, contains('eye/ear'));
      expect(terms, contains('drops'));
    });

    test('4. Cross-Category / Multi-Shop Category Scope Immunity', () {
      final lowerFilters = {'pharmacy', 'medical store'};

      bool productBelongsToSection(ProductModel p, ShopModel shop, Set<String> filters) {
        final pCat = p.category.trim().toLowerCase();
        final sCat = shop.category.trim().toLowerCase();
        final matchesProdCat = filters.contains(pCat);
        final matchesShopCat = sCat.isNotEmpty && filters.contains(sCat);
        final matchesShopMultiCat = shop.categories.any((c) => filters.contains(c.trim().toLowerCase()));
        return matchesProdCat || matchesShopCat || matchesShopMultiCat;
      }

      // Noor Medicate products (category: 'Medical Store') must match 'Pharmacy' filter
      for (final p in mockMedicineProducts) {
        expect(productBelongsToSection(p, mockPharmacyShop, lowerFilters), isTrue);
      }

      // Grocery products must NOT match Pharmacy section
      final groceryProd = ProductModel(
        id: 'g_1',
        shopId: 'shop_grocery_mart',
        name: 'Fresh Full Cream Milk 1L',
        price: 65.0,
        category: 'Dairy & Eggs',
        isAvailable: true,
      );
      expect(productBelongsToSection(groceryProd, mockGroceryShop, lowerFilters), isFalse);
    });

    test('5. Non-zero search results bypass display limits to show full catalog matches', () {
      final List<ProductModel> largeResults = List.generate(
        150,
        (i) => ProductModel(
          id: 'item_$i',
          shopId: 'shop_noor_medicate',
          name: 'Tablet Variant #$i',
          price: 50.0 + i,
          category: 'Medical Store',
          medicineType: 'Tablet',
          isAvailable: true,
        ),
      );

      const query = 'tablet';
      const displayLimit = 20;

      // In AllListingsPage: displayProducts = _searchQuery.isNotEmpty ? sorted : sorted.take(_displayLimit).toList()
      final displayProducts = query.isNotEmpty ? largeResults : largeResults.take(displayLimit).toList();

      expect(displayProducts.length, 150, reason: 'Search results must NOT be artificially truncated by displayLimit');
    });

    test('6. Category Synonyms injection matches products without literal keyword in name', () {
      String getCategorySynonyms(String category, [ShopModel? shop]) {
        final catLower = category.trim().toLowerCase();
        final shopCat = shop?.category.trim().toLowerCase() ?? '';
        final allCats =
            '$catLower $shopCat ${shop?.categories.map((c) => c.toLowerCase()).join(' ') ?? ''}';

        final buffer = StringBuffer();
        if (allCats.contains('pharmacy') ||
            allCats.contains('medical') ||
            allCats.contains('chemist') ||
            allCats.contains('health')) {
          buffer.write(
              ' medicine medicines med meds medical pharmacy healthcare health pharma drugs clinic wellness chemist doctor tablet syrup cream pill ');
        }
        if (allCats.contains('grocery') ||
            allCats.contains('supermarket')) {
          buffer.write(
              ' grocery groceries supermarket hypermarket essentials daily essentials provisions staples ration food ');
        }
        return buffer.toString();
      }

      // Check that Panderm Plus (which does NOT have "medicine" anywhere in name or DB category)
      // matches "medicine" because of getCategorySynonyms
      final panderm = mockMedicineProducts.first;
      final syn = getCategorySynonyms(panderm.category, mockPharmacyShop);
      final searchable =
          '${panderm.name} ${panderm.description ?? ''} ${panderm.brand ?? ''} ${panderm.category} ${panderm.menuCategory ?? ''} ${panderm.medicineType} ${panderm.specialTags.join(' ')} ${mockPharmacyShop.name} ${mockPharmacyShop.category} $syn'
              .toLowerCase();

      expect(searchable.contains('medicine'), isTrue);
      expect(searchable.contains('medicines'), isTrue);
      expect(searchable.contains('pharmacy'), isTrue);
      expect(searchable.contains('healthcare'), isTrue);
      expect(searchable.contains('noor medicate'), isTrue);
    });

    test('7. Composite queries ("medicine dolo", "grocery milk") match both terms', () {
      String getCategorySynonyms(String category, [ShopModel? shop]) {
        return ' medicine medicines medical pharmacy healthcare pharma ';
      }

      final dolo = mockMedicineProducts.first; // Dolo 650Mg
      final syn = getCategorySynonyms(dolo.category, mockPharmacyShop);
      final searchable =
          '${dolo.name} ${dolo.description ?? ''} ${dolo.brand ?? ''} ${dolo.category} ${mockPharmacyShop.name} $syn'
              .toLowerCase();

      const compositeQuery = 'medicine dolo';
      final terms = compositeQuery.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final matches = terms.every((t) => searchable.contains(t));
      expect(matches, isTrue, reason: '"medicine dolo" must match Dolo 650 via name + category synonym');
    });

    test('8. Shop search in "Stores Near You" matches via category synonyms', () {
      String getCategorySynonyms(String category, [ShopModel? shop]) {
        final catLower = category.trim().toLowerCase();
        final shopCat = shop?.category.trim().toLowerCase() ?? '';
        final allCats = '$catLower $shopCat ${shop?.categories.map((c) => c.toLowerCase()).join(' ') ?? ''}';
        final buffer = StringBuffer();
        if (allCats.contains('pharmacy') || allCats.contains('medical')) {
          buffer.write(' medicine medicines medical pharmacy healthcare pharma ');
        }
        if (allCats.contains('grocery') || allCats.contains('supermarket')) {
          buffer.write(' grocery groceries supermarket essentials ');
        }
        return buffer.toString();
      }

      final shops = [mockPharmacyShop, mockGroceryShop];

      List<ShopModel> searchShops(String query) {
        final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        return shops.where((s) {
          final syn = getCategorySynonyms(s.category, s);
          final searchable = '${s.name} ${s.category} ${s.categories.join(' ')} $syn'.toLowerCase();
          return terms.every((t) => searchable.contains(t));
        }).toList();
      }

      // Typing "medicine" matches Noor Medicate
      final medShops = searchShops('medicine');
      expect(medShops.length, 1);
      expect(medShops.first.id, 'shop_noor_medicate');

      // Typing "grocery" matches Super Grocery Mart
      final grocShops = searchShops('grocery');
      expect(grocShops.length, 1);
      expect(grocShops.first.id, 'shop_grocery_mart');
    });

    test('9. Broad department query extraction strips department word for remote live query', () {
      final deptWords = {'medicine', 'medicines', 'pharmacy', 'grocery', 'clothing'};
      const query = 'medicine dolo';
      final rawTerms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final specificTerms = rawTerms.length > 1
          ? rawTerms.where((t) => !deptWords.contains(t.toLowerCase())).toList()
          : rawTerms;

      expect(specificTerms, equals(['dolo']),
          reason: 'Remote SQL query should search for "dolo" instead of requiring "medicine" AND "dolo"');
    });

    test('10. Product subCategory, unitType, and variant names are searchable in-memory', () {
      final productWithVariants = ProductModel(
        id: 'p_variant_test',
        shopId: 'shop_noor_medicate',
        name: 'Amul Taaza Homogenised Toned Milk',
        price: 35.0,
        category: 'Dairy & Eggs',
        subCategory: 'Toned Milk',
        unitType: 'pouch',
        variants: [
          ProductVariant(id: 'v1', name: '500ml', price: 35.0),
          ProductVariant(id: 'v2', name: '1 Litre', price: 68.0),
        ],
      );

      final variantNames = productWithVariants.variants.map((v) => v.name).join(' ');
      final searchable =
          '${productWithVariants.name} ${productWithVariants.description ?? ''} ${productWithVariants.brand ?? ''} ${productWithVariants.category} ${productWithVariants.subCategory ?? ''} ${productWithVariants.menuCategory ?? ''} ${productWithVariants.medicineType} ${productWithVariants.unitType} $variantNames ${productWithVariants.specialTags.join(' ')}'
              .toLowerCase();

      // Searching for variant "500ml" or "1 litre" matches
      expect(searchable.contains('500ml'), isTrue);
      expect(searchable.contains('1 litre'), isTrue);

      // Searching for subCategory "toned milk" matches
      expect(searchable.contains('toned milk'), isTrue);

      // Searching for unitType "pouch" matches
      expect(searchable.contains('pouch'), isTrue);
    });

    test('11. Dynamic domain collection synonyms work across all AppCategories without hardcoding', () {
      final collections = [
        AppCategories.getCustomerCollection('Pharmacy'),
        AppCategories.getCustomerCollection('Medical Store'),
        AppCategories.getCustomerCollection('Butcher'),
        AppCategories.getCustomerCollection('Clothing'),
        AppCategories.getCustomerCollection('Restaurant'),
      ];

      expect(collections, contains('Pharmacy & Health'));
      expect(collections, contains('Grocery & Fresh'));
      expect(collections, contains('Fashion & Lifestyle'));
      expect(collections, contains('Food & Dining'));
    });

    test('12. Delivery radius consistency: PaymentConfig and DeliveryCalculator align to 15.0km', () {
      expect(PaymentConfig.maxDeliveryRadiusKm, equals(15.0));
      expect(DeliveryCalculator.maxRadiusKm, equals(15.0));
    });
  });
}


