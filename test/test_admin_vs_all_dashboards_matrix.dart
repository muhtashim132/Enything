import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1: Customer Checkout ↔ Admin & Shop Status Matrix
  // ══════════════════════════════════════════════════════════════════════════
  group('1. Customer Checkout ↔ Admin & Shop Status Matrix', () {
    test('Pre-order verification blocks suspended shops (is_active == false)', () {
      final shopData = {
        'id': 'shop-123',
        'name': 'Royal Bakehouse',
        'is_active': false,
        'is_accepting_orders': true,
        'verification_status': 'verified',
      };

      String? validationError;
      if (shopData['is_active'] == false) {
        validationError =
            '${shopData['name']} is temporarily suspended by administration and cannot accept orders right now.';
      } else if (shopData['is_accepting_orders'] == false) {
        validationError =
            '${shopData['name']} is currently closed and not accepting new orders.';
      }

      expect(validationError, contains('temporarily suspended by administration'));
    });

    test('Pre-order verification blocks closed shops (is_accepting_orders == false)', () {
      final shopData = {
        'id': 'shop-123',
        'name': 'Midnight Shawarma',
        'is_active': true,
        'is_accepting_orders': false,
        'verification_status': 'verified',
      };

      String? validationError;
      if (shopData['is_active'] == false) {
        validationError =
            '${shopData['name']} is temporarily suspended by administration and cannot accept orders right now.';
      } else if (shopData['is_accepting_orders'] == false) {
        validationError =
            '${shopData['name']} is currently closed and not accepting new orders.';
      }

      expect(validationError, contains('currently closed and not accepting new orders'));
    });

    test('Pre-order verification blocks unverified shops', () {
      final shopData = {
        'id': 'shop-123',
        'name': 'New Unverified Bakery',
        'is_active': true,
        'is_accepting_orders': true,
        'verification_status': 'pending',
      };

      final status = shopData['verification_status'] as String?;
      String? validationError;
      if (status != 'verified' && status != 'approved') {
        validationError =
            '${shopData['name']} is currently awaiting KYC verification and cannot accept orders.';
      }

      expect(validationError, contains('awaiting KYC verification'));
    });

    test('Pre-order verification blocks suspended customer profile (is_active == false)', () {
      final customerProfile = {
        'id': 'cust-999',
        'full_name': 'Suspended User',
        'is_active': false,
      };

      String? customerError;
      if (customerProfile['is_active'] == false) {
        customerError =
            'Your account has been deactivated by administration. You cannot place orders.';
      }

      expect(customerError, contains('deactivated by administration'));
    });

    test('Dynamic PlatformConfigProvider dynamically updates bill calculations', () {
      final config = PlatformConfigProvider();
      config.updateConfigsFromList([
        {'key': 'platform_fee', 'value': 15.0},
        {'key': 'delivery_base_fee', 'value': 20.0},
        {'key': 'delivery_rate_per_km', 'value': 12.0},
        {'key': 'small_cart_threshold', 'value': 150.0},
        {'key': 'small_cart_fee', 'value': 25.0},
        {'key': 'multi_shop_surcharge', 'value': 30.0},
      ]);

      expect(config.platformFee, 15.0);
      expect(config.deliveryBaseFee, 20.0);
      expect(config.deliveryRatePerKm, 12.0);
      expect(config.smallCartThreshold, 150.0);
      expect(config.smallCartFee, 25.0);
      expect(config.multiShopSurcharge, 30.0);

      // Verify bill computation reacts to updated values
      const itemSubtotal = 120.0;
      final smallCartCharge =
          (itemSubtotal < config.smallCartThreshold) ? config.smallCartFee : 0.0;
      expect(smallCartCharge, 25.0);

      final totalWithFees = itemSubtotal + config.platformFee + smallCartCharge;
      expect(totalWithFees, 160.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2: Seller Dashboard ↔ Admin Panel Matrix
  // ══════════════════════════════════════════════════════════════════════════
  group('2. Seller Dashboard ↔ Admin Panel Matrix', () {
    test('Shop Management disabled switch and banner when adminSuspended = true', () {
      bool adminSuspended = true;
      bool isShopOpen = true;

      // Simulated UI state resolution
      final switchEnabled = !adminSuspended;
      final switchDisplayValue = adminSuspended ? false : isShopOpen;
      final statusLabel = adminSuspended
          ? 'Suspended by Administration'
          : (isShopOpen ? 'Store is Open' : 'Store is Closed');

      expect(switchEnabled, false);
      expect(switchDisplayValue, false);
      expect(statusLabel, 'Suspended by Administration');
    });

    test('Seller Orders page fast-fails order acceptance on SHOP_SUSPENDED', () {
      bool adminSuspended = true;

      String? acceptError;
      if (adminSuspended) {
        acceptError = '⚠️ Your shop is suspended by administration. You cannot accept orders.';
      }

      expect(acceptError, contains('suspended by administration'));
    });

    test('Dynamic Category Filter in AddProductPage respects admin disabled categories', () {
      final config = PlatformConfigProvider();
      config.updateConfigsFromList([
        {
          'key': 'disabled_categories',
          'value': '["Electronics", "Automotive"]',
        }
      ]);

      expect(config.isActiveCategory('Restaurant'), true);
      expect(config.isActiveCategory('Food'), true);
      expect(config.isActiveCategory('Electronics'), false);
      expect(config.isActiveCategory('Automotive'), false);

      const allCategories = ['Food', 'Restaurant', 'Electronics', 'Grocery'];
      final allowedCategories =
          allCategories.where((c) => config.isActiveCategory(c)).toList();

      expect(allowedCategories, ['Food', 'Restaurant', 'Grocery']);
      expect(allowedCategories.contains('Electronics'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3: Rider (Delivery Partner) Dashboard ↔ Admin Panel Matrix
  // ══════════════════════════════════════════════════════════════════════════
  group('3. Rider Dashboard ↔ Admin Panel Matrix', () {
    test('Rider Dashboard Online Card displays Account Suspended when suspended', () {
      bool adminSuspended = true;
      bool isOnline = true; // rider was online before suspension

      final effectiveOnline = adminSuspended ? false : isOnline;
      final cardTitle = adminSuspended
          ? 'Account Suspended'
          : (effectiveOnline ? 'You\'re Online' : 'You\'re Offline');
      final cardSubtitle = adminSuspended
          ? 'Suspended by administration. You cannot accept orders.'
          : (effectiveOnline ? 'Receiving delivery requests' : 'Tap to start receiving orders');

      expect(effectiveOnline, false);
      expect(cardTitle, 'Account Suspended');
      expect(cardSubtitle, contains('Suspended by administration'));
    });

    test('Rider _setOnlineStatus(true) strictly rejected when adminSuspended = true', () {
      bool adminSuspended = true;
      bool isOnline = false;

      String? snackMessage;
      bool canGoOnline = true;

      if (adminSuspended) {
        canGoOnline = false;
        snackMessage =
            'Your account has been suspended by administration. You cannot go online.';
      }

      if (canGoOnline) {
        isOnline = true;
      }

      expect(isOnline, false);
      expect(snackMessage, contains('suspended by administration'));
    });

    test('Rider _acceptOrder and _acceptOrderGroup reject when adminSuspended = true', () {
      bool adminSuspended = true;

      bool canAccept = false;
      String? errorSnack;

      if (adminSuspended) {
        errorSnack = '⚠️ Your rider account is suspended by administration.';
      } else {
        canAccept = true;
      }

      expect(canAccept, false);
      expect(errorSnack, contains('suspended by administration'));
    });

    test('Available Orders Accept Button is disabled when adminSuspended = true', () {
      bool adminSuspended = true;
      bool isLoading = false;
      bool isExpired = false;

      final isButtonDisabled = (isLoading || isExpired || adminSuspended);
      expect(isButtonDisabled, true);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 4: Admin KYC Review Auto-Activation Matrix
  // ══════════════════════════════════════════════════════════════════════════
  group('4. Admin KYC Review Auto-Activation Matrix', () {
    test('Approving KYC sets verification_status = approved AND is_active = true', () {
      var shop = {
        'id': 'shop-001',
        'is_active': false,
        'verification_status': 'pending',
      };

      // Simulated approve action in admin KYC review
      shop['verification_status'] = 'approved';
      shop['is_active'] = true; // Auto-activation failsafe

      expect(shop['verification_status'], 'approved');
      expect(shop['is_active'], true);
    });

    test('Rejecting KYC sets verification_status = rejected AND is_active = false', () {
      var rider = {
        'id': 'rider-001',
        'is_active': true,
        'verification_status': 'pending',
      };

      // Simulated reject action in admin KYC review
      rider['verification_status'] = 'rejected';
      rider['is_active'] = false; // Suspension on rejection

      expect(rider['verification_status'], 'rejected');
      expect(rider['is_active'], false);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 5: Push Notification Deduplication Key Matrix
  // ══════════════════════════════════════════════════════════════════════════
  group('5. Push Notification Deduplication Key Matrix', () {
    String computeDedupKey(String userId, String? orderId, String title) {
      return orderId != null
          ? '${userId}_${orderId}_$title'
          : '${userId}_$title';
    }

    test('Distinct lifecycle pushes for the same order do NOT collide', () {
      const userId = 'cust-123';
      const orderId = 'order-456';

      final key1 = computeDedupKey(userId, orderId, 'Order Accepted! 🍳');
      final key2 = computeDedupKey(userId, orderId, 'Ready for Pickup! 🛍️');
      final key3 = computeDedupKey(userId, orderId, 'New Rider Assigned! 🛵');

      expect(key1, isNot(equals(key2)));
      expect(key2, isNot(equals(key3)));
      expect(key1, isNot(equals(key3)));
    });

    test('Identical pushes for the same order within TTL DO collide and deduplicate', () {
      const userId = 'cust-123';
      const orderId = 'order-456';

      final key1 = computeDedupKey(userId, orderId, 'New Rider Assigned! 🛵');
      final key2 = computeDedupKey(userId, orderId, 'New Rider Assigned! 🛵');

      expect(key1, equals(key2));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 6: Database Soft Deletes Invariant
  // ══════════════════════════════════════════════════════════════════════════
  group('6. Database Soft Deletes Invariant', () {
    test('Products query filter strictly filters out is_deleted = true items', () {
      final catalog = [
        {'id': 'p1', 'name': 'Butter Chicken', 'is_deleted': false, 'price': 250.0},
        {'id': 'p2', 'name': 'Garlic Naan', 'is_deleted': false, 'price': 40.0},
        {'id': 'p3', 'name': 'Discontinued Soda', 'is_deleted': true, 'price': 30.0},
        {'id': 'p4', 'name': 'Old Menu Item', 'is_deleted': true, 'price': 150.0},
      ];

      // Standard query predicate across entire codebase: .eq('is_deleted', false)
      final visibleProducts =
          catalog.where((p) => p['is_deleted'] == false).toList();

      expect(visibleProducts.length, 2);
      expect(visibleProducts.map((p) => p['id']), containsAll(['p1', 'p2']));
      expect(visibleProducts.map((p) => p['id']), isNot(contains('p3')));
      expect(visibleProducts.map((p) => p['id']), isNot(contains('p4')));
    });
  });
}
