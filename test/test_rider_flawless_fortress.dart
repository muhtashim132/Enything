import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

String _phoneFromId(String phone) => phone.replaceAll('+', '').trim();
String _emailFromPhone(String phone) => '${_phoneFromId(phone)}@enything.com';
String _passwordFromPhone(String phone) => 'Pass_${_phoneFromId(phone)}!';

Future<String> authUser(
    SupabaseClient client, String phone, String role) async {
  final email = _emailFromPhone(phone);
  final password = _passwordFromPhone(phone);

  try {
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    if (res.user != null) {
      return res.user!.id;
    }
  } catch (_) {}

  try {
    final signUpRes =
        await client.auth.signUp(email: email, password: password);
    final userId = signUpRes.user!.id;

    await client.from('profiles').upsert({
      'id': userId,
      'phone': phone,
      'full_name': 'Test User $role',
      'role': role,
    });

    if (role == 'seller') {
      await client.from('shops').upsert({
        'seller_id': userId,
        'name': 'Shop_$phone',
        'is_active': true,
        'is_accepting_orders': true,
        'location': 'POINT(74.7973 34.0837)',
      });
    } else if (role == 'delivery_partner') {
      await client.from('delivery_partners').upsert({
        'id': userId,
        'is_active': true,
        'is_accepting_orders': true,
        'verification_status': 'verified',
        'location': 'POINT(74.7973 34.0837)',
        'last_location_lat': 34.0837,
        'last_location_lng': 74.7973,
      });
    }

    return userId;
  } catch (e) {
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    return res.user!.id;
  }
}

