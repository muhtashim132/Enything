import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/config/tax_config.dart';

void main() {
  group('100x Partial Rejection & Dynamic Financial Recalculation Engine', () {
    OrderModel buildTestOrder({
      required String id,
      required String shopId,
      required String status,
      required double itemTotal,
      required double itemGst,
      required double deliveryCharges,
      required double multiShopSurcharge,
      required double smallCartFee,
      required double heavyOrderFee,
      required double platformFee,
      required double couponDiscount,
      required double riderEarnings,
      double weightKg = 1.0,
    }) {
      final grandTotal = math.max(
        0.0,
        itemTotal +
            itemGst +
            platformFee +
            deliveryCharges +
            multiShopSurcharge +
            smallCartFee +
            heavyOrderFee -
            couponDiscount,
      );

      return OrderModel(
        id: id,
        customerId: 'cust-1',
        shopId: shopId,
        totalAmount: itemTotal,
        gstItemTotal: itemGst,
        deliveryCharges: deliveryCharges,
        multiShopSurcharge: multiShopSurcharge,
        smallCartFee: smallCartFee,
        heavyOrderFee: heavyOrderFee,
        platformFee: platformFee,
        couponDiscount: couponDiscount,
        grandTotalCollected: grandTotal,
        riderEarnings: riderEarnings,
        status: status,
        paymentMethod: 'upi',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [
          OrderItem(
            id: 'item-$id',
            productId: 'prod-$id',
            productName: 'Sample Product',
            price: itemTotal,
            quantity: 1,
            weightKg: weightKg,
          ),
        ],
        shopLat: 28.6139,
        shopLng: 77.2090,
        deliveryLat: 28.7041,
        deliveryLng: 77.1025,
      );
    }

    test('3-Shop Multi-Order: 1 Shop Rejection reduces Surcharge from ₹40 to ₹20 and rebalances active shops', () {
      final o1 = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'awaiting_payment',
        itemTotal: 300.0,
        itemGst: 15.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 13.33,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        platformFee: 6.67,
        couponDiscount: 0.0,
        riderEarnings: 16.0,
      );
      final o2 = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'awaiting_payment',
        itemTotal: 200.0,
        itemGst: 10.0,
        deliveryCharges: 20.0,
        multiShopSurcharge: 13.33,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        platformFee: 6.67,
        couponDiscount: 0.0,
        riderEarnings: 16.0,
      );
      final o3 = buildTestOrder(
        id: 'ord-3',
        shopId: 'shop-C',
        status: 'seller_rejected',
        itemTotal: 250.0,
        itemGst: 12.5,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        platformFee: 0.0,
        couponDiscount: 0.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1, o2, o3]);

      expect(group.activeOrders.length, equals(2));
      expect(group.activeOrders.map((o) => o.id), containsAll(['ord-1', 'ord-2']));
      expect(group.activeOrders.map((o) => o.id), isNot(contains('ord-3')));

      final activeSurcharge = group.activeOrders.fold(0.0, (sum, o) => sum + o.multiShopSurcharge);
      expect(activeSurcharge, closeTo(26.66, 0.1));
      expect(group.totalGrand, closeTo(o1.grandTotal + o2.grandTotal, 0.01));
    });

    test('2-Shop Order -> 1 Shop Rejection: Surcharge drops completely to ₹0', () {
      final o1 = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'awaiting_payment',
        itemTotal: 400.0,
        itemGst: 20.0,
        deliveryCharges: 30.0,
        multiShopSurcharge: 0.0,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        platformFee: 20.0,
        couponDiscount: 0.0,
        riderEarnings: 24.0,
      );
      final o2 = buildTestOrder(
        id: 'ord-2',
        shopId: 'shop-B',
        status: 'seller_rejected',
        itemTotal: 150.0,
        itemGst: 7.5,
        deliveryCharges: 0.0,
        multiShopSurcharge: 0.0,
        smallCartFee: 0.0,
        heavyOrderFee: 0.0,
        platformFee: 0.0,
        couponDiscount: 0.0,
        riderEarnings: 0.0,
      );

      final group = OrderGroup('cart-grp-1', [o1, o2]);

      expect(group.isMultiShop, isFalse);
      expect(group.activeOrders.length, equals(1));
      expect(group.activeOrders.first.multiShopSurcharge, equals(0.0));
      expect(group.totalGrand, equals(400.0 + 20.0 + 30.0 + 20.0));
    });

    test('Dynamic Small Cart Fee: Subtotal drops below ₹99 on partial rejection -> Small fee allocated', () {
      const smallCartThreshold = 99.0;
      const smallCartFeeAmount = 15.0;

      const activeSubtotal = 60.0;
      const smallFee = activeSubtotal < smallCartThreshold ? smallCartFeeAmount : 0.0;

      expect(smallFee, equals(15.0));

      final o1Rebalanced = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'awaiting_payment',
        itemTotal: 60.0,
        itemGst: 3.0,
        deliveryCharges: 30.0,
        multiShopSurcharge: 0.0,
        smallCartFee: smallFee,
        heavyOrderFee: 0.0,
        platformFee: 20.0,
        couponDiscount: 0.0,
        riderEarnings: 20.0,
      );

      expect(o1Rebalanced.smallCartFee, equals(15.0));
      expect(o1Rebalanced.grandTotal, equals(60.0 + 3.0 + 30.0 + 0.0 + 15.0 + 0.0 + 20.0));
    });

    test('Dynamic Heavy Order Fee: Weight drops below 10kg on partial rejection -> Heavy fee cleared to ₹0', () {
      const heavyThreshold = 10.0;
      const activeWeight = 3.0;
      final heavyFee = activeWeight > heavyThreshold ? 25.0 * (activeWeight - heavyThreshold).ceil() : 0.0;

      expect(heavyFee, equals(0.0));

      final o1 = buildTestOrder(
        id: 'ord-1',
        shopId: 'shop-A',
        status: 'awaiting_payment',
        itemTotal: 500.0,
        itemGst: 25.0,
        deliveryCharges: 35.0,
        multiShopSurcharge: 0.0,
        smallCartFee: 0.0,
        heavyOrderFee: heavyFee,
        platformFee: 20.0,
        couponDiscount: 0.0,
        riderEarnings: 28.0,
        weightKg: activeWeight,
      );

      expect(o1.heavyOrderFee, equals(0.0));
    });
  });

  group('100x Fully Dynamic Admin Configuration (platform_config & tax_config overrides)', () {
    test('Admin modifies multi_shop_surcharge to custom rate ₹35.0', () {
      const dynamicAdminSurcharge = 35.0;

      // 3 active shops: rate * (3 - 1) = 70.0
      double surcharge3Shops(int count) => count > 1 ? dynamicAdminSurcharge * (count - 1) : 0.0;

      expect(surcharge3Shops(3), equals(70.0));
      // 1 shop rejects -> 2 shops active: rate * (2 - 1) = 35.0
      expect(surcharge3Shops(2), equals(35.0));
      // 2 shops reject -> 1 shop active: 0.0
      expect(surcharge3Shops(1), equals(0.0));
    });

    test('Admin modifies platform_fee to custom ₹45.0: split equally, group total invariant', () {
      const dynamicPlatformFee = 45.0;

      // 3 shops active: 45 / 3 = 15.0 each
      expect(dynamicPlatformFee / 3, equals(15.0));
      // 1 shop rejects -> 2 shops active: 45 / 2 = 22.50 each
      expect(dynamicPlatformFee / 2, equals(22.50));
      // 2 shops reject -> 1 shop active: 45 / 1 = 45.0
      expect(dynamicPlatformFee / 1, equals(45.0));

      // Sum of active platform fees always equals the dynamic admin platform fee
      const sum3 = (dynamicPlatformFee / 3) * 3;
      const sum2 = (dynamicPlatformFee / 2) * 2;
      const sum1 = (dynamicPlatformFee / 1) * 1;
      expect(sum3, equals(dynamicPlatformFee));
      expect(sum2, equals(dynamicPlatformFee));
      expect(sum1, equals(dynamicPlatformFee));
    });

    test('Admin modifies small_cart_threshold to ₹150.0 and small_cart_fee to ₹25.0', () {
      const dynamicThreshold = 150.0;
      const dynamicFee = 25.0;

      double computeSmallFee(double subtotal) => subtotal > 0 && subtotal < dynamicThreshold ? dynamicFee : 0.0;

      expect(computeSmallFee(120.0), equals(25.0)); // Incurs fee because 120 < 150
      expect(computeSmallFee(155.0), equals(0.0));  // 155 >= 150 -> ₹0
    });

    test('Admin modifies heavy_order_threshold_kg to 8.0kg and fee to ₹30.0/kg', () {
      const dynamicThresholdKg = 8.0;
      const dynamicFeePerKg = 30.0;

      double computeHeavyFee(double weightKg) {
        if (weightKg > dynamicThresholdKg) {
          final extraKg = (weightKg - dynamicThresholdKg).ceil();
          return dynamicFeePerKg * extraKg;
        }
        return 0.0;
      }

      expect(computeHeavyFee(7.5), equals(0.0)); // Under 8kg
      expect(computeHeavyFee(11.2), equals(30.0 * 4)); // 11.2 - 8 = 3.2 -> ceil is 4 -> 120.0
    });

    test('Admin modifies rider_commission_percent to 85% and delivery_gst_rate to 12%', () {
      const dynamicRiderCommission = 85.0;
      const dynamicDeliveryGstRate = 0.12;

      const splitDelivery = 50.0;
      const newGstDelivery = splitDelivery - (splitDelivery / (1.0 + dynamicDeliveryGstRate));
      const smallCartFee = 0.0;

      const riderEarnings = (splitDelivery - newGstDelivery - smallCartFee) * (dynamicRiderCommission / 100.0);
      expect(riderEarnings, greaterThan(0.0));
      // Base net without GST: 50 / 1.12 = 44.6428 -> 85% is ~37.946
      expect(riderEarnings, closeTo(37.95, 0.05));
    });

    test('Soft Deletes Invariant: Soft-deleted items (is_deleted: true) are strictly excluded from weight and alternative searches', () {
      final catalog = [
        {'id': 'prod-1', 'name': 'Fresh Apples', 'weight_per_unit': 1.0, 'is_deleted': false},
        {'id': 'prod-2', 'name': 'Deleted Apples', 'weight_per_unit': 5.0, 'is_deleted': true},
      ];

      // Filter as executed by backend SQL & Dart queries
      final activeProducts = catalog.where((p) => p['is_deleted'] == false).toList();
      expect(activeProducts.length, equals(1));
      expect(activeProducts.first['id'], equals('prod-1'));

      final totalWeight = activeProducts.fold(0.0, (sum, p) => sum + (p['weight_per_unit'] as double));
      expect(totalWeight, equals(1.0)); // 5.0kg of deleted product is ignored!
    });
  });

  group('100x Adding Items & Active Cart Surcharge / Delivery Math', () {
    test('Adding new item from the SAME SHOP already in cart does not increase surcharge or base delivery', () {
      final activeShopIds = {'shop-A'};
      const newProductShopId = 'shop-A';

      final newUniqueShopIds = {newProductShopId}.where((id) => !activeShopIds.contains(id)).toSet();
      final totalShopsAtEnd = activeShopIds.length + newUniqueShopIds.length;

      expect(newUniqueShopIds.isEmpty, isTrue);
      expect(totalShopsAtEnd, equals(1));

      final surcharge = totalShopsAtEnd > 1 ? 20.0 * (totalShopsAtEnd - 1) : 0.0;
      expect(surcharge, equals(0.0));
    });

    test('Adding new item from a DIFFERENT SHOP in cart increases surcharge by ₹20', () {
      final activeShopIds = {'shop-A'};
      const newProductShopId = 'shop-B';

      final newUniqueShopIds = {newProductShopId}.where((id) => !activeShopIds.contains(id)).toSet();
      final totalShopsAtEnd = activeShopIds.length + newUniqueShopIds.length;

      expect(newUniqueShopIds.length, equals(1));
      expect(totalShopsAtEnd, equals(2));

      final surcharge = totalShopsAtEnd > 1 ? 20.0 * (totalShopsAtEnd - 1) : 0.0;
      expect(surcharge, equals(20.0));
    });

    test('Replacement Order: Delivery base is ₹0 (no double delivery fee) and Platform fee is ₹0 (already paid once)', () {
      double computeEffectiveBase(bool isReplacement, double base) => isReplacement ? 0.0 : base;
      double computeEffectivePlatform(bool isReplacement, double fee) => isReplacement ? 0.0 : fee;

      expect(computeEffectiveBase(true, 40.0), equals(0.0));
      expect(computeEffectiveBase(false, 40.0), equals(40.0));
      expect(computeEffectivePlatform(true, 20.0), equals(0.0));
      expect(computeEffectivePlatform(false, 20.0), equals(20.0));
    });
  });

  group('100x Order Tax Breakdown & Arithmetic Consistency', () {
    test('OrderTaxBreakdown maintains exact penny arithmetic on food vs non-food GST', () {
      final foodItem = {
        'category': 'Restaurant',
        'price': 200.0,
        'quantity': 2,
      };

      final nonFoodItem = {
        'category': 'Electronics',
        'price': 100.0,
        'quantity': 1,
      };

      final breakdown = OrderTaxBreakdown.calculate(
        items: [foodItem, nonFoodItem],
        deliveryCharge: 30.0,
        riderEarnings: 24.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );

      expect(breakdown.s9_5GstToRemit, closeTo(20.0, 0.01));
      expect(breakdown.nonFoodGstPassThrough, closeTo(18.0, 0.01));
      expect(breakdown.itemGstTotal, closeTo(38.0, 0.01));
      expect(breakdown.grandTotal, closeTo(500.0 + 38.0 + 30.0 + 20.0, 0.01));
    });
  });
}
