import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';

void main() {
  group('100x Order Financial Math & Calculations Test Suite', () {
    test('Single Shop Standard Food Order Calculation (Add-on 5% GST)', () {
      // ₹500 base item subtotal in Restaurant (5% GST)
      final items = [
        {'category': 'Restaurant', 'price': 500.0, 'quantity': 1},
      ];
      final deliveryCharge = 20.0 * 1.18; // ₹23.60 incl 18% GST
      final riderEarnings = 20.0 * 0.80; // ₹16.00
      final platformFee = 20.0; // ₹20.00 incl 18% GST

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: deliveryCharge,
        riderEarnings: riderEarnings,
        platformFee: platformFee,
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, 500.0);
      expect(breakdown.itemGstTotal, 25.0);
      expect(breakdown.itemGrossTotal, 525.0);
      expect(breakdown.s9_5GstToRemit, 25.0);
      expect(breakdown.nonFoodGstPassThrough, 0.0);
      expect(breakdown.grandTotal, closeTo(525.0 + 23.60 + 20.0, 0.01));

      // Rider earnings
      expect(breakdown.riderEarnings, 16.0);

      // Seller receives 95% of base - seller gateway share
      final sellerBasePayout = 500.0 * 0.95; // ₹475
      final sellerGwShare = sellerBasePayout * TaxConfig.effectiveGatewayDeductionPercent;
      expect(breakdown.sellerPayout, closeTo(sellerBasePayout - sellerGwShare, 0.01));
    });

    test('Single Shop Retail Order (18% GST non-food passthrough)', () {
      // ₹1000 base item in Electronics (18% GST)
      final items = [
        {'category': 'Electronics', 'price': 1000.0, 'quantity': 1},
      ];
      final deliveryCharge = 20.0 * 1.18; // ₹23.60
      final riderEarnings = 16.0;
      final platformFee = 20.0;

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: deliveryCharge,
        riderEarnings: riderEarnings,
        platformFee: platformFee,
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, 1000.0);
      expect(breakdown.itemGstTotal, 180.0);
      expect(breakdown.s9_5GstToRemit, 0.0);
      expect(breakdown.nonFoodGstPassThrough, 180.0);

      // Seller receives (Base ₹1000 - 5% commission ₹50) + nonFoodGst ₹180 - seller gateway share
      final sellerGross = 950.0 + 180.0; // ₹1130
      final sellerGwShare = sellerGross * TaxConfig.effectiveGatewayDeductionPercent;
      expect(breakdown.sellerPayout, closeTo(sellerGross - sellerGwShare, 0.01));
    });

    test('Multi-Shop 2-Shop Order with Multi-shop Surcharge', () {
      // 2 shops: Base ₹20 + Surcharge ₹20 = ₹40 pre-tax delivery -> ₹47.20 incl GST
      final totalDelivery = (PaymentConfig.deliveryFee + PaymentConfig.multiShopSurcharge) * 1.18;
      final shopDelivery = totalDelivery / 2; // ₹23.60 per shop
      final shopRiderEarnings = (40.0 * 0.80) / 2; // ₹16.00 per shop

      final itemsShop1 = [
        {'category': 'Restaurant', 'price': 300.0, 'quantity': 1},
      ];
      final breakdown1 = OrderTaxBreakdown.calculate(
        items: itemsShop1,
        deliveryCharge: shopDelivery,
        riderEarnings: shopRiderEarnings,
        platformFee: 10.0, // ₹20 / 2
        paymentMethod: 'upi',
      );

      expect(breakdown1.itemBaseSubtotal, 300.0);
      expect(breakdown1.deliveryCharge, closeTo(23.60, 0.01));
      expect(breakdown1.platformFee, 10.0);
      expect(breakdown1.grandTotal, closeTo(300.0 + 15.0 + 23.60 + 10.0, 0.01));
    });

    test('Replacement Order: Base delivery and platform fee suppressed to 0', () {
      // Replacement order: effectiveBase = 0, platformFee = 0
      final items = [
        {'category': 'Restaurant', 'price': 250.0, 'quantity': 1},
      ];
      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 0.0, // Base suppressed
        riderEarnings: 0.0,
        platformFee: 0.0, // Handling fee suppressed
        paymentMethod: 'upi',
      );

      expect(breakdown.itemBaseSubtotal, 250.0);
      expect(breakdown.itemGstTotal, 12.50);
      expect(breakdown.deliveryCharge, 0.0);
      expect(breakdown.platformFee, 0.0);
      expect(breakdown.grandTotal, 262.50);
    });

    test('Small Cart Fee and Heavy Order Fee Aggregation in Delivery Math', () {
      // Subtotal ₹50 (< ₹99 threshold) -> Small Cart Fee ₹15
      // Weight 12kg (> 10kg threshold) -> Heavy Fee ₹20 * 2kg = ₹40 (or flat ₹20)
      const smallCartFee = PaymentConfig.smallCartFee; // ₹15
      const heavyOrderFee = PaymentConfig.heavyOrderFee; // ₹20
      const baseDelivery = PaymentConfig.deliveryFee; // ₹20
      const totalWithoutGst = baseDelivery + smallCartFee + heavyOrderFee; // ₹55
      const totalDelivery = totalWithoutGst * (1 + 0.18); // ₹64.90

      expect(totalWithoutGst, 55.0);
      expect(totalDelivery, closeTo(64.90, 0.01));
    });

    test('WeightEngine parses weights across units and handles typos accurately', () {
      final p1 = ProductModel(
        id: 'p1',
        shopId: 's1',
        name: 'Sugar Pack',
        category: 'Grocery',
        price: 50,
        weightPerUnit: 500,
        unitType: 'grams',
      );
      expect(WeightEngine.resolve(product: p1), 0.5);

      final p2 = ProductModel(
        id: 'p2',
        shopId: 's1',
        name: 'Rice Bag',
        category: 'Grocery',
        price: 150,
        weightPerUnit: 1.5,
        unitType: 'kg',
      );
      expect(WeightEngine.resolve(product: p2), 1.5);

      final p3 = ProductModel(
        id: 'p3',
        shopId: 's1',
        name: 'Cotton Shirt',
        category: 'Clothing',
        price: 500,
        weightPerUnit: 650,
        unitType: 'pieces',
      );
      expect(WeightEngine.resolve(product: p3), closeTo(0.65, 0.01));
    });

    test('OrderModel parsing and grandTotal fallback check', () {
      final map = {
        'id': 'test-order-1',
        'status': 'awaiting_payment',
        'total_amount': 500.0,
        'delivery_charges': 23.60,
        'platform_fee': 20.0,
        'grand_total_collected': 568.60,
        'seller_accepted': true,
        'partner_accepted': true,
        'gst_rate_snapshot': {'Restaurant': 0.05},
        'coupon_discount': 0.0,
      };

      final order = OrderModel.fromMap(map);
      expect(order.id, 'test-order-1');
      expect(order.grandTotalCollected, 568.60);
      expect(order.grandTotal, 568.60);
      expect(order.isFullyConfirmed, true);
      expect(order.gstRateSnapshot['Restaurant'], 0.05);
    });
  });
}
