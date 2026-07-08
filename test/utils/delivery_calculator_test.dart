import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';

void main() {
  group('DeliveryCalculator', () {
    group('Delivery Charges', () {
      test('calculates minimum correctly', () {
        // Distance 0.5km -> ceil is 1. Should charge for 1km.
        // Default rate is 10.0
        expect(DeliveryCalculator.calculateDeliveryCharges(0.5, 500), 10.0);
      });
      
      test('clamps correctly', () {
        // Assume maxRadiusKm is 15.0 and ratePerKm is 10.0
        // Distance 15.0 -> ceil is 15.
        expect(DeliveryCalculator.calculateDeliveryCharges(15.0, 500), 150.0);
      });
      
      test('returns -1 for out of bounds', () {
        expect(DeliveryCalculator.calculateDeliveryCharges(16.0, 500), -1.0);
      });
    });

    group('ETA Label', () {
      test('handles sub-5 minutes (BUG-19 Fix)', () {
        // Very close distance, fast prep
        // 0.1km / 25 * 60 = 0.24 (ceil = 1). 1 + 2 = 3 mins.
        expect(DeliveryCalculator.etaLabel(0.1, 2), 'Under 5 mins');
        // 0.1km / 25 * 60 = 0.24 (ceil = 1). 1 + 3 = 4 mins.
        expect(DeliveryCalculator.etaLabel(0.1, 3), 'Under 5 mins');
      });

      test('handles standard ranges', () {
        // Distance 5km (10 mins) + prep 15 = 25 mins. lo=25, hi=35
        expect(DeliveryCalculator.etaLabel(5.0, 15), '25–35 mins');
      });

      test('handles over 90 mins', () {
        // Distance 15km (30 mins) + prep 70 = 100 mins.
        expect(DeliveryCalculator.etaLabel(15.0, 70), '90+ mins');
      });
    });
  });
}
