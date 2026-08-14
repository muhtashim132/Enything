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
  print('🧪 STARTING 100x RIDER STATS, BALANCE & INSIGHTS VERIFICATION');
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
  final custPhone = '+919811111$rand';
  final s1Phone = '+919711111$rand';
  final riderPhone = '+919511111$rand';

  print('👥 Setting up test accounts...');
  final customerId = await authUser(client, custPhone, 'customer');
  final seller1Id = await authUser(client, s1Phone, 'seller');
  final riderId = await authUser(client, riderPhone, 'delivery_partner');

  final shop1 = await client
      .from('shops')
      .select('id')
      .eq('seller_id', seller1Id)
      .single();
  final shop1Id = shop1['id'];

  final p1Id = const Uuid().v4();

  await client.auth.signInWithPassword(
    email: _emailFromPhone(s1Phone),
    password: _passwordFromPhone(s1Phone),
  );
  await client.from('products').insert({
    'id': p1Id,
    'shop_id': shop1Id,
    'name': 'Test Burger',
    'category': 'Restaurant',
    'price': 250.0,
    'is_available': true,
    'total_quantity': 50,
  });

  // ── TEST 1: Place and Deliver Order ──
  print('\n--- [TEST 1] Place, Deliver Order & Verify Earnings/Stats ---');
  final order1Id = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  final now = DateTime.now();

  final order1Payload = {
    'id': order1Id,
    'shop_id': shop1Id,
    'customer_id': customerId,
    'status': 'awaiting_acceptance',
    'total_amount': 250.0,
    'payment_status': 'pending',
    'payment_method': 'upi',
    'grand_total_collected': 317.5,
    'delivery_charges': 50.0,
    'rider_earnings': 50.0,
    'multi_shop_surcharge': 0.0,
    'platform_fee': 5.0,
    'small_cart_fee': 0.0,
    'gst_item_total': 12.5,
    's9_5_gst_amount': 12.5,
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
    'shop_lat': 34.0839,
    'shop_lng': 74.7975,
    'delivery_lat': 34.0838,
    'delivery_lng': 74.7974,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  };

  final item1Payload = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': order1Id,
    'product_id': p1Id,
    'product_name': 'Test Burger',
    'quantity': 1,
    'price': 250.0,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };

  await client.auth.signInWithPassword(
    email: _emailFromPhone(custPhone),
    password: _passwordFromPhone(custPhone),
  );

  await client.rpc('place_orders_transaction', params: {
    'p_orders': [order1Payload],
    'p_items': [item1Payload],
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
    'p_cart_group_id': cartGroupId,
    'p_order_id_to_cancel': null,
  });

  print('Order placed: $order1Id');

  // Rider accepts
  await client.auth.signInWithPassword(
    email: _emailFromPhone(riderPhone),
    password: _passwordFromPhone(riderPhone),
  );

  await client.rpc('accept_order_rider', params: {
    'p_order_id': order1Id,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.0837,
    'p_shop_lng': 74.7973,
  });

  // Seller accepts & prepares
  await client.auth.signInWithPassword(
    email: _emailFromPhone(s1Phone),
    password: _passwordFromPhone(s1Phone),
  );
  await client.rpc('accept_order_seller', params: {'p_order_id': order1Id});

  // Simulate payment confirmation via supabase db query
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$order1Id'",
    '--linked'
  ]);

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

  // Rider picks up and delivers
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
  await client.rpc('update_order_status', params: {
    'p_order_id': order1Id,
    'p_new_status': 'delivered',
    'p_rider_lat': 34.0838,
    'p_rider_lng': 74.7974,
  });

  print('✅ Order delivered successfully');

  // ── TEST 2: Add Wait Penalty & Compensated Cancellation via DB ──
  print('\n--- [TEST 2] Testing Wait Penalty & Cancellation Sync ---');
  final order2Id = const Uuid().v4();
  final twoDaysAgo = DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String();
  final nowIso = DateTime.now().toUtc().toIso8601String();

  // Set order 1 created_at to 2 days ago to verify updated_at date binning in get_rider_stats
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET created_at = '$twoDaysAgo', wait_time_penalty = 10.0 WHERE id = '$order1Id'",
    '--linked'
  ]);

  // Insert a compensated cancelled order directly using supabase db query
  await Process.run('supabase', [
    'db',
    'query',
    """
    INSERT INTO orders (
      id, customer_id, shop_id, delivery_partner_id, status, payment_method, payment_status,
      delivery_charges, rider_earnings, wait_time_penalty, estimated_distance_km,
      total_amount, grand_total_collected, created_at, updated_at
    ) VALUES (
      '$order2Id', '$customerId', '$shop1Id', '$riderId', 'cancelled', 'cod', 'captured',
      30.0, 25.0, 0.0, 2.0,
      200.0, 230.0, '$twoDaysAgo', '$nowIso'
    );
    """,
    '--linked'
  ]);

  print('✅ Test datasets synchronized');

  // ── TEST 3: Verify get_rider_stats & get_rider_balance ──
  print('\n--- [TEST 3] Verifying get_rider_stats & get_rider_balance ---');
  await client.auth.signInWithPassword(
    email: _emailFromPhone(riderPhone),
    password: _passwordFromPhone(riderPhone),
  );

  final stats = await client.rpc('get_rider_stats', params: {'p_rider_id': riderId});
  final balance = await client.rpc('get_rider_balance', params: {'p_rider_id': riderId});

  print('📊 get_rider_stats result: $stats');
  print('💰 get_rider_balance result: $balance');

  final todayEarnings = (stats['today_earnings'] as num).toDouble();
  final totalEarnings = (stats['total_earnings'] as num).toDouble();
  final totalKms = (stats['total_kms'] as num).toDouble();
  final availableBal = (balance['available_balance'] as num).toDouble();
  final totalEarned = (balance['total_earned'] as num).toDouble();

  print('Today Earnings: ₹$todayEarnings');
  print('Total Earnings: ₹$totalEarnings');
  print('Available Balance: ₹$availableBal');
  print('Total KMs: $totalKms km');

  // Verification Assertions:
  // 1. Both orders were completed/updated today, so Today Earnings MUST match Total Earnings!
  if ((todayEarnings - totalEarnings).abs() > 0.01) {
    throw Exception('FAILED: todayEarnings ($todayEarnings) does not match totalEarnings ($totalEarnings)! Completion date sync failed.');
  }

  // 2. Total Earnings in stats MUST equal total_earned in balance (100% reconciliation)!
  if ((totalEarnings - totalEarned).abs() > 0.01) {
    throw Exception('FAILED: totalEarnings ($totalEarnings) does not match balance total_earned ($totalEarned)! Cancellation compensation sync failed.');
  }

  // 3. Available balance must match total earned before any withdrawal
  if ((availableBal - totalEarned).abs() > 0.01) {
    throw Exception('FAILED: availableBal ($availableBal) does not match totalEarned ($totalEarned)!');
  }

  print('✅ [TEST 3 PASSED] get_rider_stats and get_rider_balance are 100% reconciled and date-synced!');

  // ── TEST 4: Withdrawal Request & Lock ──
  print('\n--- [TEST 4] Request Withdrawal & Re-check Balance ---');
  await client.rpc('request_rider_withdrawal', params: {
    'p_amount': 20.0,
    'p_upi_id': 'testrider@upi',
  });

  final balanceAfterWithdrawal = await client.rpc('get_rider_balance', params: {'p_rider_id': riderId});
  final newBal = (balanceAfterWithdrawal['available_balance'] as num).toDouble();
  print('Remaining Balance after ₹20 withdrawal: ₹$newBal (Expected: ${availableBal - 20.0})');

  if ((newBal - (availableBal - 20.0)).abs() > 0.01) {
    throw Exception('FAILED: Remaining balance incorrect! Expected ${availableBal - 20.0}, got $newBal');
  }
  print('✅ [TEST 4 PASSED] Withdrawal balance lock and escrow reservation verified');

  print('\n================================================================');
  print('🎉 ALL 100x RIDER EARNINGS, STATS & BALANCES VERIFIED 100%!');
  print('================================================================');
}
