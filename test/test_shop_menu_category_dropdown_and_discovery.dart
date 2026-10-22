import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';

void main() {
  group('100x Shop Menu Category Dropdown & Discovery Engine Tests', () {
    test('Discovers all distinct menu categories including 1-off outliers', () {
      // Mock raw database response from Supabase query:
      // .from('products').select('menu_category').eq('shop_id', shopId).eq('is_deleted', false)
      final rawDbRows = [
        {'menu_category': 'Starter'},
        {'menu_category': 'Starter'},
        {'menu_category': 'Starter'},
        {'menu_category': 'Main Course Veg.'},
        {'menu_category': 'Main Course Veg.'},
        {'menu_category': 'Main Course Non Veg.'},
        // Exactly ONE product has 'Non Veg. Pizza'
        {'menu_category': 'Non Veg. Pizza'},
        // Null and empty values in database
        {'menu_category': null},
        {'menu_category': ''},
        {'menu_category': '   '},
      ];

      final Set<String> seen = {};
      final List<String> categories = [];

      for (final item in rawDbRows) {
        final raw = item['menu_category']?.toString() ?? '';
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          categories.add(trimmed);
        }
      }

      categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      // Verify all 4 categories are captured without dropping the 1-off outlier
      expect(categories.length, 4);
      expect(categories, contains('Non Veg. Pizza'));
      expect(categories, contains('Starter'));
      expect(categories, contains('Main Course Veg.'));
      expect(categories, contains('Main Course Non Veg.'));
    });

    test('Case-insensitively deduplicates categories and trims whitespace', () {
      final rawDbRows = [
        {'menu_category': 'Beverages'},
        {'menu_category': ' beverages '},
        {'menu_category': 'BEVERAGES'},
        {'menu_category': 'Desserts'},
        {'menu_category': '  desserts'},
      ];

      final Set<String> seen = {};
      final List<String> categories = [];

      for (final item in rawDbRows) {
        final raw = item['menu_category']?.toString() ?? '';
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          categories.add(trimmed);
        }
      }

      expect(categories.length, 2);
      expect(categories.first, 'Beverages');
      expect(categories.last, 'Desserts');
    });

    test('Ensures existing product menu_category is pre-seeded on edit mode', () {
      final rawDbRows = [
        {'menu_category': 'Starter'},
        {'menu_category': 'Main Course'},
      ];

      // Existing product has an exclusive category not shared with other products
      const existingProductCategory = 'Chef Specials';

      final Set<String> seen = {};
      final List<String> categories = [];

      for (final item in rawDbRows) {
        final raw = item['menu_category']?.toString() ?? '';
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          categories.add(trimmed);
        }
      }

      // Pre-seed check
      final current = existingProductCategory.trim();
      if (current.isNotEmpty && seen.add(current.toLowerCase())) {
        categories.add(current);
      }

      categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      expect(categories.length, 3);
      expect(categories, contains('Chef Specials'));
      expect(categories, contains('Starter'));
      expect(categories, contains('Main Course'));
    });

    test('Handles brand-new shop with zero categories gracefully', () {
      final List<Map<String, dynamic>> rawDbRows = [];

      final Set<String> seen = {};
      final List<String> categories = [];

      for (final item in rawDbRows) {
        final raw = item['menu_category']?.toString() ?? '';
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          categories.add(trimmed);
        }
      }

      expect(categories.isEmpty, isTrue);
    });

    test('Menu Category validator rejects null, empty, or whitespace strings and accepts valid names', () {
      String? validateMenuCategory(String? val) {
        if (val == null || val.trim().isEmpty) {
          return 'Menu Category is required';
        }
        return null;
      }

      expect(validateMenuCategory(null), 'Menu Category is required');
      expect(validateMenuCategory(''), 'Menu Category is required');
      expect(validateMenuCategory('   '), 'Menu Category is required');
      expect(validateMenuCategory('\t\n'), 'Menu Category is required');
      expect(validateMenuCategory('Starters'), isNull);
      expect(validateMenuCategory('  Main Course  '), isNull);
    });

    test('ProductModel properly serializes and deserializes menuCategory', () {
      final model = ProductModel(
        id: 'p-1',
        shopId: 's-1',
        name: 'Paneer Tikka',
        category: 'Food',
        price: 250,
        menuCategory: 'Starters',
      );

      final map = model.toMap();
      expect(map['menu_category'], 'Starters');

      final fromMap = ProductModel.fromMap(map);
      expect(fromMap.menuCategory, 'Starters');
    });
  });
}

