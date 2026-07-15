import 'package:supabase/supabase.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  print('--- Starting Enything Comprehensive Flow Test ---');
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('No .env file found');
    exit(1);
  }
  
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl;
  String? supabaseKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
  }

  if (supabaseUrl == null || supabaseKey == null) {
    print('Missing environment variables.');
    exit(1);
  }

  final client = SupabaseClient(
    supabaseUrl, 
    supabaseKey, 
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit)
  );
  print('Connected to Supabase');

  try {
    await runComprehensiveTests(client);
    print('\n✅ ALL COMPREHENSIVE COMBINATIONS PASSED');
  } catch (e, stack) {
    print('\n❌ TEST FAILED: $e');
    print(stack);
    exit(1);
  }
}

String _emailFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return '$digits@auth.enything.app';
}

String _passwordFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final bytes = utf8.encode('Enything_${digits}_Secured#2026');
  final digest = sha256.convert(bytes);
  return 'EnY\$${digest.toString().substring(0, 16)}';
}

Future<String> authUser(SupabaseClient client, String phone, String role) async {
  final email = _emailFromPhone(phone);
  final password = _passwordFromPhone(phone);
  
  String? userId;
  try {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    userId = res.user?.id;
  } catch (e) {
    try {
      final res = await client.auth.signUp(email: email, password: password, data: <String, dynamic>{'phone': phone});
      userId = res.user?.id;
    } catch (e2) {
      throw Exception('Failed to auth user $phone: $e2');
    }
  }

  if (userId == null) throw Exception('Failed to get user id for $phone');

  await client.from('profiles').upsert({
    'id': userId,
    'role': role,
    'full_name': 'Test $role',
    'phone': phone,
  });

  if (role == 'seller') {
    final existingShop = await client.from('shops').select('id').eq('seller_id', userId).maybeSingle();
    if (existingShop == null) {
      await client.from('shops').insert({
        'seller_id': userId,
        'name': 'Test Shop $phone',
        'address': 'Test Address',
        'category': 'food',
        'is_active': true,
        'is_accepting_orders': true,
        'verification_status': 'verified',
        'location': 'POINT(74.6366 34.4225)',
      });
    }
  } else if (role == 'delivery_partner') {
    final existingDp = await client.from('delivery_partners').select('id').eq('id', userId).maybeSingle();
    if (existingDp == null) {
      await client.from('delivery_partners').insert({
        'id': userId,
        'vehicle_type': 'bike',
        'vehicle_number': 'TEST-123',
        'is_active': true,
        'verification_status': 'verified',
        'location': 'POINT(74.6366 34.4225)',
      });
    }
  }
  return userId;
}

