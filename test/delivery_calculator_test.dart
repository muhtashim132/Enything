import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/models/shop_model.dart';

void main() {
  group('DeliveryCalculator', () {
    test('calculateDeliveryCharges correctly applies rate per km', () {
      // 0.5 km ceil = 1km => 1 * 10 = 10
      expect(DeliveryCalculator.calculateDeliveryCharges(0.5, 100), 10.0); 
      // 1.5 km ceil = 2km => 2 * 10 = 20
      expect(DeliveryCalculator.calculateDeliveryCharges(1.5, 100), 20.0); 
      // > maxRadiusKm => -1
      expect(DeliveryCalculator.calculateDeliveryCharges(16.0, 100), -1.0); 
    });

    test('calculateMultiShopSurcharge applies greedy nearest-neighbor logic', () {
      // 3 shops at coordinates that give known distances.
      // 1 degree latitude = ~111km, so 0.01 degree = ~1.11km
      final shop1 = ShopModel(
        id: '1', sellerId: 's1', name: 'S1', category: 'Cat', 
        categories: [], location: const LatLng(0, 0), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a1',
        shopType: 'shop'
      );
      final shop2 = ShopModel(
        id: '2', sellerId: 's2', name: 'S2', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.01), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a2',
        shopType: 'shop'
      );
      final shop3 = ShopModel(
        id: '3', sellerId: 's3', name: 'S3', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.02), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a3',
        shopType: 'shop'
      );

      final shops = [shop1, shop2, shop3];
      // Shop 2 distance from shop 1 = ~1.11km -> ceil = 2km -> 2 * 10 = 20
      // Shop 3 distance from shop 2 (nearest visited) = ~1.11km -> ceil = 2km -> 2 * 10 = 20
      // Total surcharge = 40
      
      final surcharge = DeliveryCalculator.calculateMultiShopSurcharge(shops);
      expect(surcharge, 40.0);
    });
  });
}
