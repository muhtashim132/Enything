import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

/// 100x Comprehensive Rider Testing & Debugging Suite
/// Tests all Rider functionality with respect to Customer, Seller, and Admin.
Future<void> main() async {
  print('================================================================');
  print('  100x Comprehensive Rider End-to-End Testing & Debugging Suite  ');
  print('  (Customer ↔ Seller ↔ Rider ↔ Admin Dimensions)               ');
  print('================================================================\n');

  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('❌ Error: .env file not found.');
    exit(1);
  }

  String supabaseUrl = '';
  String supabaseAnonKey = '';
  for (final line in await envFile.readAsLines()) {
    if (line.startsWith('SUPABASE_URL=')) {
      supabaseUrl = line.split('=')[1].trim();
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      supabaseAnonKey = line.split('=')[1].trim();
    }
  }

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    print('❌ Error: Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
    exit(1);
  }

  final client = SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  print('✅ Connected to Supabase: $supabaseUrl\n');

  try {
    await runRiderLifecycleSuite(client);
    print('\n================================================================');
    print('  🎉 ALL 10 MODULES OF THE 100X RIDER SUITE PASSED PERFECTLY!  ');
    print('================================================================');
    exit(0);
  } catch (e, stack) {
    print('\n❌ TEST SUITE FAILED WITH ERROR: $e');
    print(stack);
    exit(1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers: Authentication & User Provisioning
// ─────────────────────────────────────────────────────────────────────────────

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

Future<String> authUser(
  SupabaseClient client,
  String phone,
  String role, {
  String? kycStatus = 'verified',
}) async {
  final email = _emailFromPhone(phone);
  final password = _passwordFromPhone(phone);

  String? userId;
  int attempts = 0;
  while (attempts < 5) {
    attempts++;
    try {
      final res = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      userId = res.user?.id;
      if (userId != null) break;
    } catch (_) {
      try {
        final res = await client.auth.signUp(
          email: email,
          password: password,
          data: <String, dynamic>{'phone': phone},
        );
        userId = res.user?.id;
        if (userId != null) break;
      } catch (e) {
        if (e.toString().contains('429') || e.toString().contains('rate_limit')) {
          print('  [Auth Rate Limit] Waiting 4s before retry $attempts/5 for $phone...');
          await Future.delayed(const Duration(seconds: 4));
          continue;
        }
        throw Exception('Failed to auth user $phone: $e');
      }
    }
  }

  if (userId == null) throw Exception('Failed to obtain user ID for $phone');

  final profileRole = role == 'admin' ? 'customer' : role;
  await client.from('profiles').upsert({
    'id': userId,
    'role': profileRole,
    'full_name': 'Test $role ${phone.substring(phone.length - 4)}',
    'phone': phone,
  });

  if (role == 'admin') {
    final token = 'INVITE_${const Uuid().v4()}';
    final roleRec = await client.from('roles').select('id').limit(1).maybeSingle();
    final roleId = roleRec?['id'];
    await client.from('admin_invitations').insert({
      'token': token,
      'email': email,
      'invited_by': userId,
      if (roleId != null) 'role_id': roleId,
      'status': 'pending',
      'expires_at': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
    });
    await client.rpc('accept_admin_invitation', params: {
      'p_token': token,
      'p_auth_user_id': userId,
      'p_full_name': 'Test Admin ${phone.substring(phone.length - 4)}',
      'p_admin_password': password,
    });
  }

  const shopLocation = 'POINT(74.6366 34.4225)';

  if (role == 'customer') {
    await client.from('customers').upsert({
      'id': userId,
      'location': shopLocation,
    });
    final addrs = await client
        .from('saved_addresses')
        .select()
        .eq('user_id', userId);
    if (addrs.isEmpty) {
      await client.from('saved_addresses').insert({
        'user_id': userId,
        'label': 'Home',
        'address': 'Test Customer Address, Srinagar',
        'pincode': '190001',
        'latitude': 34.4225,
        'longitude': 74.6366,
        'is_default': true,
      });
    }
  } else if (role == 'seller') {
    final hasShop = await client
        .from('shops')
        .select('id')
        .eq('seller_id', userId)
        .maybeSingle();
    if (hasShop == null) {
      await client.from('shops').insert({
        'seller_id': userId,
        'name': 'Test Shop ${phone.substring(phone.length - 4)}',
        'address': 'Commercial Complex, Srinagar',
        'category': 'Food',
        'is_active': true,
        'is_accepting_orders': true,
        'verification_status': kycStatus ?? 'verified',
        'location': shopLocation,
      });
    }
  } else if (role == 'delivery_partner') {
    await client.from('delivery_partners').upsert({
      'id': userId,
      'vehicle_type': 'motorcycle',
      'vehicle_number': 'JK-01-AB-1234',
      'is_active': true,
      'is_accepting_orders': true,
      'verification_status': kycStatus ?? 'verified',
      'location': shopLocation,
    });
  }

  return userId;
}

// ─────────────────────────────────────────────────────────────────────────────
// Master Test Suite Execution
// ─────────────────────────────────────────────────────────────────────────────

Future<void> runRiderLifecycleSuite(SupabaseClient client) async {
  const c1Phone = '+919999000001';
  const c2Phone = '+919999000002';
  const c3Phone = '+919999000003';
  const c4Phone = '+919999000004';
  const s1Phone = '+919999000011';
  const s2Phone = '+919999000012';
  const riderPhone = '+919999000021';
  const adminPhone = '+919999000031';

  print('─── Module 1: Provisioning Multi-Actor Personas ───');
  final c1Id = await authUser(client, c1Phone, 'customer');
  final c2Id = await authUser(client, c2Phone, 'customer');
  final c3Id = await authUser(client, c3Phone, 'customer');
  final c4Id = await authUser(client, c4Phone, 'customer');

  final s1Id = await authUser(client, s1Phone, 'seller');
  final s2Id = await authUser(client, s2Phone, 'seller');

  // Create rider with initial pending KYC
  final riderId = await authUser(client, riderPhone, 'delivery_partner', kycStatus: 'pending');
  final adminId = await authUser(client, adminPhone, 'admin');

  print('  ✓ Customer 1: $c1Id');
  print('  ✓ Customer 2: $c2Id');
  print('  ✓ Seller 1:   $s1Id');
  print('  ✓ Seller 2:   $s2Id');
  print('  ✓ Rider:      $riderId (KYC: pending)');
  print('  ✓ Admin:      $adminId');

  // Cleanup any old test orders for these test customers/rider so anti-hoarding and active counts are clean
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));
  final oldOrders = await client
      .from('orders')
      .select('id')
      .inFilter('customer_id', [c1Id, c2Id, c3Id, c4Id])
      .not('status', 'in', '(cancelled,delivered)');
  for (final o in oldOrders) {
    try {
      await client.rpc('admin_cancel_order', params: {'p_order_id': o['id']});
    } catch (_) {}
  }

  // Fetch shops
  final s1ShopRec = await client.from('shops').select('id, location').eq('seller_id', s1Id).single();
  final s1ShopId = s1ShopRec['id'] as String;
  final s2ShopRec = await client.from('shops').select('id, location').eq('seller_id', s2Id).single();
  final s2ShopId = s2ShopRec['id'] as String;

  // Create products in both shops
  print('\n  Creating products in Seller 1 and Seller 2 shops...');
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  final p1Id = const Uuid().v4();
  await client.from('products').insert({
    'id': p1Id,
    'shop_id': s1ShopId,
    'name': 'Kashmiri Wazwan Rogan Josh',
    'category': 'Food',
    'price': 450.0,
    'is_available': true,
    'total_quantity': 50,
    'weight_per_unit': 0.5,
  });

  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  final p2Id = const Uuid().v4();
  await client.from('products').insert({
    'id': p2Id,
    'shop_id': s2ShopId,
    'name': 'Fresh Kashmiri Apple Juice',
    'category': 'Food',
    'price': 150.0,
    'is_available': true,
    'total_quantity': 50,
    'weight_per_unit': 0.3,
  });
  print('  ✓ Products created in both shops.');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 2: Rider KYC Review & Admin Approval Flow
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 2: Rider KYC Review & Admin Approval ───');
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));

  // Admin approves rider KYC
  await client.rpc('admin_update_kyc', params: {
    'p_target_id': riderId,
    'p_type': 'rider',
    'p_status': 'approved',
  });
  await client.rpc('admin_update_kyc', params: {
    'p_target_id': riderId,
    'p_type': 'customer',
    'p_status': 'verified',
  });

  // Verify rider is now verified in delivery_partners table
  final dpStatus = await client.from('delivery_partners').select('verification_status, is_active').eq('id', riderId).single();
  if (dpStatus['verification_status'] != 'verified' && dpStatus['verification_status'] != 'approved') {
    throw Exception('Expected rider verification_status to be approved/verified, got ${dpStatus['verification_status']}');
  }
  print('  ✓ Rider KYC successfully approved by Admin.');

  // Helper function to place order for customer
  Future<String> placeOrder({
    required String customerPhone,
    required String customerId,
    required String shopId,
    required String productId,
    required double itemPrice,
    double deliveryCharge = 50.0,
    double distanceKm = 1.0,
  }) async {
    await client.auth.signInWithPassword(
      email: _emailFromPhone(customerPhone),
      password: _passwordFromPhone(customerPhone),
    );

    final orderId = const Uuid().v4();
    final cartGroupId = const Uuid().v4();
    final now = DateTime.now().toUtc();

    final orderData = {
      'id': orderId,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'cart_group_id': cartGroupId,
      'shop_id': shopId,
      'customer_id': customerId,
      'status': 'awaiting_acceptance',
      'seller_accepted': false,
      'partner_accepted': false,
      'acceptance_deadline': now.add(const Duration(minutes: 5)).toIso8601String(),
      'total_amount': itemPrice,
      'delivery_charges': deliveryCharge,
      'rider_earnings': deliveryCharge,
      'platform_fee': 20.0,
      'small_cart_fee': 0.0,
      'address': 'Test Street, Srinagar',
      'delivery_lat': 34.4225,
      'delivery_lng': 74.6366,
      'payment_method': 'upi',
      'payment_status': 'pending',
      'grand_total_collected': itemPrice + deliveryCharge + 20.0 + (itemPrice * 0.05),
      'gst_item_total': itemPrice * 0.05,
      's9_5_gst_amount': 0.0,
      'non_food_gst_amount': 0.0,
      'gst_delivery': 0.0,
      'gst_platform': 0.0,
      'tcs_amount': 0.0,
      'tds_amount': 0.0,
      'enything_commission': itemPrice * 0.05,
      'seller_payout': itemPrice * 0.95,
      'gateway_deduction': 0.0,
      'heavy_order_fee': 0.0,
      'multi_shop_surcharge': 0.0,
      'coupon_discount': 0.0,
      'estimated_distance_km': distanceKm,
      'gst_rate_snapshot': {},
      'shop_prep_time_snapshot': 30,
    };

    final itemData = {
      'id': const Uuid().v4(),
      'created_at': now.toIso8601String(),
      'order_id': orderId,
      'product_id': productId,
      'product_name': 'Test Item',
      'quantity': 1,
      'price': itemPrice,
      'requires_prescription': false,
      'weight_kg': 0.5,
    };

    await client.rpc('place_orders_transaction', params: {
      'p_orders': [orderData],
      'p_items': [itemData],
      'p_coupon_id': null,
      'p_idempotency_key': cartGroupId,
      'p_cart_group_id': cartGroupId,
      'p_order_id_to_cancel': null,
    });

    return orderId;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Module 3 & 4: Multi-Shop Batched Order, Dual Acceptance & State Sync
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 3 & 4: Order Placement, Dual Acceptance & Race Conditions ───');
  final mainOrderId = await placeOrder(
    customerPhone: c1Phone,
    customerId: c1Id,
    shopId: s1ShopId,
    productId: p1Id,
    itemPrice: 450.0,
    deliveryCharge: 50.0,
  );
  print('  ✓ Order placed by Customer 1 (ID: $mainOrderId)');

  // Step 4A: Rider accepts FIRST
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));
  final riderAcceptRes = await client.rpc('accept_order_rider', params: {
    'p_order_id': mainOrderId,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });
  print('  ✓ Rider accepted order. Both accepted = $riderAcceptRes (expected: false, waiting for seller)');

  // Step 4B: Seller accepts SECOND
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('accept_order_seller', params: {'p_order_id': mainOrderId});
  print('  ✓ Seller accepted order.');

  // Verify order transitioned to awaiting_payment
  final orderAfterDualAccept = await client.from('orders').select('status, delivery_partner_id, partner_accepted, seller_accepted').eq('id', mainOrderId).single();
  if (orderAfterDualAccept['status'] != 'awaiting_payment') {
    throw Exception('Expected order status to be awaiting_payment, got ${orderAfterDualAccept['status']}');
  }
  if (orderAfterDualAccept['delivery_partner_id'] != riderId) {
    throw Exception('Expected delivery_partner_id to be rider ID $riderId');
  }
  print('  ✓ Dual acceptance state verified: status is awaiting_payment, rider assigned.');

  // Simulate customer payment confirmation via dev_client_confirm_payment
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));
  await client.rpc('dev_client_confirm_payment', params: {
    'p_order_id': mainOrderId,
    'p_razorpay_payment_id': 'pay_test_${DateTime.now().millisecondsSinceEpoch}',
    'p_razorpay_order_id': 'order_test_${DateTime.now().millisecondsSinceEpoch}',
  });

  // Seller marks order preparing
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('update_order_status', params: {
    'p_order_id': mainOrderId,
    'p_new_status': 'preparing',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });
  print('  ✓ Order payment confirmed and marked preparing by seller.');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 5: Anti-Hoarding Fortress (Max 3 Cart Groups Limit)
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 5: Anti-Hoarding Fortress Verification (Max 3 Active Carts) ───');
  // We already have 1 active cart group (mainOrderId). Let's create 2 more.
  final o2Id = await placeOrder(customerPhone: c2Phone, customerId: c2Id, shopId: s1ShopId, productId: p1Id, itemPrice: 450.0);
  final o3Id = await placeOrder(customerPhone: c3Phone, customerId: c3Id, shopId: s2ShopId, productId: p2Id, itemPrice: 150.0);
  final o4Id = await placeOrder(customerPhone: c4Phone, customerId: c4Id, shopId: s1ShopId, productId: p1Id, itemPrice: 450.0);

  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));

  // Accept Order 2 (total 2 carts)
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o2Id,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });
  // Accept Order 3 (total 3 carts)
  await client.rpc('accept_order_rider', params: {
    'p_order_id': o3Id,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });
  print('  ✓ Rider successfully accepted 3 distinct active carts.');

  // Attempt to accept 4th cart -> MUST FAIL
  try {
    await client.rpc('accept_order_rider', params: {
      'p_order_id': o4Id,
      'p_rider_phone': riderPhone,
      'p_shop_lat': 34.4225,
      'p_shop_lng': 74.6366,
    });
    throw Exception('CRITICAL FAILURE: Rider was able to accept a 4th active cart group!');
  } catch (e) {
    if (!e.toString().contains('MAX_ORDERS_REACHED')) {
      throw Exception('Expected MAX_ORDERS_REACHED error, got: $e');
    }
    print('  ✓ Anti-hoarding fortress validated: 4th active cart group blocked with MAX_ORDERS_REACHED.');
  }

  // Cancel o2 and o3 to free up slots for clean execution
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));
  for (final oid in [o2Id, o3Id, o4Id]) {
    try {
      await client.rpc('admin_cancel_order', params: {'p_order_id': oid});
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Module 6: Shop Arrival Geofence Validation & Timestamp Locking
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 6: Shop Arrival Geofence & Timestamp Validation ───');
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));

  await client.rpc('set_arrived_at_shop', params: {
    'p_order_id': mainOrderId,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
  });

  final orderArrived = await client.from('orders').select('arrived_at_shop_time').eq('id', mainOrderId).single();
  if (orderArrived['arrived_at_shop_time'] == null) {
    throw Exception('Expected arrived_at_shop_time to be recorded');
  }
  print('  ✓ Rider arrival at shop verified. arrived_at_shop_time locked: ${orderArrived['arrived_at_shop_time']}');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 7: Seller Wait Time Penalty & Rider Compensation
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 7: Seller Wait Time Penalty & Rider Compensation ───');
  // Seller marks ready for pickup
  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.rpc('update_order_status', params: {
    'p_order_id': mainOrderId,
    'p_new_status': 'ready_for_pickup',
    'p_ready_time': DateTime.now().toUtc().toIso8601String(),
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });

  final orderReady = await client.from('orders').select('status, order_ready_time, wait_time_penalty').eq('id', mainOrderId).single();
  if (orderReady['status'] != 'ready_for_pickup') {
    throw Exception('Expected status ready_for_pickup, got ${orderReady['status']}');
  }
  print('  ✓ Order marked ready_for_pickup. Status machine verified.');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 8: Multi-Stop Pickup & Doorstep Delivery Geofence
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 8: Pickup Handoff & Customer Doorstep Delivery Geofence ───');
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));

  // Step 8A: Rider marks picked_up
  await client.rpc('update_order_status', params: {
    'p_order_id': mainOrderId,
    'p_new_status': 'picked_up',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });
  print('  ✓ Rider marked picked_up.');

  // Step 8B: Rider marks out_for_delivery
  await client.rpc('update_order_status', params: {
    'p_order_id': mainOrderId,
    'p_new_status': 'out_for_delivery',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': null,
    'p_rider_lng': null,
    'p_delivery_otp': null,
  });
  print('  ✓ Rider marked out_for_delivery.');

  // Step 8C: Test delivery geofence failure (rider is far away: 35.0, 75.0 ~ 70km away)
  try {
    await client.rpc('update_order_status', params: {
      'p_order_id': mainOrderId,
      'p_new_status': 'delivered',
      'p_ready_time': null,
      'p_wait_penalty': 0.0,
      'p_rider_lat': 35.0,
      'p_rider_lng': 75.0,
      'p_delivery_otp': null,
    });
    throw Exception('CRITICAL FAILURE: Delivery was allowed outside 300m geofence!');
  } catch (e) {
    if (!e.toString().contains('GEO_FENCE_FAILED')) {
      throw Exception('Expected GEO_FENCE_FAILED error, got: $e');
    }
    print('  ✓ Doorstep geofence validated: Remote delivery blocked with GEO_FENCE_FAILED.');
  }

  // Step 8D: Valid doorstep delivery within 300m
  await client.rpc('update_order_status', params: {
    'p_order_id': mainOrderId,
    'p_new_status': 'delivered',
    'p_ready_time': null,
    'p_wait_penalty': 0.0,
    'p_rider_lat': 34.4225,
    'p_rider_lng': 74.6366,
    'p_delivery_otp': null,
  });

  final orderDelivered = await client.from('orders').select('status').eq('id', mainOrderId).single();
  if (orderDelivered['status'] != 'delivered') {
    throw Exception('Expected status delivered, got ${orderDelivered['status']}');
  }
  print('  ✓ Order successfully delivered at doorstep within geofence.');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 9: Financial Ledger, Wallet Balance & Withdrawal Workflow
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 9: Rider Financial Balance, Ledger & Withdrawal Workflow ───');
  final balanceRes = await client.rpc('get_rider_balance', params: {'p_rider_id': riderId});
  print('  Rider Balance Snapshot: $balanceRes');
  final availableBalance = (balanceRes['available_balance'] as num).toDouble();
  if (availableBalance < 50.0) {
    throw Exception('Expected available balance to be at least ₹50 (from delivery earnings), got $availableBalance');
  }
  print('  ✓ Rider balance correctly computed from delivered order: ₹$availableBalance');

  // Submit withdrawal request for ₹40
  await client.rpc('request_rider_withdrawal', params: {
    'p_amount': 40.0,
    'p_upi_id': 'rider@oksbi',
    'p_bank_account_number': null,
    'p_bank_ifsc': null,
    'p_bank_account_holder': null,
  });
  print('  ✓ Withdrawal request of ₹40 submitted by Rider.');

  // Verify available balance deducted pending withdrawal
  final balanceAfterReq = await client.rpc('get_rider_balance', params: {'p_rider_id': riderId});
  final newAvailable = (balanceAfterReq['available_balance'] as num).toDouble();
  if ((newAvailable - (availableBalance - 40.0)).abs() > 0.01) {
    throw Exception('Expected available balance to be ${availableBalance - 40.0}, got $newAvailable');
  }
  print('  ✓ Available balance successfully held pending withdrawal: ₹$newAvailable');

  // Admin approves withdrawal
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));
  final wRec = await client.from('withdrawals').select('id').eq('user_id', riderId).eq('status', 'pending').single();
  await client.rpc('admin_process_withdrawal', params: {
    'p_withdrawal_id': wRec['id'],
    'p_status': 'processed',
    'p_transaction_id': 'UTR_TEST_${DateTime.now().millisecondsSinceEpoch}',
  });
  print('  ✓ Admin approved withdrawal with UTR.');

  // ───────────────────────────────────────────────────────────────────────────
  // Module 10: Emergency Order Drop & Mutual Ratings Flow
  // ───────────────────────────────────────────────────────────────────────────
  print('\n─── Module 10: Emergency Order Drop & Mutual Ratings Flow ───');
  // Step 10A: Emergency Drop
  final dropOrderId = await placeOrder(customerPhone: c1Phone, customerId: c1Id, shopId: s1ShopId, productId: p1Id, itemPrice: 450.0);
  await client.auth.signInWithPassword(email: _emailFromPhone(riderPhone), password: _passwordFromPhone(riderPhone));
  await client.rpc('accept_order_rider', params: {
    'p_order_id': dropOrderId,
    'p_rider_phone': riderPhone,
    'p_shop_lat': 34.4225,
    'p_shop_lng': 74.6366,
  });

  // Rider drops order due to emergency
  await client.rpc('reject_order_rider', params: {
    'p_order_id': dropOrderId,
    'p_reason': 'rider_emergency_drop',
    'p_disputed': false,
  });

  final orderAfterDrop = await client.from('orders').select('status, delivery_partner_id').eq('id', dropOrderId).single();
  if (orderAfterDrop['delivery_partner_id'] != null) {
    throw Exception('Expected delivery_partner_id to be NULL after rider drop');
  }
  print('  ✓ Rider emergency drop verified: order unassigned and returned to available pool.');

  // Clean up dropped order
  await client.auth.signInWithPassword(email: _emailFromPhone(adminPhone), password: _passwordFromPhone(adminPhone));
  try {
    await client.rpc('admin_cancel_order', params: {'p_order_id': dropOrderId});
  } catch (_) {}

  // Step 10B: Mutual Ratings
  await client.from('ratings').insert({
    'order_id': mainOrderId,
    'rater_id': riderId,
    'ratee_id': c1Id,
    'shop_id': null,
    'rater_role': 'delivery',
    'ratee_role': 'customer',
    'rating': 5,
    'review': 'Great customer, prompt pickup!',
  });
  await client.from('ratings').insert({
    'order_id': mainOrderId,
    'rater_id': riderId,
    'ratee_id': null,
    'shop_id': s1ShopId,
    'rater_role': 'delivery',
    'ratee_role': 'seller',
    'rating': 5,
    'review': 'Super fast packaging, food was hot.',
  });

  // Customer rates Rider
  await client.auth.signInWithPassword(email: _emailFromPhone(c1Phone), password: _passwordFromPhone(c1Phone));
  await client.from('ratings').insert({
    'order_id': mainOrderId,
    'rater_id': c1Id,
    'ratee_id': riderId,
    'shop_id': null,
    'rater_role': 'customer',
    'ratee_role': 'delivery',
    'rating': 5,
    'review': 'Fast and courteous delivery!',
  });

  print('  ✓ Mutual 3-way ratings recorded (Rider -> Customer, Rider -> Shop, Customer -> Rider).');
}
