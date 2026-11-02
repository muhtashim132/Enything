import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/widgets/seller/seller_deductible_card.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('100X Grocerylm (Low Margin) Architecture & Edge-Case Tests', () {
    test('1. AppCategories configuration & public/internal isolation', () {
      expect(AppCategories.groceryLm, equals('Grocerylm'));

      // In all categories list
      final allNames = AppCategories.names;
      expect(allNames.contains('Grocerylm'), isTrue);

      // Identified as internal-only category
      expect(AppCategories.isInternalOnly('Grocerylm'), isTrue);
      expect(AppCategories.isInternalOnly('grocerylm'), isTrue);
      expect(AppCategories.isInternalOnly('Grocery (Low Margin)'), isTrue);
      expect(AppCategories.isInternalOnly('grocery low margin'), isTrue);
      expect(AppCategories.isInternalOnly('grocery_lm'), isTrue);
      expect(AppCategories.isGroceryLowMargin('Grocerylm'), isTrue);

      // Standard categories are NOT internal-only
      expect(AppCategories.isInternalOnly('Grocery'), isFalse);
      expect(
          AppCategories.isInternalOnly('Supermarket / Hypermarket'), isFalse);
      expect(AppCategories.isInternalOnly('Restaurant'), isFalse);
      expect(AppCategories.isInternalOnly('Pharmacy'), isFalse);

      // Customer-facing public categories strictly exclude Grocerylm
      final publicNames = AppCategories.publicNames;
      expect(publicNames.contains('Grocerylm'), isFalse);
      expect(publicNames.contains('Grocery (Low Margin)'), isFalse);
      expect(publicNames.contains('Grocery'), isTrue);
      expect(publicNames.contains('Supermarket / Hypermarket'), isTrue);

      // Group and food categorization
      expect(AppCategories.groupFor('Grocerylm'),
          equals(CategoryGroup.perishable));
      expect(AppCategories.isFoodCategory('Grocerylm'), isTrue);
      expect(AppCategories.isFoodCategory('grocerylm'), isTrue);
      expect(AppCategories.getCustomerCollection('Grocerylm'),
          equals('Grocery & Fresh'));
      expect(AppCategories.getSuggestedVariants('Grocerylm'),
          containsAll(['100g', '500g', '1kg']));
    });

    test('2. TaxConfig GST & Section 9(5) classification for Grocerylm', () {
      // 5% standard grocery blended rate
      expect(TaxConfig.gstRateForCategory('Grocerylm'), equals(0.05));
      expect(
          TaxConfig.gstRateForCategory('Grocery (Low Margin)'), equals(0.05));

      // Grocerylm is standard non-deemed supplier (seller files GST, unlike restaurants)
      expect(TaxConfig.isEnythingDeemedSupplier('Grocerylm'), isFalse);
      expect(TaxConfig.gstLabel('Grocerylm'), equals('GST 5%'));
    });

    test('3. PlatformConfigProvider customer isolation & admin visibility', () {
      final config = PlatformConfigProvider();

      // Customer feeds (activeCategoryMaps / activeCategoryNames) must NOT show Grocerylm
      final activeNames = config.activeCategoryNames;
      expect(activeNames.contains('Grocerylm'), isFalse);
      expect(activeNames.contains('Grocery (Low Margin)'), isFalse);
      expect(activeNames.contains('Grocery'), isTrue);

      // Admin feeds (allCategoryMaps / allCategoryNames) MUST show Grocerylm
      final allNames = config.allCategoryNames;
      expect(allNames.contains('Grocerylm'), isTrue);

      // Commission resolution with aliases
      expect(config.getCommissionPercentForCategory('Grocerylm'),
          equals(5.0)); // fallback default
      expect(config.getCommissionPercentForCategory('grocerylm'), equals(5.0));
      expect(config.getCommissionPercentForCategory('Grocery (Low Margin)'),
          equals(5.0));
    });

    test(
        '4. Seller omnibus schedule includes Grocerylm with low-margin commission',
        () {
      final schedules = SellerDeductibleCard.omnibusDepartmentSchedules;
      final groceryLmSchedule = schedules.firstWhere(
        (s) => s['name'] == 'Grocerylm',
        orElse: () => {},
      );

      expect(groceryLmSchedule.isNotEmpty, isTrue);
      expect(groceryLmSchedule['defaultCommission'], equals(3.0));
      expect(groceryLmSchedule['gstRate'], equals(0.05));
      expect(groceryLmSchedule['emoji'], equals('🛒'));
    });

    test('5. 100% Prepaid Model Invariance (Zero COD Doorstep Collection)', () {
      final mockOrder = OrderModel(
        id: 'test-order-1',
        cartGroupId: 'cg-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        totalAmount: 250.0,
        deliveryCharges: 30.0,
        status: 'awaiting_acceptance',
        paymentStatus: 'captured',
        paymentMethod: 'upi',
        address: '123 Market St',
        deliveryLat: 12.9716,
        deliveryLng: 77.5946,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: const [],
      );

      final group = OrderGroup(
        'cg-1',
        [mockOrder],
      );

      // Enything operates strictly on 100% prepaid model
      expect(group.isCod, isFalse);
      expect(group.isPrepaid, isTrue);
      expect(group.codAmountToCollect, equals(0.0));
    });
  });
}
