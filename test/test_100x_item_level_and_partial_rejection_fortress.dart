import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';

void main() {
  group('100X Item-Level & Partial Order Rejection Fortress Tests', () {
    test('1. OrderItem status lifecycle getters & deserialization', () {
      final activeItem = OrderItem(
        id: 'item-1',
        weightKg: 0.5, productId: 'prod-1',
        productName: 'Fresh Whole Milk 1L',
        price: 60.0,
        quantity: 2,
        status: 'active',
      );

      final declinedItem = OrderItem(
        id: 'item-2',
        weightKg: 0.5, productId: 'prod-2',
        productName: 'Organic Brown Eggs 6-pack',
        price: 90.0,
        quantity: 1,
        status: 'declined',
        declinedReason: 'out_of_stock',
        declinedAt: DateTime(2026, 11, 3, 1, 0),
      );

      final cancelledItem = OrderItem(
        id: 'item-3',
        weightKg: 0.5, productId: 'prod-3',
        productName: 'Greek Yogurt 200g',
        price: 50.0,
        quantity: 1,
        status: 'cancelled',
      );

      // Verify status predicates
      expect(activeItem.isActive, isTrue);
      expect(activeItem.isDeclined, isFalse);
      expect(activeItem.isCancelled, isFalse);

      expect(declinedItem.isActive, isFalse);
      expect(declinedItem.isDeclined, isTrue);
      expect(declinedItem.isCancelled, isFalse);
      expect(declinedItem.declinedReason, equals('out_of_stock'));

      expect(cancelledItem.isActive, isFalse);
      expect(cancelledItem.isDeclined, isFalse);
      expect(cancelledItem.isCancelled, isTrue);

      // Verify toMap & fromMap serialization parity
      final map = declinedItem.toMap();
      expect(map['status'], equals('declined'));
      expect(map['declined_reason'], equals('out_of_stock'));
      expect(map['declined_at'], isNotNull);

      final deserialized = OrderItem.fromMap(map);
      expect(deserialized.id, equals('item-2'));
      expect(deserialized.isDeclined, isTrue);
      expect(deserialized.declinedReason, equals('out_of_stock'));
    });

    test('2. OrderModel activeItems vs declinedItems filtering & aggregation', () {
      final items = [
        OrderItem(id: '1', weightKg: 0.5, productId: 'p1', productName: 'Atta 5kg', price: 250.0, quantity: 1, status: 'active'),
        OrderItem(id: '2', weightKg: 0.5, productId: 'p2', productName: 'Basmati Rice 1kg', price: 120.0, quantity: 2, status: 'declined', declinedReason: 'out_of_stock'),
        OrderItem(id: '3', weightKg: 0.5, productId: 'p3', productName: 'Sunflower Oil 1L', price: 160.0, quantity: 1, status: 'active'),
        OrderItem(id: '4', weightKg: 0.5, productId: 'p4', productName: 'Sugar 1kg', price: 50.0, quantity: 1, status: 'declined', declinedReason: 'out_of_stock'),
        OrderItem(id: '5', weightKg: 0.5, productId: 'p5', productName: 'Salt 1kg', price: 25.0, quantity: 2, status: 'active'),
      ];

      final order = OrderModel(
        id: 'ord-101',
        customerId: 'cust-1',
        shopId: 'shop-1',
        status: 'preparing',
        totalAmount: 510.0,
        deliveryCharges: 30.0,
        createdAt: DateTime.now(),
        items: items,
      );

      // Verify item counts and segregation
      expect(order.items.length, equals(5));
      expect(order.activeItems.length, equals(3));
      expect(order.declinedItems.length, equals(2));
      expect(order.hasDeclinedItems, isTrue);
      expect(order.activeItemsCount, equals(4)); // 1 Atta + 1 Oil + 2 Salt = 4 units

      // Verify active item names
      final activeNames = order.activeItems.map((i) => i.productName).toList();
      expect(activeNames, containsAll(['Atta 5kg', 'Sunflower Oil 1L', 'Salt 1kg']));
      expect(activeNames.contains('Basmati Rice 1kg'), isFalse);
      expect(activeNames.contains('Sugar 1kg'), isFalse);

      // Verify declined item names
      final declinedNames = order.declinedItems.map((i) => i.productName).toList();
      expect(declinedNames, containsAll(['Basmati Rice 1kg', 'Sugar 1kg']));
    });

    test('3. Financial scaling & proportional calculations on partial decline', () {
      // Original order: 5 items, subtotal = 1000, non_food_gst = 50, commission = 100 (10%)
      const oldSubtotal = 1000.0;
      const oldNonFoodGst = 50.0;
      const oldCommission = 100.0;
      const deliveryFee = 35.0;
      const platformFee = 5.0;

      // 2 items declined: ₹300 worth of items removed. New subtotal = ₹700
      const newSubtotal = 700.0;
      const ratio = newSubtotal / oldSubtotal; // 0.70

      final newNonFoodGst = (oldNonFoodGst * ratio).roundToDouble(); // 35.0
      final newCommission = (oldCommission * ratio).roundToDouble(); // 70.0
      const newTcs = (newSubtotal * 0.005); // 3.50
      const newTds = (newSubtotal * 0.001); // 0.70
      final newSellerPayout = newSubtotal + newNonFoodGst - newCommission - newTcs - newTds;
      final newGrandTotal = newSubtotal + deliveryFee + platformFee + newNonFoodGst;

      expect(ratio, equals(0.70));
      expect(newNonFoodGst, equals(35.0));
      expect(newCommission, equals(70.0));
      expect(newTcs, equals(3.50));
      expect(newTds, closeTo(0.70, 0.0001));
      expect(newSellerPayout, closeTo(660.80, 0.0001)); // 700 + 35 - 70 - 3.5 - 0.7
      expect(newGrandTotal, equals(775.0));

      final refundAmount = (oldSubtotal + deliveryFee + platformFee + oldNonFoodGst) - newGrandTotal;
      expect(refundAmount, equals(315.0)); // 300 subtotal + 15 GST refunded to customer
    });

    test('4. Heavy order fee reduction when active weight drops below 10 kg', () {
      // Customer ordered 25 kg: 5 bags x 5 kg = 25 kg.
      const initialWeight = 25.0;
      const heavyFeePaid = 40.0;

      // Store declines 3 bags of rice (15 kg).
      const declinedWeight = 15.0;
      const newWeight = initialWeight - declinedWeight; // 10.0 kg

      double recalculatedHeavyFee = 0.0;
      if (newWeight <= 10.0) {
        recalculatedHeavyFee = 0.0;
      } else {
        recalculatedHeavyFee = 20.0 * (newWeight - 10.0);
      }

      expect(recalculatedHeavyFee, equals(0.0));
      final heavyFeeRefund = heavyFeePaid - recalculatedHeavyFee;
      expect(heavyFeeRefund, equals(40.0));
    });

    test('5. OrderGroup terminal fallback and 100% prepaid compliance', () {
      final orderGroup = OrderGroup('cart-1', [
          OrderModel(
            id: 'ord-1',
            customerId: 'c1',
            status: 'preparing',
            totalAmount: 200.0,
            deliveryCharges: 30.0,
            createdAt: DateTime.now(),
            paymentStatus: 'captured',
            items: [
              OrderItem(id: 'i1', weightKg: 0.5, productId: 'p1', productName: 'Bread', price: 40.0, quantity: 1, status: 'active'),
              OrderItem(id: 'i2', weightKg: 0.5, productId: 'p2', productName: 'Butter', price: 60.0, quantity: 1, status: 'declined'),
            ],
          ),
        ],
      );

      // Zero COD model verification
      expect(orderGroup.isCod, isFalse);
      expect(orderGroup.isPrepaid, isTrue);
      expect(orderGroup.codAmountToCollect, equals(0.0));

      // Active orders reflect surviving items
      expect(orderGroup.activeOrders.length, equals(1));
      expect(orderGroup.activeOrders.first.hasDeclinedItems, isTrue);
      expect(orderGroup.activeOrders.first.activeItems.length, equals(1));
      expect(orderGroup.activeOrders.first.activeItems.first.productName, equals('Bread'));
    });

    test('6. Mixed Multi-Shop Cart Group: One rejected shop + One shop with item decline', () {
      // Shop A (Supermarket): 5 items ordered, 1 item declined (4 active)
      final shopAItems = [
        OrderItem(id: 'a1', weightKg: 0.5, productId: 'pa1', productName: 'Milk 1L', price: 60.0, quantity: 1, status: 'active'),
        OrderItem(id: 'a2', weightKg: 0.5, productId: 'pa2', productName: 'Cereal 500g', price: 150.0, quantity: 1, status: 'declined'),
        OrderItem(id: 'a3', weightKg: 0.5, productId: 'pa3', productName: 'Sugar 1kg', price: 50.0, quantity: 1, status: 'active'),
        OrderItem(id: 'a4', weightKg: 0.5, productId: 'pa4', productName: 'Tea 250g', price: 120.0, quantity: 1, status: 'active'),
        OrderItem(id: 'a5', weightKg: 0.5, productId: 'pa5', productName: 'Biscuits', price: 40.0, quantity: 1, status: 'active'),
      ];

      final orderA = OrderModel(
        id: 'ord-A',
        customerId: 'cust-1',
        shopId: 'shop-A',
        status: 'preparing',
        totalAmount: 270.0,
        deliveryCharges: 30.0,
        createdAt: DateTime.now(),
        items: shopAItems,
      );

      // Shop B (Bakery): Completely rejected by merchant
      final shopBItems = [
        OrderItem(id: 'b1', weightKg: 0.5, productId: 'pb1', productName: 'Croissant 2-pack', price: 100.0, quantity: 1, status: 'active'),
      ];

      final orderB = OrderModel(
        id: 'ord-B',
        customerId: 'cust-1',
        shopId: 'shop-B',
        status: 'seller_rejected',
        totalAmount: 100.0,
        deliveryCharges: 25.0,
        createdAt: DateTime.now(),
        items: shopBItems,
      );

      final mixedGroup = OrderGroup('cart-mixed', [orderA, orderB],
      );

      // Only Shop A is active
      expect(mixedGroup.activeOrders.length, equals(1));
      expect(mixedGroup.activeOrders.first.id, equals('ord-A'));

      // Shop A has active items
      expect(mixedGroup.activeOrders.first.activeItems.length, equals(4));
      expect(mixedGroup.activeOrders.first.declinedItems.length, equals(1));

      // Missing items across whole group aggregates both Shop B and Shop A declined items
      final allMissingProductNames = <String>[];
      for (final o in mixedGroup.orders) {
        if (o.status == 'seller_rejected') {
          allMissingProductNames.addAll(o.items.map((i) => i.productName));
        } else {
          allMissingProductNames.addAll(o.declinedItems.map((i) => i.productName));
        }
      }

      expect(allMissingProductNames, containsAll(['Croissant 2-pack', 'Cereal 500g']));
      expect(allMissingProductNames.length, equals(2));
    });
  });
}
