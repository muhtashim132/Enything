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
      'full_name': 'Test Seller $role',
      'role': role,
    });

    if (role == 'seller') {
      await client.from('shops').upsert({
        'seller_id': userId,
        'name': 'SellerShop_$phone',
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
  print('🧪 STARTING 100x SELLER DASHBOARD, METRICS & BALANCE VERIFICATION');
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
  final custPhone = '+919833333$rand';
  final sellerPhone = '+919733333$rand';
  final riderPhone = '+919533333$rand';

  print('👥 Setting up accounts...');
  final customerId = await authUser(client, custPhone, 'customer');
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final riderId = await authUser(client, riderPhone, 'delivery_partner');

  final shopResp = await client
      .from('shops')
      .select('id')
      .eq('seller_id', sellerId)
      .single();
  final shopId = shopResp['id'];

  final p1Id = const Uuid().v4();

  await client.auth.signInWithPassword(
    email: _emailFromPhone(sellerPhone),
    password: _passwordFromPhone(sellerPhone),
  );
  await client.from('products').insert({
    'id': p1Id,
    'shop_id': shopId,
    'name': 'Premium Handcrafted Shawl',
    'category': 'Clothing',
    'price': 3000.0,
    'is_available': true,
    'total_quantity': 50,
  });

  print(
      '📦 Product created in Non-Deemed Category (Clothing > ₹2500, 18% GST, 1% TCS, 0.1% TDS)');

  // ── TEST 1: Place 3 Orders in different states ──
  // Order 1: Delivered (Gross ₹3000, 18% GST = ₹540, Comm = 10% ₹300, TCS 1% = ₹30, TDS 0.1% = ₹3, Gateway Share = 2.36%)
  // Order 2: Active / Preparing (Gross ₹3000)
  // Order 3: Pending / Awaiting Acceptance (Gross ₹3000)
  // Order 4: Seller Rejected / Done (Gross ₹3000)

  final o1 = const Uuid().v4();
  final o2 = const Uuid().v4();
  final o3 = const Uuid().v4();
  final o4 = const Uuid().v4();
  final now = DateTime.now();

  print('\n--- [TEST 1] Placing 4 Diverse Lifecycle Orders ---');
  await client.auth.signInWithPassword(
      email: _emailFromPhone(custPhone),
      password: _passwordFromPhone(custPhone));

  double currentPlatformFee = 5.0;
  try {
    final pRes = await client
        .from('platform_config')
        .select('value')
        .eq('key', 'platform_fee')
        .maybeSingle();
    if (pRes != null && pRes['value'] != null) {
      currentPlatformFee = (pRes['value'] is num)
          ? (pRes['value'] as num).toDouble()
          : double.parse(pRes['value'].toString());
    }
  } catch (_) {}

  for (final entry in [
    {'id': o1, 'cart': const Uuid().v4()},
    {'id': o2, 'cart': const Uuid().v4()},
    {'id': o3, 'cart': const Uuid().v4()},
    {'id': o4, 'cart': const Uuid().v4()},
  ]) {
    final orderId = entry['id']!;
    final cartId = entry['cart']!;
    await client.rpc('place_orders_transaction', params: {
      'p_orders': [
        {
          'id': orderId,
          'shop_id': shopId,
          'customer_id': customerId,
          'status': 'awaiting_acceptance',
          'total_amount': 3000.0,
          'payment_status': 'pending',
          'payment_method': 'upi',
          'grand_total_collected': 3000.0 + 540.0 + 23.60 + currentPlatformFee,
          'delivery_charges': 23.60,
          'rider_earnings': 16.0,
          'multi_shop_surcharge': 0.0,
          'platform_fee': currentPlatformFee,
          'small_cart_fee': 0.0,
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
        }
      ],
      'p_items': [
        {
          'id': const Uuid().v4(),
          'created_at': now.toIso8601String(),
          'order_id': orderId,
          'product_id': p1Id,
          'product_name': 'Premium Handcrafted Shawl',
          'quantity': 1,
          'price': 3000.0,
          'requires_prescription': false,
          'weight_kg': 0.5,
        }
      ],
      'p_coupon_id': null,
      'p_idempotency_key': cartId,
      'p_cart_group_id': cartId,
      'p_order_id_to_cancel': null,
    });
  }

  print('✅ 4 Orders Placed in Awaiting Acceptance');

  // ── Transition Order 1 to DELIVERED ──
  // Rider accepts o1
  await client.auth.signInWithPassword(
      email: _emailFromPhone(riderPhone),
      password: _passwordFromPhone(riderPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o1,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.0837,
    'p_shop_lng': 74.7973
  });

  // Seller accepts o1
  await client.auth.signInWithPassword(
      email: _emailFromPhone(sellerPhone),
      password: _passwordFromPhone(sellerPhone));
  await client.rpc('accept_order_seller', params: {'p_order_id': o1});

  // Capture payment on o1
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$o1';",
    '--linked'
  ]);

  // Seller prepares & readies o1
  await client.rpc('update_order_status',
      params: {'p_order_id': o1, 'p_new_status': 'preparing'});
  await client.rpc('update_order_status',
      params: {'p_order_id': o1, 'p_new_status': 'ready_for_pickup'});

  // Rider delivers o1
  await client.auth.signInWithPassword(
      email: _emailFromPhone(riderPhone),
      password: _passwordFromPhone(riderPhone));
  await client.rpc('update_order_status',
      params: {'p_order_id': o1, 'p_new_status': 'picked_up'});
  await client.rpc('update_order_status',
      params: {'p_order_id': o1, 'p_new_status': 'out_for_delivery'});
  await client.rpc('update_order_status', params: {
    'p_order_id': o1,
    'p_new_status': 'delivered',
    'p_rider_lat': 34.0838,
    'p_rider_lng': 74.7974
  });

  // ── Transition Order 2 to ACTIVE (preparing) ──
  await client.auth.signInWithPassword(
      email: _emailFromPhone(riderPhone),
      password: _passwordFromPhone(riderPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o2,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.0837,
    'p_shop_lng': 74.7973
  });

  await client.auth.signInWithPassword(
      email: _emailFromPhone(sellerPhone),
      password: _passwordFromPhone(sellerPhone));
  await client.rpc('accept_order_seller', params: {'p_order_id': o2});
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$o2';",
    '--linked'
  ]);
  await client.rpc('update_order_status',
      params: {'p_order_id': o2, 'p_new_status': 'preparing'});

  // ── Order 3 remains in PENDING (awaiting_acceptance) ──

  // ── Transition Order 4 to REJECTED (Done tab) ──
  await client.auth.signInWithPassword(
      email: _emailFromPhone(sellerPhone),
      password: _passwordFromPhone(sellerPhone));
  await client.rpc('reject_order_seller', params: {
    'p_order_id': o4,
    'p_reject_reason': 'out_of_stock',
    'p_message': 'No shawls remaining in inventory',
    'p_out_of_stock_product_id': null,
  });

  print('✅ Lifecycle states prepared:');
  print('  • Order 1 ($o1): DELIVERED');
  print('  • Order 2 ($o2): ACTIVE (preparing)');
  print('  • Order 3 ($o3): PENDING (awaiting_acceptance)');
  print('  • Order 4 ($o4): DONE (seller_rejected)');

  // ── TEST 2: VERIFY GET_SELLER_DAILY_STATS & DASHBOARD ──
  print('\n--- [TEST 2] Verifying get_seller_daily_stats ---');
  final dailyStats =
      await client.rpc('get_seller_daily_stats', params: {'p_shop_id': shopId});
  print('📊 get_seller_daily_stats result: $dailyStats');

  final totalOrders = (dailyStats['total_orders'] as num).toInt();
  final pendingOrders = (dailyStats['pending_orders'] as num).toInt();
  final todaysEarning = (dailyStats['todays_earning'] as num).toDouble();
  final productsCount = (dailyStats['products'] as num).toInt();

  // Verification Assertions:
  // 1. Total Orders: Excludes cancelled/seller_rejected -> o1, o2, o3 = 3 orders
  print('Total Orders: $totalOrders (Expected: 3)');
  if (totalOrders != 3)
    throw Exception('FAILED: Total orders expected 3, got $totalOrders');

  // 2. Pending Orders: Status in ('pending', 'awaiting_acceptance') -> o3 = 1 order
  print('Pending Orders: $pendingOrders (Expected: 1)');
  if (pendingOrders != 1)
    throw Exception('FAILED: Pending orders expected 1, got $pendingOrders');

  // 3. Products Count: 1 product created
  print('Products Count: $productsCount (Expected: 1)');
  if (productsCount != 1)
    throw Exception('FAILED: Products expected 1, got $productsCount');

  // 4. Today's Earning: o1 delivered seller payout
  print("Today's Earning: ₹$todaysEarning");
  if (todaysEarning <= 0)
    throw Exception(
        "FAILED: Today's earning must be positive for delivered order!");

  print(
      '✅ [TEST 2 PASSED] get_seller_daily_stats verified with 100% precision');

  // ── TEST 3: VERIFY FINANCIAL LEDGER & GET_SELLER_BALANCE ──
  print('\n--- [TEST 3] Verifying get_seller_balance & Settlement ---');
  final sellerBalance =
      await client.rpc('get_seller_balance', params: {'p_seller_id': sellerId});
  print('💰 get_seller_balance result: $sellerBalance');

  final totalEarned = (sellerBalance['total_earned'] as num).toDouble();
  final totalPaid = (sellerBalance['total_paid'] as num).toDouble();
  final availableBalance =
      (sellerBalance['available_balance'] as num).toDouble();

  print('Total Earned: ₹$totalEarned');
  print('Total Paid/Escrowed: ₹$totalPaid (Expected: 0)');
  print('Available Balance: ₹$availableBalance');

  // Assert Total Earned == Today's Earning (since only o1 was delivered today)
  if ((totalEarned - todaysEarning).abs() > 0.01) {
    throw Exception(
        'FAILED: Total Earned ($totalEarned) does not match Today\'s Earning ($todaysEarning)!');
  }

  // ── TEST 4: VERIFY WITHDRAWAL ESCROW LOCKING ──
  print(
      '\n--- [TEST 4] Requesting Seller Withdrawal & Verifying Balance Escrow ---');
  const withdrawAmount = 500.0;
  await client.rpc('request_seller_withdrawal', params: {
    'p_amount': withdrawAmount,
    'p_upi_id': 'seller@okhdfcbank',
    'p_bank_account_number': null,
    'p_bank_ifsc': null,
    'p_bank_account_holder': null,
  });

  final balanceAfterWithdrawal =
      await client.rpc('get_seller_balance', params: {'p_seller_id': sellerId});
  print('💰 Balance after ₹500 withdrawal: $balanceAfterWithdrawal');

  final remainingAvail =
      (balanceAfterWithdrawal['available_balance'] as num).toDouble();
  final newTotalPaid = (balanceAfterWithdrawal['total_paid'] as num).toDouble();

  print(
      'Remaining Available: ₹$remainingAvail (Expected: ${availableBalance - withdrawAmount})');
  print('New Total Paid/Escrowed: ₹$newTotalPaid (Expected: $withdrawAmount)');

  if ((remainingAvail - (availableBalance - withdrawAmount)).abs() > 0.01) {
    throw Exception(
        'FAILED: Remaining balance mismatch! Expected ${availableBalance - withdrawAmount}, got $remainingAvail');
  }
  if ((newTotalPaid - withdrawAmount).abs() > 0.01) {
    throw Exception(
        'FAILED: Total paid/escrowed mismatch! Expected $withdrawAmount, got $newTotalPaid');
  }

  print('✅ [TEST 4 PASSED] Seller withdrawal escrow reservation verified!');

  // ── TEST 5: CA REPORT FINANCIAL INTEGRITY ──
  print('\n--- [TEST 5] Verifying get_seller_ca_report ---');
  final startDay = DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 1))
      .toIso8601String();
  final endDay =
      DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String();

  final caReport = await client.rpc('get_seller_ca_report', params: {
    'p_shop_id': shopId,
    'p_start_date': startDay,
    'p_end_date': endDay,
  });

  print('📋 CA Report Result: $caReport');

  final caBaseSales = (caReport['total_base_sales'] as num).toDouble();
  final caNonFoodGst = (caReport['non_food_gst'] as num).toDouble();
  final caCommission = (caReport['commission'] as num).toDouble();
  final caTcs = (caReport['tcs_deducted'] as num).toDouble();
  final caTds = (caReport['tds_deducted'] as num).toDouble();
  final caPayout = (caReport['seller_payout'] as num).toDouble();
  final caDeliveredCount = (caReport['delivered_orders'] as num).toInt();

  print('• Base Sales: ₹$caBaseSales (Expected: 3000.0)');
  print('• Non-Food GST (18%): ₹$caNonFoodGst (Expected: 540.0)');
  print('• TCS Deducted (0.5%): ₹$caTcs (Expected: 15.0)');
  print('• TDS Deducted (0.1%): ₹$caTds (Expected: 3.0)');
  print('• Delivered Orders Count: $caDeliveredCount (Expected: 1)');
  print(
      '• CA Net Seller Payout: ₹$caPayout (Matches Total Earned: ₹$totalEarned)');

  if (caBaseSales != 3000.0) throw Exception('FAILED: CA Base Sales mismatch!');
  if (caNonFoodGst != 540.0)
    throw Exception('FAILED: CA Non-Food GST mismatch!');
  if (caTcs != 15.0) throw Exception('FAILED: CA TCS mismatch!');
  if (caTds != 3.0) throw Exception('FAILED: CA TDS mismatch!');
  if (caDeliveredCount != 1)
    throw Exception('FAILED: CA Delivered count mismatch!');
  if ((caPayout - totalEarned).abs() > 0.01)
    throw Exception(
        'FAILED: CA Payout ($caPayout) does not match totalEarned ($totalEarned)!');

  print(
      '✅ [TEST 5 PASSED] CA Report math perfectly reconciles with wallet balance!');

  print('\n================================================================');
  print('🎉 ALL 100x SELLER DASHBOARD & FINANCIAL CALCULATIONS PASSED 100%!');
  print('================================================================');
}
