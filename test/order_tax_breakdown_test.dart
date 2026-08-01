import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/tax_config.dart';

void main() {
  group('OrderTaxBreakdown.calculate', () {
    test('Correctly calculates for a mixed cart (food + retail) with UPI', () {
      final items = [
        {'category': 'Restaurant', 'price': 100.0, 'quantity': 1}, // Deemed supplier, 5% GST = 5.0
        {'category': 'Grocery', 'price': 200.0, 'quantity': 2}, // Passthrough, 5% GST = 10.0 per item = 20.0
      ];
      
      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 35.0, // 35 includes 18% GST => 35 - 35/1.18 = 5.33898
        riderEarnings: 28.0, // 80% of 35
        platformFee: 15.0, // Includes 18% GST => 15 - 15/1.18 = 2.288
        paymentMethod: 'upi',
      );

      // Base Subtotal: 100 + 400 = 500
      expect(breakdown.itemBaseSubtotal, 500.0);
      
      // S9_5 GST: 5.0
      expect(breakdown.s9_5GstToRemit, 5.0);
      
      // Non-food GST: 20.0
      expect(breakdown.nonFoodGstPassThrough, 20.0);
      
      // Item GST Total: 25.0
      expect(breakdown.itemGstTotal, 25.0);
      
      // Delivery GST
      expect(breakdown.deliveryGst, closeTo(5.33898, 0.001));
      
      // Platform Fee GST
      expect(breakdown.platformFeeGst, closeTo(2.288, 0.001));
      
      // Grand Total = 500 + 25 + 35 + 15 = 575
      expect(breakdown.grandTotal, 575.0);
      
      // Gateway deduction (2.36% of 575 = 13.57)
      expect(breakdown.gatewayDeduction, closeTo(13.57, 0.01));
      
      // Pure commission (default is 5%)
      // enythingNetCommission = 500 * 0.05 = 25.0
      expect(breakdown.enythingNetCommission, 25.0);
      
      // Seller Payout = base (500) + nonFoodGst (20) - enythingGross - sellerGwShare
      // sellerGwShare = (500 - 25 + 20) * 0.0236 = 495 * 0.0236 = 11.682
      // enythingGross = pure (25) + sellerGwShare (11.682) = 36.682
      expect(breakdown.sellerGatewayShare, closeTo(11.682, 0.001));
      expect(breakdown.enythingGrossCommission, closeTo(36.682, 0.001));
      expect(breakdown.sellerPayout, closeTo(500 + 20 - 36.682, 0.001));
    });

    test('Correctly calculates for COD payment method', () {
      final items = [
        {'category': 'Restaurant', 'price': 500.0, 'quantity': 1}, 
      ];
      
      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 35.0,
        riderEarnings: 28.0,
        platformFee: 15.0,
        paymentMethod: 'cod',
      );

      // Gateway deduction should be 0.0 for COD
      expect(breakdown.gatewayDeduction, 0.0);
      expect(breakdown.sellerGatewayShare, 0.0);
      expect(breakdown.enythingGatewayShare, 0.0);
      
      // Enything Gross == Enything Net for COD
      expect(breakdown.enythingNetCommission, 25.0);
      expect(breakdown.enythingGrossCommission, 25.0);
      
      // Seller Payout = base (500) + nonFoodGst (0) - enythingGross (25)
      expect(breakdown.sellerPayout, 475.0);
    });
  });
}
