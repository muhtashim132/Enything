import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/app_categories.dart';

void main() {
  group('100x Omnibus Supermarket & Grocery Store-Level Product Inheritance Fortress', () {
    test('1. AppCategories.isOmnibusStoreCategory accurately identifies all multi-department formats', () {
      expect(AppCategories.isOmnibusStoreCategory('Supermarket / Hypermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Supermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Hypermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Supermart'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Hypermart'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Grocery'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Grocerylm'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Grocery (Low Margin)'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Departmental Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('General Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Kirana Store'), isTrue);

      // Non-omnibus specialty stores must return false
      expect(AppCategories.isOmnibusStoreCategory('Pharmacy'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Medical Store'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Clothing'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Electronics'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Restaurant'), isFalse);
    });

    test('2. AppCategories.isSupermarketOrGroceryCategory correctly identifies grocery/supermarket targets', () {
      expect(AppCategories.isSupermarketOrGroceryCategory('Supermarket / Hypermarket'), isTrue);
      expect(AppCategories.isSupermarketOrGroceryCategory('Grocery'), isTrue);
      expect(AppCategories.isSupermarketOrGroceryCategory('Grocerylm'), isTrue);
      expect(AppCategories.isSupermarketOrGroceryCategory('Supermarket'), isTrue);
      expect(AppCategories.isSupermarketOrGroceryCategory('Hypermarket'), isTrue);
      expect(AppCategories.isSupermarketOrGroceryCategory('Hypermart'), isTrue);

      expect(AppCategories.isSupermarketOrGroceryCategory('Cosmetics & Beauty'), isFalse);
      expect(AppCategories.isSupermarketOrGroceryCategory('Pharmacy'), isFalse);
      expect(AppCategories.isSupermarketOrGroceryCategory('Clothing'), isFalse);
    });

    test('3. Lipstick in Maxx Retail (Supermarket): INCLUDED in Supermarket / Hypermarket view', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Supermarket / Hypermarket', 'Grocery'],
      );
      expect(matches, isTrue);
    });

    test('4. Lipstick in Maxx Retail (Supermarket): INCLUDED in Grocery view', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Grocery'],
      );
      expect(matches, isTrue);
    });

    test('5. Lipstick in Maxx Retail (Supermarket): INCLUDED in Cosmetics & Beauty view (Item Category Match)', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Cosmetics & Beauty'],
      );
      expect(matches, isTrue);
    });

    test('6. Atta / Dal in Maxx Retail (Supermarket): EXCLUDED from Cosmetics & Beauty (Zero Leakage Guard)', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Grocery',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Cosmetics & Beauty'],
      );
      expect(matches, isFalse);
    });

    test('7. Paracetamol in Noor Medicate (Pharmacy): EXCLUDED from Supermarket / Hypermarket', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Pharmacy',
        shopCategory: 'Pharmacy',
        targetCategories: ['Supermarket / Hypermarket'],
      );
      expect(matches, isFalse);
    });

    test('8. Soap / Shampoo in Daily Grocery Store (Grocery): INCLUDED in Grocery view', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Grocery',
        targetCategories: ['Grocery'],
      );
      expect(matches, isTrue);
    });

    test('9. Soap / Shampoo in Daily Grocery Store (Grocery): INCLUDED in Cosmetics & Beauty view', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Grocery',
        targetCategories: ['Cosmetics & Beauty'],
      );
      expect(matches, isTrue);
    });

    test('10. Notebook in Maxx Retail: INCLUDED in Supermarket / Hypermarket AND Stationery', () {
      final inSupermarket = AppCategories.matchesBrowsingCategory(
        productCategory: 'Stationery',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Supermarket / Hypermarket'],
      );
      expect(inSupermarket, isTrue);

      final inStationery = AppCategories.matchesBrowsingCategory(
        productCategory: 'Stationery',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Stationery'],
      );
      expect(inStationery, isTrue);
    });

    test('11. Grocerylm low-margin items: INCLUDED in Supermarket / Grocery feeds', () {
      final inSupermarket = AppCategories.matchesBrowsingCategory(
        productCategory: 'Grocerylm',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Supermarket / Hypermarket'],
      );
      expect(inSupermarket, isTrue);
    });

    test('12. Shop with secondary categories JSONB array inherits omnibus status correctly', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cosmetics & Beauty',
        shopCategory: 'Retail',
        shopCategories: ['Retail', 'Supermarket / Hypermarket'],
        targetCategories: ['Supermarket / Hypermarket'],
      );
      expect(matches, isTrue);
    });

    test('13. Food Store Inheritance: Biryani in Restaurant INCLUDED when browsing Food tab', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Biryani',
        shopCategory: 'Restaurant',
        targetCategories: ['Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Beverages'],
      );
      expect(matches, isTrue);
    });

    test('14. Pharmacy Store Inheritance: First Aid Kit in Pharmacy INCLUDED when browsing Pharmacy tab', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'First Aid',
        shopCategory: 'Pharmacy',
        targetCategories: ['Pharmacy', 'Medical Store'],
      );
      expect(matches, isTrue);
    });

    test('15. Clothing Store Inheritance: Denim Jeans in Clothing Store INCLUDED when browsing Clothing tab', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Jeans',
        shopCategory: 'Clothing',
        targetCategories: ['Clothing', 'Footwear', 'Jewellery'],
      );
      expect(matches, isTrue);
    });

    test('16. Electronics Store Inheritance: USB-C Cable in Mobile & Repair INCLUDED when browsing Electronics tab', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Cables & Chargers',
        shopCategory: 'Mobile & Repair',
        targetCategories: ['Electronics', 'Mobile & Repair'],
      );
      expect(matches, isTrue);
    });

    test('17. More Category Store Inheritance: Ballpoint Pen in Stationery Shop INCLUDED when browsing More tab', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Pens & Pencils',
        shopCategory: 'Stationery',
        targetCategories: ['Hardware Store', 'Stationery', 'Toys & Games', 'Sports', 'Pet Supplies', 'Cosmetics & Beauty', 'Salon & Beauty', 'Flowers', 'Home Decor', 'Furniture', 'Auto Parts', 'Other'],
      );
      expect(matches, isTrue);
    });

    test('18. Zero Leakage Across Specialty Categories: Biryani in Restaurant EXCLUDED from Pharmacy', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Biryani',
        shopCategory: 'Restaurant',
        targetCategories: ['Pharmacy', 'Medical Store'],
      );
      expect(matches, isFalse);
    });

    test('19. Zero Leakage Across Specialty Categories: T-Shirt in Clothing Shop EXCLUDED from Food', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'T-Shirts',
        shopCategory: 'Clothing',
        targetCategories: ['Restaurant', 'Fast Food', 'Bakery'],
      );
      expect(matches, isFalse);
    });

    test('20. Zero Leakage Across Specialty Categories: Atta/Rice in Supermarket EXCLUDED from Food', () {
      final matches = AppCategories.matchesBrowsingCategory(
        productCategory: 'Grocery',
        shopCategory: 'Supermarket / Hypermarket',
        targetCategories: ['Restaurant', 'Fast Food', 'Bakery'],
      );
      expect(matches, isFalse);
    });
  });
}

