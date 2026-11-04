import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100x Explore Categories Contextual Section Titles & See-All Fortress', () {
    const Map<String, List<String>> tabCategories = {
      'Food': [
        'Restaurant',
        'Fast Food',
        'Bakery',
        'Sweets & Mithai',
        'Tea & Coffee',
        'Ice Cream',
        'Paan Shop',
        'Beverages'
      ],
      'Grocery': [
        'Grocery',
        'Grocerylm',
        'Supermarket / Hypermarket',
        'Fruits & Vegs',
        'Dairy & Eggs',
        'Butcher',
        'Fish & Seafood',
        'Organic'
      ],
      'Pharmacy': ['Pharmacy', 'Medical Store'],
      'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
      'Electronics': ['Electronics', 'Mobile & Repair'],
      'Supermarket / Hypermarket': [
        'Supermarket / Hypermarket',
        'Grocery',
        'Grocerylm',
        'Fruits & Vegs',
        'Dairy & Eggs',
        'Butcher',
        'Fish & Seafood',
        'Organic'
      ],
      'More': [
        'Hardware Store',
        'Stationery',
        'Toys & Games',
        'Sports',
        'Pet Supplies',
        'Cosmetics & Beauty',
        'Salon & Beauty',
        'Flowers',
        'Home Decor',
        'Furniture',
        'Auto Parts',
        'Other'
      ],
    };

    ({String sectionTitle, String buttonLabel, List<String>? categoryFilter})
        computeProductMeta({
      required int selectedTabIndex,
      required List<String> categoryNames,
      required String selectedFeedDemographic,
      required Set<String> selectedFilterCategories,
    }) {
      if (selectedTabIndex >= 0 && selectedTabIndex < categoryNames.length) {
        final tabName = categoryNames[selectedTabIndex];
        final rawSubcategories = tabCategories[tabName] ?? [tabName];
        final finalCategories = rawSubcategories.toList();

        if (tabName == 'Supermarket / Hypermarket') {
          return (
            sectionTitle: 'Popular in Supermarket & Hypermarket',
            buttonLabel: 'See all Supermarket & Hypermarket products',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Food') {
          return (
            sectionTitle: 'Popular in Food & Restaurants',
            buttonLabel: 'See all Food & Restaurant items',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Pharmacy') {
          return (
            sectionTitle: 'Popular in Pharmacy & Healthcare',
            buttonLabel: 'See all Pharmacy & Healthcare products',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Clothing') {
          final demoTitle = selectedFeedDemographic == 'Men/Boys'
              ? 'Popular for Men & Boys'
              : (selectedFeedDemographic == 'Women/Girls'
                  ? 'Popular for Women & Girls'
                  : (selectedFeedDemographic == 'Kids'
                      ? 'Popular for Kids'
                      : (selectedFeedDemographic == 'Unisex'
                          ? 'Popular Unisex Fashion'
                          : 'Popular in Clothing & Fashion')));
          final demoBtn = selectedFeedDemographic != 'All'
              ? 'See all $selectedFeedDemographic fashion'
              : 'See all Clothing & Fashion products';
          return (
            sectionTitle: demoTitle,
            buttonLabel: demoBtn,
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Electronics') {
          return (
            sectionTitle: 'Popular in Electronics & Gadgets',
            buttonLabel: 'See all Electronics & Gadgets',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'More') {
          return (
            sectionTitle: 'Popular in More Categories',
            buttonLabel: 'See all products in this category',
            categoryFilter: finalCategories,
          );
        } else {
          return (
            sectionTitle: 'Popular in $tabName',
            buttonLabel: 'See all $tabName products',
            categoryFilter: finalCategories,
          );
        }
      }

      if (selectedFilterCategories.isNotEmpty) {
        final firstFilter = selectedFilterCategories.first;
        final effectiveCategories = <String>[];
        for (final cat in selectedFilterCategories) {
          final subs = tabCategories[cat] ?? [cat];
          effectiveCategories.addAll(subs);
        }
        return (
          sectionTitle: selectedFilterCategories.length == 1
              ? 'Popular in $firstFilter'
              : 'Filtered Popular Products',
          buttonLabel: 'See all filtered products',
          categoryFilter: effectiveCategories,
        );
      }

      final defaultTitle = selectedFeedDemographic == 'Men/Boys'
          ? 'Popular for Men & Boys'
          : (selectedFeedDemographic == 'Women/Girls'
              ? 'Popular for Women & Girls'
              : (selectedFeedDemographic == 'Kids'
                  ? 'Popular for Kids'
                  : (selectedFeedDemographic == 'Unisex'
                      ? 'Popular Unisex Fashion'
                      : 'Popular in your area')));
      final defaultBtn = selectedFeedDemographic != 'All'
          ? 'See all $selectedFeedDemographic products'
          : 'See all popular products';

      return (
        sectionTitle: defaultTitle,
        buttonLabel: defaultBtn,
        categoryFilter: null,
      );
    }

    ({String sectionTitle, String buttonLabel, List<String>? categoryFilter})
        computeStoreMeta({
      required int selectedTabIndex,
      required List<String> categoryNames,
      required String selectedFeedDemographic,
    }) {
      if (selectedTabIndex >= 0 && selectedTabIndex < categoryNames.length) {
        final tabName = categoryNames[selectedTabIndex];
        final rawSubcategories = tabCategories[tabName] ?? [tabName];
        final finalCategories = rawSubcategories.toList();

        if (tabName == 'Food') {
          return (
            sectionTitle: 'Restaurants near you',
            buttonLabel: 'See all restaurants',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Supermarket / Hypermarket') {
          return (
            sectionTitle: 'Supermarkets & Hypermarkets near you',
            buttonLabel: 'See all supermarkets & hypermarkets',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Pharmacy') {
          return (
            sectionTitle: 'Pharmacies & Medical Stores near you',
            buttonLabel: 'See all pharmacies & medical stores',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Clothing') {
          return (
            sectionTitle: selectedFeedDemographic == 'Men/Boys'
                ? 'Men & Boys Stores'
                : (selectedFeedDemographic == 'Women/Girls'
                    ? 'Women & Girls Stores'
                    : 'Clothing & Fashion Stores near you'),
            buttonLabel: 'See all clothing stores',
            categoryFilter: finalCategories,
          );
        } else if (tabName == 'Electronics') {
          return (
            sectionTitle: 'Electronics Stores near you',
            buttonLabel: 'See all electronics stores',
            categoryFilter: finalCategories,
          );
        } else {
          return (
            sectionTitle: 'Stores in $tabName near you',
            buttonLabel: 'See all $tabName stores',
            categoryFilter: finalCategories,
          );
        }
      }

      return (
        sectionTitle: 'Stores near you',
        buttonLabel: 'See all stores',
        categoryFilter: null,
      );
    }

    final categoryTabs = [
      'Food',
      'Supermarket / Hypermarket',
      'Pharmacy',
      'Clothing',
      'Electronics',
      'More'
    ];

    test('1. Supermarket / Hypermarket tab generates contextual product & store meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: 1, // Supermarket / Hypermarket
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in Supermarket & Hypermarket');
      expect(pMeta.buttonLabel, 'See all Supermarket & Hypermarket products');
      expect(pMeta.categoryFilter, contains('Supermarket / Hypermarket'));
      expect(pMeta.categoryFilter, contains('Grocery'));

      final sMeta = computeStoreMeta(
        selectedTabIndex: 1,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Supermarkets & Hypermarkets near you');
      expect(sMeta.buttonLabel, 'See all supermarkets & hypermarkets');
      expect(sMeta.categoryFilter, contains('Supermarket / Hypermarket'));
    });

    test('2. Food tab generates contextual product & store meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: 0, // Food
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in Food & Restaurants');
      expect(pMeta.buttonLabel, 'See all Food & Restaurant items');
      expect(pMeta.categoryFilter, contains('Restaurant'));
      expect(pMeta.categoryFilter, contains('Fast Food'));

      final sMeta = computeStoreMeta(
        selectedTabIndex: 0,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Restaurants near you');
      expect(sMeta.buttonLabel, 'See all restaurants');
      expect(sMeta.categoryFilter, contains('Restaurant'));
    });

    test('3. Pharmacy tab generates contextual product & store meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: 2, // Pharmacy
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in Pharmacy & Healthcare');
      expect(pMeta.buttonLabel, 'See all Pharmacy & Healthcare products');
      expect(pMeta.categoryFilter, contains('Pharmacy'));
      expect(pMeta.categoryFilter, contains('Medical Store'));

      final sMeta = computeStoreMeta(
        selectedTabIndex: 2,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Pharmacies & Medical Stores near you');
      expect(sMeta.buttonLabel, 'See all pharmacies & medical stores');
      expect(sMeta.categoryFilter, contains('Pharmacy'));
    });

    test('4. Clothing tab generates demographic-aware contextual meta', () {
      // All
      final pMetaAll = computeProductMeta(
        selectedTabIndex: 3, // Clothing
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMetaAll.sectionTitle, 'Popular in Clothing & Fashion');
      expect(pMetaAll.buttonLabel, 'See all Clothing & Fashion products');

      // Men/Boys
      final pMetaMen = computeProductMeta(
        selectedTabIndex: 3,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'Men/Boys',
        selectedFilterCategories: {},
      );
      expect(pMetaMen.sectionTitle, 'Popular for Men & Boys');
      expect(pMetaMen.buttonLabel, 'See all Men/Boys fashion');

      final sMetaMen = computeStoreMeta(
        selectedTabIndex: 3,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'Men/Boys',
      );
      expect(sMetaMen.sectionTitle, 'Men & Boys Stores');
      expect(sMetaMen.buttonLabel, 'See all clothing stores');
    });

    test('5. Electronics tab generates contextual product & store meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: 4, // Electronics
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in Electronics & Gadgets');
      expect(pMeta.buttonLabel, 'See all Electronics & Gadgets');
      expect(pMeta.categoryFilter, contains('Electronics'));

      final sMeta = computeStoreMeta(
        selectedTabIndex: 4,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Electronics Stores near you');
      expect(sMeta.buttonLabel, 'See all electronics stores');
    });

    test('6. More tab generates contextual product & store meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: 5, // More
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in More Categories');
      expect(pMeta.buttonLabel, 'See all products in this category');
      expect(pMeta.categoryFilter, contains('Stationery'));

      final sMeta = computeStoreMeta(
        selectedTabIndex: 5,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Stores in More near you');
      expect(sMeta.buttonLabel, 'See all More stores');
    });

    test('7. Default "All" view (-1 tab) retains broad platform discovery', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: -1,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {},
      );
      expect(pMeta.sectionTitle, 'Popular in your area');
      expect(pMeta.buttonLabel, 'See all popular products');
      expect(pMeta.categoryFilter, isNull);

      final sMeta = computeStoreMeta(
        selectedTabIndex: -1,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
      );
      expect(sMeta.sectionTitle, 'Stores near you');
      expect(sMeta.buttonLabel, 'See all stores');
      expect(sMeta.categoryFilter, isNull);
    });

    test('8. Filter category chip active without tab generates custom filtered meta', () {
      final pMeta = computeProductMeta(
        selectedTabIndex: -1,
        categoryNames: categoryTabs,
        selectedFeedDemographic: 'All',
        selectedFilterCategories: {'Pharmacy'},
      );
      expect(pMeta.sectionTitle, 'Popular in Pharmacy');
      expect(pMeta.buttonLabel, 'See all filtered products');
      expect(pMeta.categoryFilter, contains('Pharmacy'));
      expect(pMeta.categoryFilter, contains('Medical Store'));
    });
  });
}
