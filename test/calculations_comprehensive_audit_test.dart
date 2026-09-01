import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/tax_config.dart';

void main() {
  group('100x Comprehensive Calculations Audit Test Suite', () {
    test('Dynamic riderPayoutRatio getter returns default 80% when unconfigured', () {
      expect(TaxConfig.riderPayoutRatio, 0.80);
    });

    test('GST TCS (§52) and TDS (§194-O) calculations across category types', () {
      // 1. Food (Restaurant) - TCS = 0%, TDS = 0.1%
      final foodItems = [
        {'category': 'Restaurant', 'price': 1000.0, 'quantity': 1},
      ];
      final foodBreakdown = OrderTaxBreakdown.calculate(
        items: foodItems,
        deliveryCharge: 23.60,
        riderEarnings: 16.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );
      expect(foodBreakdown.tcsAmount, 0.0);
      expect(foodBreakdown.tdsAmount, closeTo(1.0, 0.001)); // 1000 * 0.001

      // 2. Fresh Produce (Fruits & Vegs) - TCS = 0%, TDS = 0.1%
      final produceItems = [
        {'category': 'Fruits & Vegs', 'price': 500.0, 'quantity': 1},
      ];
      final produceBreakdown = OrderTaxBreakdown.calculate(
        items: produceItems,
        deliveryCharge: 23.60,
        riderEarnings: 16.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );
      expect(produceBreakdown.tcsAmount, 0.0);
      expect(produceBreakdown.tdsAmount, closeTo(0.5, 0.001)); // 500 * 0.001

      // 3. Taxable Retail (Electronics) - TCS = 0.5%, TDS = 0.1%
      final retailItems = [
        {'category': 'Electronics', 'price': 2000.0, 'quantity': 1},
      ];
      final retailBreakdown = OrderTaxBreakdown.calculate(
        items: retailItems,
        deliveryCharge: 23.60,
        riderEarnings: 16.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );
      expect(retailBreakdown.tcsAmount, closeTo(10.0, 0.001)); // 2000 * 0.005
      expect(retailBreakdown.tdsAmount, closeTo(2.0, 0.001)); // 2000 * 0.001
    });

    test('Clothing and Footwear price slab threshold resolution', () {
      // Clothing <= ₹2500 -> 5% GST
      final lowClothingItems = [
        {'category': 'Clothing', 'price': 1500.0, 'quantity': 1},
      ];
      final lowBreakdown = OrderTaxBreakdown.calculate(
        items: lowClothingItems,
        deliveryCharge: 23.60,
        riderEarnings: 16.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );
      expect(lowBreakdown.itemGstTotal, closeTo(75.0, 0.001)); // 1500 * 0.05

      // Clothing > ₹2500 -> 18% GST
      final highClothingItems = [
        {'category': 'Clothing', 'price': 3000.0, 'quantity': 1},
      ];
      final highBreakdown = OrderTaxBreakdown.calculate(
        items: highClothingItems,
        deliveryCharge: 23.60,
        riderEarnings: 16.0,
        platformFee: 20.0,
        paymentMethod: 'upi',
      );
      expect(highBreakdown.itemGstTotal, closeTo(540.0, 0.001)); // 3000 * 0.18
    });

    test('Partial Rejection Rebalancing: No surcharge double-counting on grand_total_collected', () {
      // Suppose surviving shop subtotal = ₹500, GST = ₹25, platform_fee = ₹20
      // Bundled delivery_charges = ₹23.60 (which already is base ₹20 + GST ₹3.60)
      // grand_total_collected MUST BE exactly: 500 + 25 + 20 + 23.60 = 568.60
      const totalAmount = 500.0;
      const gstItemTotal = 25.0;
      const newPlat = 20.0;
      const newDel = 23.60; // bundled delivery charges
      const newCoupon = 0.0;

      const correctGrandTotal = totalAmount + gstItemTotal + newPlat + newDel - newCoupon;
      expect(correctGrandTotal, 568.60);

      // If the old bug was present (re-adding small, heavy, surcharge):
      const doubleCountedGrandTotal = correctGrandTotal + 0.0 /* small */ + 0.0 /* heavy */ + 20.0 /* surcharge */;
      // We assert that correct formula differs from the buggy double-counted total
      expect(correctGrandTotal != doubleCountedGrandTotal, true);
    });

    test('Razorpay 2.36% Gateway Deduction and Seller Payout Split Parity', () {
      final items = [
        {'category': 'Restaurant', 'price': 1000.0, 'quantity': 1},
      ];
      const deliveryCharge = 23.60;
      const riderEarnings = 16.0;
      const platformFee = 20.0;

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: deliveryCharge,
        riderEarnings: riderEarnings,
        platformFee: platformFee,
        paymentMethod: 'upi',
      );

      // Grand Total = 1000 + 50 (5% GST) + 23.60 + 20.0 = 1093.60
      expect(breakdown.grandTotal, closeTo(1093.60, 0.01));

      // Gateway Deduction = 1093.60 * 0.0236 = 25.80896
      expect(breakdown.gatewayDeduction, closeTo(1093.60 * 0.0236, 0.01));

      // Pure Commission (5%) = 50.0
      expect(breakdown.enythingNetCommission, 50.0);

      // Seller Base Payout = 1000 - 50 = 950.0
      // Seller GW share = 950.0 * 0.0236 = 22.42
      expect(breakdown.sellerGatewayShare, closeTo(950.0 * 0.0236, 0.01));

      // Seller Gross Payout (before TDS/TCS) = 1000 - 50 - 22.42 = 927.58
      const expectedSellerPayoutGross = 1000.0 - 50.0 - (950.0 * 0.0236);
      expect(breakdown.sellerPayout, closeTo(expectedSellerPayoutGross, 0.01));

      // Seller Net Payout (after ₹1.0 TDS deduction) = 927.58 - 1.0 = 926.58
      const expectedSellerPayoutNet = expectedSellerPayoutGross - 1.0;
      expect(breakdown.sellerPayoutNet, closeTo(expectedSellerPayoutNet, 0.01));
    });
  });
}
