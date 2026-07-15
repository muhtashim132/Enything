import 'dart:convert';
import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  print('--- Starting Enything Integration Flow Test ---');

  // Load env manually
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('No .env file found');
    exit(1);
  }

  String supabaseUrl = '';
  String supabaseAnonKey = '';
  for (var line in await envFile.readAsLines()) {
    if (line.startsWith('SUPABASE_URL=')) {
      supabaseUrl = line.split('=')[1].trim();
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      supabaseAnonKey = line.split('=')[1].trim();
    }
  }

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    print('Missing Supabase credentials');
    exit(1);
  }

  final client = SupabaseClient(supabaseUrl, supabaseAnonKey, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  print('Connected to Supabase');

  try {
    await runTests(client);
    print('\n✅ ALL INTEGRATION TESTS PASSED');
    exit(0);
  } catch (e, stack) {
    print('\n❌ TEST FAILED: $e');
    print(stack);
    exit(1);
  }
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
    'phone': uniquePhone
  });

  const location = 'POINT(74.6366 34.4225)';
  
  if (role == 'customer') {
    await client.from('customers').upsert({'id': userId, 'location': location});
    final addrs = await client.from('saved_addresses').select().eq('user_id', userId);
    if (addrs.isEmpty) {
      await client.from('saved_addresses').insert({
        'user_id': userId,
        'label': 'Home',
        'address': 'Test Address',
        'pincode': '193502',
        'latitude': 34.4225,
        'longitude': 74.6366,
        'is_default': true
      });
    }
  } else if (role == 'seller') {
    await client.from('shops').insert({
      'seller_id': userId,
      'name': 'Test Shop ${phone.substring(phone.length - 2)}',
      'is_active': true,
      'is_accepting_orders': true,
      'verification_status': 'verified',
      'location': location,
    });
  } else if (role == 'delivery_partner') {
    await client.from('delivery_partners').upsert({
      'id': userId,
      'is_active': true,
      'verification_status': 'verified',
      'location': location,
    });
  }

  return userId;
}

Future<void> runTests(SupabaseClient client) async {
  print('\n--- SCENARIO A: Single Customer, Single Seller, Single DP ---');
  
  final randomPrefix = DateTime.now().millisecondsSinceEpoch.toString().substring(5, 12);
  final customerPhone = '999$randomPrefix';
  final sellerPhone = '998$randomPrefix';
  final dpPhone = '997$randomPrefix';

  print('Authenticating users...');
  final customerId = await authUser(client, customerPhone, 'customer');
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final dpId = await authUser(client, dpPhone, 'delivery_partner');

  print('Customer: $customerId');
  print('Seller: $sellerId');
  print('DP: $dpId');

  final shop = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shop['id'];

  final products = await client.from('products').select('id, price').eq('shop_id', shopId).limit(1);
  String productId;
  double price = 100.0;
  if (products.isEmpty) {
    print('Signing in as seller to create product...');
    await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
    productId = const Uuid().v4();
    await client.from('products').insert({
      'id': productId,
      'shop_id': shopId,
      'name': 'Test Item',
      'category': 'food',
      'price': price,
      'is_available': true,
      'total_quantity': 100
    });
  } else {
    productId = products.first['id'];
    price = (products.first['price'] as num).toDouble();
  }

  print('Placing order...');
  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));

  final cartGroupId = const Uuid().v4();
  final orderId = const Uuid().v4();
  final now = DateTime.now().toUtc();
  
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
    'small_cart_fee': 15.0,
    'address': 'Test Address',
    'payment_method': 'upi',
    'payment_status': 'pending',
    'grand_total_collected': 138.0,
    'gst_item_total': 0.0,
    's9_5_gst_amount': 0.0,
    'non_food_gst_amount': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'tcs_amount': 0.0,
    'tds_amount': 0.0,
    'enything_commission': 0.0,
    'seller_payout': 100.0,
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
  print('Order placed successfully. ID: $orderId');

  print('Seller accepting order...');
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('accept_order_seller', params: {'p_order_id': orderId});
  
  print('DP accepting order...');
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': orderId,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });

  var check = await client.from('orders').select('status, seller_accepted, partner_accepted').eq('id', orderId).single();
  print('Status after accept: ${check['status']}');
  if (check['status'] != 'awaiting_payment') {
    throw Exception('Status is not awaiting_payment! It is ${check['status']}');
  }

  print('Customer paying...');
  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));
  print('Simulating payment confirmation via direct DB query (bypassing HMAC)...');
  final updateResult = await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured', payment_method = 'upi' WHERE id = '$orderId'",
    '--linked'
  ]);
  print('Supabase CLI output: ${updateResult.stdout}');
  if (updateResult.stderr.toString().isNotEmpty) {
    print('Supabase CLI stderr: ${updateResult.stderr}');
  }
  
  // Wait a moment for DB to settle
  await Future.delayed(const Duration(seconds: 2));

  check = await client.from('orders').select('status, payment_status').eq('id', orderId).single();
  print('Status after payment: ${check['status']}, Payment: ${check['payment_status']}');
  if (check['status'] != 'confirmed') {
    throw Exception('Status is not confirmed! It is ${check['status']}');
  }

  print('Seller marking preparing...');
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

  await Future.delayed(const Duration(seconds: 1));
  check = await client.from('orders').select('status').eq('id', orderId).single();
  if (check['status'] != 'preparing') {
    throw Exception('Status is not preparing! It is ${check['status']}');
  }

  print('Seller marking ready_for_pickup...');
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'ready_for_pickup',
    'p_ready_time': DateTime.now().toIso8601String(),
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });

  print('DP marking arrived at shop...');
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('set_arrived_at_shop', params: {
    'p_order_id': orderId,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
  });
  await Future.delayed(const Duration(seconds: 1));

  print('DP signing in to mark picked_up...');
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));

    await client.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'picked_up',
      'p_ready_time': null,
      'p_wait_penalty': 0.0,
      'p_rider_lat': null,
      'p_rider_lng': null,
      'p_delivery_otp': null,
    });
  
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  
  print('DP marking delivered...');
  await client.rpc('update_order_status', params: {
    'p_order_id': orderId,
    'p_new_status': 'delivered',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
    'p_delivery_otp': null,
  });

  check = await client.from('orders').select('status').eq('id', orderId).single();
  print('Final status: ${check['status']}');
  if (check['status'] != 'delivered') {
    throw Exception('Failed to reach delivered status!');
  }
}
