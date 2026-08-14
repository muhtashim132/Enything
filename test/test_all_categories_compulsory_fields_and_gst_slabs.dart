import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/services/gst_recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Category Mapping & Group Classification Tests', () {
    test('All categories map to valid CategoryGroup', () {
      expect(AppCategories.all.isNotEmpty, isTrue);

      for (final catMap in AppCategories.all) {
        final name = catMap['name']!;
        final group = AppCategories.groupFor(name);

        expect(
          [CategoryGroup.food, CategoryGroup.pharmacy, CategoryGroup.perishable, CategoryGroup.retail],
          contains(group),
          reason: '$name must map to a valid CategoryGroup',
        );

        final groupInfo = AppCategories.groupInfo(group);
        expect(groupInfo['label'], isNotEmpty);
        expect(groupInfo['hint'], isNotEmpty);
        expect(groupInfo['emoji'], isNotEmpty);
      }
    });

    test('Specific category group classifications are exact', () {
      // Food Group
      expect(AppCategories.groupFor('Restaurant'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Fast Food'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Bakery'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Sweets & Mithai'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Tea & Coffee'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Ice Cream'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Paan Shop'), equals(CategoryGroup.food));
      expect(AppCategories.groupFor('Beverages'), equals(CategoryGroup.food));

      // Pharmacy Group
      expect(AppCategories.groupFor('Pharmacy'), equals(CategoryGroup.pharmacy));
      expect(AppCategories.groupFor('Medical Store'), equals(CategoryGroup.pharmacy));

      // Perishable Group
      expect(AppCategories.groupFor('Fruits & Vegs'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Butcher'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Fish & Seafood'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Dairy & Eggs'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Grocery'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Organic'), equals(CategoryGroup.perishable));
      expect(AppCategories.groupFor('Supermarket / Hypermarket'), equals(CategoryGroup.perishable));

      // Retail Group
      expect(AppCategories.groupFor('Clothing'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Footwear'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Electronics'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Mobile & Repair'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Jewellery'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Hardware Store'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Stationery'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Sports'), equals(CategoryGroup.retail));
      expect(AppCategories.groupFor('Toys & Games'), equals(CategoryGroup.retail));
    });

    test('Variant requirements are enforced strictly for Clothing and Footwear', () {
      expect(AppCategories.requiresVariant('Clothing'), isTrue);
      expect(AppCategories.requiresVariant('Footwear'), isTrue);
      expect(AppCategories.requiresVariant('Electronics'), isFalse);
      expect(AppCategories.requiresVariant('Grocery'), isFalse);
      expect(AppCategories.requiresVariant('Pharmacy'), isFalse);
      expect(AppCategories.requiresVariant('Restaurant'), isFalse);

      final clothingVariants = AppCategories.getSuggestedVariants('Clothing');
      expect(clothingVariants, containsAll(['S', 'M', 'L', 'XL']));

      final footwearVariants = AppCategories.getSuggestedVariants('Footwear');
      expect(footwearVariants, containsAll(['UK 7', 'UK 8', 'UK 9']));
    });
  });

  group('2. Statutory Indian GST Slabs Matrix Tests', () {
    test('0% Nil/Exempt Produce GST rates', () {
      expect(TaxConfig.gstRateForCategory('Fruits & Vegs'), equals(0.00));
      expect(TaxConfig.gstRateForCategory('Butcher'), equals(0.00));
      expect(TaxConfig.gstRateForCategory('Fish & Seafood'), equals(0.00));
    });

    test('3% Precious Metals & Jewellery GST rate', () {
      expect(TaxConfig.gstRateForCategory('Jewellery'), equals(0.03));
    });

    test('5% Section 9(5) Deemed Supplier Restaurant Food GST rates', () {
      expect(TaxConfig.gstRateForCategory('Restaurant'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Restaurant'), isTrue);

      expect(TaxConfig.gstRateForCategory('Fast Food'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Fast Food'), isTrue);

      expect(TaxConfig.gstRateForCategory('Bakery'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Bakery'), isTrue);

      expect(TaxConfig.gstRateForCategory('Sweets & Mithai'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Sweets & Mithai'), isTrue);

      expect(TaxConfig.gstRateForCategory('Tea & Coffee'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Tea & Coffee'), isTrue);

      expect(TaxConfig.gstRateForCategory('Ice Cream'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Ice Cream'), isTrue);

      expect(TaxConfig.gstRateForCategory('Paan Shop'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Paan Shop'), isTrue);
    });

    test('5% Concessional & FMCG / Pharma Rates', () {
      expect(TaxConfig.gstRateForCategory('Pharmacy'), equals(0.05));
      expect(TaxConfig.isEnythingDeemedSupplier('Pharmacy'), isFalse);

      expect(TaxConfig.gstRateForCategory('Medical Store'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Grocery'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Organic'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Supermarket / Hypermarket'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Dairy & Eggs'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Flowers'), equals(0.05));
    });

    test('5% / 18% Price-Threshold Slabs (Clothing & Footwear)', () {
      // At or below threshold (<= 2500) -> 5%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 500.0), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500.0), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 1999.0), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 2500.0), equals(0.05));

      // Above threshold (> 2500) -> 18%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500.01), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 4500.0), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 3200.0), equals(0.18));

      // Dynamic Admin Override of threshold
      expect(
        TaxConfig.gstRateForCategory('Clothing', itemPrice: 1500.0, slabThreshold: 1000.0, slabHighRate: 0.18),
        equals(0.18),
      );
      expect(
        TaxConfig.gstRateForCategory('Clothing', itemPrice: 900.0, slabThreshold: 1000.0, slabHighRate: 0.18),
        equals(0.05),
      );
    });

    test('18% Standard Retail & Electronics GST Rates', () {
      expect(TaxConfig.gstRateForCategory('Beverages'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Electronics'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Mobile & Repair'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Stationery'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Toys & Games'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Sports'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Pet Supplies'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Salon & Beauty'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Cosmetics & Beauty'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Home Decor'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Furniture'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Hardware Store'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Auto Parts'), equals(0.18));
    });

    test('Enything Own Platform Services (SAC 9965/9967 and SAC 9985)', () {
      expect(TaxConfig.deliveryGstRate, equals(0.18));
      expect(TaxConfig.platformFeeGstRate, equals(0.18));
    });
  });

  group('3. Smart GST Recommendation Engine Tests Across All Slabs', () {
    final engine = GstRecommendationEngine.instance;

    test('Tobacco / Sin Goods recommend 40% rate', () {
      final rec = engine.recommend('Marlboro Gold Lights Cigarette', 'Paan Shop');
      expect(rec.rate, equals(0.40));
      expect(rec.rateLabel, equals('40%'));
      expect(rec.reason, contains('Tobacco'));
    });

    test('Jewellery / Gold recommendations include 3% and diamond rates', () {
      final rec = engine.recommend('22K Gold Ring', 'Jewellery');
      expect(rec.rate, equals(0.03));
      expect(rec.alternatives, containsAll([0.00, 0.0025, 0.015, 0.03, 0.05, 0.18]));
    });

    test('Pharmacy recommendation contains essential vs cosmetic alternatives', () {
      final rec = engine.recommend('Paracetamol 650 Tablet', 'Pharmacy');
      expect(rec.rate, equals(0.05));
      expect(rec.alternatives, containsAll([0.00, 0.05, 0.12, 0.18]));
    });

    test('Electronics recommendation includes peak luxury 28% alternatives', () {
      final rec = engine.recommend('Inverter Split AC 1.5 Ton', 'Electronics');
      expect(rec.rate, equals(0.18));
      expect(rec.alternatives, containsAll([0.05, 0.18, 0.28]));
    });

    test('Apparel recommendation handles price slabs', () {
      final rec = engine.recommend('Cotton Casual Shirt', 'Clothing');
      expect(rec.rate, equals(0.05));
      expect(rec.alternatives, containsAll([0.05, 0.12, 0.18]));
    });
  });

  group('4. Full Order Tax Calculation Breakdown Verification', () {
    test('Multi-category Cart Tax Breakdown', () {
      final items = [
        // 1. Restaurant item: ₹300 @ 5% S.9(5) = ₹15 GST (Enything remit)
        {
          'name': 'Butter Chicken',
          'category': 'Restaurant',
          'price': 300.0,
          'quantity': 1,
        },
        // 2. Electronics item: ₹1000 @ 18% = ₹180 GST (Seller remit)
        {
          'name': 'Wireless Mouse',
          'category': 'Electronics',
          'price': 1000.0,
          'quantity': 1,
        },
        // 3. Fresh Veg item: ₹200 @ 0% = ₹0 GST
        {
          'name': 'Organic Tomatoes',
          'category': 'Fruits & Vegs',
          'price': 200.0,
          'quantity': 1,
        },
        // 4. Gold Jewellery item: ₹5000 @ 3% = ₹150 GST (Seller remit)
        {
          'name': 'Silver Coin 10g',
          'category': 'Jewellery',
          'price': 5000.0,
          'quantity': 1,
        },
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 40.0,
        riderEarnings: 32.0,
        platformFee: 15.0,
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, equals(6500.0));
      // S.9(5) GST = 300 * 0.05 = 15.0
      expect(breakdown.s9_5GstToRemit, equals(15.0));
      // Non-9(5) GST = (1000 * 0.18) + (200 * 0.0) + (5000 * 0.03) = 180 + 0 + 150 = 330.0
      expect(breakdown.nonFoodGstPassThrough, equals(330.0));
      expect(breakdown.itemGstTotal, equals(345.0));

      // Services GST = 18% included in delivery (40) + platform (15)
      expect(breakdown.deliveryGst, closeTo(40.0 - (40.0 / 1.18), 0.01));
      expect(breakdown.platformFeeGst, closeTo(15.0 - (15.0 / 1.18), 0.01));

      // Grand Total = 6500 (items) + 345 (item GST) + 40 (del) + 15 (plat) = 6900.0
      expect(breakdown.grandTotal, equals(6900.0));
    });
  });
}
