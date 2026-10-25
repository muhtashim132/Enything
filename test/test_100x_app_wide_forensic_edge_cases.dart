import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/order_group.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/rbac/admin_user_model.dart';

void main() {
  group('100x App-Wide Forensic Edge-Cases & Integrity Matrix', () {
    test('1. AdminUserModel parses PostgREST joined roles as List without crash', () {
      final postgrestListPayload = {
        'id': 'admin-uuid-1',
        'email': 'admin@enything.com',
        'full_name': 'Chief Super Admin',
        'admin_level': 'superadmin',
        'is_active': true,
        'is_suspended': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'roles': [
          {
            'id': 'role-uuid-1',
            'name': 'Super Administrator',
            'slug': 'super_admin',
            'description': 'Full System Access',
            'is_system': true,
            'color': '#8B2FC9',
            'icon': 'shield',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }
        ],
      };

      final admin = AdminUserModel.fromMap(postgrestListPayload);
      expect(admin.id, 'admin-uuid-1');
      expect(admin.role, isNotNull);
      expect(admin.role?.name, 'Super Administrator');
      expect(admin.role?.slug, 'super_admin');
    });

    test('2. AdminUserModel parses PostgREST joined roles as Map directly', () {
      final postgrestMapPayload = {
        'id': 'admin-uuid-2',
        'email': 'ops@enything.com',
        'full_name': 'Operations Dispatcher',
        'admin_level': 'admin',
        'is_active': true,
        'is_suspended': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'roles': {
          'id': 'role-uuid-2',
          'name': 'Order Dispatcher',
          'slug': 'dispatcher',
          'description': 'Proxy and Radar Dispatch',
          'is_system': false,
          'color': '#0284C7',
          'icon': 'navigation',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      };

      final admin = AdminUserModel.fromMap(postgrestMapPayload);
      expect(admin.id, 'admin-uuid-2');
      expect(admin.role, isNotNull);
      expect(admin.role?.name, 'Order Dispatcher');
      expect(admin.role?.slug, 'dispatcher');
    });

    test('3. OrderGroup accurately reports payment_failed when all sub-orders fail payment', () {
      final order1 = OrderModel(
        id: 'o-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        totalAmount: 200,
        deliveryCharges: 30,
        grandTotalCollected: 250,
        status: 'payment_failed',
        paymentMethod: 'upi',
        paymentStatus: 'failed',
        sellerAccepted: false,
        partnerAccepted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final order2 = OrderModel(
        id: 'o-2',
        shopId: 'shop-2',
        customerId: 'cust-1',
        totalAmount: 300,
        deliveryCharges: 30,
        grandTotalCollected: 350,
        status: 'payment_failed',
        paymentMethod: 'upi',
        paymentStatus: 'failed',
        sellerAccepted: false,
        partnerAccepted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final group = OrderGroup('group-1', [order1, order2]);
      expect(group.activeOrders, isEmpty);
      expect(group.groupStatus, 'payment_failed');
    });

    test('4. OrderGroup accurately reports shop_dispute_cancel when sub-orders disputed', () {
      final order1 = OrderModel(
        id: 'o-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        totalAmount: 200,
        deliveryCharges: 30,
        grandTotalCollected: 250,
        status: 'shop_dispute_cancel',
        paymentMethod: 'upi',
        paymentStatus: 'captured',
        sellerAccepted: true,
        partnerAccepted: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final group = OrderGroup('group-1', [order1]);
      expect(group.activeOrders, isEmpty);
      expect(group.groupStatus, 'shop_dispute_cancel');
    });

    test('5. 100% Prepaid Model Inviolability across OrderGroup', () {
      final order1 = OrderModel(
        id: 'o-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        totalAmount: 200,
        deliveryCharges: 30,
        grandTotalCollected: 250,
        status: 'confirmed',
        paymentMethod: 'upi',
        paymentStatus: 'captured',
        sellerAccepted: true,
        partnerAccepted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final group = OrderGroup('group-1', [order1]);
      expect(group.isPrepaid, isTrue);
      expect(group.isCod, isFalse);
      expect(group.codAmountToCollect, 0.0);
    });
  });
}
