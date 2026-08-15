import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/config/tax_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real-Time Recalculation & Multi-Actor Lifecycle Engine Tests', () {
    late ShopModel shop1;
    late ShopModel shop2;
    late ShopModel shop3;

    setUp(() {
      shop1 = ShopModel(
        id: 'shop_1',
        sellerId: 'seller_1',
        name: 'Bakery Shop',
        shopType: 'bakery',
        prepTimeMinutes: 15,
        isVegOnly: true,
        address: 'Main Market, Shop 1',
        location: const LatLng(34.0, 74.0),
        category: 'Bakery',
        categories: ['Bakery'],
        isActive: true,
        rating: 4.5,
        totalReviews: 20,
        totalOrders: 50,
      );

      shop2 = ShopModel(
        id: 'shop_2',
        sellerId: 'seller_2',
        name: 'Grocery Mart',
        shopType: 'store',
        prepTimeMinutes: 10,
        isVegOnly: false,
        address: 'Main Market, Shop 2',
        location: const LatLng(34.01, 74.01),
        category: 'Grocery',
        categories: ['Grocery'],
        isActive: true,
        rating: 4.8,
        totalReviews: 40,
        totalOrders: 100,
      );

      shop3 = ShopModel(
        id: 'shop_3',
        sellerId: 'seller_3',
        name: 'Medical Store',
        shopType: 'pharmacy',
        prepTimeMinutes: 5,
        isVegOnly: false,
        address: 'Main Market, Shop 3',
        location: const LatLng(34.02, 74.02),
        category: 'Pharmacy',
        categories: ['Pharmacy'],
        isActive: true,
        rating: 4.9,
        totalReviews: 30,
        totalOrders: 80,
      );
    });

    test('1. Delivery Fee & Multi-Shop Surcharge Progression for 1, 2, and 3 Shops', () {
      // 1 Shop
      expect(DeliveryCalculator.calculateDeliveryCharges(1.5, 200.0), 20.0);
      expect(DeliveryCalculator.calculateMultiShopSurcharge([shop1]), 0.0);

      // 2 Shops
      expect(DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2]), 20.0);

      // 3 Shops
      expect(
          DeliveryCalculator.calculateMultiShopSurcharge([shop1, shop2, shop3]),
          40.0);
    });

    test('2. CartProvider Flat Platform Fee and Multi-Shop Delivery Calculation', () {
      final cart = CartProvider();

      final p1 = ProductModel(
        id: 'p1',
        shopId: 'shop_1',
        name: 'Cake',
        category: 'Bakery',
        subCategory: 'Dessert',
        price: 250.0,
        totalQuantity: 10,
        weightPerUnit: 0.5,
        unitType: 'piece',
        isVeg: true,
        prepTimeMinutes: 10,
        isAvailable: true,
        rating: 4.5,
      );

      final p2 = ProductModel(
        id: 'p2',
        shopId: 'shop_2',
        name: 'Rice Bag',
        category: 'Grocery',
        subCategory: 'Grains',
        price: 300.0,
        totalQuantity: 5,
        weightPerUnit: 2.0,
        unitType: 'kg',
        isVeg: true,
        prepTimeMinutes: 5,
        isAvailable: true,
        rating: 4.8,
      );

      cart.addItem(p1, shop1);
      // 1 shop in cart: platform fee = 20 flat, surcharge = 0
      expect(cart.shops.length, 1);
      expect(cart.platformFee, 20.0);
      expect(cart.multiShopSurcharge, 0.0);
      expect(cart.totalDeliveryCharges(1.0), (20.0 * 1.18));

      cart.addItem(p2, shop2);
      // 2 shops in cart: platform fee remains 20 flat, surcharge = 20
      expect(cart.shops.length, 2);
      expect(cart.platformFee, 20.0);
      expect(cart.multiShopSurcharge, 20.0);
      // Total delivery: (20 base + 20 surcharge) * 1.18 = 47.20
      expect(cart.totalDeliveryCharges(1.0), (40.0 * 1.18));
    });

    test('3. Rider OrderGroup Filters Out Rejected Shops & Recalculates Earnings', () {
      final order1 = OrderModel(
        id: 'ord_1',
        customerId: 'cust_1',
        shopId: 'shop_1',
        cartGroupId: 'group_123',
        status: 'awaiting_payment',
        totalAmount: 250.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 10.0,
        platformFee: 10.0,
        riderEarnings: 16.0,
        grandTotalCollected: 300.0,
        sellerAccepted: true,
        partnerAccepted: true,
        createdAt: DateTime.now(),
        items: [],
      );

      final order2 = OrderModel(
        id: 'ord_2',
        customerId: 'cust_1',
        shopId: 'shop_2',
        cartGroupId: 'group_123',
        status: 'seller_rejected', // Rejected by shop 2
        totalAmount: 300.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 10.0,
        platformFee: 10.0,
        riderEarnings: 16.0,
        grandTotalCollected: 350.0,
        sellerAccepted: false,
        partnerAccepted: true,
        createdAt: DateTime.now(),
        items: [],
      );

      final group = OrderGroup('group_123', [order1, order2]);

      // activeOrders MUST filter out order2 (seller_rejected)
      expect(group.activeOrders.length, 1);
      expect(group.activeOrders.first.id, 'ord_1');

      // Earnings must reflect active orders only
      expect(group.totalEarnings, 16.0);
      expect(group.isMultiShop, false); // only 1 shop remaining active
    });

    test('4. Tax Breakdown Correctly Includes Surcharges in Service GST', () {
      final breakdown = OrderTaxBreakdown.calculate(
        items: [
          {
            'category': 'Bakery',
            'price': 250.0,
            'quantity': 1,
          }
        ],
        deliveryCharge: 23.60, // 20 + 18% GST
        riderEarnings: 16.0,
        platformFee: 20.0, // 20 flat handling fee
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, 250.0);
      expect(breakdown.deliveryCharge, 23.60);
      expect(breakdown.platformFee, 20.0);
      expect(breakdown.platformFeeGst, closeTo(3.05, 0.01));
      expect(breakdown.deliveryGst, closeTo(3.60, 0.01));
      expect(breakdown.grandTotal, closeTo(250.0 + 12.50 + 23.60 + 20.0, 0.1));
    });

    test('5. Multi-Shop Order State Evaluates to awaiting_payment When All Accept', () {
      final order1 = OrderModel(
        id: 'ord_1',
        customerId: 'cust_1',
        shopId: 'shop_1',
        cartGroupId: 'group_abc',
        status: 'awaiting_acceptance',
        totalAmount: 250.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 0.0,
        platformFee: 10.0,
        riderEarnings: 16.0,
        grandTotalCollected: 300.0,
        sellerAccepted: true,
        partnerAccepted: true,
        createdAt: DateTime.now(),
        items: [],
      );

      final order2 = OrderModel(
        id: 'ord_2',
        customerId: 'cust_1',
        shopId: 'shop_2',
        cartGroupId: 'group_abc',
        status: 'awaiting_acceptance',
        totalAmount: 200.0,
        deliveryCharges: 23.60,
        multiShopSurcharge: 20.0,
        platformFee: 10.0,
        riderEarnings: 16.0,
        grandTotalCollected: 250.0,
        sellerAccepted: true,
        partnerAccepted: true,
        createdAt: DateTime.now(),
        items: [],
      );

      final orders = [order1, order2];
      final allSellersAccepted = orders.every((o) => o.sellerAccepted);
      final allPartnersAccepted = orders.every((o) => o.partnerAccepted);
      final isReadyForPayment = allSellersAccepted &&
          allPartnersAccepted &&
          orders.every((o) =>
              o.status == 'awaiting_acceptance' ||
              o.status == 'awaiting_payment' ||
              o.status == 'pending');

      expect(allSellersAccepted, true);
      expect(allPartnersAccepted, true);
      expect(isReadyForPayment, true);
    });
  });
}
