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
      'full_name': 'Test User $role',
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

  group('100x CUSTOM EVENT QUOTES & P2P CATERING PIPELINE INTEGRATION MATRIX', () {
    late SupabaseClient client;
    String? adminId;
    String? customerId;
    String? testOrderId;
    String? testQuoteId;

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
      final adminPhone = '+919876543$rand';
      final customerPhone = '+919123456$rand';

      // 1. Authenticate Admin
      adminId = await authUser(client, adminPhone, 'admin');

      // Grant Super Admin privileges
      await Process.run('supabase', [
        'db',
        'query',
        "INSERT INTO admin_users (id, full_name, admin_level, is_active) VALUES ('$adminId', 'Test Admin $rand', 'superadmin', true) ON CONFLICT (id) DO UPDATE SET admin_level = 'superadmin', is_active = true;",
        '--linked'
      ]);

      // Grant profile role super_admin
      await Process.run('supabase', [
        'db',
        'query',
        "UPDATE public.profiles SET role = 'super_admin' WHERE id = '$adminId';",
        '--linked'
      ]);

      // Re-sign in admin
      await client.auth.signInWithPassword(
        email: _emailFromPhone(adminPhone),
        password: _passwordFromPhone(adminPhone),
      );

      // 2. Authenticate Customer
      customerId = await authUser(client, customerPhone, 'customer');

      // Re-sign in as admin for test execution
      await client.auth.signInWithPassword(
        email: _emailFromPhone(adminPhone),
        password: _passwordFromPhone(adminPhone),
      );

      print('✅ Test Harness Initialized: Admin=$adminId, Customer=$customerId');
    });

    tearDownAll(() async {
      print('🧹 Executing immediate test entity cleanup (Zero Leftovers Rule)...');
      if (testOrderId != null) {
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.audit_logs WHERE entity_id = '$testOrderId';"
          "DELETE FROM public.bulk_dispatch_riders WHERE dispatch_group_id IN (SELECT id FROM public.bulk_dispatch_groups WHERE order_id = '$testOrderId');"
          "DELETE FROM public.bulk_dispatch_groups WHERE order_id = '$testOrderId';"
          "DELETE FROM public.bulk_orders WHERE order_id = '$testOrderId';"
          "DELETE FROM public.orders WHERE id = '$testOrderId';",
          '--linked'
        ]);
      }
      if (testQuoteId != null) {
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.quote_requests WHERE id = '$testQuoteId';",
          '--linked'
        ]);
      }
      if (customerId != null) {
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.profiles WHERE id = '$customerId';",
          '--linked'
        ]);
      }
      if (adminId != null) {
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.admin_users WHERE id = '$adminId';"
          "DELETE FROM public.profiles WHERE id = '$adminId';",
          '--linked'
        ]);
      }
      print('✅ All test leftovers successfully purged from live database.');
    });

    test('1. Create Custom Event Quote & Seed Paid Catering Order', () async {
      // Create test order directly for event party
      final orderRes = await client.from('orders').insert({
        'customer_id': customerId,
        'order_type': 'manual_quote',
        'status': 'bulk_pending',
        'total_amount': 25000.0,
        'grand_total_collected': 25000.0,
        'payment_status': 'captured',
        'payment_method': 'upi',
        'delivery_otp': '7821',
        'address': 'Grand Ballroom, Srinagar, J&K',
        'address_label': 'Wedding Reception',
        'customer_phone': '+919123456789',
      }).select().single();

      testOrderId = orderRes['id'].toString();
      expect(testOrderId, isNotNull);
      expect(orderRes['status'], 'bulk_pending');
      expect(orderRes['shop_id'], isNull, reason: 'Initially no kitchen is appointed');
      print('✅ Event catering order created: $testOrderId (Status: bulk_pending, shop_id: null)');
    });

    test('2. Step 1: Appoint Kitchen WITHOUT forced shop selection (NULL shop_id)', () async {
      expect(testOrderId, isNotNull);

      // Admin appoints kitchen without providing any shop_id (external/offline kitchen)
      final appointRes = await client.rpc('admin_appoint_catering_kitchen', params: {
        'p_order_id': testOrderId,
        'p_auto_confirm': true,
        'p_total_batches': 1,
      });

      expect(appointRes['success'], true);
      expect(appointRes['status'], 'bulk_confirmed');
      print('✅ Step 1 Success: Kitchen Appointed without name/selection -> Status: bulk_confirmed');

      // Verify orders table
      final order = await client.from('orders').select().eq('id', testOrderId!).single();
      expect(order['status'], 'bulk_confirmed');
      expect(order['seller_accepted'], true);

      // Verify bulk_orders metadata record self-healed
      final bulk = await client.from('bulk_orders').select().eq('order_id', testOrderId!).single();
      expect(bulk['seller_response_status'], 'accepted');
      expect(bulk['total_batches'], 1);
      expect(bulk['batches_packed'], 0);
    });

    test('3. Step 2: Mark Food Ready in 1-Tap (No micro-batches)', () async {
      expect(testOrderId, isNotNull);

      // Admin marks food ready directly
      final readyRes = await client.rpc('admin_update_catering_packaging', params: {
        'p_order_id': testOrderId,
        'p_batches_packed': 1,
        'p_total_batches': 1,
      });

      expect(readyRes['success'], true);
      expect(readyRes['status'], 'bulk_ready');
      print('✅ Step 2 Success: Food Marked Ready -> Status: bulk_ready');

      // Verify orders table
      final order = await client.from('orders').select().eq('id', testOrderId!).single();
      expect(order['status'], 'bulk_ready');
      expect(order['order_ready_time'], isNotNull);

      // Verify bulk_orders table
      final bulk = await client.from('bulk_orders').select().eq('order_id', testOrderId!).single();
      expect(bulk['batches_packed'], 1);
      expect(bulk['all_batches_packed_at'], isNotNull);
    });

    test('4. Step 3: Deliver Myself / Out for Delivery (In-House Van, No Gig Rider)', () async {
      expect(testOrderId, isNotNull);

      // Admin dispatches order via self delivery
      final dispatchRes = await client.rpc('admin_dispatch_catering_order', params: {
        'p_order_id': testOrderId,
        'p_dispatch_type': 'admin_self_delivery',
        'p_driver_name': 'In-House Team',
      });

      expect(dispatchRes['success'], true);
      expect(dispatchRes['status'], 'bulk_dispatched');
      print('✅ Step 3 Success: Self-Delivery Dispatched -> Status: bulk_dispatched');

      // Verify orders table
      final order = await client.from('orders').select().eq('id', testOrderId!).single();
      expect(order['status'], 'bulk_dispatched');
      expect(order['partner_accepted'], true);

      // Verify bulk_dispatch_groups
      final groupId = dispatchRes['dispatch_group_id'];
      expect(groupId, isNotNull);
      final group = await client.from('bulk_dispatch_groups').select().eq('id', groupId).single();
      expect(group['dispatch_type'], 'merchant_delivery');
      expect(group['driver_name'], 'In-House Team');
      expect(group['dispatch_status'], 'in_transit');
    });

    test('5. Step 4: Complete Delivery with Customer Handover OTP', () async {
      expect(testOrderId, isNotNull);

      // A. Test invalid OTP -> Should fail with INVALID_OTP
      expect(
        () async => await client.rpc('admin_complete_catering_delivery', params: {
          'p_order_id': testOrderId,
          'p_otp': '0000',
          'p_admin_override': false,
        }),
        throwsA(predicate((e) => e.toString().contains('INVALID_OTP'))),
      );
      print('✅ Handover Shield verified: Invalid OTP rejected.');

      // B. Test Super Admin Override -> Should succeed without checking OTP
      // First verify correct OTP handover
      final completeRes = await client.rpc('admin_complete_catering_delivery', params: {
        'p_order_id': testOrderId,
        'p_otp': '7821', // Customer's real OTP
        'p_admin_override': false,
      });

      expect(completeRes['success'], true);
      expect(completeRes['status'], 'delivered');
      print('✅ Step 4 Success: Handover OTP verified -> Status: delivered 🎉');

      // Verify orders table final terminal state
      final order = await client.from('orders').select().eq('id', testOrderId!).single();
      expect(order['status'], 'delivered');

      // Verify bulk_dispatch_groups marked delivered
      final group = await client.from('bulk_dispatch_groups').select().eq('order_id', testOrderId!).single();
      expect(group['dispatch_status'], 'delivered');
    });

    test('6. Edge Case: Self-healing bulk_orders when missing before dispatch', () async {
      // Create a second test order without bulk_orders record
      final secondOrderRes = await client.from('orders').insert({
        'customer_id': customerId,
        'order_type': 'manual_quote',
        'status': 'bulk_pending',
        'total_amount': 15000.0,
        'payment_status': 'captured',
        'payment_method': 'upi',
        'delivery_otp': '4321',
      }).select().single();

      final secondOrderId = secondOrderRes['id'].toString();

      try {
        // Appoint kitchen without prior metadata -> Self heals
        final res1 = await client.rpc('admin_appoint_catering_kitchen', params: {
          'p_order_id': secondOrderId,
          'p_auto_confirm': true,
        });
        expect(res1['success'], true);

        // Mark ready directly -> Self heals
        final res2 = await client.rpc('admin_update_catering_packaging', params: {
          'p_order_id': secondOrderId,
          'p_batches_packed': 1,
        });
        expect(res2['success'], true);

        // Dispatch directly -> Self heals
        final res3 = await client.rpc('admin_dispatch_catering_order', params: {
          'p_order_id': secondOrderId,
          'p_dispatch_type': 'admin_self_delivery',
        });
        expect(res3['success'], true);

        // Super Admin override handover -> Success
        final res4 = await client.rpc('admin_complete_catering_delivery', params: {
          'p_order_id': secondOrderId,
          'p_admin_override': true,
        });
        expect(res4['success'], true);
        print('✅ Edge Case Success: Self-healing pipeline resilient across missing metadata.');
      } finally {
        // Immediate cleanup of second order
        await Process.run('supabase', [
          'db',
          'query',
          "DELETE FROM public.audit_logs WHERE entity_id = '$secondOrderId';"
          "DELETE FROM public.bulk_dispatch_groups WHERE order_id = '$secondOrderId';"
          "DELETE FROM public.bulk_orders WHERE order_id = '$secondOrderId';"
          "DELETE FROM public.orders WHERE id = '$secondOrderId';",
          '--linked'
        ]);
      }
    });
  });
}
