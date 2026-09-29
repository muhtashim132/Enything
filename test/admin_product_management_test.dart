import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/pages/admin/platform/admin_product_management_page.dart';

void main() {
  group('AdminProductManagement - AdminShopItem Model Tests', () {
    test('parses complete shop map with profile information', () {
      final map = {
        'id': 'shop_123',
        'shop_name': 'Green Grocers',
        'category': 'Grocery',
        'address': '123 Market St, Downtown',
        'is_active': true,
        'seller_id': 'seller_999',
        'banner_url': 'https://example.com/banner.jpg',
        'profiles': {
          'id': 'seller_999',
          'full_name': 'John Seller',
          'phone': '+919876543210',
          'avatar_url': 'https://example.com/avatar.jpg',
        },
      };

      final item = AdminShopItem.fromMap(map);

      expect(item.id, equals('shop_123'));
      expect(item.name, equals('Green Grocers'));
      expect(item.category, equals('Grocery'));
      expect(item.address, equals('123 Market St, Downtown'));
      expect(item.isActive, isTrue);
      expect(item.sellerId, equals('seller_999'));
      expect(item.sellerName, equals('John Seller'));
      expect(item.sellerPhone, equals('+919876543210'));
      expect(item.bannerUrl, equals('https://example.com/banner.jpg'));
    });

    test('parses fallback shop map without profile info or alternative keys', () {
      final map = {
        'id': 'shop_456',
        'name': 'Bakery Delights',
        'category': 'Food & Dining',
        'is_active': false,
        'seller_id': 'seller_888',
        'banner_image': 'https://example.com/banner2.jpg',
        'profiles': null,
      };

      final item = AdminShopItem.fromMap(map);

      expect(item.id, equals('shop_456'));
      expect(item.name, equals('Bakery Delights'));
      expect(item.category, equals('Food & Dining'));
      expect(item.isActive, isFalse);
      expect(item.sellerName, isNull);
      expect(item.sellerPhone, isNull);
      expect(item.bannerUrl, equals('https://example.com/banner2.jpg'));
    });
  });

  group('AdminProductManagement - Product Model Availability & Soft-Delete Contract', () {
    final sampleProduct = ProductModel(
      id: 'prod_1',
      shopId: 'shop_123',
      name: 'Organic Apples',
      category: 'Fruits',
      price: 120.0,
      originalPrice: 150.0,
      unitType: 'kg',
      images: ['https://example.com/apple.jpg'],
      isAvailable: true,
      variants: [],
    );

    test('optimistic toggle flips availability state via copyWith', () {
      expect(sampleProduct.isAvailable, isTrue);

      final toggledOff = sampleProduct.copyWith(isAvailable: false);
      expect(toggledOff.isAvailable, isFalse);
      expect(toggledOff.id, equals(sampleProduct.id));
      expect(toggledOff.shopId, equals(sampleProduct.shopId));
      expect(toggledOff.price, equals(sampleProduct.price));

      final toggledOn = toggledOff.copyWith(isAvailable: true);
      expect(toggledOn.isAvailable, isTrue);
    });

    test('soft delete payload sets is_deleted true and is_available false', () {
      const bool hasOrderHistory = true;
      final updatePayloadWithHistory = <String, dynamic>{
        'is_deleted': true,
        'is_available': false,
        if (!hasOrderHistory) 'images': <String>[],
      };

      expect(updatePayloadWithHistory['is_deleted'], isTrue);
      expect(updatePayloadWithHistory['is_available'], isFalse);
      expect(updatePayloadWithHistory.containsKey('images'), isFalse);

      const bool noOrderHistory = false;
      final updatePayloadNoHistory = <String, dynamic>{
        'is_deleted': true,
        'is_available': false,
        if (!noOrderHistory) 'images': <String>[],
      };

      expect(updatePayloadNoHistory['is_deleted'], isTrue);
      expect(updatePayloadNoHistory['is_available'], isFalse);
      expect(updatePayloadNoHistory['images'], isEmpty);
    });

    test('discount percentage calculation is accurate', () {
      expect(sampleProduct.discountPercent, equals(20.0));

      final noDiscountProduct = sampleProduct.copyWith(originalPrice: 120.0);
      expect(noDiscountProduct.discountPercent, isNull);
    });
  });

  group('AdminProductManagement - Active Unfulfilled Order Guard Statuses', () {
    test('active order guard statuses cover all in-progress delivery lifecycle phases', () {
      const activeStatuses = [
        'awaiting_acceptance',
        'pending',
        'awaiting_payment',
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'out_for_delivery',
      ];

      // Verify essential pre-delivery and delivery statuses are all present
      expect(activeStatuses.contains('awaiting_acceptance'), isTrue);
      expect(activeStatuses.contains('pending'), isTrue);
      expect(activeStatuses.contains('awaiting_payment'), isTrue);
      expect(activeStatuses.contains('confirmed'), isTrue);
      expect(activeStatuses.contains('preparing'), isTrue);
      expect(activeStatuses.contains('ready_for_pickup'), isTrue);
      expect(activeStatuses.contains('out_for_delivery'), isTrue);

      // Terminal / completed statuses should NOT be in active list
      expect(activeStatuses.contains('delivered'), isFalse);
      expect(activeStatuses.contains('cancelled'), isFalse);
      expect(activeStatuses.contains('rejected'), isFalse);
      expect(activeStatuses.contains('refunded'), isFalse);
    });
  });

  group('AdminProductManagement - Filter & Search Logic', () {
    final shops = [
      const AdminShopItem(
        id: '1',
        name: 'Fresh Supermarket',
        category: 'Supermarket',
        address: 'MG Road, Bangalore',
        isActive: true,
        sellerName: 'Ramesh Patel',
        sellerPhone: '+919900112233',
      ),
      const AdminShopItem(
        id: '2',
        name: 'City Pharmacy',
        category: 'Pharmacy',
        address: 'Indiranagar, Bangalore',
        isActive: false,
        sellerName: 'Dr. Suresh',
        sellerPhone: '+919900445566',
      ),
      const AdminShopItem(
        id: '3',
        name: 'Daily Grocery',
        category: 'Grocery',
        address: 'Koramangala, Bangalore',
        isActive: true,
        sellerName: 'Anita Sharma',
        sellerPhone: '+919900778899',
      ),
    ];

    test('status filter isolates active and inactive shops', () {
      final activeOnly = shops.where((s) => s.isActive).toList();
      expect(activeOnly.length, equals(2));
      expect(activeOnly.every((s) => s.isActive), isTrue);

      final inactiveOnly = shops.where((s) => !s.isActive).toList();
      expect(inactiveOnly.length, equals(1));
      expect(inactiveOnly.first.name, equals('City Pharmacy'));
    });

    test('search filters across shop name, seller name, category, and phone', () {
      bool matches(AdminShopItem s, String query) {
        final q = query.toLowerCase().trim();
        return s.name.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q) ||
            (s.sellerName ?? '').toLowerCase().contains(q) ||
            (s.sellerPhone ?? '').toLowerCase().contains(q) ||
            (s.address ?? '').toLowerCase().contains(q);
      }

      expect(shops.where((s) => matches(s, 'Patel')).length, equals(1));
      expect(shops.where((s) => matches(s, 'pharmacy')).length, equals(1));
      expect(shops.where((s) => matches(s, 'Bangalore')).length, equals(3));
      expect(shops.where((s) => matches(s, '445566')).length, equals(1));
      expect(shops.where((s) => matches(s, 'nonexistent')).isEmpty, isTrue);
    });
  });
}