Future<void> runComprehensiveTests(SupabaseClient client) async {
  // Generate random prefix to ensure clean auth data every run
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  
  final c1Phone = '+9199991$rand';
  final c2Phone = '+9199992$rand';
  final s1Phone = '+9199993$rand';
  final s2Phone = '+9199994$rand';
  final d1Phone = '+9199995$rand';

  print('Authenticating Multi-Users...');
  final c1Id = await authUser(client, c1Phone, 'customer');
  final c2Id = await authUser(client, c2Phone, 'customer');
  final s1Id = await authUser(client, s1Phone, 'seller');
  final s2Id = await authUser(client, s2Phone, 'seller');
  final d1Id = await authUser(client, d1Phone, 'delivery_partner');

  final s1Shop = await client.from('shops').select('id').eq('seller_id', s1Id).single();
  final s2Shop = await client.from('shops').select('id').eq('seller_id', s2Id).single();
  
  // Create products
  final p1Id = const Uuid().v4();
  final p2Id = const Uuid().v4();
  
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.from('products').insert([
    {'id': p1Id, 'shop_id': s1Shop['id'], 'name': 'Item S1', 'category': 'food', 'price': 100, 'is_available': true, 'total_quantity': 10},
  ]);
  
  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  await client.from('products').insert([
    {'id': p2Id, 'shop_id': s2Shop['id'], 'name': 'Item S2', 'category': 'food', 'price': 200, 'is_available': true, 'total_quantity': 10},
  ]);
  
  print('--- Testing Combinations ---');
  
  // Scenario 1: Multi Customers -> Single Seller
  print('C1 -> S1');
  final o1 = await _placeOrder(client, c1Phone, c1Id, s1Shop['id'], p1Id, 100);
  print('C2 -> S1');
  final o2 = await _placeOrder(client, c2Phone, c2Id, s1Shop['id'], p1Id, 100);
  
  // Scenario 2: Single Customer -> Multi Sellers (separate carts)
  print('C1 -> S2');
  final o3 = await _placeOrder(client, c1Phone, c1Id, s2Shop['id'], p2Id, 200);
  print('C1 -> S1 (Another order)');
  final o4 = await _placeOrder(client, c1Phone, c1Id, s1Shop['id'], p1Id, 100);

  print('Orders created: $o1, $o2, $o3, $o4');
  
  // Seller accepts all
  print('Seller 1 accepts O1, O2, O4');
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': o1});
  await client.rpc('accept_order_seller', params: {'p_order_id': o2});
  await client.rpc('accept_order_seller', params: {'p_order_id': o4});

  print('Seller 2 accepts O3');
  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': o3});
  
  // Rider (D1) tries to accept all 4. 4th should fail with MAX_ORDERS_REACHED
  print('Rider accepts orders...');
  await client.auth.signInWithPassword(email: _emailFromPhone(d1Phone), password: _passwordFromPhone(d1Phone));
  
  bool o4Failed = false;
  await client.rpc('accept_order_rider', params: {'p_order_id': o1, 'p_rider_phone': d1Phone, 'p_shop_lat': 34.0, 'p_shop_lng': 74.0});
  print('Rider accepted O1');
  await client.rpc('accept_order_rider', params: {'p_order_id': o2, 'p_rider_phone': d1Phone, 'p_shop_lat': 34.0, 'p_shop_lng': 74.0});
  print('Rider accepted O2');
  await client.rpc('accept_order_rider', params: {'p_order_id': o3, 'p_rider_phone': d1Phone, 'p_shop_lat': 34.0, 'p_shop_lng': 74.0});
  print('Rider accepted O3 (Max limit reached)');
  
  try {
    await client.rpc('accept_order_rider', params: {'p_order_id': o4, 'p_rider_phone': d1Phone, 'p_shop_lat': 34.0, 'p_shop_lng': 74.0});
  } catch (e) {
    if (e.toString().contains('MAX_ORDERS_REACHED')) {
      o4Failed = true;
      print('✅ Rider properly blocked from accepting 4th active cart group!');
    }
  }
  
  if (!o4Failed) throw Exception('Rider was allowed to accept 4 orders! Max limit bypass failed.');
  
  print('Simulating delivery of O1 to free rider slot...');
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured', payment_method = 'upi' WHERE id = '$o1'",
    '--linked'
  ]);
  await Future.delayed(const Duration(seconds: 1));

  // Seller progression
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 'p_new_status': 'preparing',
    'p_ready_time': null, 'p_wait_penalty': 0.0, 'p_rider_lat': null, 'p_rider_lng': null, 'p_delivery_otp': null,
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 'p_new_status': 'ready_for_pickup',
    'p_ready_time': null, 'p_wait_penalty': 0.0, 'p_rider_lat': null, 'p_rider_lng': null, 'p_delivery_otp': null,
  });

  // Rider progression
  await client.auth.signInWithPassword(email: _emailFromPhone(d1Phone), password: _passwordFromPhone(d1Phone));
  await client.rpc('set_arrived_at_shop', params: {'p_order_id': o1, 'p_rider_lat': 34.0, 'p_rider_lng': 74.0});
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 'p_new_status': 'picked_up',
    'p_ready_time': null, 'p_wait_penalty': 0.0, 'p_rider_lat': null, 'p_rider_lng': null, 'p_delivery_otp': null,
  });

  await client.rpc('update_order_status', params: {
    'p_order_id': o1,
    'p_new_status': 'delivered',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': 34.0,
    'p_rider_lng': 74.0,
    'p_delivery_otp': null,
  });
  
  await Future.delayed(Duration(seconds: 1));
  print('Rider trying to accept O4 again...');
  await client.rpc('accept_order_rider', params: {'p_order_id': o4, 'p_rider_phone': d1Phone, 'p_shop_lat': 34.0, 'p_shop_lng': 74.0});
  print('✅ Rider accepted O4 after a slot freed up!');
  
  print('All flow constraints verified!');
}

Future<String> _placeOrder(SupabaseClient client, String phone, String customerId, String shopId, String productId, double price) async {
  await client.auth.signInWithPassword(email: _emailFromPhone(phone), password: _passwordFromPhone(phone));
  final orderId = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  
  final now = DateTime.now().toUtc();
  final smallCartFee = price < 200 ? 15.0 : 0.0;
  final gst = price == 100 ? 3.0 : 36.0;
  final grandTotal = price == 100 ? 138.0 : 256.0;
  
  final order = {
    'id': orderId,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'cart_group_id': cartGroupId,
    'shop_id': shopId,
    'customer_id': customerId,
    'status': 'awaiting_acceptance',
    'seller_accepted': false,
    'partner_accepted': false,
    'acceptance_deadline': now.add(const Duration(minutes: 3)).toIso8601String(),
    'total_amount': price,
    'delivery_charges': 15.0,
    'rider_earnings': 15.0,
    'platform_fee': 5.0,
    'small_cart_fee': smallCartFee,
    'delivery_address': 'Test Address',
    'delivery_lat': 34.0,
    'delivery_lng': 74.0,
    'payment_method': 'upi',
    'payment_status': 'pending',
    'grand_total_collected': grandTotal,
    'gst_item_total': gst,
    's9_5_gst_amount': 0.0,
    'non_food_gst_amount': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'tcs_amount': 0.0,
    'tds_amount': 0.0,
    'enything_commission': 0.0,
    'seller_payout': price,
    'gateway_deduction': 0.0,
    'heavy_order_fee': 0.0,
    'coupon_discount': 0.0,
    'estimated_distance_km': 1.0,
    'gst_rate_snapshot': {},
    'shop_prep_time_snapshot': 30,
  };
  
  final item = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': orderId,
    'product_id': productId,
    'product_name': 'Test Item',
    'quantity': 1,
    'price': price,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };
  
  await client.rpc('place_orders_transaction', params: {
    'p_orders': [order],
    'p_items': [item],
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
  });
  return orderId;
}
