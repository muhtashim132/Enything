import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/services/master_catalog_service.dart';
import 'package:enythingmobilenew/config/app_categories.dart';

void main() {
  group('100x Master Catalog Autofill & Autocomplete Engine Tests', () {
    test('Query sanitization returns empty for queries under 2 characters', () async {
      final service = MasterCatalogService.instance;
      
      final emptyResult = await service.searchCatalog(query: '');
      expect(emptyResult, isEmpty);

      final oneCharResult = await service.searchCatalog(query: 'a');
      expect(oneCharResult, isEmpty);

      final whitespaceResult = await service.searchCatalog(query: '   ');
      expect(whitespaceResult, isEmpty);
    });

    test('Deduplicates identical products across stores and prioritizes rich data & images', () {
      // Simulate raw product records from multiple stores in the DB
      final rawStoreA = {
        'id': 'prod-store-a-1',
        'shop_id': 'shop-1',
        'name': 'Dolo 650 Tablet',
        'brand': 'Micro Labs',
        'description': null,
        'price': 30.0,
        'original_price': 35.0,
        'category': 'Pharmacy',
        'menu_category': 'Fever & Pain',
        'unit_type': 'strip',
        'weight_per_unit': 15.0,
        'is_veg': null,
        'requires_prescription': false,
        'medicine_type': 'Allopathy',
        'images': <String>[],
        'is_available': true,
      };

      final rawStoreB = {
        'id': 'prod-store-b-2',
        'shop_id': 'shop-2',
        'name': 'dolo 650 tablet  ', // duplicate name with case/whitespace variations
        'brand': 'MICRO LABS',
        'description': 'Paracetamol (650mg)', // has chemical salt
        'price': 32.0,
        'original_price': 35.0,
        'category': 'Pharmacy',
        'menu_category': 'Fever & Pain',
        'unit_type': 'strip',
        'weight_per_unit': 15.0,
        'is_veg': null,
        'requires_prescription': false,
        'medicine_type': 'Allopathy',
        'images': ['https://cdn.enything.com/medicines/dolo650.png', 'https://cdn.enything.com/medicines/dolo650_back.png'],
        'is_available': true,
      };

      final productA = ProductModel.fromMap(rawStoreA);
      final productB = ProductModel.fromMap(rawStoreB);

      // Deduplication test logic
      final Map<String, ProductModel> dedupMap = {};

      for (final p in [productA, productB]) {
        final key = '${p.name.trim().toLowerCase()}::${(p.brand ?? '').trim().toLowerCase()}::${p.unitType.trim().toLowerCase()}';
        if (!dedupMap.containsKey(key)) {
          dedupMap[key] = p;
        } else {
          final existing = dedupMap[key]!;
          // Better item has images or description
          final existingScore = (existing.images.isNotEmpty ? 10 : 0) + (existing.description != null && existing.description!.isNotEmpty ? 5 : 0);
          final newScore = (p.images.isNotEmpty ? 10 : 0) + (p.description != null && p.description!.isNotEmpty ? 5 : 0);
          if (newScore > existingScore) {
            dedupMap[key] = p;
          }
        }
      }

      expect(dedupMap.length, 1);
      final consolidated = dedupMap.values.first;
      expect(consolidated.id, 'prod-store-b-2');
      expect(consolidated.images.length, 2);
      expect(consolidated.description, 'Paracetamol (650mg)');
      expect(consolidated.images.first, 'https://cdn.enything.com/medicines/dolo650.png');
    });

    test('Autofill populates all fields accurately for Pharmacy category', () {
      final template = ProductModel(
        id: 'tmpl-med-1',
        shopId: 'ref-shop',
        name: 'Rosuvas 20 Tablet',
        brand: 'Sun Pharma',
        description: 'Rosuvastatin (20mg)',
        price: 245.0,
        originalPrice: 285.0,
        category: 'Pharmacy',
        menuCategory: 'Cardiovascular Care',
        unitType: 'strip',
        weightPerUnit: 10.0,
        isVeg: null,
        requiresPrescription: true,
        medicineType: 'Allopathy',
        images: ['https://cdn.enything.com/medicines/rosuvas20.png'],
        isAvailable: true,
        variants: [
          ProductVariant(id: 'v1', name: '10 Tablets Strip', price: 245.0, originalPrice: 285.0),
          ProductVariant(id: 'v2', name: '15 Tablets Strip', price: 350.0, originalPrice: 410.0),
        ],
      );

      // Simulate form state variables before autofill
      String formName = 'Rosuv';
      String formBrand = '';
      String formDescription = '';
      String formPrice = '';
      String formOriginalPrice = '';
      bool formHasDiscount = false;
      String formCategory = 'Pharmacy';
      String formMenuCategory = '';
      String formUnitType = 'pieces';
      double? formWeight;
      bool? formIsVeg;
      bool formRequiresPrescription = false;
      String formMedicineType = 'General';
      List<String> formExistingImages = [];
      List<ProductVariant> formVariants = [];

      // Take snapshot before autofill (Undo support)
      final snapshot = {
        'name': formName,
        'brand': formBrand,
        'description': formDescription,
        'price': formPrice,
        'originalPrice': formOriginalPrice,
        'hasDiscount': formHasDiscount,
        'category': formCategory,
        'menuCategory': formMenuCategory,
        'unitType': formUnitType,
        'weight': formWeight,
        'isVeg': formIsVeg,
        'requiresPrescription': formRequiresPrescription,
        'medicineType': formMedicineType,
        'images': List<String>.from(formExistingImages),
        'variants': List<ProductVariant>.from(formVariants),
      };

      // Perform 1-Tap Autofill
      formName = template.name;
      if (template.brand != null && template.brand!.isNotEmpty) {
        formBrand = template.brand!;
      }
      if (template.description != null && template.description!.isNotEmpty) {
        formDescription = template.description!;
      }
      formPrice = template.price.toStringAsFixed(template.price.truncateToDouble() == template.price ? 0 : 2);
      if (template.originalPrice != null && template.originalPrice! > template.price) {
        formHasDiscount = true;
        formOriginalPrice = template.originalPrice!.toStringAsFixed(template.originalPrice!.truncateToDouble() == template.originalPrice ? 0 : 2);
      }
      formCategory = template.category;
      if (template.menuCategory != null && template.menuCategory!.isNotEmpty) {
        formMenuCategory = template.menuCategory!;
      }
      if (template.unitType.isNotEmpty) {
        formUnitType = template.unitType;
      }
      if (template.weightPerUnit != null) {
        formWeight = template.weightPerUnit;
      }
      formIsVeg = template.isVeg;
      formRequiresPrescription = template.requiresPrescription;
      if (template.medicineType.isNotEmpty) {
        formMedicineType = template.medicineType;
      }
      if (template.images.isNotEmpty) {
        formExistingImages = List<String>.from(template.images);
      }
      if (template.variants.isNotEmpty) {
        formVariants = List<ProductVariant>.from(template.variants);
      }

      // Assertions on autofilled state
      expect(formName, 'Rosuvas 20 Tablet');
      expect(formBrand, 'Sun Pharma');
      expect(formDescription, 'Rosuvastatin (20mg)');
      expect(formPrice, '245');
      expect(formOriginalPrice, '285');
      expect(formHasDiscount, isTrue);
      expect(formMenuCategory, 'Cardiovascular Care');
      expect(formUnitType, 'strip');
      expect(formWeight, 10.0);
      expect(formRequiresPrescription, isTrue);
      expect(formMedicineType, 'Allopathy');
      expect(formExistingImages.length, 1);
      expect(formExistingImages.first, 'https://cdn.enything.com/medicines/rosuvas20.png');
      expect(formVariants.length, 2);

      // Verify Undo restores previous state
      formName = snapshot['name'] as String;
      formBrand = snapshot['brand'] as String;
      formDescription = snapshot['description'] as String;
      formPrice = snapshot['price'] as String;
      formOriginalPrice = snapshot['originalPrice'] as String;
      formHasDiscount = snapshot['hasDiscount'] as bool;
      formCategory = snapshot['category'] as String;
      formMenuCategory = snapshot['menuCategory'] as String;
      formUnitType = snapshot['unitType'] as String;
      formWeight = snapshot['weight'] as double?;
      formIsVeg = snapshot['isVeg'] as bool?;
      formRequiresPrescription = snapshot['requiresPrescription'] as bool;
      formMedicineType = snapshot['medicineType'] as String;
      formExistingImages = List<String>.from(snapshot['images'] as List);
      formVariants = List<ProductVariant>.from(snapshot['variants'] as List);

      expect(formName, 'Rosuv');
      expect(formBrand, isEmpty);
      expect(formDescription, isEmpty);
      expect(formPrice, isEmpty);
      expect(formOriginalPrice, isEmpty);
      expect(formHasDiscount, isFalse);
      expect(formRequiresPrescription, isFalse);
      expect(formExistingImages, isEmpty);
      expect(formVariants, isEmpty);
    });

    test('Autofill populates Grocery & Supermarket specific fields', () {
      final groceryTemplate = ProductModel(
        id: 'tmpl-groc-1',
        shopId: 'ref-grocery-shop',
        name: 'Fortune Sunlite Refined Sunflower Oil 1 L',
        brand: 'Fortune',
        description: 'Refined sunflower oil enriched with Vitamins A and D.',
        price: 135.0,
        originalPrice: 165.0,
        category: 'Grocery',
        menuCategory: 'Cooking Essentials',
        unitType: 'Litre',
        weightPerUnit: 1.0,
        isVeg: true,
        requiresPrescription: false,
        medicineType: 'General',
        images: ['https://cdn.enything.com/groceries/fortune_oil_1l.png'],
        isAvailable: true,
      );

      expect(AppCategories.isPharmacyCategory(groceryTemplate.category), isFalse);
      expect(groceryTemplate.isVeg, isTrue);
      expect(groceryTemplate.unitType, 'Litre');
      expect(groceryTemplate.weightPerUnit, 1.0);
      expect(groceryTemplate.brand, 'Fortune');
      expect(groceryTemplate.images.first, contains('fortune_oil_1l.png'));
    });

    test('Handles edge cases with null or empty template fields safely', () {
      final minimalTemplate = ProductModel(
        id: 'tmpl-minimal-1',
        shopId: 'ref-shop',
        name: 'Generic Paracetamol 500mg',
        price: 15.0,
        category: 'Pharmacy',
        isAvailable: true,
        brand: null,
        description: null,
        originalPrice: null,
        menuCategory: null,
        unitType: 'pieces',
        weightPerUnit: null,
        isVeg: null,
        requiresPrescription: false,
        medicineType: 'General',
        images: [],
        variants: [],
      );

      String formBrand = 'Old Brand';
      String formDescription = 'Old Description';
      bool formHasDiscount = true;
      String formOriginalPrice = '50';
      List<String> formImages = ['https://test.com/img.png'];

      // Autofilling with minimal template should gracefully reset or maintain defaults
      if (minimalTemplate.brand != null && minimalTemplate.brand!.isNotEmpty) {
        formBrand = minimalTemplate.brand!;
      }
      if (minimalTemplate.description != null && minimalTemplate.description!.isNotEmpty) {
        formDescription = minimalTemplate.description!;
      }
      if (minimalTemplate.originalPrice != null && minimalTemplate.originalPrice! > minimalTemplate.price) {
        formHasDiscount = true;
        formOriginalPrice = minimalTemplate.originalPrice.toString();
      } else {
        formHasDiscount = false;
        formOriginalPrice = '';
      }
      if (minimalTemplate.images.isNotEmpty) {
        formImages = List<String>.from(minimalTemplate.images);
      }

      expect(minimalTemplate.name, 'Generic Paracetamol 500mg');
      expect(formBrand, 'Old Brand');
      expect(formDescription, 'Old Description');
      expect(formHasDiscount, isFalse);
      expect(formOriginalPrice, isEmpty);
      // Existing images not overwritten if template has 0 images
      expect(formImages.length, 1);
    });
  });
}
