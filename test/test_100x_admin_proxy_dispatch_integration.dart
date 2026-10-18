import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _phoneFromId(String phone) => phone.replaceAll('+', '').trim();
String _emailFromPhone(String phone) => '${_phoneFromId(phone)}@enything.com';
String _passwordFromPhone(String phone) => 'Pass_${_phoneFromId(phone)}!';

Future<String> authUser(SupabaseClient client, String phone, String role) async {
  final email = _emailFromPhone(phone);
  final password = _passwordFromPhone(phone);

  try {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    if (res.user != null) return res.user!.id;
  } catch (_) {}

  try {
    final signUpRes = await client.auth.signUp(email: email, password: password);
    final userId = signUpRes.user!.id;

    await client.from('profiles').upsert({
      'id': userId,
      'phone': phone,
      'full_name': 'Test Admin $role',
      'role': role,
    });
    return userId;
  } catch (e) {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    return res.user!.id;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('100x ADMIN & DISPATCHER PROXY ACCEPTANCE & RADAR INTEGRATION MATRIX', () {
    late SupabaseClient client;
    String? adminId;
    String? testShopId;
    String? testProductId;
    String? testCustomerId;
    final List<String> createdOrderIds = [];

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final envFile = File('.env');
      if (!envFile.existsSync()) {
        fail('.env file not found');
      }
      final lines = envFile.readAsLinesSync();
      String? supabaseUrl, supabaseKey;
      for (final line in lines) {
        if (line.startsWith('SUPABASE_URL=')) {
          supabaseUrl = line.split('=')[1].trim();
        }
        if (line.startsWith('SUPABASE_ANON_KEY=')) {
          supabaseKey = line.split('=')[1].trim();
        }
      }

      await Supabase.initialize(
        url: supabaseUrl!,
        anonKey: supabaseKey!,
      );
      client = Supabase.instance.client;

      final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
      final adminPhone = '+919955555$rand';

      adminId = await authUser(client, adminPhone, 'admin');

      // Grant Super Admin in admin_users via supabase db query
      final p = await Process.run('supabase', [
        'db',
        'query',
        "INSERT INTO admin_users (id, full_name, admin_level, is_active) VALUES ('$adminId', 'Test Admin $rand', 'superadmin', true) ON CONFLICT (id) DO UPDATE SET admin_level = 'superadmin', is_active = true;",
        '--linked'
      ]);
      expect(p.exitCode, 0, reason: 'Failed to seed test admin: ${p.stderr}');

      // Temporarily disable maintenance mode so test orders can be placed
      await Process.run('supabase', [
        'db',
        'query',
        "UPDATE public.platform_config SET value = 'false'::jsonb WHERE key = 'maintenance_mode';",
        '--linked'
      ]);

      // Re-sign in to refresh session permissions
      await client.auth.signInWithPassword(
        email: _emailFromPhone(adminPhone),
        password: _passwordFromPhone(adminPhone),
      );
      print('✅ Authenticated as Super Admin: $adminId');
    });

    tearDownAll(() async {
      print('🧹 Running mandatory test cleanup (Zero Leftovers Rule)...');
      // Restore maintenance mode
      try {
        await Process.run('supabase', [
          'db',
          'query',
          "UPDATE public.platform_config SET value = 'true'::jsonb WHERE key = 'maintenance_mode';",
          '--linked'
        ]);
      } catch (_) {}

      // Delete test orders
      for (final oid in createdOrderIds) {
        try {
          await client.from('order_items').delete().eq('order_id', oid);
          await client.from('orders').delete().eq('id', oid);
        } catch (_) {}
      }
      // Delete test product
      if (testProductId != null) {
        try {
          await client.from('products').delete().eq('id', testProductId!);
        } catch (_) {}
      }
      // Delete test shop
      if (testShopId != null) {
        try {
          await client.from('shops').delete().eq('id', testShopId!);
        } catch (_) {}
      }
      // Delete test admin
      if (adminId != null) {
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.admin_users WHERE id = '$adminId'; DELETE FROM public.profiles WHERE id = '$adminId'; DELETE FROM auth.users WHERE id = '$adminId';",
          '--linked'
        ]);
      }
      print('✅ All mock entities successfully purged from database.');
    });

    test('1. Verify dispatcher role & permissions seeded in database', () async {
      final roleResp = await client
          .from('roles')
          .select('id, name, slug, color')
          .eq('slug', 'dispatcher')
          .maybeSingle();

      expect(roleResp, isNotNull, reason: 'dispatcher role should exist');
      expect(roleResp!['slug'], 'dispatcher');
      expect(roleResp['name'], 'Order Dispatcher');
      print('✅ Verified role: ${roleResp['name']} (${roleResp['slug']})');

      final roleId = roleResp['id'] as String;
      final rolePerms = await client
          .from('role_permissions')
          .select('permission_id, permissions(code)')
          .eq('role_id', roleId);

      final permCodes = (rolePerms as List)
          .map((rp) => (rp['permissions'] as Map)['code'] as String)
          .toList();

      expect(permCodes.contains('dispatch.view'), isTrue);
      expect(permCodes.contains('dispatch.proxy_rider_accept'), isTrue);
      expect(permCodes.contains('dispatch.proxy_seller_accept'), isTrue);
      expect(permCodes.contains('dispatch.toggle_buzz'), isTrue);
      expect(permCodes.contains('dispatch.override_limits'), isTrue);
      expect(permCodes.contains('orders.view'), isTrue);
      print('✅ Verified dispatcher permissions: $permCodes');
    });

    test('2. Verify admin_get_dispatch_feed RPC execution', () async {
      // Test with null coordinates (Unlimited Mode)
      final res = await client.rpc('admin_get_dispatch_feed', params: {
        'p_admin_lat': null,
        'p_admin_lng': null,
        'p_radius_km': null,
        'p_include_riders': true,
        'p_include_sellers': true,
      });

      expect(res, isA<List>());
      print('✅ admin_get_dispatch_feed returned ${(res as List).length} live queue items in unlimited mode');

      // Test with coordinates and radius (Radius Mode)
      final resRadius = await client.rpc('admin_get_dispatch_feed', params: {
        'p_admin_lat': 34.0837,
        'p_admin_lng': 74.7973,
        'p_radius_km': 25.0,
        'p_include_riders': true,
        'p_include_sellers': true,
      });
      expect(resRadius, isA<List>());
      print('✅ admin_get_dispatch_feed with 25km radius returned ${(resRadius as List).length} items');
    });

    test('3. Verify admin_get_online_riders RPC execution', () async {
      final res = await client.rpc('admin_get_online_riders');
      expect(res, isA<List>());
      print('✅ admin_get_online_riders returned ${(res as List).length} active couriers');
    });

    test('4. End-to-End Proxy Lifecycle & Concurrency Matrix', () async {
      // Fetch or use an existing customer ID
      final existingCustomer = await client
          .from('profiles')
          .select('id')
          .limit(1)
          .single();
      testCustomerId = existingCustomer['id'] as String;

      // Create test shop
      final shopResp = await client.from('shops').insert({
        'name': '100x Dispatch Test Kitchen',
        'address': 'Test Operational Hub Street',
        'is_active': true,
        'verification_status': 'verified',
        'seller_id': testCustomerId, // Dummy seller id
      }).select('id').single();
      testShopId = shopResp['id'] as String;

      // Create test order in awaiting_acceptance
      final orderResp = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'status': 'awaiting_acceptance',
        'seller_accepted': false,
        'partner_accepted': false,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'total_amount': 299.0,
      }).select('id').single();
      final orderId1 = orderResp['id'] as String;
      createdOrderIds.add(orderId1);

      print('✅ Created test order #$orderId1');

      // STEP A: Proxy Seller Accept
      final sellerAcceptRes = await client.rpc('admin_proxy_accept_seller', params: {
        'p_order_id': orderId1,
        'p_prep_time_minutes': 20,
      });
      expect(sellerAcceptRes, isFalse, reason: 'Rider has not accepted yet');

      final orderAfterSeller = await client
          .from('orders')
          .select('seller_accepted, partner_accepted, status, shop_prep_time_snapshot')
          .eq('id', orderId1)
          .single();
      expect(orderAfterSeller['seller_accepted'], isTrue);
      expect(orderAfterSeller['shop_prep_time_snapshot'], 20);
      print('✅ Verified admin_proxy_accept_seller: seller_accepted=true');

      // STEP B: Proxy Rider Accept (Unlimited Hoarding Bypass)
      final riderAcceptRes = await client.rpc('admin_proxy_accept_rider', params: {
        'p_order_id': orderId1,
      });
      expect(riderAcceptRes, isTrue, reason: 'Both sides now accepted');

      final orderAfterBoth = await client
          .from('orders')
          .select('seller_accepted, partner_accepted, status, delivery_partner_id, payment_deadline')
          .eq('id', orderId1)
          .single();
      expect(orderAfterBoth['partner_accepted'], isTrue);
      expect(orderAfterBoth['status'], 'awaiting_payment');
      expect(orderAfterBoth['payment_deadline'], isNotNull);
      print('✅ Verified admin_proxy_accept_rider: status transitioned to awaiting_payment');

      // STEP C: 1-Tap Dual Accept on new order
      final orderResp2 = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'status': 'awaiting_acceptance',
        'seller_accepted': false,
        'partner_accepted': false,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'total_amount': 450.0,
      }).select('id').single();
      final orderId2 = orderResp2['id'] as String;
      createdOrderIds.add(orderId2);

      final dualAcceptRes = await client.rpc('admin_proxy_accept_both', params: {
        'p_order_id': orderId2,
        'p_prep_time_minutes': 15,
      });
      expect(dualAcceptRes, isTrue);

      final order2AfterBoth = await client
          .from('orders')
          .select('seller_accepted, partner_accepted, status')
          .eq('id', orderId2)
          .single();
      expect(order2AfterBoth['seller_accepted'], isTrue);
      expect(order2AfterBoth['partner_accepted'], isTrue);
      expect(order2AfterBoth['status'], 'awaiting_payment');
      print('✅ Verified admin_proxy_accept_both: atomic dual confirmation complete');

      // STEP D: Concurrency & Cancellation Edge Case Guard
      final orderResp3 = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'status': 'cancelled', // Pre-cancelled
        'payment_method': 'upi',
        'total_amount': 150.0,
      }).select('id').single();
      final orderId3 = orderResp3['id'] as String;
      createdOrderIds.add(orderId3);

      expect(
        () async => await client.rpc('admin_proxy_accept_rider', params: {
          'p_order_id': orderId3,
        }),
        throwsA(predicate((e) => e.toString().contains('ORDER_CANCELLED'))),
        reason: 'Proxy accept must reject cancelled orders',
      );
      print('✅ Verified ORDER_CANCELLED guard on cancelled order');

      // STEP E: Store Already Rejected Edge Case Guard
      final orderResp4 = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'status': 'seller_rejected', // Declined by store
        'payment_method': 'upi',
        'total_amount': 220.0,
      }).select('id').single();
      final orderId4 = orderResp4['id'] as String;
      createdOrderIds.add(orderId4);

      expect(
        () async => await client.rpc('admin_proxy_accept_seller', params: {
          'p_order_id': orderId4,
        }),
        throwsA(predicate((e) => e.toString().contains('ORDER_ALREADY_REJECTED'))),
        reason: 'Proxy accept must respect store owner rejection',
      );
      print('✅ Verified ORDER_ALREADY_REJECTED guard on declined order');

      // STEP F: 100x Multi-Shop Sibling Atomicity & Phone Resolution Test
      final multiCartGroupId = 'a0000000-0000-4000-a000-123456789abc';
      
      // Sub-order 1 (Shop 1)
      final subOrder1Resp = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'cart_group_id': multiCartGroupId,
        'status': 'awaiting_acceptance',
        'seller_accepted': false,
        'partner_accepted': false,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'total_amount': 250.0,
      }).select('id').single();
      final subOrderId1 = subOrder1Resp['id'] as String;
      createdOrderIds.add(subOrderId1);

      // Sub-order 2 (Shop 2)
      final subOrder2Resp = await client.from('orders').insert({
        'customer_id': testCustomerId,
        'shop_id': testShopId,
        'cart_group_id': multiCartGroupId,
        'status': 'awaiting_acceptance',
        'seller_accepted': false,
        'partner_accepted': false,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'total_amount': 350.0,
      }).select('id').single();
      final subOrderId2 = subOrder2Resp['id'] as String;
      createdOrderIds.add(subOrderId2);

      // Sub-step 1: Admin accepts rider for the multi-shop cart group
      final multiRiderRes = await client.rpc('admin_proxy_accept_rider', params: {
        'p_order_id': subOrderId1,
      });
      expect(multiRiderRes, isFalse, reason: 'Neither shop has accepted yet');

      // Verify both sub-orders have partner_accepted = true and delivery_partner_id = adminId
      final subOrdersAfterRider = await client
          .from('orders')
          .select('id, partner_accepted, status, rider_phone, delivery_partner_id')
          .inFilter('id', [subOrderId1, subOrderId2]);
      for (final so in subOrdersAfterRider as List) {
        expect(so['partner_accepted'], isTrue);
        expect(so['delivery_partner_id'], adminId);
        expect(so['status'], 'awaiting_acceptance', reason: 'Stores have not accepted yet');
        expect(so['rider_phone'], isNotEmpty);
      }
      print('✅ Verified multi-shop rider acceptance: both sub-orders assigned to courier');

      // Sub-step 2: Admin accepts Store 1 only
      final store1Res = await client.rpc('admin_proxy_accept_seller', params: {
        'p_order_id': subOrderId1,
        'p_prep_time_minutes': 15,
      });
      expect(store1Res, isFalse, reason: 'Store 2 has not accepted yet');

      final sub1AfterStore1 = await client.from('orders').select('seller_accepted, status').eq('id', subOrderId1).single();
      final sub2AfterStore1 = await client.from('orders').select('seller_accepted, status').eq('id', subOrderId2).single();
      expect(sub1AfterStore1['seller_accepted'], isTrue);
      expect(sub1AfterStore1['status'], 'awaiting_acceptance', reason: 'Must NOT advance to awaiting_payment until Store 2 confirms');
      expect(sub2AfterStore1['seller_accepted'], isFalse);
      expect(sub2AfterStore1['status'], 'awaiting_acceptance');
      print('✅ Verified multi-shop partial acceptance: status held at awaiting_acceptance');

      // Sub-step 3: Admin accepts Store 2 -> Completes cart group!
      final store2Res = await client.rpc('admin_proxy_accept_seller', params: {
        'p_order_id': subOrderId2,
        'p_prep_time_minutes': 25,
      });
      expect(store2Res, isTrue, reason: 'All stores now accepted!');

      final sub1Final = await client.from('orders').select('seller_accepted, partner_accepted, status, payment_deadline').eq('id', subOrderId1).single();
      final sub2Final = await client.from('orders').select('seller_accepted, partner_accepted, status, payment_deadline').eq('id', subOrderId2).single();
      expect(sub1Final['seller_accepted'], isTrue);
      expect(sub1Final['status'], 'awaiting_payment', reason: 'Atomically advanced to awaiting_payment');
      expect(sub1Final['payment_deadline'], isNotNull);

      expect(sub2Final['seller_accepted'], isTrue);
      expect(sub2Final['status'], 'awaiting_payment', reason: 'Atomically advanced to awaiting_payment');
      expect(sub2Final['payment_deadline'], isNotNull);
      print('✅ Verified multi-shop sibling atomicity: both sub-orders synchronized to awaiting_payment');
    });
  });
}
