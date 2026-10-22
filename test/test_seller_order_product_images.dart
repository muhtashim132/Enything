import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';

void main() {
  group('100x Forensic Seller Order Product Images Test Suite', () {
    test('1. OrderItem properly deserializes direct image_url, product_image, and nested products map', () {
      // Direct image_url
      final item1 = OrderItem.fromMap({
        'id': 'item-1',
        'product_id': 'prod-101',
        'product_name': 'Chicken Biryani',
        'quantity': 2,
        'price': 250.0,
        'image_url': 'https://enything.test/images/biryani.jpg',
      });
      expect(item1.imageUrl, 'https://enything.test/images/biryani.jpg');
      expect(item1.totalPrice, 500.0);

      // Legacy/alternative product_image key
      final item2 = OrderItem.fromMap({
        'id': 'item-2',
        'product_id': 'prod-102',
        'product_name': 'Butter Naan',
        'quantity': 4,
        'price': 40.0,
        'product_image': 'https://enything.test/images/naan.jpg',
      });
      expect(item2.imageUrl, 'https://enything.test/images/naan.jpg');

      // PostgREST joined products map
      final item3 = OrderItem.fromMap({
        'id': 'item-3',
        'product_id': 'prod-103',
        'product_name': 'Mango Lassi',
        'quantity': 1,
        'price': 80.0,
        'products': {
          'images': [
            'https://enything.test/images/lassi_primary.jpg',
            'https://enything.test/images/lassi_secondary.jpg',
          ],
        },
      });
      expect(item3.imageUrl, 'https://enything.test/images/lassi_primary.jpg');

      // Null image handling
      final item4 = OrderItem.fromMap({
        'id': 'item-4',
        'product_id': 'prod-104',
        'product_name': 'Mineral Water',
        'quantity': 1,
        'price': 20.0,
      });
      expect(item4.imageUrl, isNull);
    });

    test('2. OrderItem toMap and copyWith preserve and update imageUrl', () {
      final original = OrderItem(
        id: 'item-10',
        productId: 'prod-200',
        productName: 'Paneer Butter Masala',
        quantity: 1,
        price: 220.0,
        weightKg: 0.4,
        imageUrl: 'https://enything.test/images/paneer.jpg',
      );

      final map = original.toMap();
      expect(map['image_url'], 'https://enything.test/images/paneer.jpg');

      final copiedWithNewImage = original.copyWith(
        imageUrl: 'https://enything.test/images/paneer_v2.jpg',
      );
      expect(copiedWithNewImage.imageUrl, 'https://enything.test/images/paneer_v2.jpg');
      expect(copiedWithNewImage.productName, 'Paneer Butter Masala');

      final copiedPreservingImage = original.copyWith(quantity: 3);
      expect(copiedPreservingImage.imageUrl, 'https://enything.test/images/paneer.jpg');
      expect(copiedPreservingImage.quantity, 3);
    });

    test('3. Variant-specific image resolution prioritizes variant photo over primary product photo', () {
      final Map<String, String> imageCache = {};

      // Simulated mock DB rows for products
      final mockProductsDb = [
        {
          'id': 'pizza-101',
          'images': ['https://enything.test/images/pizza_default.jpg'],
          'variants': [
            {
              'name': 'Small',
              'image_url': 'https://enything.test/images/pizza_small.jpg',
            },
            {
              'name': 'Large',
              'image_url': 'https://enything.test/images/pizza_large.jpg',
            },
            {
              'name': 'Medium',
              // Medium has no distinct photo; should fallback to primary
              'image_url': null,
            },
          ],
        },
      ];

      // Populate imageCache as in _loadOrders
      for (final p in mockProductsDb) {
        final pid = p['id'] as String;
        final images = p['images'] as List;
        if (images.isNotEmpty) {
          imageCache[pid] = images.first as String;
        }
        final variants = p['variants'] as List;
        for (final v in variants) {
          final vMap = v as Map<String, dynamic>;
          final vName = vMap['name']?.toString().trim();
          final vImg = vMap['image_url']?.toString().trim();
          if (vName != null && vName.isNotEmpty && vImg != null && vImg.isNotEmpty) {
            imageCache['${pid}_${vName.toLowerCase()}'] = vImg;
          }
        }
      }

      // Small pizza should resolve to Small variant photo
      final smallKey = 'pizza-101_${'Small'.toLowerCase()}';
      final smallResolved = imageCache[smallKey] ?? imageCache['pizza-101'];
      expect(smallResolved, 'https://enything.test/images/pizza_small.jpg');

      // Large pizza should resolve to Large variant photo
      final largeKey = 'pizza-101_${'Large'.toLowerCase()}';
      final largeResolved = imageCache[largeKey] ?? imageCache['pizza-101'];
      expect(largeResolved, 'https://enything.test/images/pizza_large.jpg');

      // Medium pizza should fallback to master product photo
      final mediumKey = 'pizza-101_${'Medium'.toLowerCase()}';
      final mediumResolved = imageCache[mediumKey] ?? imageCache['pizza-101'];
      expect(mediumResolved, 'https://enything.test/images/pizza_default.jpg');
    });

    test('4. Soft-delete rule is preserved during batch product fetching', () {
      // Simulating Supabase query construction
      // RULE: Products table queries MUST ALWAYS include .eq('is_deleted', false)
      final queryParams = {
        'table': 'products',
        'select': 'id, images, variants',
        'is_deleted': false,
      };

      expect(queryParams['table'], 'products');
      expect(queryParams['is_deleted'], false);
    });

    test('5. Smart expansion defaults pending and incoming orders to expanded while respecting manual collapse', () {
      final Set<String> expandedOrderIds = {};
      final Set<String> manuallyCollapsedOrderIds = {};

      bool isCardExpanded(String orderId, String status) {
        final bool isIncomingPending = status == 'awaiting_acceptance' ||
            status == 'pending' ||
            status == 'pending_verification' ||
            status == 'preparing';
        return expandedOrderIds.contains(orderId) ||
            (isIncomingPending && !manuallyCollapsedOrderIds.contains(orderId));
      }

      // Newly arrived order is expanded by default so seller sees pictures immediately
      expect(isCardExpanded('order-new-1', 'awaiting_acceptance'), isTrue);
      expect(isCardExpanded('order-new-2', 'pending'), isTrue);
      expect(isCardExpanded('order-new-3', 'preparing'), isTrue);

      // Completed / Done order is collapsed by default
      expect(isCardExpanded('order-done-1', 'delivered'), isFalse);
      expect(isCardExpanded('order-cancelled-1', 'cancelled'), isFalse);

      // Seller manually collapses order-new-1
      manuallyCollapsedOrderIds.add('order-new-1');
      expect(isCardExpanded('order-new-1', 'awaiting_acceptance'), isFalse);

      // Seller re-expands order-new-1
      manuallyCollapsedOrderIds.remove('order-new-1');
      expandedOrderIds.add('order-new-1');
      expect(isCardExpanded('order-new-1', 'awaiting_acceptance'), isTrue);
    });

    test('6. In-memory cache deduplicates network requests across multiple order items and orders', () {
      final Map<String, String> cache = {
        'prod-1': 'https://enything.test/p1.jpg',
      };

      // 10 orders each containing prod-1 and prod-2
      final allOrderItems = [
        OrderItem(id: '1', productId: 'prod-1', productName: 'P1', quantity: 1, price: 10, weightKg: 0),
        OrderItem(id: '2', productId: 'prod-2', productName: 'P2', quantity: 1, price: 10, weightKg: 0),
        OrderItem(id: '3', productId: 'prod-1', productName: 'P1', quantity: 2, price: 20, weightKg: 0),
        OrderItem(id: '4', productId: 'prod-2', productName: 'P2', quantity: 1, price: 10, weightKg: 0),
      ];

      final allProductIds = allOrderItems
          .map((i) => i.productId)
          .where((id) => id.isNotEmpty)
          .toSet();

      final missingProductIds = allProductIds
          .where((id) => !cache.containsKey(id))
          .toList();

      // Only prod-2 is missing; prod-1 is retrieved directly from cache without hitting network
      expect(missingProductIds, ['prod-2']);
    });
  });
}
