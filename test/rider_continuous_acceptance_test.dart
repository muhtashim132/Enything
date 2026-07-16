import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

Future<void> main() async {
  print('--- Starting Continuous Order Acceptance Edge Cases Test ---');
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
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final c1Phone = '+919999999${rand}1';
  final c2Phone = '+919999999${rand}2';
  final c3Phone = '+919999999${rand}3';
  final c4Phone = '+919999999${rand}4';
  final c5Phone = '+919999999${rand}5';
  
  final sellerPhone = '+919999998$rand';
  final dpPhone = '+919999997$rand';

  final c1Id = await authUser(client, c1Phone, 'customer');
  final c2Id = await authUser(client, c2Phone, 'customer');
  final c3Id = await authUser(client, c3Phone, 'customer');
  final c4Id = await authUser(client, c4Phone, 'customer');
  final c5Id = await authUser(client, c5Phone, 'customer');
  
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final shopRec = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shopRec['id'];
  
  final productId = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.from('products').insert({
    'id': productId,
    'shop_id': shopId,
    'name': 'Test Item',
    'category': 'food',
    'price': 500.0,
    'is_available': true,
    'total_quantity': 10
  });

  final dpId = await authUser(client, dpPhone, 'delivery_partner');

  Future<String> createOrderForCustomer(String cPhone, String cId) async {
    await client.auth.signInWithPassword(email: _emailFromPhone(cPhone), password: _passwordFromPhone(cPhone));
    final orderId = const Uuid().v4();
    final cartGroupId = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final order = {
      'id': orderId,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'cart_group_id': cartGroupId,
      'shop_id': shopId,
      'customer_id': cId,
      'status': 'awaiting_acceptance',
      'total_amount': 500.0,
      'payment_status': 'pending',
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
    
    // Seller accepts it to make it ready for rider to accept
    await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
    await client.rpc('accept_order_seller', params: {'p_order_id': orderId});
    return orderId;
  }

  print('\nCreating 4 orders...');
  final o1 = await createOrderForCustomer(c1Phone, c1Id);
  final o2 = await createOrderForCustomer(c2Phone, c2Id);
  final o3 = await createOrderForCustomer(c3Phone, c3Id);
  final o4 = await createOrderForCustomer(c4Phone, c4Id);

  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));

  print('\nStep 1: Rider accepts 3 orders');
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o1,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o2,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o3,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });

  print('\nStep 2: Rider tries to accept 4th order (should fail)');
  try {
    await client.rpc('accept_order_rider', params: {
      'p_order_id': o4,
      'p_rider_phone': dpPhone,
      'p_shop_lat': 34.0,
      'p_shop_lng': 74.0,
    });
    throw Exception('Should have failed to accept 4th order');
  } catch (e) {
    if (!e.toString().contains('MAX_ORDERS_REACHED')) {
      throw Exception('Unexpected error: $e');
    }
    print('✅ Correctly prevented accepting 4th distinct cart group.');
  }

  print('\nStep 3: Deliver Order 1');
  
  // Simulate Customer paying for Order 1
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$o1'",
    '--linked'
  ]);
  
  // Need seller to mark preparing then ready
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 
    'p_new_status': 'preparing',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 
    'p_new_status': 'ready_for_pickup',
    'p_ready_time': DateTime.now().toUtc().toIso8601String(),
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null
  });
  
  // Rider picks up and delivers
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 
    'p_new_status': 'picked_up',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 
    'p_new_status': 'out_for_delivery',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': o1, 
    'p_new_status': 'delivered',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
    'p_delivery_otp': null
  });

  print('\nStep 4: Rider accepts 4th order (should succeed)');
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o4,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });

  print('\nStep 5: Customer/Admin cancels Order 2');
  final res = await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'cancelled' WHERE id = '$o2'",
    '--linked'
  ]);
  if (res.exitCode != 0) {
    throw Exception('Failed to cancel order 2: ${res.stderr}');
  }

  print('\nStep 6: Rider accepts 5th order (should succeed)');
  final o5 = await createOrderForCustomer(c5Phone, c5Id);
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o5,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });
}

String _emailFromPhone(String phone) => '${phone.replaceAll('+', '')}@enything.com';
String _passwordFromPhone(String phone) => phone.replaceAll('+', '');

Future<String> authUser(SupabaseClient client, String phone, String role) async {
  final email = _emailFromPhone(phone);
  final password = _passwordFromPhone(phone);
  
  String? userId;
  try {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    userId = res.user?.id;
  } catch (e) {
    try {
      final res2 = await client.auth.signUp(email: email, password: password, data: <String, dynamic>{'phone': phone});
      userId = res2.user?.id;
    } catch (e2) {
      throw Exception('Could not auth $phone: $e2');
    }
  }
  
  if (userId != null) {
    await client.from('profiles').upsert({
      'id': userId,
      'role': role,
      'full_name': 'Test $role',
      'phone': phone,
    });
  }
  
  // Create shop if seller
  if (role == 'seller') {
    final hasShop = await client.from('shops').select('id').eq('seller_id', userId as Object).maybeSingle();
    if (hasShop == null) {
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
    final existingDp = await client.from('delivery_partners').select('id').eq('id', userId as Object).maybeSingle();
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
  return userId!;
}
