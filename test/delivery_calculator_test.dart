import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/utils/delivery_calculator.dart';
import 'package:enythingmobilenew/models/shop_model.dart';

void main() {
  group('DeliveryCalculator', () {
    test('calculateDeliveryCharges correctly applies rate per km', () {
      // Dynamic per-km delivery fee: ceil(km) * rate (default ₹20/km) with floor ₹20
      expect(DeliveryCalculator.calculateDeliveryCharges(0.5, 100), 20.0); 
      expect(DeliveryCalculator.calculateDeliveryCharges(1.5, 100), 40.0); 
      expect(DeliveryCalculator.calculateDeliveryCharges(3.0, 100), 60.0); 
      // > maxRadiusKm => -1
      expect(DeliveryCalculator.calculateDeliveryCharges(16.0, 100), -1.0); 
    });

    test('calculateMultiShopSurcharge applies sequential distance logic', () {
      final shop1 = ShopModel(
        id: '1', sellerId: 's1', name: 'S1', category: 'Cat', 
        categories: [], location: const LatLng(0, 0), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a1',
        shopType: 'shop'
      );
      // Shop 2 is ~0.55 km from Shop 1 (<= 1 km -> 1 km floor = ₹20)
      final shop2Close = ShopModel(
        id: '2', sellerId: 's2', name: 'S2', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.005), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a2',
        shopType: 'shop'
      );
      // Shop 3 is ~0.55 km from Shop 2 (<= 1 km -> 1 km floor = ₹20)
      final shop3Close = ShopModel(
        id: '3', sellerId: 's3', name: 'S3', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.010), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a3',
        shopType: 'shop'
      );

      final closeShops = [shop1, shop2Close, shop3Close];
      // 2 legs <= 1km: 20 + 20 = 40
      expect(DeliveryCalculator.calculateMultiShopSurcharge(closeShops), 40.0);

      // Shop 2 is ~1.11 km from Shop 1 (ceil 2 km -> 2 * 20 = ₹40)
      final shop2Far = ShopModel(
        id: '2', sellerId: 's2', name: 'S2', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.01), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a2',
        shopType: 'shop'
      );
      // Shop 3 is ~1.11 km from Shop 2 (ceil 2 km -> 2 * 20 = ₹40)
      final shop3Far = ShopModel(
        id: '3', sellerId: 's3', name: 'S3', category: 'Cat', 
        categories: [], location: const LatLng(0, 0.02), isActive: true, 
        rating: 4.5, totalReviews: 10, totalOrders: 10, address: 'a3',
        shopType: 'shop'
      );

      final farShops = [shop1, shop2Far, shop3Far];
      // 2 legs ~1.11km: 40 + 40 = 80
      expect(DeliveryCalculator.calculateMultiShopSurcharge(farShops), 80.0);
    });
  });
}
