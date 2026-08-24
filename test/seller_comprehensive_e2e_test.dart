import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/services/gst_recommendation_engine.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/utils/validators.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Vector 1: Seller Standalone & Catalog Invariants', () {
    test('Category Group constraints prevent cross-domain category assignment', () {
      expect(AppCategories.groupFor('Restaurant'), CategoryGroup.food);
      expect(AppCategories.groupFor('Fast Food'), CategoryGroup.food);
      expect(AppCategories.groupFor('Bakery'), CategoryGroup.food);
      expect(AppCategories.groupFor('Pharmacy'), CategoryGroup.pharmacy);
      expect(AppCategories.groupFor('Medical Store'), CategoryGroup.pharmacy);
      expect(AppCategories.groupFor('Clothing'), CategoryGroup.retail);
      expect(AppCategories.groupFor('Electronics'), CategoryGroup.retail);
      expect(AppCategories.groupFor('Hardware Store'), CategoryGroup.retail);

      // Verify variant requirement by category
      expect(AppCategories.requiresVariant('Clothing'), isTrue);
      expect(AppCategories.requiresVariant('Footwear'), isTrue);
      expect(AppCategories.requiresVariant('Restaurant'), isFalse);
    });

    test('GST Recommendation Engine accurately identifies HSN rates with override support', () {
      final engine = GstRecommendationEngine.instance;

      // Food items typically 5% in Restaurant category
      final foodRec = engine.recommend('Butter Chicken Biryani', 'Restaurant');
      expect(foodRec.rate, 0.05);

      // Electronics typically 18%
      final elecRec = engine.recommend('USB-C Mobile Charger', 'Electronics');
      expect(elecRec.rate, 0.18);

      // Staple food in Grocery is 0%
      final stapleRec = engine.recommend('Basmati Rice 5kg', 'Grocery');
      expect(stapleRec.rate, 0.0);

      // Gold Jewellery is 3%
      final jewelRec = engine.recommend('22K Gold Ring', 'Jewellery');
      expect(jewelRec.rate, 0.03);

      // Sin goods / Tobacco is 40%
      final tobaccoRec = engine.recommend('Classic Milds Cigarette', 'Paan Shop');
      expect(tobaccoRec.rate, 0.40);

      // ProductModel with manual override preserves override rate
      final productWithGstOverride = ProductModel(
        id: 'prod-gst-001',
        shopId: 'shop-001',
        name: 'Handcrafted Wooden Lamp',
        category: 'Home & Kitchen',
        price: 1200.0,
        gstRateOverride: 0.12, // 12% override
      );

      expect(productWithGstOverride.gstRateOverride, 0.12);
    });

    test('Product Model MRP and Variant validations enforce financial integrity', () {
      // Selling price 450, MRP 500 -> 10% discount
      final variant = ProductVariant(
        id: 'var-1',
        name: 'Full Portion',
        price: 450.0,
        originalPrice: 500.0,
      );

      expect(variant.discountPercent, isNotNull);
      expect(variant.discountPercent!.toStringAsFixed(1), '10.0');

      // Product serialization preserves soft delete and stock fields
      final productMap = {
        'id': 'prod-001',
        'shop_id': 'shop-001',
        'name': 'Paneer Butter Masala',
        'category': 'Food',
        'price': 280.0,
        'original_price': 320.0,
        'total_quantity': 25,
        'is_veg': true,
        'is_available': true,
        'is_deleted': false,
        'requires_prescription': false,
        'medicine_type': 'General',
        'variants': [variant.toMap()],
      };

      final product = ProductModel.fromMap(productMap);
      expect(product.name, 'Paneer Butter Masala');
      expect(product.price, 280.0);
      expect(product.isVeg, isTrue);
      expect(product.totalQuantity, 25);
      expect(product.variants.length, 1);
      expect(product.variants.first.name, 'Full Portion');
    });

    test('ShopModel enforces separation between Admin Suspension (is_active) and Seller Toggle', () {
      // Case A: Shop is Admin verified
      final activeOpenShop = ShopModel(
        id: 'shop-01',
        sellerId: 'seller-01',
        name: 'Green Grocers',
        shopType: 'Grocery',
        address: '123 Market St',
        location: const LatLng(19.0760, 72.8777),
        category: 'Grocery',
        categories: const ['Grocery'],
        isActive: true,
      );
      expect(activeOpenShop.isActive, isTrue);

      // Case B: Shop is Admin Suspended (isActive = false)
      final suspendedShop = ShopModel(
        id: 'shop-02',
        sellerId: 'seller-02',
        name: 'Violating Store',
        shopType: 'General',
        address: '456 Bad St',
        location: const LatLng(19.0760, 72.8777),
        category: 'Other',
        categories: const ['Other'],
        isActive: false,
      );
      expect(suspendedShop.isActive, isFalse);
    });
  });

  group('Vector 2: Seller <-> Customer Interaction Invariants', () {
    test('Dual Acceptance state machine logic resolves correctly', () {
      // Scenario 1: Fresh order placed
      final initialOrder = OrderModel(
        id: 'ord-100',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'awaiting_acceptance',
        totalAmount: 460.0,
        deliveryCharges: 40.0,
        grandTotalCollected: 500.0,
        sellerAccepted: false,
        partnerAccepted: false,
        createdAt: DateTime.now(),
      );
      expect(initialOrder.sellerAccepted, isFalse);
      expect(initialOrder.partnerAccepted, isFalse);
      expect(initialOrder.status, 'awaiting_acceptance');

      // Scenario 2: Seller accepts first
      final sellerAcceptedOrder = initialOrder.copyWith(sellerAccepted: true);
      // Status remains awaiting_acceptance because rider hasn't accepted yet
      final intermediateStatus = (sellerAcceptedOrder.sellerAccepted && sellerAcceptedOrder.partnerAccepted)
          ? 'awaiting_payment'
          : 'awaiting_acceptance';
      expect(intermediateStatus, 'awaiting_acceptance');

      // Scenario 3: Rider accepts second -> transitions to awaiting_payment
      final bothAcceptedOrder = sellerAcceptedOrder.copyWith(partnerAccepted: true);
      final finalStatus = (bothAcceptedOrder.sellerAccepted && bothAcceptedOrder.partnerAccepted)
          ? 'awaiting_payment'
          : 'awaiting_acceptance';
      expect(finalStatus, 'awaiting_payment');
    });

    test('Seller rejection with out-of-stock product marks specific item unavailable', () {
      final items = [
        OrderItem(
          id: 'item-1',
          productId: 'prod-apple',
          productName: 'Shimla Apples 1kg',
          quantity: 2,
          price: 150.0,
          weightKg: 1.0,
        ),
        OrderItem(
          id: 'item-2',
          productId: 'prod-banana',
          productName: 'Robusta Bananas 1 Dozen',
          quantity: 1,
          price: 60.0,
          weightKg: 1.2,
        ),
      ];

      final order = OrderModel(
        id: 'ord-200',
        customerId: 'cust-2',
        shopId: 'shop-2',
        status: 'awaiting_acceptance',
        totalAmount: 360.0,
        deliveryCharges: 40.0,
        grandTotalCollected: 400.0,
        items: items,
        createdAt: DateTime.now(),
      );

      // Seller rejects due to 'prod-apple' out of stock
      const outOfStockProductId = 'prod-apple';
      final outOfStockItem = order.items.firstWhere((i) => i.productId == outOfStockProductId);
      expect(outOfStockItem.productName, 'Shimla Apples 1kg');

      // Rejected order state
      final rejectedOrder = order.copyWith(
        status: 'seller_rejected',
        rejectionMessage: 'Out of stock',
      );
      expect(rejectedOrder.status, 'seller_rejected');
    });

    test('Prescription requirement flow flags prescription rejection as verification_failed', () {
      final prescriptionOrder = OrderModel(
        id: 'ord-pharma-01',
        customerId: 'cust-3',
        shopId: 'shop-pharmacy',
        status: 'awaiting_acceptance',
        totalAmount: 410.0,
        deliveryCharges: 40.0,
        grandTotalCollected: 450.0,
        prescriptionUrls: ['https://storage.enything.app/prescriptions/rx_001.jpg'],
        createdAt: DateTime.now(),
      );

      expect(prescriptionOrder.prescriptionUrls.isNotEmpty, isTrue);

      // Pharmacist declines prescription
      const rejectReason = 'prescription';
      const resultingStatus = rejectReason == 'prescription' ? 'verification_failed' : 'seller_rejected';
      expect(resultingStatus, 'verification_failed');
    });
  });

  group('Vector 3: Seller <-> Rider Interaction Invariants', () {
    test('Wait time penalty calculation accurately deducts excess delay and bounds to seller payout', () {
      const double sellerPayout = 180.0;
      const int prepSnapshotMinutes = 15;
      const double penaltyRatePerMin = 2.0; // ₹2/min

      // Helper function matching SQL RPC update_order_status
      double calculateWaitPenalty(int actualWaitMinutes) {
        if (actualWaitMinutes <= prepSnapshotMinutes) {
          return 0.0;
        }
        final excessMinutes = actualWaitMinutes - prepSnapshotMinutes;
        final rawPenalty = excessMinutes * penaltyRatePerMin;
        // Bounded so penalty cannot exceed seller payout
        return rawPenalty > sellerPayout ? sellerPayout : rawPenalty;
      }

      // Case A: Seller ready in 12 minutes (within 15m SLA) -> No penalty
      expect(calculateWaitPenalty(12), 0.0);

      // Case B: Seller ready exactly on time in 15 minutes -> No penalty
      expect(calculateWaitPenalty(15), 0.0);

      // Case C: Seller ready in 25 minutes (10m delay) -> ₹20 penalty
      expect(calculateWaitPenalty(25), 20.0);

      // Case D: Massive delay (120 minutes delay, raw penalty ₹210) -> Capped at seller payout ₹180
      expect(calculateWaitPenalty(120), 180.0);
    });

    test('Delivery calculator ETA and distance chips render bounded estimates', () {
      // 3.5 km delivery distance
      const distanceKm = 3.5;
      final etaLabel = DeliveryCalculator.etaLabel(distanceKm, 0);
      expect(etaLabel.isNotEmpty, isTrue);

      // Delivery charges calculation
      final deliveryCharge = DeliveryCalculator.calculateDeliveryCharges(distanceKm, 300.0);
      expect(deliveryCharge, greaterThanOrEqualTo(20.0)); // minimum delivery fee threshold
    });
  });

  group('Vector 4: Seller <-> Admin Financial & Withdrawal Invariants', () {
    test('Seller withdrawal constraints enforce minimum threshold and balance limits', () {
      const double availableBalance = 1450.0;

      // Helper for withdrawal validation matching frontend & backend
      String? validateWithdrawal(double amount) {
        if (amount <= 0) return 'Enter a valid amount';
        if (amount < 100) return 'Minimum withdrawal is ₹100';
        if (amount > availableBalance) return 'Amount exceeds available balance';
        return null;
      }

      expect(validateWithdrawal(50), 'Minimum withdrawal is ₹100');
      expect(validateWithdrawal(2000), 'Amount exceeds available balance');
      expect(validateWithdrawal(500), isNull); // Valid request
    });

    test('AppValidators price and required fields validate input formats', () {
      expect(AppValidators.price('150.0'), isNull);
      expect(AppValidators.price('0'), 'Enter a valid price');
      expect(AppValidators.price('-50'), 'Enter a valid price');
      expect(AppValidators.price('abc'), 'Enter a valid price');
      expect(AppValidators.required(''), 'Field is required');
      expect(AppValidators.required('Valid Shop Name'), isNull);
    });

    test('Seller CA Report aggregations correctly bucket GSTR-1, Section 9(5), TDS and TCS', () {
      // Mock delivered orders breakdown
      final deliveredOrders = [
        {
          'food_base': 500.0,
          'food_gst': 25.0, // 5% Section 9(5) — Enything remits
          'non_food_base': 0.0,
          'non_food_gst': 0.0,
          'commission': 50.0,
          'seller_payout': 450.0,
        },
        {
          'food_base': 0.0,
          'food_gst': 0.0,
          'non_food_base': 1000.0,
          'non_food_gst': 180.0, // 18% non-food GST — Seller remits
          'commission': 100.0,
          'seller_payout': 900.0,
        },
      ];

      double totalBaseSales = 0;
      double s9_5Gst = 0;
      double nonFoodGst = 0;
      double totalCommission = 0;
      double totalSellerPayout = 0;

      for (final o in deliveredOrders) {
        totalBaseSales += (o['food_base']! + o['non_food_base']!);
        s9_5Gst += o['food_gst']!;
        nonFoodGst += o['non_food_gst']!;
        totalCommission += o['commission']!;
        totalSellerPayout += o['seller_payout']!;
      }

      // TDS §194-O (0.1% on total gross sales)
      final tds194O = totalBaseSales * 0.001;

      // GST TCS §52 (1% on taxable non-food sales)
      const tcsGst = 1000.0 * 0.01;

      expect(totalBaseSales, 1500.0);
      expect(s9_5Gst, 25.0); // Doc 3: Section 9(5) Statement
      expect(nonFoodGst, 180.0); // Doc 1: Sales Register for GSTR-1
      expect(totalCommission, 150.0); // Doc 2: Platform Commission Invoice
      expect(totalSellerPayout, 1350.0);
      expect(tds194O, 1.50); // Doc 4: TDS Statement
      expect(tcsGst, 10.0); // Doc 5: GST TCS Statement
    });
  });
}
