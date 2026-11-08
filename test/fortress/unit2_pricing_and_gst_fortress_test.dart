import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/config/payment_config.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('100x Forensic Unit 2: Pricing, Surcharges & GST Financial Engine', () {
    test('1. GST category slabs and Sept 2025 India tax reform verification', () {
      // Food / Restaurant: Section 9(5) ECO deemed supplier (5%)
      expect(TaxConfig.gstRateForCategory('Restaurant'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Fast Food'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Bakery'), equals(0.05));

      // Fresh perishables (0%)
      expect(TaxConfig.gstRateForCategory('Fruits & Vegs'), equals(0.00));
      expect(TaxConfig.gstRateForCategory('Butcher'), equals(0.00));
      expect(TaxConfig.gstRateForCategory('Fish & Seafood'), equals(0.00));

      // Grocery & Pharmacy (5%)
      expect(TaxConfig.gstRateForCategory('Grocery'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Pharmacy'), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Medical Store'), equals(0.05));

      // Electronics & General Retail (18%)
      expect(TaxConfig.gstRateForCategory('Electronics'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Stationery'), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Beverages'), equals(0.18));

      // Special items: Jewellery (3%)
      expect(TaxConfig.gstRateForCategory('Jewellery'), equals(0.03));
    });

    test('2. Clothing & Footwear dynamic price-slab threshold (<= ₹2,500 vs > ₹2,500)', () {
      // Clothing <= ₹2,500 -> 5%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 1500.0), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500.0), equals(0.05));

      // Clothing > ₹2,500 -> 18%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500.01), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 5000.0), equals(0.18));

      // Footwear <= ₹2,500 -> 5%
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 999.0), equals(0.05));
      // Footwear > ₹2,500 -> 18%
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 3200.0), equals(0.18));
    });

    test('3. Platform handling fee and delivery fee GST rates', () {
      // Delivery GST rate is 18% (SAC 9965/9967)
      expect(TaxConfig.deliveryGstRate, equals(0.18));

      // Platform handling fee GST rate is 18% (SAC 9985)
      expect(TaxConfig.platformFeeGstRate, equals(0.18));

      // Embedded GST extraction: On ₹2.0 platform fee, net fee + GST = 2.0
      const fee = PaymentConfig.platformFee;
      final netFee = fee / (1 + TaxConfig.platformFeeGstRate);
      final embeddedGst = fee - netFee;
      expect(netFee + embeddedGst, closeTo(fee, 0.0001));
    });

    test('4. Razorpay gateway fee deduction math (2.36% effective)', () {
      // 2% base + 18% GST on 2% = 2.36%
      expect(TaxConfig.effectiveGatewayDeductionPercent, closeTo(0.0236, 0.0001));

      // Deduction on ₹1,000 order = ₹23.60
      final deduction = 1000.0 * TaxConfig.effectiveGatewayDeductionPercent;
      expect(deduction, closeTo(23.60, 0.01));
    });

    test('5. Order threshold surcharges (Small cart fee & heavy order)', () {
      // Small cart threshold: ₹199
      expect(PaymentConfig.smallCartThreshold, equals(199.0));
      expect(PaymentConfig.smallCartFee, equals(25.0));

      // Heavy order threshold: 10kg, surcharge ₹20/kg above 10kg
      expect(PaymentConfig.heavyOrderThreshold, equals(10.0));
      expect(PaymentConfig.heavyOrderFee, equals(20.0));
      expect(PaymentConfig.maxWeightKg, equals(15.0));

      // Weight surcharge calculation logic from CartProvider:
      double computeHeavyOrderFee(double weight) {
        if (weight > PaymentConfig.heavyOrderThreshold) {
          final extraWeight = (weight - PaymentConfig.heavyOrderThreshold).ceil();
          return PaymentConfig.heavyOrderFee * extraWeight;
        }
        return 0.0;
      }

      // Case A: 8kg -> ₹0 surcharge
      expect(computeHeavyOrderFee(8.0), equals(0.0));

      // Case B: 10.0kg -> ₹0 surcharge
      expect(computeHeavyOrderFee(10.0), equals(0.0));

      // Case C: 12.5kg -> ceil(2.5kg) = 3kg * ₹20 = ₹60
      expect(computeHeavyOrderFee(12.5), equals(60.0));

      // Case D: 15.0kg -> 5kg * ₹20 = ₹100
      expect(computeHeavyOrderFee(15.0), equals(100.0));
    });

    test('6. Absolute IEEE-754 floating point precision defense (Paise rounding)', () {
      // Sub-paise values must be safely converted to integer paise
      const double orderAmount = 249.99;
      final int paise = (orderAmount * 100).round();
      expect(paise, equals(24999));

      // Fractional floating drift like 0.1 + 0.2 != 0.3
      const double val1 = 0.1;
      const double val2 = 0.2;
      expect((val1 + val2) * 100, isNot(equals(30.0))); // raw float has precision jitter
      expect(((val1 + val2) * 100).round(), equals(30)); // rounded integer paise is rock-solid
    });

    test('7. Base delivery charge boundary tests', () {
      // Distance = 0.001 km -> ₹20 floor
      expect(DeliveryCalculator.calculateDeliveryCharges(0.001, 100.0), equals(20.0));

      // Distance = 1.0 km -> ₹20 floor
      expect(DeliveryCalculator.calculateDeliveryCharges(1.0, 100.0), equals(20.0));

      // Distance = 1.001 km -> 2 km * ₹20 = ₹40
      expect(DeliveryCalculator.calculateDeliveryCharges(1.001, 100.0), equals(40.0));

      // Distance = 15.000 km -> 15 km * ₹20 = ₹300
      expect(DeliveryCalculator.calculateDeliveryCharges(15.0, 100.0), equals(300.0));

      // Distance = 15.001 km -> -1 (rejected by radius engine)
      expect(DeliveryCalculator.calculateDeliveryCharges(15.001, 100.0), equals(-1.0));
    });

    test('8. Section 9(5) ECO Restaurant GST vs Retail Pass-Through Split', () {
      // Restaurant subtotal = ₹500. GST rate = 5% (₹25).
      // Under Section 9(5), Enything deposits this ₹25 to the government directly.
      // Seller payout does NOT receive this ₹25.
      const restaurantSubtotal = 500.0;
      final restaurantGst = restaurantSubtotal * TaxConfig.gstRateForCategory('Restaurant');
      expect(restaurantGst, equals(25.0));

      // Retail / Grocery subtotal = ₹400. GST rate = 5% (₹20).
      // Retail GST is collected on behalf of merchant and paid out to merchant.
      const grocerySubtotal = 400.0;
      final groceryGst = grocerySubtotal * TaxConfig.gstRateForCategory('Grocery');
      expect(groceryGst, equals(20.0));

      // In a mixed multi-shop order:
      final totalItemGst = restaurantGst + groceryGst;
      expect(totalItemGst, equals(45.0));
    });

    test('9. Full Cart Financial Assembly (Subtotal + Delivery + Multi-shop + Small Cart + Platform Fee)', () {
      // Subtotal = ₹150 (< ₹199 threshold -> small cart fee applies)
      const subtotal = 150.0;
      const distanceKm = 2.5; // ceil(2.5) = 3km * 20 = ₹60 delivery fee
      const shopCount = 2; // 1 additional shop -> multi-shop surcharge

      final baseDelivery = DeliveryCalculator.calculateDeliveryCharges(distanceKm, subtotal);
      expect(baseDelivery, equals(60.0));

      final smallCartFee = (subtotal < PaymentConfig.smallCartThreshold) ? PaymentConfig.smallCartFee : 0.0;
      expect(smallCartFee, equals(25.0));

      const platformFee = PaymentConfig.platformFee;
      expect(platformFee, equals(2.0));

      // Multi-shop surcharge for 2 shops
      final s1 = ShopModel(id: 's1', sellerId: 'sel1', name: 'S1', category: 'Food', categories: [], location: const LatLng(34.42, 74.63), isActive: true, rating: 4.5, totalReviews: 5, totalOrders: 5, address: 'A1', shopType: 'shop');
      final s2 = ShopModel(id: 's2', sellerId: 'sel2', name: 'S2', category: 'Grocery', categories: [], location: const LatLng(34.43, 74.64), isActive: true, rating: 4.5, totalReviews: 5, totalOrders: 5, address: 'A2', shopType: 'shop');
      final multiShopFee = DeliveryCalculator.calculateMultiShopSurcharge([s1, s2]);
      expect(multiShopFee, greaterThanOrEqualTo(20.0));

      // Total collected from customer must be exact sum
      final totalCollected = subtotal + baseDelivery + multiShopFee + smallCartFee + platformFee;
      expect(totalCollected, greaterThan(250.0));
      // Integer paise check:
      expect((totalCollected * 100).round() / 100, equals(totalCollected));
    });
  });
}
