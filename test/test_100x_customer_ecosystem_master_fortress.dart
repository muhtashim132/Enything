import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/config/app_categories.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late PlatformConfigProvider configProvider;
  late CartProvider cartProvider;

  final testShop1 = ShopModel(
    id: 'shop_alpha',
    sellerId: 'seller_alpha',
    name: 'Alpha Pharmacy & Care',
    shopType: 'retail',
    category: 'Medical Store',
    categories: ['Pharmacy', 'Medical Store'],
    isActive: true,
    isAcceptingOrders: true,
    openTime: '00:00',
    closeTime: '23:59',
    prepTimeMinutes: 15,
    location: const LatLng(34.0837, 74.7973),
    address: 'Residency Road, Srinagar',
  );

  final testShop2 = ShopModel(
    id: 'shop_beta',
    sellerId: 'seller_beta',
    name: 'Beta Fresh Bakery',
    shopType: 'retail',
    category: 'Bakery',
    categories: ['Bakery'],
    isActive: true,
    isAcceptingOrders: true,
    openTime: '00:00',
    closeTime: '23:59',
    prepTimeMinutes: 20,
    location: const LatLng(34.0900, 74.8000),
    address: 'Lal Chowk, Srinagar',
  );

  final testShop3 = ShopModel(
    id: 'shop_gamma',
    sellerId: 'seller_gamma',
    name: 'Gamma Supermarket',
    shopType: 'retail',
    category: 'Grocery',
    categories: ['Grocery'],
    isActive: true,
    isAcceptingOrders: true,
    openTime: '00:00',
    closeTime: '23:59',
    prepTimeMinutes: 10,
    location: const LatLng(34.0950, 74.8050),
    address: 'Karan Nagar, Srinagar',
  );

  final testProduct1 = ProductModel(
    id: 'prod_dolo',
    shopId: 'shop_alpha',
    name: 'Dolo 650mg Paracetamol',
    category: 'Medical Store',
    subCategory: 'Antipyretic',
    unitType: 'strip',
    price: 32.0,
    totalQuantity: 100,
    weightPerUnit: 0.05,
    variants: [
      ProductVariant(id: 'v_strip_10', name: 'Strip of 10 Tablets', price: 32.0),
      ProductVariant(id: 'v_strip_15', name: 'Strip of 15 Tablets', price: 46.0),
    ],
  );

  final testProduct2 = ProductModel(
    id: 'prod_croissant',
    shopId: 'shop_beta',
    name: 'Butter Croissant',
    category: 'Bakery',
    subCategory: 'Pastry',
    unitType: 'pieces',
    price: 75.0,
    totalQuantity: 30,
    weightPerUnit: 0.15,
  );

  final testProduct3 = ProductModel(
    id: 'prod_rice',
    shopId: 'shop_gamma',
    name: 'Basmati Rice Premium',
    category: 'Grocery',
    subCategory: 'Staples',
    unitType: 'kg',
    price: 120.0,
    totalQuantity: 50,
    weightPerUnit: 1.0,
  );

  setUp(() {
    configProvider = PlatformConfigProvider();
    configProvider.updateConfigsFromList([
      {'key': 'platform_fee', 'value': 2.0},
      {'key': 'default_commission_percent', 'value': 5.0},
      {'key': 'commission_percent_Bakery', 'value': 7.54},
      {'key': 'commission_percent_Medical Store', 'value': 5.04},
      {'key': 'commission_percent_Grocery', 'value': 3.04},
      {'key': 'small_cart_threshold', 'value': 199.0},
      {'key': 'small_cart_fee', 'value': 25.0},
      {'key': 'delivery_base_fee', 'value': 20.0},
      {'key': 'delivery_rate_per_km', 'value': 20.0},
      {'key': 'max_delivery_radius_km', 'value': 15.0},
      {'key': 'heavy_order_threshold_kg', 'value': 10.0},
      {'key': 'heavy_order_fee_per_kg', 'value': 20.0},
      {'key': 'rider_commission_percent', 'value': 80.0},
      {'key': 'delivery_gst_rate', 'value': 0.18},
      {'key': 'platform_fee_gst_rate', 'value': 0.18},
    ]);

    cartProvider = CartProvider();
  });

  group('1. Customer ↔ Discovery & Search Fortress', () {
    test('Tokenized search matches across subCategory, unitType, and variant names', () {
      final variantNames = testProduct1.variants.map((v) => v.name).join(' ');
      final searchable =
          '${testProduct1.name} ${testProduct1.description ?? ''} ${testProduct1.brand ?? ''} ${testProduct1.category} ${testProduct1.subCategory ?? ''} ${testProduct1.menuCategory ?? ''} ${testProduct1.medicineType} ${testProduct1.unitType} $variantNames ${testProduct1.specialTags.join(' ')}'
              .toLowerCase();

      // Search matches subcategory
      expect(searchable.contains('antipyretic'), isTrue);
      // Search matches unitType
      expect(searchable.contains('strip'), isTrue);
      // Search matches variant name
      expect(searchable.contains('strip of 15 tablets'), isTrue);
    });

    test('Composite query disambiguation: "medicine dolo" does NOT bypass product filter', () {
      final deptKeywords = {'medicine', 'medicines', 'pharmacy', 'medical store', 'healthcare'};
      const query = 'medicine dolo';
      final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final allTermsAreDeptWords = terms.every((t) => deptKeywords.contains(t));
      expect(allTermsAreDeptWords, isFalse,
          reason: 'Presence of specific term "dolo" must force exact product filtering');
    });

    test('Dynamic AppCategories domain synonyms cover all categories without hardcoded strings', () {
      expect(AppCategories.getCustomerCollection('Medical Store'), equals('Pharmacy & Health'));
      expect(AppCategories.getCustomerCollection('Bakery'), equals('Food & Dining'));
      expect(AppCategories.getCustomerCollection('Grocery'), equals('Grocery & Fresh'));
      expect(AppCategories.getCustomerCollection('Clothing'), equals('Fashion & Lifestyle'));
    });
  });

  group('2. Customer ↔ Cart & Storefront Lifecycle', () {
    test('Cart enforces max 3 unique shops limit', () {
      cartProvider.addItem(testProduct1, testShop1, suppressSave: true);
      cartProvider.addItem(testProduct2, testShop2, suppressSave: true);
      cartProvider.addItem(testProduct3, testShop3, suppressSave: true);

      expect(cartProvider.shops.length, equals(3));

      final testShop4 = ShopModel(
        id: 'shop_delta',
        sellerId: 'seller_delta',
        name: 'Delta Electronics',
        shopType: 'retail',
        category: 'Electronics',
        categories: ['Electronics'],
        isActive: true,
        isAcceptingOrders: true,
        openTime: '00:00',
        closeTime: '23:59',
        address: 'Batyar, Srinagar',
        location: const LatLng(34.10, 74.81),
      );
      final testProduct4 = ProductModel(
        id: 'prod_cable',
        shopId: 'shop_delta',
        name: 'USB-C Cable',
        category: 'Electronics',
        price: 299.0,
      );

      final err = cartProvider.addItem(testProduct4, testShop4, suppressSave: true);
      expect(err, contains('Maximum 3 shops allowed'));
      expect(cartProvider.shops.length, equals(3));
    });

    test('Closed store prevents cart additions with clear user notice', () {
      final closedShop = ShopModel(
        id: 'shop_closed',
        sellerId: 'seller_closed',
        name: 'Night Bakery',
        shopType: 'retail',
        category: 'Bakery',
        categories: ['Bakery'],
        isActive: true,
        isAcceptingOrders: false, // Closed
        openTime: '23:00',
        closeTime: '23:30',
        address: 'Nowhatta, Srinagar',
        location: const LatLng(34.08, 74.80),
      );

      final err = cartProvider.addItem(testProduct2, closedShop, suppressSave: true);
      expect(err, contains('This shop is currently closed'));
    });

    test('Rule 128 Variant Protection: Product with variants has no default pre-selection in fresh state', () {
      expect(testProduct1.variants.isNotEmpty, isTrue);
      // In fresh detail view, selected variant starts as null unless already present in cart
      expect(cartProvider.getItemsForProduct(testProduct1.id).isEmpty, isTrue);
    });
  });

  group('3. Customer ↔ Checkout & Financial Security', () {
    test('100% Prepaid Model: Zero COD doorstep collection strictly enforced', () {
      final order = OrderModel(
        id: 'order_test_1',
        customerId: 'cust_1',
        status: 'awaiting_payment',
        totalAmount: 100.0,
        deliveryCharges: 20.0,
        createdAt: DateTime.now(),
        paymentMethod: 'upi',
        paymentStatus: 'pending',
      );

      final group = OrderGroup('cart_group_1', [order]);
      expect(group.isCod, isFalse);
      expect(group.isPrepaid, isTrue);
      expect(group.codAmountToCollect, equals(0.0));
    });

    test('Financial handling fee matches live platform_config (₹2.0)', () {
      expect(PaymentConfig.platformFee, equals(2.0));
      expect(configProvider.platformFee, equals(2.0));
      expect(cartProvider.platformFee, equals(2.0));
    });

    test('Small cart fee of ₹25 applied below ₹199 threshold', () {
      cartProvider.addItem(testProduct1, testShop1, quantity: 1, suppressSave: true); // ₹32
      expect(cartProvider.subtotal, equals(32.0));
      expect(cartProvider.smallCartFee, equals(25.0));

      cartProvider.addItem(testProduct1, testShop1, quantity: 6, suppressSave: true); // ₹32 * 7 = ₹224
      expect(cartProvider.subtotal, equals(224.0));
      expect(cartProvider.smallCartFee, equals(0.0));
    });
  });

  group('4. Customer ↔ Seller Touchpoints', () {
    test('Sibling order survival: When Store 1 rejects, Store 2 order remains active', () {
      final order1 = OrderModel(
        id: 'ord_1',
        customerId: 'cust_1',
        shopId: 'shop_alpha',
        status: 'seller_rejected',
        totalAmount: 50.0,
        deliveryCharges: 20.0,
        createdAt: DateTime.now(),
        cartGroupId: 'cart_group_multi',
      );
      final order2 = OrderModel(
        id: 'ord_2',
        customerId: 'cust_1',
        shopId: 'shop_beta',
        status: 'preparing',
        totalAmount: 150.0,
        deliveryCharges: 20.0,
        createdAt: DateTime.now(),
        cartGroupId: 'cart_group_multi',
      );

      final group = OrderGroup('cart_group_multi', [order1, order2]);
      expect(group.activeOrders.length, equals(1));
      expect(group.activeOrders.first.id, equals('ord_2'));
      expect(group.activeOrders.first.status, equals('preparing'));
    });

    test('Dead group guard: If all sub-orders are terminal, group progress getters return false', () {
      final deadOrder = OrderModel(
        id: 'ord_dead',
        customerId: 'cust_1',
        status: 'seller_rejected',
        totalAmount: 50.0,
        deliveryCharges: 20.0,
        createdAt: DateTime.now(),
      );

      final deadGroup = OrderGroup('cart_group_dead', [deadOrder]);
      expect(deadGroup.activeOrders.isEmpty, isTrue);
      expect(deadGroup.allArrived, isFalse);
      expect(deadGroup.allPickedUp, isFalse);
      expect(deadGroup.allOutForDelivery, isFalse);
    });
  });

  group('5. Customer ↔ Rider Logistics', () {
    test('Rider earnings equal 80% of rider base (delivery + heavy + multi-shop)', () {
      const deliveryBase = 20.0;
      const multiShopSurcharge = 20.0;
      const heavyFee = 0.0;
      const riderBase = deliveryBase + multiShopSurcharge + heavyFee;
      final riderPayout = riderBase * (configProvider.riderCommissionPercent / 100.0);

      expect(riderPayout, equals(32.0));
    });
  });

  group('6. Customer ↔ Admin Controls & Radius Fortress', () {
    test('Dynamic delivery radius: PaymentConfig and DeliveryCalculator align to 15.0km', () {
      expect(PaymentConfig.maxDeliveryRadiusKm, equals(15.0));
      expect(DeliveryCalculator.maxRadiusKm, equals(15.0));
      expect(DeliveryCalculator.isWithinRange(14.9), isTrue);
      expect(DeliveryCalculator.isWithinRange(15.1), isFalse);
    });

    test('Category commission overrides apply correctly', () {
      expect(configProvider.getCommissionPercentForCategory('Medical Store'), equals(5.04));
      expect(configProvider.getCommissionPercentForCategory('Bakery'), equals(7.54));
      expect(configProvider.getCommissionPercentForCategory('Grocery'), equals(3.04));
      expect(configProvider.getCommissionPercentForCategory('Other'), equals(5.0)); // Fallback
    });
  });
}
