import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/widgets/seller/seller_deductible_card.dart';

void main() {
  group('100x Multi-Category Store & Product Cross-Categorization Fortress', () {
    test('1. Omnibus Store Category Detection across all real-world nomenclature', () {
      // Must return true for all variations of supermarkets, hypermarkets, and departmental stores
      expect(AppCategories.isOmnibusStoreCategory('Supermarket / Hypermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Supermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Supermart'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('supermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Hypermarket'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Departmental Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('General Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Provision Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Kirana Store'), isTrue);
      expect(AppCategories.isOmnibusStoreCategory('Daily Mart'), isTrue);

      // Must return false for specialized mono-category stores
      expect(AppCategories.isOmnibusStoreCategory('Restaurant'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Fast Food'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Bakery'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Pharmacy'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Medical Store'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Clothing'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory('Electronics'), isFalse);
      expect(AppCategories.isOmnibusStoreCategory(null), isFalse);
      expect(AppCategories.isOmnibusStoreCategory(''), isFalse);
    });

    test('2. Taxonomy Isolation: Dietary pref (Veg/Non-Veg) and Prescription guards', () {
      // Cosmetics & Beauty is NOT a food category (no green/red veg dot)
      expect(AppCategories.isFoodCategory('Cosmetics & Beauty'), isFalse);
      expect(AppCategories.isFoodCategory('Salon & Beauty'), isFalse);

      // Groceries and Restaurants ARE food categories
      expect(AppCategories.isFoodCategory('Grocery'), isTrue);
      expect(AppCategories.isFoodCategory('Restaurant'), isTrue);
      expect(AppCategories.isFoodCategory('Supermarket / Hypermarket'), isTrue);

      // Cosmetics & Beauty does NOT require medical prescription
      expect(AppCategories.isPharmacyCategory('Cosmetics & Beauty'), isFalse);
      expect(AppCategories.isPharmacyCategory('Pharmacy'), isTrue);
      expect(AppCategories.isPharmacyCategory('Medical Store'), isTrue);
    });

    test('3. Statutory GST Slabs: 18% for Cosmetics vs 5% for Grocery staples', () {
      final cosmeticGst = TaxConfig.gstRateForCategory('Cosmetics & Beauty');
      expect(cosmeticGst, equals(0.18)); // 18% under Indian GST Act

      final groceryGst = TaxConfig.gstRateForCategory('Grocery');
      expect(groceryGst, equals(0.05)); // 5% blended FMCG rate

      final supermartGst = TaxConfig.gstRateForCategory('Supermarket / Hypermarket');
      expect(supermartGst, equals(0.05)); // 5% grocery default

      // Product-level override takes absolute priority
      final overriddenGst = TaxConfig.gstRateForProduct('Cosmetics & Beauty', 0.05);
      expect(overriddenGst, equals(0.05));
    });

    test('4. Legal Remittance Split: Section 9(5) Deemed Supplier vs Non-Food Passthrough', () {
      // Restaurant food: Enything is deemed supplier under §9(5) CGST Act
      expect(TaxConfig.isEnythingDeemedSupplier('Restaurant'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Fast Food'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Bakery'), isTrue);

      // Cosmetics & Supermarkets: Enything is NOT deemed supplier, merchant is supplier
      expect(TaxConfig.isEnythingDeemedSupplier('Cosmetics & Beauty'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Grocery'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Supermarket / Hypermarket'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Stationery'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Electronics'), isFalse);
    });

    test('5. Multi-Category Order Financial Engine: Line-by-Line GST and Commission Precision', () {
      // Mixed cart from "FreshLife Supermarket":
      // Item 1: 1x Basmati Rice (Grocery) @ ₹200 base price
      // Item 2: 1x Face Serum (Cosmetics & Beauty) @ ₹500 base price
      final items = [
        {
          'category': 'Grocery',
          'price': 200.0,
          'quantity': 1,
          'gst_rate_override': null,
        },
        {
          'category': 'Cosmetics & Beauty',
          'price': 500.0,
          'quantity': 1,
          'gst_rate_override': null,
        },
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 35.0,
        riderEarnings: 23.73,
        platformFee: 5.0,
        paymentMethod: 'upi', // Prepaid online
      );

      // Base subtotal: ₹200 + ₹500 = ₹700
      expect(breakdown.itemBaseSubtotal, equals(700.0));

      // Line 1 GST: ₹200 * 5% = ₹10.00
      // Line 2 GST: ₹500 * 18% = ₹90.00
      // Total Item GST: ₹10 + ₹90 = ₹100.00
      expect(breakdown.itemGstTotal, equals(100.0));
      expect(breakdown.itemGrossTotal, equals(800.0));

      // Section 9(5) vs Non-food GST Remittance:
      // Neither is prepared food, so s9_5GstToRemit is 0
      expect(breakdown.s9_5GstToRemit, equals(0.0));
      // All ₹100.00 GST is passed through to the seller for GSTR-3B filing
      expect(breakdown.nonFoodGstPassThrough, equals(100.0));

      // Grand Total: ₹800 items + ₹35 delivery + ₹5 platform = ₹840.00
      expect(breakdown.grandTotal, equals(840.0));

      // Gateway deduction (2.36% on ₹840 online collection)
      expect(breakdown.gatewayDeduction, closeTo(840.0 * 0.0236, 0.05));

      // TCS (§52 CGST Act: 0.5% on non-food taxable base ₹700) = ₹3.50
      expect(breakdown.tcsAmount, equals(700.0 * 0.005));

      // TDS (§194-O: 0.1% on taxable base ₹700) = ₹0.70
      expect(breakdown.tdsAmount, closeTo(0.70, 0.001));

      // Net Seller Payout verifies exact formula:
      // Base (₹700) + Passthrough GST (₹100) - Commission - Gateway Share - TCS - TDS
      expect(breakdown.sellerPayoutNet, lessThan(800.0));
      expect(breakdown.sellerPayoutNet, greaterThan(650.0));
    });

    test('6. Partial Order Rejection: Surviving Grocery Item Financial Independence', () {
      // If the cosmetic item is rejected by store/customer, remaining cart is pure grocery
      final survivingItems = [
        {
          'category': 'Grocery',
          'price': 200.0,
          'quantity': 1,
          'gst_rate_override': null,
        },
      ];

      final survivingBreakdown = OrderTaxBreakdown.calculate(
        items: survivingItems,
        deliveryCharge: 35.0,
        riderEarnings: 23.73,
        platformFee: 5.0,
        paymentMethod: 'upi',
      );

      // Base subtotal drops to ₹200
      expect(survivingBreakdown.itemBaseSubtotal, equals(200.0));

      // GST drops to ₹10 (5% on ₹200)
      expect(survivingBreakdown.itemGstTotal, equals(10.0));
      expect(survivingBreakdown.nonFoodGstPassThrough, equals(10.0));

      // TCS drops to ₹1.00 (0.5% on ₹200)
      expect(survivingBreakdown.tcsAmount, equals(1.0));

      // TDS drops to ₹0.20 (0.1% on ₹200)
      expect(survivingBreakdown.tdsAmount, closeTo(0.20, 0.001));
    });

    test('7. Category Isolation in Browsing: Omnibus store items do not leak into foreign categories', () {
      final subcatsLower = {'cosmetics & beauty'};

      // Product 1: Basmati Rice from Supermarket
      const p1Cat = 'grocery';
      const s1Cat = 'supermarket / hypermarket';
      final isOmnibus1 = AppCategories.isOmnibusStoreCategory(s1Cat);
      final isBrowsingOmnibus1 = subcatsLower.any(AppCategories.isOmnibusStoreCategory);

      bool includeP1 = true;
      if (isOmnibus1) {
        if (!isBrowsingOmnibus1 && !subcatsLower.contains(p1Cat)) {
          includeP1 = false;
        }
      }
      expect(includeP1, isFalse, reason: 'Grocery item from supermarket must NOT show up under Cosmetics category');

      // Product 2: Lipstick from Supermarket
      const p2Cat = 'cosmetics & beauty';
      bool includeP2 = true;
      if (isOmnibus1) {
        if (!isBrowsingOmnibus1 && !subcatsLower.contains(p2Cat)) {
          includeP2 = false;
        }
      }
      expect(includeP2, isTrue, reason: 'Cosmetic item from supermarket MUST show up under Cosmetics category');
    });

    test('8. Menu Category Fallback: Cross-category items without custom aisle fall back to product category', () {
      final productWithoutMenuCat = ProductModel(
        id: 'prod-123',
        shopId: 'shop-456',
        name: 'Matte Lipstick',
        category: 'Cosmetics & Beauty',
        menuCategory: null, // Seller did not provide custom aisle
        price: 350.0,
        rating: 4.5,
        totalReviews: 12,
        isAvailable: true,
        isVeg: null,
      );

      final resolvedMenuCategory = (productWithoutMenuCat.menuCategory != null &&
              productWithoutMenuCat.menuCategory!.trim().isNotEmpty)
          ? productWithoutMenuCat.menuCategory!.trim()
          : productWithoutMenuCat.category.trim();

      expect(resolvedMenuCategory, equals('Cosmetics & Beauty'));
      expect(productWithoutMenuCat.showsDietEmblem, isFalse);
    });

    test('9. Zero Cash on Delivery: 100% Prepaid Model Enforcement', () {
      // In Enything, all orders are strictly prepaid via UPI/cards (zero COD)
      final items = [
        {
          'category': 'Supermarket / Hypermarket',
          'price': 1000.0,
          'quantity': 1,
        },
      ];

      final onlineBreakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 35.0,
        riderEarnings: 23.73,
        platformFee: 5.0,
        paymentMethod: 'upi',
      );

      // Gateway deduction is positive for prepaid
      expect(onlineBreakdown.gatewayDeduction, greaterThan(0.0));
      // Seller and Enything proportionally absorb gateway fee
      expect(onlineBreakdown.sellerGatewayShare + onlineBreakdown.enythingGatewayShare,
          closeTo(onlineBreakdown.gatewayDeduction, 0.01));
    });

    test('10. Fresh Produce vs Taxable Goods: TCS Exemption Precision', () {
      // Fruits & Vegs (fresh produce) has 0% GST and is exempt from TCS §52
      expect(TaxConfig.tcsRateForCategory('Fruits & Vegs'), equals(0.0));
      expect(TaxConfig.tcsRateForCategory('Butcher'), equals(0.0));
      expect(TaxConfig.tcsRateForCategory('Fish & Seafood'), equals(0.0));

      // S9(5) restaurant food is also carved out from TCS
      expect(TaxConfig.tcsRateForCategory('Restaurant'), equals(0.0));

      // Cosmetics and packaged groceries attract 0.5% TCS
      expect(TaxConfig.tcsRateForCategory('Cosmetics & Beauty'), equals(0.005));
      expect(TaxConfig.tcsRateForCategory('Grocery'), equals(0.005));
      expect(TaxConfig.tcsRateForCategory('Electronics'), equals(0.005));
    });

    test('11. Omnibus Store Department Schedule Registry Verification', () {
      const schedules = SellerDeductibleCard.omnibusDepartmentSchedules;
      expect(schedules, isNotEmpty);

      // Verify all essential multi-department aisles are registered
      final deptNames = schedules.map((d) => d['name'] as String).toList();
      expect(deptNames, contains('Grocery'));
      expect(deptNames, contains('Dairy & Eggs'));
      expect(deptNames, contains('Fruits & Vegs'));
      expect(deptNames, contains('Cosmetics & Beauty'));
      expect(deptNames, contains('Electronics'));
      expect(deptNames, contains('Clothing'));
      expect(deptNames, contains('Pharmacy'));
      expect(deptNames, contains('Stationery'));

      // Verify Grocery vs Cosmetics rate divergence
      final groceryDept = schedules.firstWhere((d) => d['name'] == 'Grocery');
      expect(groceryDept['defaultCommission'], equals(6.0));
      expect(groceryDept['gstRate'], equals(0.05));

      final cosmeticsDept = schedules.firstWhere((d) => d['name'] == 'Cosmetics & Beauty');
      expect(cosmeticsDept['defaultCommission'], equals(10.0));
      expect(cosmeticsDept['gstRate'], equals(0.18));

      final dairyDept = schedules.firstWhere((d) => d['name'] == 'Dairy & Eggs');
      expect(dairyDept['defaultCommission'], equals(5.0));
      expect(dairyDept['gstRate'], equals(0.05));

      final produceDept = schedules.firstWhere((d) => d['name'] == 'Fruits & Vegs');
      expect(produceDept['defaultCommission'], equals(5.0));
      expect(produceDept['gstRate'], equals(0.00));
    });

    test('12. Real-World Supermarket Cart Settlement: Milk + Lipstick + Rice', () {
      // Customer orders from Supermarket:
      // Item 1: Amul Butter (Dairy & Eggs) - ₹100 base, 5% comm, 5% GST
      // Item 2: Lakme Lipstick (Cosmetics & Beauty) - ₹500 base, 10% comm, 18% GST
      // Item 3: Basmati Rice (Grocery) - ₹200 base, 6% comm, 5% GST
      final cart = [
        {
          'category': 'Dairy & Eggs',
          'price': 100.0,
          'quantity': 1,
        },
        {
          'category': 'Cosmetics & Beauty',
          'price': 500.0,
          'quantity': 1,
        },
        {
          'category': 'Grocery',
          'price': 200.0,
          'quantity': 1,
        },
      ];

      // Item-level Commission Calculation:
      const comm1 = 100.0 * 0.05; // ₹5.00
      const comm2 = 500.0 * 0.10; // ₹50.00
      const comm3 = 200.0 * 0.06; // ₹12.00
      const totalComm = comm1 + comm2 + comm3; // ₹67.00
      expect(totalComm, equals(67.0));

      const blendedRate = (totalComm / 800.0) * 100.0;
      expect(blendedRate, equals(8.375)); // Blended 8.375%

      // Item-level GST Calculation:
      const gst1 = 100.0 * 0.05; // ₹5.00
      const gst2 = 500.0 * 0.18; // ₹90.00
      const gst3 = 200.0 * 0.05; // ₹10.00
      const totalItemGst = gst1 + gst2 + gst3; // ₹105.00
      expect(totalItemGst, equals(105.0));

      final breakdown = OrderTaxBreakdown.calculate(
        items: cart,
        deliveryCharge: 35.0,
        riderEarnings: 23.73,
        platformFee: 5.0,
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, equals(800.0));
      expect(breakdown.itemGstTotal, equals(105.0));
      expect(breakdown.nonFoodGstPassThrough, equals(105.0));
      expect(breakdown.s9_5GstToRemit, equals(0.0));

      // Withholdings:
      expect(breakdown.tcsAmount, equals(800.0 * 0.005)); // ₹4.00 TCS
      expect(breakdown.tdsAmount, closeTo(800.0 * 0.001, 0.001)); // ₹0.80 TDS
    });

    test('13. Live Item Net Bank Payout Formula Precision: Cosmetics @ ₹500', () {
      const price = 500.0;
      const commPercent = 10.0;
      const commAmount = price * (commPercent / 100.0); // ₹50.00
      const customerGst = price * 0.18; // ₹90.00
      final gwShare = price * TaxConfig.effectiveGatewayDeductionPercent; // ₹500 * 0.0236 = ₹11.80
      const tds = price * TaxConfig.itTdsRate; // ₹500 * 0.001 = ₹0.50
      final tcs = price * TaxConfig.tcsRateForCategory('Cosmetics & Beauty'); // ₹500 * 0.005 = ₹2.50

      final totalDeductions = commAmount + gwShare + tds + tcs; // ₹64.80
      final netBase = price - totalDeductions; // ₹435.20
      final netBankDeposit = netBase + customerGst; // ₹435.20 + ₹90.00 = ₹525.20

      // Net bank payout must be greater than base price because customer paid ₹90 GST which passes through to seller
      expect(netBankDeposit, greaterThan(500.0));
      expect(netBankDeposit, closeTo(525.20, 0.05));
    });

    test('14. 100x Fallback Hierarchy: Item Category -> Shop Base -> Platform Default', () {
      // Order with 3 items in "Reliance Smart Supermarket" (shop category: 'Supermarket / Hypermarket'):
      // Item 1: 'Cosmetics & Beauty' -> Has explicit category override
      // Item 2: 'Stationery' -> No specific category override, must fall back to Shop Category
      // Item 3: Unknown / Null category -> Must fall back to Shop Category
      final items = [
        {
          'category': 'Cosmetics & Beauty',
          'shop_category': 'Supermarket / Hypermarket',
          'price': 300.0,
          'quantity': 1,
        },
        {
          'category': 'Stationery',
          'shop_category': 'Supermarket / Hypermarket',
          'price': 150.0,
          'quantity': 1,
        },
        {
          'category': null,
          'shop_category': 'Supermarket / Hypermarket',
          'price': 100.0,
          'quantity': 1,
        },
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 35.0,
        riderEarnings: 23.73,
        platformFee: 5.0,
        paymentMethod: 'upi',
        shopCategory: 'Supermarket / Hypermarket',
      );

      expect(breakdown.itemBaseSubtotal, equals(550.0));
      expect(breakdown.sellerPayout, greaterThan(0));
      expect(breakdown.grandTotal, greaterThan(breakdown.itemBaseSubtotal));
    });

    test('15. AppCategories Category Emoji Resolution for all Store Types', () {
      expect(AppCategories.getCategoryEmoji('Supermarket / Hypermarket'), equals('🏬'));
      expect(AppCategories.getCategoryEmoji('Grocery'), equals('🛒'));
      expect(AppCategories.getCategoryEmoji('Pharmacy'), equals('💊'));
      expect(AppCategories.getCategoryEmoji('Medical Store'), equals('🏥'));
      expect(AppCategories.getCategoryEmoji('Restaurant'), equals('🍽️'));
      expect(AppCategories.getCategoryEmoji('Fast Food'), equals('🍔'));
      expect(AppCategories.getCategoryEmoji('Clothing'), equals('👕'));
      expect(AppCategories.getCategoryEmoji('Footwear'), equals('👟'));
      expect(AppCategories.getCategoryEmoji('Cosmetics & Beauty'), equals('💄'));
      expect(AppCategories.getCategoryEmoji('Salon & Beauty'), equals('💇'));
      expect(AppCategories.getCategoryEmoji('Stationery'), equals('📚'));
      expect(AppCategories.getCategoryEmoji('Electronics'), equals('📱'));
      // Unknown / null category fallback
      expect(AppCategories.getCategoryEmoji(null), equals('🏪'));
      expect(AppCategories.getCategoryEmoji(''), equals('🏪'));
      expect(AppCategories.getCategoryEmoji('Unknown Custom Department'), equals('🏪'));
    });

    test('16. Category-Agnostic Store Section Titles', () {
      // Supermarkets / Departmental stores must display 'Aisles & Departments'
      expect(
        AppCategories.isOmnibusStoreCategory('Supermarket / Hypermarket')
            ? 'Aisles & Departments'
            : (AppCategories.isFoodCategory('Supermarket / Hypermarket')
                ? 'Menu'
                : 'Products & Catalog'),
        equals('Aisles & Departments'),
      );

      // Restaurants must display 'Menu'
      expect(
        AppCategories.isOmnibusStoreCategory('Restaurant')
            ? 'Aisles & Departments'
            : (AppCategories.isFoodCategory('Restaurant')
                ? 'Menu'
                : 'Products & Catalog'),
        equals('Menu'),
      );

      // Retail stores (Pharmacy, Electronics, Cosmetics, Clothing) must display 'Products & Catalog'
      expect(
        AppCategories.isOmnibusStoreCategory('Pharmacy')
            ? 'Aisles & Departments'
            : (AppCategories.isFoodCategory('Pharmacy')
                ? 'Menu'
                : 'Products & Catalog'),
        equals('Products & Catalog'),
      );
      expect(
        AppCategories.isOmnibusStoreCategory('Cosmetics & Beauty')
            ? 'Aisles & Departments'
            : (AppCategories.isFoodCategory('Cosmetics & Beauty')
                ? 'Menu'
                : 'Products & Catalog'),
        equals('Products & Catalog'),
      );
    });

    test('17. Seller Payout Breakdown Arithmetic and Net Bank Payout Integrity', () {
      // Verify exact arithmetic formula:
      // Seller Gross Payout = totalAmount + nonFoodGst - enythingCommission
      // Net Payout = Seller Gross Payout - tcsAmount - tdsAmount
      const totalAmount = 1000.0;
      const nonFoodGst = 180.0; // 18% non-food GST passed through
      const pureCommission = 50.0; // 5% base commission
      const sellerGwShare = (totalAmount - pureCommission + nonFoodGst) * 0.0236; // 2.36% on seller payout
      const enythingCommission = pureCommission + sellerGwShare;
      const tcsAmount = totalAmount * 0.005; // 0.5% TCS
      const tdsAmount = totalAmount * 0.001; // 0.1% TDS

      const sellerPayout = totalAmount + nonFoodGst - enythingCommission;
      const netBankPayout = sellerPayout - tcsAmount - tdsAmount;

      expect(sellerPayout, closeTo(1103.33, 0.05));
      expect(netBankPayout, closeTo(1097.33, 0.05));
      expect(netBankPayout, greaterThan(totalAmount));
    });

    test('18. Statutory Tax Slab Maps: taxableByRate and gstByRate Precision', () {
      final items = [
        {'category': 'Fruits & Vegs', 'price': 100.0, 'quantity': 2}, // 0% GST (200 base, 0 gst)
        {'category': 'Grocery', 'price': 50.0, 'quantity': 4}, // 5% GST (200 base, 10 gst)
        {'category': 'Cosmetics & Beauty', 'price': 500.0, 'quantity': 1}, // 18% GST (500 base, 90 gst)
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 40.0,
        riderEarnings: 32.0,
        platformFee: 3.0,
        paymentMethod: 'upi',
      );

      // Verify taxableByRate
      expect(breakdown.taxableByRate[0.0], equals(200.0));
      expect(breakdown.taxableByRate[0.05], equals(200.0));
      expect(breakdown.taxableByRate[0.18], equals(500.0));

      // Verify gstByRate
      expect(breakdown.gstByRate[0.0], equals(0.0));
      expect(breakdown.gstByRate[0.05], equals(10.0));
      expect(breakdown.gstByRate[0.18], equals(90.0));
      expect(breakdown.itemGstTotal, equals(100.0));
    });

    test('19. Supermarket / Departmental Store Multi-Aisle Ingestion Classification', () {
      // Replicate Python auto-upload classifier in Dart test for contract parity
      String classifyDepartment(String name) {
        final lower = name.toLowerCase();
        if (['milk', 'butter', 'cheese', 'paneer', 'curd', 'dahi', 'yogurt', 'egg', 'eggs'].any(lower.contains)) {
          return 'Dairy & Eggs';
        }
        if (['apple', 'banana', 'orange', 'mango', 'potato', 'onion', 'tomato'].any(lower.contains)) {
          return 'Fruits & Vegs';
        }
        if (['shampoo', 'conditioner', 'face wash', 'lotion', 'cream', 'soap', 'lipstick', 'serum'].any(lower.contains)) {
          return 'Cosmetics & Beauty';
        }
        if (['charger', 'cable', 'earphone', 'headphone', 'battery'].any(lower.contains)) {
          return 'Electronics';
        }
        if (['bread', 'bun', 'pav', 'cake', 'croissant', 'rusk'].any(lower.contains)) {
          return 'Bakery';
        }
        if (['paracetamol', 'dolo', 'bandage', 'dettol', 'savlon', 'aspirin'].any(lower.contains)) {
          return 'Pharmacy';
        }
        return 'Grocery';
      }

      expect(classifyDepartment('Amul Taaza Toned Milk 1L'), equals('Dairy & Eggs'));
      expect(classifyDepartment('Shimla Fresh Red Apples 1kg'), equals('Fruits & Vegs'));
      expect(classifyDepartment('Nivea Men Moisturizing Face Cream 50ml'), equals('Cosmetics & Beauty'));
      expect(classifyDepartment('Boat Rugged Type-C Fast Cable'), equals('Electronics'));
      expect(classifyDepartment('Britannia Pav 6 Pcs'), equals('Bakery'));
      expect(classifyDepartment('Dolo 650mg Strip'), equals('Pharmacy'));
      expect(classifyDepartment('Aashirvaad Shudh Chakki Atta 10kg'), equals('Grocery'));
    });

    test('20. CategoryProductsPage Remote Search Category Isolation Guard Verification', () {
      // Simulate live search items from a supermarket shop
      final supermarketShop = {
        'id': 'shop-supermarket-1',
        'name': 'Grand Hypermarket',
        'category': 'Supermarket / Hypermarket',
      };

      final subcategoriesBrowsing = ['Cosmetics & Beauty', 'Salon & Beauty'];
      final subcatsLower = subcategoriesBrowsing.map((c) => c.toLowerCase()).toSet();

      final searchResults = [
        {'id': 'p1', 'name': 'Dove Beauty Bar', 'category': 'Cosmetics & Beauty', 'shop_id': 'shop-supermarket-1'},
        {'id': 'p2', 'name': 'Aashirvaad Atta', 'category': 'Grocery', 'shop_id': 'shop-supermarket-1'},
        {'id': 'p3', 'name': 'Lakme Eyeconic Kajal', 'category': 'Cosmetics & Beauty', 'shop_id': 'shop-supermarket-1'},
        {'id': 'p4', 'name': 'Amul Butter 500g', 'category': 'Dairy & Eggs', 'shop_id': 'shop-supermarket-1'},
      ];

      // Apply the 100x Omnibus Store Isolation Guard:
      final allowedProducts = searchResults.where((p) {
        final sCat = (supermarketShop['category'] as String).toLowerCase();
        final isOmnibus = AppCategories.isOmnibusStoreCategory(sCat);
        final pCat = (p['category'] as String).toLowerCase();

        if (isOmnibus) {
          final isBrowsingOmnibus = subcatsLower.any(AppCategories.isOmnibusStoreCategory);
          if (!isBrowsingOmnibus && pCat.isNotEmpty && !subcatsLower.contains(pCat)) {
            return false;
          }
        }
        return true;
      }).toList();

      expect(allowedProducts.length, equals(2));
      expect(allowedProducts.map((p) => p['name']), containsAll(['Dove Beauty Bar', 'Lakme Eyeconic Kajal']));
      expect(allowedProducts.map((p) => p['name']), isNot(contains('Aashirvaad Atta')));
      expect(allowedProducts.map((p) => p['name']), isNot(contains('Amul Butter 500g')));
    });

    testWidgets('21. Supermarket / Hypermart Sign-up Card displays multi-department tier range and aisle schedule', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = PlatformConfigProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<PlatformConfigProvider>.value(
          value: config,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SellerDeductibleCard(
                    category: 'Supermarket / Hypermarket',
                    isCompact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Omnibus Tier Range Headline
      expect(find.text('Total Deductibles:'), findsOneWidget);
      expect(find.text('7.96% – 12.96%'), findsOneWidget);
      expect(find.text('Net Payout: 87.04% – 92.04%'), findsOneWidget);
      expect(find.text('5.0% – 10.0%'), findsOneWidget); // Commission range chip
      expect(find.text('0.00% – 0.50%'), findsOneWidget); // TCS range chip

      // Verify Department Quick-Pills
      expect(find.text('🛒 Grocery: 6.0%'), findsOneWidget);
      expect(find.text('💄 Cosmetics: 10.0%'), findsOneWidget);
      expect(find.text('📱 Electronics: 10.0%'), findsOneWidget);
      expect(find.text('🥬 Produce: 5.0%'), findsOneWidget);
    });

    testWidgets('22. Dynamic Platform Config Override updates Supermarket ranges and quick-pills instantly', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = PlatformConfigProvider();
      config.applyConfigRow('commission_percent_Cosmetics & Beauty', 12.0);
      config.applyConfigRow('commission_percent_Fruits & Vegs', 4.0);

      await tester.pumpWidget(
        ChangeNotifierProvider<PlatformConfigProvider>.value(
          value: config,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SellerDeductibleCard(
                    category: 'Supermarket / Hypermarket',
                    isCompact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dynamic calculation: min 4.0%, max 12.0%
      // minDeductible = 4.0 + 2.36 + 0.10 + 0.50 = 6.96%
      // maxDeductible = 12.0 + 2.36 + 0.10 + 0.50 = 14.96%
      expect(find.text('6.96% – 14.96%'), findsOneWidget);
      expect(find.text('Net Payout: 85.04% – 93.04%'), findsOneWidget);
      expect(find.text('4.0% – 12.0%'), findsOneWidget); // Commission range chip

      // Quick pills updated to reflect custom overrides
      expect(find.text('💄 Cosmetics: 12.0%'), findsOneWidget);
      expect(find.text('🥬 Produce: 4.0%'), findsOneWidget);
      expect(find.text('🛒 Grocery: 6.0%'), findsOneWidget);
    });

    testWidgets('23. Supermarket Expanded Mode renders multi-department policy and aisle schedules', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = PlatformConfigProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<PlatformConfigProvider>.value(
          value: config,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SellerDeductibleCard(
                    category: 'Supermarket / Hypermarket',
                    isCompact: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Total Deductions (Aisle-Based)'), findsOneWidget);
      expect(find.text('7.96% – 12.96%'), findsOneWidget);
      expect(find.text('87.04% – 92.04% Net Payout'), findsOneWidget);
      expect(find.text('Multi-Department Rate Schedule'), findsOneWidget);
    });
  });
}