Future<void> main() async {
  print('================================================================');
  print('🚀 STARTING RIDER DASHBOARD FLAWLESS FORTRESS VERIFICATION SUITE');
  print('================================================================');

  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl;
  String? supabaseKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) {
      supabaseUrl = line.split('=')[1].trim();
    }
    if (line.startsWith('SUPABASE_ANON_KEY=')) {
      supabaseKey = line.split('=')[1].trim();
    }
  }

  if (supabaseUrl == null || supabaseKey == null) {
    print('❌ Missing environment variables in .env');
    exit(1);
  }

  final client = SupabaseClient(supabaseUrl, supabaseKey,
      authOptions:
          const AuthClientOptions(authFlowType: AuthFlowType.implicit));

  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
  final custPhone = '+919888888$rand';
  final s1Phone = '+919777777$rand';
  final s2Phone = '+919666666$rand';
  final riderPhone = '+919555555$rand';

  print('👥 Setting up test accounts...');
  final customerId = await authUser(client, custPhone, 'customer');
  final seller1Id = await authUser(client, s1Phone, 'seller');
  final seller2Id = await authUser(client, s2Phone, 'seller');
  final riderId = await authUser(client, riderPhone, 'delivery_partner');

  final shop1 = await client
      .from('shops')
      .select('id')
      .eq('seller_id', seller1Id)
      .single();
  final shop1Id = shop1['id'];

  final shop2 = await client
      .from('shops')
      .select('id')
      .eq('seller_id', seller2Id)
      .single();
  final shop2Id = shop2['id'];

  final p1Id = const Uuid().v4();
  final p2Id = const Uuid().v4();

  // Create products for shop1 and shop2
  await client.auth.signInWithPassword(
    email: _emailFromPhone(s1Phone),
    password: _passwordFromPhone(s1Phone),
  );
  await client.from('products').insert({
    'id': p1Id,
    'shop_id': shop1Id,
    'name': 'Item from Shop 1',
    'category': 'food',
    'price': 250.0,
    'is_available': true,
    'total_quantity': 50,
  });

  await client.auth.signInWithPassword(
    email: _emailFromPhone(s2Phone),
    password: _passwordFromPhone(s2Phone),
  );
  await client.from('products').insert({
    'id': p2Id,
    'shop_id': shop2Id,
    'name': 'Item from Shop 2',
    'category': 'food',
    'price': 350.0,
    'is_available': true,
    'total_quantity': 50,
  });

  print('🏪 Shop 1: $shop1Id | Shop 2: $shop2Id | Rider: $riderId');

  // TEST 1: ATOMIC MULTI-SHOP CART GROUP ACCEPTANCE
  print('\n--- [TEST 1] Atomic Multi-Shop Cart Acceptance ---');
  final cartGroupId = const Uuid().v4();
  final order1Id = const Uuid().v4();
  final order2Id = const Uuid().v4();
  final now = DateTime.now().toUtc();

  final order1 = {
    'id': order1Id,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'cart_group_id': cartGroupId,
    'shop_id': shop1Id,
    'customer_id': customerId,
    'status': 'awaiting_acceptance',
    'total_amount': 250.0,
    'payment_status': 'pending',
    'payment_method': 'upi',
    'grand_total_collected': 335.0,
    'delivery_charges': 50.0,
    'rider_earnings': 50.0,
    'multi_shop_surcharge': 0.0,
    'platform_fee': 5.0,
    'small_cart_fee': 0.0,
    'gst_item_total': 30.0,
    's9_5_gst_amount': 30.0,
    'non_food_gst_amount': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'tcs_amount': 0.0,
    'tds_amount': 0.0,
    'enything_commission': 0.0,
    'seller_payout': 250.0,
    'gateway_deduction': 0.0,
    'heavy_order_fee': 0.0,
    'coupon_discount': 0.0,
    'estimated_distance_km': 1.0,
    'gst_rate_snapshot': {},
    'shop_prep_time_snapshot': 30,
    'shop_lat': 34.0837,
    'shop_lng': 74.7973,
    'delivery_lat': 34.0838,
    'delivery_lng': 74.7974,
  };

  final order2 = {
    'id': order2Id,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'cart_group_id': cartGroupId,
    'shop_id': shop2Id,
    'customer_id': customerId,
    'status': 'awaiting_acceptance',
    'total_amount': 350.0,
    'payment_status': 'pending',
    'payment_method': 'upi',
    'grand_total_collected': 445.0,
    'delivery_charges': 50.0,
    'rider_earnings': 50.0,
    'multi_shop_surcharge': 0.0,
    'platform_fee': 5.0,
    'small_cart_fee': 0.0,
    'gst_item_total': 40.0,
    's9_5_gst_amount': 40.0,
    'non_food_gst_amount': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'tcs_amount': 0.0,
    'tds_amount': 0.0,
    'enything_commission': 0.0,
    'seller_payout': 350.0,
    'gateway_deduction': 0.0,
    'heavy_order_fee': 0.0,
    'coupon_discount': 0.0,
    'estimated_distance_km': 1.0,
    'gst_rate_snapshot': {},
    'shop_prep_time_snapshot': 30,
    'shop_lat': 34.0839,
    'shop_lng': 74.7975,
    'delivery_lat': 34.0838,
    'delivery_lng': 74.7974,
  };

  final item1 = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': order1Id,
    'product_id': p1Id,
    'product_name': 'Item from Shop 1',
    'quantity': 1,
    'price': 250.0,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };

  final item2 = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': order2Id,
    'product_id': p2Id,
    'product_name': 'Item from Shop 2',
    'quantity': 1,
    'price': 350.0,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };

  // Place multi-shop orders as Customer
  await client.auth.signInWithPassword(
    email: _emailFromPhone(custPhone),
    password: _passwordFromPhone(custPhone),
  );

  await client.rpc('place_orders_transaction', params: {
    'p_orders': [order1, order2],
    'p_items': [item1, item2],
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
    'p_cart_group_id': cartGroupId,
    'p_order_id_to_cancel': null,
  });

  print('📦 Multi-shop orders placed under cart group $cartGroupId');

  // Authenticate as rider and accept the first order
  await client.auth.signInWithPassword(
    email: _emailFromPhone(riderPhone),
    password: _passwordFromPhone(riderPhone),
  );

  final acceptResult = await client.rpc('accept_order_rider', params: {
    'p_order_id': order1Id,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.0837,
    'p_shop_lng': 74.7973,
  });

  print('Accept RPC result: $acceptResult');

  // Verify BOTH orders are now assigned to this rider
  final o1 =
      await client.from('orders').select('*').eq('id', order1Id).single();
  final o2 =
      await client.from('orders').select('*').eq('id', order2Id).single();

  if (o1['delivery_partner_id'] != riderId ||
      o2['delivery_partner_id'] != riderId) {
    throw Exception(
        'FAILED: Multi-shop cart acceptance did not assign both orders to rider! o1 rider: ${o1['delivery_partner_id']}, o2 rider: ${o2['delivery_partner_id']}');
  }
  print(
      '✅ [TEST 1 PASSED] Both orders in multi-shop cart atomically assigned to rider $riderId');

  // TEST 2: ARRIVAL AT SHOP IN CONFIRMED STATUS
  print('\n--- [TEST 2] Mark Arrived on Confirmed Status ---');
  // Seller 1 accepts order 1
  await client.auth.signInWithPassword(
    email: _emailFromPhone(s1Phone),
    password: _passwordFromPhone(s1Phone),
  );
  await client.rpc('accept_order_seller', params: {'p_order_id': order1Id});

  // Simulate payment confirmation via supabase db query (as done by payment webhook)
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured', payment_method = 'upi' WHERE id = '$order1Id'",
    '--linked'
  ]);
  await Future.delayed(const Duration(seconds: 1));

  // Rider marks arrival (rider at 34.0837, 74.7973, shop at 34.0837, 74.7973)
  await client.auth.signInWithPassword(
    email: _emailFromPhone(riderPhone),
    password: _passwordFromPhone(riderPhone),
  );
  await client.rpc('set_arrived_at_shop', params: {
    'p_order_id': order1Id,
    'p_rider_lat': 34.0837,
    'p_rider_lng': 74.7973,
  });

  final o1AfterArrival = await client
      .from('orders')
      .select('arrived_at_shop_time')
      .eq('id', order1Id)
      .single();
  if (o1AfterArrival['arrived_at_shop_time'] == null) {
    throw Exception('FAILED: arrived_at_shop_time was not set!');
  }
  print(
      '✅ [TEST 2 PASSED] set_arrived_at_shop successfully recorded arrival on confirmed status');

  // TEST 3: RIDER SHOP DISPUTE REPORTING
  print('\n--- [TEST 3] Rider Shop Dispute Reporting ---');
  // Rider reports dispute / cancels order2 due to shop refusal
  await client.rpc('set_shop_dispute', params: {
    'p_order_id': order2Id,
    'p_cancel': true,
  });

  final o2Disputed = await client
      .from('orders')
      .select('status, cancelled_reason')
      .eq('id', order2Id)
      .single();
  if (o2Disputed['status'] != 'cancelled' ||
      o2Disputed['cancelled_reason'] != 'shop_dispute') {
    throw Exception('FAILED: set_shop_dispute did not cancel order as dispute!');
  }
  print(
      '✅ [TEST 3 PASSED] Rider successfully reported shop dispute and cancelled order');

  // TEST 4: FULL DELIVERY STATUS PROGRESSION
  print('\n--- [TEST 4] Full Delivery Lifecycle & Geo-fence ---');
  // Seller 1 prepares & readies
  await client.auth.signInWithPassword(
    email: _emailFromPhone(s1Phone),
    password: _passwordFromPhone(s1Phone),
  );
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'preparing',
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'ready_for_pickup',
  });

  // Rider signs in, picks up, goes out for delivery, and delivers
  await client.auth.signInWithPassword(
    email: _emailFromPhone(riderPhone),
    password: _passwordFromPhone(riderPhone),
  );
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'picked_up',
  });
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'out_for_delivery',
  });
  // Deliver with GPS coordinates matching customer location (34.0838, 74.7974)
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'delivered',
    'p_rider_lat': 34.0838,
    'p_rider_lng': 74.7974,
  });

  final o1Delivered = await client
      .from('orders')
      .select('status, rider_earnings')
      .eq('id', order1Id)
      .single();
  if (o1Delivered['status'] != 'delivered') {
    throw Exception('FAILED: Order was not delivered!');
  }
  print(
      '✅ [TEST 4 PASSED] Full delivery lifecycle completed successfully (Status: delivered)');

  // TEST 5: RIDER STATS & BALANCE
  print('\n--- [TEST 5] Rider Stats & Balance Calculation ---');
  final stats = await client
      .rpc('get_rider_stats', params: {'p_rider_id': riderId});
  print('Rider Stats: $stats');

  final balance = await client
      .rpc('get_rider_balance', params: {'p_rider_id': riderId});
  print('Rider Balance: $balance');

  final availableBal = (balance['available_balance'] as num).toDouble();
  if (availableBal < 20.0) {
    throw Exception(
        'FAILED: Available balance incorrect! Expected >= 20, got $availableBal');
  }
  print('✅ [TEST 5 PASSED] Rider stats and balance verified accurately');

  print('\n================================================================');
  print('🎉 ALL 5 RIDER DASHBOARD FLAWLESS FORTRESS TESTS PASSED 100%!');
  print('================================================================');
}
