import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';
import 'package:enythingmobilenew/utils/search_relevance_engine.dart';

void main() {
  group('100x Forensic Unit 9: Weight Engine & Search Relevance Fortress', () {
    test('1. WeightEngine resolves explicit weight and unit conversion', () {
      final productGrams = ProductModel(
        id: 'p1', shopId: 's1', name: 'Almonds 500g', category: 'Grocery',
        price: 450.0, weightPerUnit: 500.0, unitType: 'g', isAvailable: true
      );
      // 500 grams -> 0.5 kg
      final weightKg = WeightEngine.resolve(product: productGrams, quantity: 1);
      expect(weightKg, closeTo(0.5, 0.01));

      // 3 units -> 1.5 kg
      final weightKg3 = WeightEngine.resolve(product: productGrams, quantity: 3);
      expect(weightKg3, closeTo(1.5, 0.01));
    });

    test('2. WeightEngine parses embedded title weight and multi-pack multipliers', () {
      final productTitle = ProductModel(
        id: 'p2', shopId: 's1', name: 'Basmati Rice 5kg', category: 'Grocery',
        price: 600.0, isAvailable: true
      );
      // Extracts 5kg from title
      final weight5Kg = WeightEngine.resolve(product: productTitle, quantity: 1);
      expect(weight5Kg, closeTo(5.0, 0.1));

      final productPack = ProductModel(
        id: 'p3', shopId: 's1', name: 'Soap Bar 125g Pack of 4', category: 'Grocery',
        price: 200.0, isAvailable: true
      );
      // 125g * 4 = 500g = 0.5 kg
      final weightPack = WeightEngine.resolve(product: productPack, quantity: 1);
      expect(weightPack, closeTo(0.5, 0.05));
    });

    test('3. WeightEngine sanitizes corrupted inputs (zero, negative, NaN)', () {
      final corruptedProduct = ProductModel(
        id: 'p4', shopId: 's1', name: 'Mystery Item', category: 'Grocery',
        price: 100.0, weightPerUnit: -10.0, isAvailable: true
      );
      // Must not return negative weight; falls back to category heuristic baseline
      final safeWeight = WeightEngine.resolve(product: corruptedProduct, quantity: 1);
      expect(safeWeight, greaterThan(0.0));
      expect(safeWeight.isNaN, isFalse);
      expect(safeWeight.isNegative, isFalse);
    });

    test('4. SearchRelevanceEngine hierarchical scoring tiers', () {
      final exactProduct = ProductModel(
        id: 'm1', shopId: 's1', name: 'Mountain Dew', category: 'Beverages',
        price: 40.0, rating: 4.8, isAvailable: true
      );
      final prefixProduct = ProductModel(
        id: 'm2', shopId: 's1', name: 'Mountain Dew 750ml', category: 'Beverages',
        price: 40.0, rating: 4.5, isAvailable: true
      );
      final wordProduct = ProductModel(
        id: 'm3', shopId: 's1', name: 'Chilled Mountain Dew Can', category: 'Beverages',
        price: 35.0, rating: 4.5, isAvailable: true
      );
      final substringProduct = ProductModel(
        id: 'm4', shopId: 's1', name: 'Dermadew Soap', category: 'Pharmacy',
        price: 120.0, rating: 4.5, isAvailable: true
      );

      // Query "mountain dew"
      final scoreExact = SearchRelevanceEngine.computeScore(
        product: exactProduct, query: 'Mountain Dew'
      );
      final scorePrefix = SearchRelevanceEngine.computeScore(
        product: prefixProduct, query: 'Mountain Dew'
      );
      final scoreWord = SearchRelevanceEngine.computeScore(
        product: wordProduct, query: 'Mountain Dew'
      );

      // Exact match > Prefix match > Word match
      expect(scoreExact, greaterThan(scorePrefix));
      expect(scorePrefix, greaterThan(scoreWord));

      // Query "dew"
      final scoreDewPrefix = SearchRelevanceEngine.computeScore(
        product: prefixProduct, query: 'dew'
      );
      final scoreDewSubstring = SearchRelevanceEngine.computeScore(
        product: substringProduct, query: 'dew'
      );

      // Distinct word / prefix match ("Mountain Dew") must decisively outrank compound substring ("Dermadew")
      expect(scoreDewPrefix, greaterThan(scoreDewSubstring));
    });

    test('5. Medicine composition and salt search boost', () {
      final paracetamolMed = ProductModel(
        id: 'med1', shopId: 's1', name: 'Dolo 650', category: 'Pharmacy',
        description: 'Contains Paracetamol 650mg for fever and headache relief',
        medicineType: 'Paracetamol', price: 30.0, rating: 4.9, isAvailable: true
      );
      final unrelatedItem = ProductModel(
        id: 'med2', shopId: 's1', name: 'Bandage Strip', category: 'Pharmacy',
        price: 10.0, rating: 4.0, isAvailable: true
      );

      final doloScore = SearchRelevanceEngine.computeScore(
        product: paracetamolMed, query: 'Paracetamol'
      );
      final unrelatedScore = SearchRelevanceEngine.computeScore(
        product: unrelatedItem, query: 'Paracetamol'
      );

      expect(doloScore, greaterThan(unrelatedScore));
      expect(doloScore, greaterThan(1000.0));
    });
  });
}

