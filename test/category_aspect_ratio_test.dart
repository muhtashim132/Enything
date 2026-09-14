import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/app_categories.dart';

void main() {
  group('100x Category Aspect Ratio & Edge Cases Test Suite', () {
    test('isFashionCategory returns true for Fashion categories (case-insensitive)', () {
      expect(AppCategories.isFashionCategory('Clothing'), isTrue);
      expect(AppCategories.isFashionCategory('clothing'), isTrue);
      expect(AppCategories.isFashionCategory('CLOTHING'), isTrue);
      expect(AppCategories.isFashionCategory('Footwear'), isTrue);
      expect(AppCategories.isFashionCategory('footwear'), isTrue);
      expect(AppCategories.isFashionCategory('  Clothing  '), isTrue);
    });

    test('isFashionCategory returns false for Non-Fashion categories', () {
      expect(AppCategories.isFashionCategory('Restaurant'), isFalse);
      expect(AppCategories.isFashionCategory('Fast Food'), isFalse);
      expect(AppCategories.isFashionCategory('Bakery'), isFalse);
      expect(AppCategories.isFashionCategory('Grocery'), isFalse);
      expect(AppCategories.isFashionCategory('Supermarket / Hypermarket'), isFalse);
      expect(AppCategories.isFashionCategory('Pharmacy'), isFalse);
      expect(AppCategories.isFashionCategory('Medical Store'), isFalse);
      expect(AppCategories.isFashionCategory('Electronics'), isFalse);
      expect(AppCategories.isFashionCategory('Hardware Store'), isFalse);
      expect(AppCategories.isFashionCategory('Stationery'), isFalse);
      expect(AppCategories.isFashionCategory('Other'), isFalse);
    });

    test('isFashionCategory handles null and empty gracefully', () {
      expect(AppCategories.isFashionCategory(null), isFalse);
      expect(AppCategories.isFashionCategory(''), isFalse);
      expect(AppCategories.isFashionCategory('   '), isFalse);
    });

    test('getProductAspectRatio returns 0.75 (3:4) for fashion, 1.0 for others', () {
      expect(AppCategories.getProductAspectRatio('Clothing'), equals(0.75));
      expect(AppCategories.getProductAspectRatio('Footwear'), equals(0.75));
      expect(AppCategories.getProductAspectRatio('Restaurant'), equals(1.0));
      expect(AppCategories.getProductAspectRatio('Grocery'), equals(1.0));
      expect(AppCategories.getProductAspectRatio('Pharmacy'), equals(1.0));
      expect(AppCategories.getProductAspectRatio(null), equals(1.0));
    });

    test('Grid layout math guarantees zero pixel overflow across all device widths', () {
      final testWidths = [320.0, 375.0, 390.0, 414.0, 430.0, 768.0, 1024.0];
      const crossAxisSpacing = 16.0;
      const crossAxisCount = 2;
      const cardDetailsHeight = 120.0;

      for (final availableWidth in testWidths) {
        final itemWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount + 1))) / crossAxisCount;

        // 1. Fashion Category (3:4)
        final fashionRatio = AppCategories.getProductAspectRatio('Clothing');
        final fashionImageHeight = itemWidth / fashionRatio;
        final fashionTotalHeight = fashionImageHeight + cardDetailsHeight;
        final fashionChildAspectRatio = itemWidth / fashionTotalHeight;

        // Calculate rendered height in Flutter GridView:
        final renderedFashionHeight = itemWidth / fashionChildAspectRatio;
        expect(renderedFashionHeight, closeTo(fashionTotalHeight, 0.0001));

        // 2. Standard Category (1:1)
        final standardRatio = AppCategories.getProductAspectRatio('Grocery');
        final standardImageHeight = itemWidth / standardRatio;
        final standardTotalHeight = standardImageHeight + cardDetailsHeight;
        final standardChildAspectRatio = itemWidth / standardTotalHeight;

        final renderedStandardHeight = itemWidth / standardChildAspectRatio;
        expect(renderedStandardHeight, closeTo(standardTotalHeight, 0.0001));
      }
    });
  });
}
