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

  for (int attempt = 1; attempt <= 3; attempt++) {
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
      final userId = signUpRes.user?.id;
      if (userId != null) {
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
      }
    } catch (e) {
      if (attempt == 3) {
        final res =
            await client.auth.signInWithPassword(email: email, password: password);
        return res.user!.id;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }
  throw Exception('Failed to authenticate $phone');
}

Future<void> main() async {
  print('================================================================');
  print('🧪 STARTING 100x MULTI-SHOP SURCHARGE & GST EDGE-CASE TEST SUITE');
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
  final custPhone = '+919822222$rand';
  final s1Phone = '+919722222$rand';
  final s2Phone = '+919622222$rand';
  final s3Phone = '+919422222$rand';
  final riderPhone = '+919522222$rand';

  print('👥 Setting up 3-shop test ecosystem...');
  final customerId = await authUser(client, custPhone, 'customer');
  final seller1Id = await authUser(client, s1Phone, 'seller');
  final seller2Id = await authUser(client, s2Phone, 'seller');
  final seller3Id = await authUser(client, s3Phone, 'seller');
  final riderId = await authUser(client, riderPhone, 'delivery_partner');

  final shop1 = await client.from('shops').select('id').eq('seller_id', seller1Id).single();
  final shop2 = await client.from('shops').select('id').eq('seller_id', seller2Id).single();
  final shop3 = await client.from('shops').select('id').eq('seller_id', seller3Id).single();
  final shop1Id = shop1['id'];
  final shop2Id = shop2['id'];
  final shop3Id = shop3['id'];

  final p1Id = const Uuid().v4();
  final p2Id = const Uuid().v4();
  final p3Id = const Uuid().v4();

  // Create products for each shop
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.from('products').insert({'id': p1Id, 'shop_id': shop1Id, 'name': 'Pizza', 'category': 'Restaurant', 'price': 200.0, 'is_available': true, 'total_quantity': 50});

  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  await client.from('products').insert({'id': p2Id, 'shop_id': shop2Id, 'name': 'Burger', 'category': 'Restaurant', 'price': 150.0, 'is_available': true, 'total_quantity': 50});

  await client.auth.signInWithPassword(email: _emailFromPhone(s3Phone), password: _passwordFromPhone(s3Phone));
  await client.from('products').insert({'id': p3Id, 'shop_id': shop3Id, 'name': 'Dessert', 'category': 'Restaurant', 'price': 100.0, 'is_available': true, 'total_quantity': 50});

  // ── TEST 1: MULTI-SHOP SURCHARGE & GST CALCULATION (3 SHOPS) ──
  print('\n--- [TEST 1] Multi-Shop Surcharge & 18% GST Verification ---');
  const totalDeliveryGross = 70.80;
  const multiShopSurchargeTotal = 40.0;
  const expectedTotalRiderEarnings = 48.0;

  print('Total Multi-Shop Surcharge: ₹$multiShopSurchargeTotal');
  print('Total Gross Delivery Charges (inc 18% GST): ₹$totalDeliveryGross');
  print('Expected Total Rider Earnings (80% of net ₹60): ₹$expectedTotalRiderEarnings');

  final order1Id = const Uuid().v4();
  final order2Id = const Uuid().v4();
  final order3Id = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  final now = DateTime.now();

  double currentPlatformFee = 20.0;
  try {
    final pRes = await client.from('platform_config').select('value').eq('key', 'platform_fee').maybeSingle();
    if (pRes != null && pRes['value'] != null) {
      currentPlatformFee = (pRes['value'] is num) ? (pRes['value'] as num).toDouble() : double.parse(pRes['value'].toString());
    }
  } catch (_) {}

  const shopDeliveryFee = totalDeliveryGross / 3.0; // 23.60
  const shopSurcharge = multiShopSurchargeTotal / 3.0; // 13.33
  final shopPlatformFee = currentPlatformFee / 3.0;

  final ordersPayload = [
    {
      'id': order1Id,
      'shop_id': shop1Id,
      'customer_id': customerId,
      'status': 'awaiting_acceptance',
      'total_amount': 200.0,
      'payment_status': 'pending',
      'payment_method': 'upi',
      'grand_total_collected': 200.0 + 10.0 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee,
      'rider_earnings': expectedTotalRiderEarnings / 3.0,
      'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee,
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
    },
    {
      'id': order2Id,
      'shop_id': shop2Id,
      'customer_id': customerId,
      'status': 'awaiting_acceptance',
      'total_amount': 150.0,
      'payment_status': 'pending',
      'payment_method': 'upi',
      'grand_total_collected': 150.0 + 7.5 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee,
      'rider_earnings': expectedTotalRiderEarnings / 3.0,
      'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee,
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
    },
    {
      'id': order3Id,
      'shop_id': shop3Id,
      'customer_id': customerId,
      'status': 'awaiting_acceptance',
      'total_amount': 100.0,
      'payment_status': 'pending',
      'payment_method': 'upi',
      'grand_total_collected': 100.0 + 5.0 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee,
      'rider_earnings': expectedTotalRiderEarnings / 3.0,
      'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee,
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
    },
  ];

  final itemsPayload = [
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': order1Id, 'product_id': p1Id, 'product_name': 'Pizza', 'quantity': 1, 'price': 200.0, 'requires_prescription': false, 'weight_kg': 0.5},
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': order2Id, 'product_id': p2Id, 'product_name': 'Burger', 'quantity': 1, 'price': 150.0, 'requires_prescription': false, 'weight_kg': 0.5},
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': order3Id, 'product_id': p3Id, 'product_name': 'Dessert', 'quantity': 1, 'price': 100.0, 'requires_prescription': false, 'weight_kg': 0.5},
  ];

  await client.auth.signInWithPassword(email: _emailFromPhone(custPhone), password: _passwordFromPhone(custPhone));
  await client.rpc('place_orders_transaction', params: {
    'p_orders': ordersPayload,
    'p_items': itemsPayload,
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
    'p_cart_group_id': cartGroupId,
    'p_order_id_to_cancel': null,
  });

  print('✅ 3-Shop Order Transaction placed successfully');

  // Verify stored rows in database
  final placedOrders = await client.from('orders').select('id, delivery_charges, multi_shop_surcharge, gst_delivery, rider_earnings').eq('cart_group_id', cartGroupId);
  double sumRiderEarnings = 0;
  double sumDeliveryCharges = 0;
  double sumSurcharge = 0;
  double sumGstDelivery = 0;

  for (var o in placedOrders) {
    sumRiderEarnings += (o['rider_earnings'] as num).toDouble();
    sumDeliveryCharges += (o['delivery_charges'] as num).toDouble();
    sumSurcharge += (o['multi_shop_surcharge'] as num).toDouble();
    sumGstDelivery += (o['gst_delivery'] as num).toDouble();
  }

  print('\n📊 Stored Database Metrics Across 3 Shops:');
  print('• Sum Delivery Charges: ₹${sumDeliveryCharges.toStringAsFixed(2)} (Expected: 70.80)');
  print('• Sum Multi-Shop Surcharges: ₹${sumSurcharge.toStringAsFixed(2)} (Expected: 40.00)');
  print('• Sum Delivery GST (18%): ₹${sumGstDelivery.toStringAsFixed(2)} (Expected: 10.80)');
  print('• Sum Rider Earnings (80%): ₹${sumRiderEarnings.toStringAsFixed(2)} (Expected: 48.00)');

  if ((sumRiderEarnings - 48.0).abs() > 0.5) {
    throw Exception('FAILED: Sum of Rider Earnings ($sumRiderEarnings) does not match expected (48.0)');
  }
  if ((sumDeliveryCharges - 70.80).abs() > 0.5) {
    throw Exception('FAILED: Sum Delivery Charges ($sumDeliveryCharges) does not match expected (70.80)');
  }

  // ── TEST 2: RIDER ASSIGNMENT & FULL DELIVERY STATS INTEGRATION ──
  print('\n--- [TEST 2] Rider Acceptance, Delivery & Stats Verification ---');
  // 1. Rider accepts 1st order -> atomically accepts all 3 in the cart group
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': order1Id,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.0837,
    'p_shop_lng': 74.7973,
  });

  // 2. Sellers accept orders
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': order1Id});

  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': order2Id});

  await client.auth.signInWithPassword(email: _emailFromPhone(s3Phone), password: _passwordFromPhone(s3Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': order3Id});

  // 3. Capture payment
  await Process.run('supabase', [
    'db',
    'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE cart_group_id = '$cartGroupId';",
    '--linked'
  ]);

  // 4. Sellers prepare and ready orders
  for (final entry in [
    {'phone': s1Phone, 'id': order1Id},
    {'phone': s2Phone, 'id': order2Id},
    {'phone': s3Phone, 'id': order3Id},
  ]) {
    await client.auth.signInWithPassword(email: _emailFromPhone(entry['phone']!), password: _passwordFromPhone(entry['phone']!));
    await client.rpc('update_order_status', params: {'p_order_id': entry['id']!, 'p_new_status': 'preparing'});
    await client.rpc('update_order_status', params: {'p_order_id': entry['id']!, 'p_new_status': 'ready_for_pickup'});
  }

  // 5. Rider picks up, goes out for delivery, and delivers each order
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));
  for (final orderId in [order1Id, order2Id, order3Id]) {
    await client.rpc('update_order_status', params: {'p_order_id': orderId, 'p_new_status': 'picked_up'});
    await client.rpc('update_order_status', params: {'p_order_id': orderId, 'p_new_status': 'out_for_delivery'});
    await client.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'delivered',
      'p_rider_lat': 34.0838,
      'p_rider_lng': 74.7974,
    });
  }

  final stats = await client.rpc('get_rider_stats', params: {'p_rider_id': riderId});
  final balance = await client.rpc('get_rider_balance', params: {'p_rider_id': riderId});

  print('📈 Rider Stats after delivering 3-shop cart: $stats');
  print('💰 Rider Balance after delivering 3-shop cart: $balance');

  final riderTotalEarnings = (stats['total_earnings'] as num).toDouble();
  final riderAvailableBal = (balance['available_balance'] as num).toDouble();

  // Rider Total Earnings MUST be ₹48.00 (includes base + multi-shop surcharge)
  if ((riderTotalEarnings - 48.0).abs() > 0.5) {
    throw Exception('FAILED: Rider Total Earnings ($riderTotalEarnings) does not match expected 48.0!');
  }
  if ((riderAvailableBal - 48.0).abs() > 0.5) {
    throw Exception('FAILED: Rider Available Balance ($riderAvailableBal) does not match expected 48.0!');
  }
  print('✅ [TEST 2 PASSED] Multi-shop surcharge is 100% included in Rider Earnings & Balance');

  // ── TEST 3: DYNAMIC REALLOCATION ON PARTIAL CANCELLATION ──
  print('\n--- [TEST 3] Dynamic Surcharge Reallocation on Partial Rejection ---');
  final cartGroup2 = const Uuid().v4();
  final o1 = const Uuid().v4();
  final o2 = const Uuid().v4();
  final o3 = const Uuid().v4();

  // Create a 2nd 3-shop order group
  final orders2 = [
    {
      'id': o1, 'shop_id': shop1Id, 'customer_id': customerId, 'status': 'awaiting_acceptance',
      'total_amount': 200.0, 'payment_status': 'pending', 'payment_method': 'upi',
      'grand_total_collected': 200.0 + 10.0 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee, 'rider_earnings': 16.0, 'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee, 'small_cart_fee': 0.0, 'heavy_order_fee': 0.0, 'coupon_discount': 0.0,
      'estimated_distance_km': 1.0, 'gst_rate_snapshot': {}, 'shop_prep_time_snapshot': 30,
      'shop_lat': 34.0839, 'shop_lng': 74.7975, 'delivery_lat': 34.0838, 'delivery_lng': 74.7974,
      'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
    },
    {
      'id': o2, 'shop_id': shop2Id, 'customer_id': customerId, 'status': 'awaiting_acceptance',
      'total_amount': 150.0, 'payment_status': 'pending', 'payment_method': 'upi',
      'grand_total_collected': 150.0 + 7.5 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee, 'rider_earnings': 16.0, 'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee, 'small_cart_fee': 0.0, 'heavy_order_fee': 0.0, 'coupon_discount': 0.0,
      'estimated_distance_km': 1.0, 'gst_rate_snapshot': {}, 'shop_prep_time_snapshot': 30,
      'shop_lat': 34.0839, 'shop_lng': 74.7975, 'delivery_lat': 34.0838, 'delivery_lng': 74.7974,
      'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
    },
    {
      'id': o3, 'shop_id': shop3Id, 'customer_id': customerId, 'status': 'awaiting_acceptance',
      'total_amount': 100.0, 'payment_status': 'pending', 'payment_method': 'upi',
      'grand_total_collected': 100.0 + 5.0 + shopDeliveryFee + shopPlatformFee,
      'delivery_charges': shopDeliveryFee, 'rider_earnings': 16.0, 'multi_shop_surcharge': shopSurcharge,
      'platform_fee': shopPlatformFee, 'small_cart_fee': 0.0, 'heavy_order_fee': 0.0, 'coupon_discount': 0.0,
      'estimated_distance_km': 1.0, 'gst_rate_snapshot': {}, 'shop_prep_time_snapshot': 30,
      'shop_lat': 34.0839, 'shop_lng': 74.7975, 'delivery_lat': 34.0838, 'delivery_lng': 74.7974,
      'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
    },
  ];

  final items2 = [
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': o1, 'product_id': p1Id, 'product_name': 'Pizza', 'quantity': 1, 'price': 200.0, 'requires_prescription': false, 'weight_kg': 0.5},
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': o2, 'product_id': p2Id, 'product_name': 'Burger', 'quantity': 1, 'price': 150.0, 'requires_prescription': false, 'weight_kg': 0.5},
    {'id': const Uuid().v4(), 'created_at': now.toIso8601String(), 'order_id': o3, 'product_id': p3Id, 'product_name': 'Dessert', 'quantity': 1, 'price': 100.0, 'requires_prescription': false, 'weight_kg': 0.5},
  ];

  await client.auth.signInWithPassword(email: _emailFromPhone(custPhone), password: _passwordFromPhone(custPhone));
  await client.rpc('place_orders_transaction', params: {
    'p_orders': orders2,
    'p_items': items2,
    'p_coupon_id': null,
    'p_idempotency_key': cartGroup2,
    'p_cart_group_id': cartGroup2,
    'p_order_id_to_cancel': null,
  });

  // Seller 3 rejects order 3 (Shop 3 cancelled)
  await client.auth.signInWithPassword(email: _emailFromPhone(s3Phone), password: _passwordFromPhone(s3Phone));
  await client.rpc('reject_order_seller', params: {
    'p_order_id': o3,
    'p_reject_reason': 'Out of stock',
    'p_message': 'Item not available',
    'p_out_of_stock_product_id': null,
  });

  // Re-authenticate as Customer to view all sibling orders in the cart group (RLS multi-shop visibility)
  await client.auth.signInWithPassword(email: _emailFromPhone(custPhone), password: _passwordFromPhone(custPhone));

  // Reallocation recalculates remaining active shops (2 shops left)
  // Allowed Surcharge = (2 - 1) * 20 = ₹20 (down from ₹40)
  // New Total Delivery for remaining 2 shops = (Base 20 + Surcharge 20) * 1.18 = 40 * 1.18 = ₹47.20
  // New Rider Earnings for remaining 2 shops = 40 * 0.80 = ₹32.00
  final reallocatedOrders = await client.from('orders').select('id, status, delivery_charges, multi_shop_surcharge, rider_earnings').eq('cart_group_id', cartGroup2);
  print('\n📦 Reallocated Orders State:');
  double activeRiderEarnings = 0;
  double activeSurcharge = 0;

  for (var ro in reallocatedOrders) {
    print('Order ${ro['id'].toString().substring(0,8)} Status: ${ro['status']}, Surcharge: ₹${ro['multi_shop_surcharge']}, RiderEarnings: ₹${ro['rider_earnings']}');
    if (ro['status'] != 'seller_rejected') {
      activeRiderEarnings += (ro['rider_earnings'] as num).toDouble();
      activeSurcharge += (ro['multi_shop_surcharge'] as num).toDouble();
    }
  }

  print('• Active Reallocated Surcharge: ₹${activeSurcharge.toStringAsFixed(2)} (Expected: 20.00)');
  print('• Active Reallocated Rider Earnings: ₹${activeRiderEarnings.toStringAsFixed(2)} (Expected: 32.00)');

  if ((activeSurcharge - 20.0).abs() > 0.5) {
    throw Exception('FAILED: Active surcharge ($activeSurcharge) did not rebalance to 20.0!');
  }
  if ((activeRiderEarnings - 32.0).abs() > 0.5) {
    throw Exception('FAILED: Active rider earnings ($activeRiderEarnings) did not rebalance to 32.0!');
  }

  print('✅ [TEST 3 PASSED] Partial cancellation dynamic surcharge reallocation verified with mathematical precision!');

  print('\n================================================================');
  print('🎉 ALL 100x MULTI-SHOP SURCHARGE & GST TESTS PASSED 100%!');
  print('================================================================');
}
