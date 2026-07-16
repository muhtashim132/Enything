import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

Future<void> main() async {
  print('--- Starting Shop Continuous Acceptance Edge Cases Test ---');
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
    await runShopEdgeCaseTests(client);
    print('\n✅ ALL SHOP ACCEPTANCE EDGE CASE TESTS PASSED');
  } catch (e) {
    print('\n❌ TEST FAILED: $e');
    exit(1);
  }
}

Future<void> runShopEdgeCaseTests(SupabaseClient client) async {
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final customerPhone = '+919999999${rand}1';
  final sellerPhone = '+919999998$rand';
  final otherSellerPhone = '+919999998${rand}2';
  final dpPhone = '+919999997$rand';

  final customerId = await authUser(client, customerPhone, 'customer');
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final otherSellerId = await authUser(client, otherSellerPhone, 'seller');
  final dpId = await authUser(client, dpPhone, 'delivery_partner');

  final shopRec = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shopRec['id'];
  
  final otherShopRec = await client.from('shops').select('id').eq('seller_id', otherSellerId).single();
  final otherShopId = otherShopRec['id'];

  final productId = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.from('products').insert({
    'id': productId,
    'shop_id': shopId,
    'name': 'Test Item Shop',
    'category': 'food',
    'price': 500.0,
    'is_available': true,
    'total_quantity': 10
  });

  Future<String> createOrder() async {
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
      'product_name': 'Test Item Shop',
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
    
    return orderId;
  }

  // Case 1: Normal Acceptance (Rider has NOT accepted yet)
  print('\nTest 1: Normal Acceptance (Seller accepts first)');
  final o1 = await createOrder();
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  final res1 = await client.rpc('accept_order_seller', params: {'p_order_id': o1});
  if (res1 == true) throw Exception('Test 1 Failed: Returned true but rider had not accepted yet');
  final fetchO1 = await client.from('orders').select('status, seller_accepted').eq('id', o1).single();
  if (fetchO1['status'] != 'awaiting_acceptance' && fetchO1['status'] != 'pending') {
    throw Exception('Test 1 Failed: Status should be awaiting_acceptance, got ${fetchO1['status']}');
  }
  if (fetchO1['seller_accepted'] != true) {
    throw Exception('Test 1 Failed: seller_accepted not true');
  }
  print('✅ Test 1 Passed');

  // Case 2: Acceptance when Rider ALREADY accepted
  print('\nTest 2: Rider already accepted, then Seller accepts');
  final o2 = await createOrder();
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o2,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });
  
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  final res2 = await client.rpc('accept_order_seller', params: {'p_order_id': o2});
  if (res2 != true) throw Exception('Test 2 Failed: Returned false but rider HAD accepted');
  final fetchO2 = await client.from('orders').select('status, payment_deadline').eq('id', o2).single();
  if (fetchO2['status'] != 'awaiting_payment') {
    throw Exception('Test 2 Failed: Status should be awaiting_payment, got ${fetchO2['status']}');
  }
  if (fetchO2['payment_deadline'] == null) {
    throw Exception('Test 2 Failed: payment_deadline not set');
  }
  print('✅ Test 2 Passed');

  // Case 3: Unauthorized Caller
  print('\nTest 3: Unauthorized caller attempts to accept');
  final o3 = await createOrder();
  await client.auth.signInWithPassword(email: _emailFromPhone(otherSellerPhone), password: _passwordFromPhone(otherSellerPhone));
  try {
    await client.rpc('accept_order_seller', params: {'p_order_id': o3});
    throw Exception('Test 3 Failed: Unauthorized seller succeeded in accepting the order');
  } catch (e) {
    if (!e.toString().contains('Unauthorized')) {
      throw Exception('Test 3 Failed: Unexpected error for unauthorized caller: $e');
    }
    print('✅ Test 3 Passed (Prevented unauthorized acceptance)');
  }

  // Case 4: ORDER_CANCELLED
  print('\nTest 4: Customer cancels order before seller accepts');
  final o4 = await createOrder();
  // Simulate Customer cancellation
  final res4 = await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'cancelled' WHERE id = '$o4'",
    '--linked'
  ]);
  print('res4 exitCode: ${res4.exitCode}, stdout: ${res4.stdout}, stderr: ${res4.stderr}');
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  try {
    await client.rpc('accept_order_seller', params: {'p_order_id': o4});
    throw Exception('Test 4 Failed: Accepted a cancelled order');
  } catch (e) {
    if (!e.toString().contains('ORDER_CANCELLED')) {
      throw Exception('Test 4 Failed: Unexpected error for cancelled order: $e');
    }
    print('✅ Test 4 Passed (Prevented accepting cancelled order)');
  }

  // Case 5: Invalid State Transition
  print('\nTest 5: Invalid State Transition (already accepted)');
  final o5 = await createOrder();
  
  // Rider accepts
  await client.auth.signInWithPassword(email: _emailFromPhone(dpPhone), password: _passwordFromPhone(dpPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o5,
    'p_rider_phone': dpPhone,
    'p_shop_lat': 34.0,
    'p_shop_lng': 74.0,
  });

  // Seller accepts (transitions to awaiting_payment)
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('accept_order_seller', params: {'p_order_id': o5});

  // Try to accept again!
  try {
    await client.rpc('accept_order_seller', params: {'p_order_id': o5});
    throw Exception('Test 5 Failed: Accepted order in awaiting_payment state');
  } catch (e) {
    if (!e.toString().contains('Invalid state transition')) {
      throw Exception('Test 5 Failed: Unexpected error for invalid state: $e');
    }
    print('✅ Test 5 Passed (Prevented invalid state transition)');
  }

  // Case 6: Order Not Found
  print('\nTest 6: Order Not Found');
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  try {
    final randomId = const Uuid().v4();
    await client.rpc('accept_order_seller', params: {'p_order_id': randomId});
    throw Exception('Test 6 Failed: Accepted non-existent order');
  } catch (e) {
    if (!e.toString().contains('Order not found')) {
      throw Exception('Test 6 Failed: Unexpected error for order not found: $e');
    }
    print('✅ Test 6 Passed (Order not found handled)');
  }
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
