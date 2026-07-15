import 'package:supabase/supabase.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  print('--- Starting Enything Edge Cases Stress Test ---');
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl;
  String? supabaseKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
  }

  if (supabaseUrl == null || supabaseKey == null) {
    print('Missing environment variables. Please check your .env file.');
    return;
  }

  final client = SupabaseClient(
    supabaseUrl, 
    supabaseKey, 
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit)
  );
  print('Connected to Supabase');

  try {
    await runEdgeCaseTests(client, supabaseUrl, supabaseKey);
    print('\n✅ ALL EDGE CASE TESTS PASSED');
  } catch (e) {
    print('\n❌ TEST FAILED: $e');
    exit(1);
  }
}

Future<void> runEdgeCaseTests(SupabaseClient client, String supabaseUrl, String supabaseKey) async {
  // 1. Get test users (Customer, Seller, DP)
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final customerPhone = '+919999999$rand';
  final sellerPhone = '+919999998$rand';
  final dpPhone = '+919999997$rand';



  final customerId = await authUser(client, customerPhone, 'customer');
  
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final shopRec = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shopRec['id'];

  final dpId = await authUser(client, dpPhone, 'delivery_partner');

  // Sign back in as customer to place an order with a LEGACY address (no lat/lng)
  print('\n--- SCENARIO: Legacy Address, Idempotency, and OTP ---');
  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));
  
  final orderId = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  final now = DateTime.now().toUtc();
  
  final order = {
    'id': orderId,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'cart_group_id': cartGroupId,
    'shop_id': shopId,
    'customer_id': customerId,
    'status': 'awaiting_payment', // Bypass early states for speed
    'total_amount': 500.0,
    'delivery_address': 'Legacy Address Unknown Location',
    'delivery_lat': null,
    'delivery_lng': null,
    'payment_status': 'captured',
    'payment_method': 'upi',
    'grand_total_collected': 610.0,
    'delivery_charges': 15.0,
    'rider_earnings': 15.0,
    'platform_fee': 5.0,
    'small_cart_fee': 0.0,
    'gst_item_total': 90.0,
    's9_5_gst_amount': 90.0,
    'non_food_gst_amount': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'tcs_amount': 0.0,
    'tds_amount': 0.0,
    'enything_commission': 0.0,
    'seller_payout': 500.0,
    'gateway_deduction': 0.0,
    'heavy_order_fee': 0.0,
    'coupon_discount': 0.0,
    'estimated_distance_km': 1.0,
    'gst_rate_snapshot': {},
    'shop_prep_time_snapshot': 30,
  };

  // We must create a real product, as SQL logic validates product existence and availability!
  final productId = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.from('products').insert({
    'id': productId,
    'shop_id': shopId,
    'name': 'Test Legacy Item',
    'category': 'food',
    'price': 500.0,
    'is_available': true,
    'total_quantity': 10
  });

  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));

  final item = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': orderId,
    'product_id': productId,
    'product_name': 'Test Item',
    'quantity': 1,
    'price': 500.0,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };

  await client.rpc('place_orders_transaction', params: {
    'p_orders': [order],
    'p_items': [item],
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
  });
  
  print('Order placed with NO coordinates via RPC. ID: $orderId');

  // Mark confirmed
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed' WHERE id = '$orderId'",
    '--linked'
  ]);
  
  print('DP accepting order...');
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': orderId,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });

  // Seller preparing
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'preparing',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });

  // Seller ready
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'ready_for_pickup',
    'p_ready_time': DateTime.now().toIso8601String(),
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });

  // Rider Arrival
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  print('Rider marking arrived...');
  await client.rpc('set_arrived_at_shop', params: {
    'p_order_id': orderId,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
  });

  // Get the arrival time
  final t1Rec = await client.from('orders').select('arrived_at_shop_time').eq('id', orderId).single();
  final t1 = t1Rec['arrived_at_shop_time'];
  print('Initial arrival time: $t1');

  // Wait 2 seconds and mark arrived AGAIN to test idempotency
  await Future.delayed(Duration(seconds: 2));
  print('Rider marking arrived AGAIN (testing idempotency)...');
  await client.rpc('set_arrived_at_shop', params: {
    'p_order_id': orderId,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
  });

  final t2Rec = await client.from('orders').select('arrived_at_shop_time').eq('id', orderId).single();
  final t2 = t2Rec['arrived_at_shop_time'];
  print('Second arrival time: $t2');

  if (t1 != t2) {
    throw Exception('Idempotency failed! Arrival time was overwritten from $t1 to $t2');
  }
  print('✅ Idempotency test passed.');

  // Pick up
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'picked_up',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });

  // Switch back to DP
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));

  // Rider trying to deliver
  print('Rider attempting to deliver on legacy address...');
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'delivered',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': 34.4225, // Rider has GPS
    'p_rider_lng': 74.6366,
    'p_delivery_otp': null,
  });

  final check = await client.from('orders').select('status, wait_time_penalty').eq('id', orderId).single();
  if (check['status'] != 'delivered') {
    throw Exception('Status is not delivered! It is ${check['status']}');
  }
  print('✅ Order delivered successfully on legacy address! Geo-fence bypass works.');
  print('Wait time penalty stored as: ${check['wait_time_penalty']}');
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
    } catch (e2, st2) {
      print('e1: $e, e2: $e2');
      print(st2);
      throw Exception('Failed to auth user $phone: $e2');
    }
  }

  if (userId == null) throw Exception('Failed to get user id for $phone');

  final uniquePhone = phone.contains('999999999') 
      ? '+9199999${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}' 
      : phone;
      
  await client.from('profiles').upsert({
    'id': userId,
    'role': role,
    'full_name': 'Test $role',
    'phone': uniquePhone,
  });

  if (role == 'seller') {
    final existingShop = await client.from('shops').select('id').eq('seller_id', userId).maybeSingle();
    if (existingShop == null) {
      await client.from('shops').insert({
        'seller_id': userId,
        'name': 'Test Shop $userId',
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

String _emailFromPhone(String phone) {
  if (phone.contains('9999999996')) {
    return 'mock919999999996@enything.com';
  }
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return '$digits@auth.enything.app';
}

String _passwordFromPhone(String phone) {
  if (phone.contains('9999999996')) return 'Dummy123';
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final bytes = utf8.encode('Enything_${digits}_Secured#2026');
  final digest = sha256.convert(bytes);
  return 'EnY\$${digest.toString().substring(0, 16)}';
}
