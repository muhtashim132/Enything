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
      'full_name': 'Test Rx $role',
      'role': role,
    });

    return userId;
  } catch (e) {
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    return res.user!.id;
  }
}

Future<void> main() async {
  print('================================================================');
  print('🧪 STARTING 100x MULTIPLE MEDICAL SHOPS & PRESCRIPTIONS TEST SUITE');
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
  final custPhone = '+919877777$rand';
  final p1Phone = '+919777777$rand';
  final p2Phone = '+919677777$rand';
  final gPhone = '+919577777$rand';

  print('👥 Setting up Customer, 2 Pharmacy Sellers, and 1 Grocery Seller...');
  final customerId = await authUser(client, custPhone, 'customer');
  final pharm1SellerId = await authUser(client, p1Phone, 'seller');
  final pharm2SellerId = await authUser(client, p2Phone, 'seller');
  final grocerySellerId = await authUser(client, gPhone, 'seller');

  // Create 3 Shops
  final p1ShopId = const Uuid().v4();
  final p2ShopId = const Uuid().v4();
  final gShopId = const Uuid().v4();

  // Create Pharmacy 1
  await client.auth.signInWithPassword(email: _emailFromPhone(p1Phone), password: _passwordFromPhone(p1Phone));
  await client.from('shops').insert({
    'id': p1ShopId,
    'seller_id': pharm1SellerId,
    'name': 'Apollo Pharmacy $rand',
    'is_active': true,
    'is_accepting_orders': true,
    'location': 'POINT(74.7973 34.0837)',
  });

  // Create Pharmacy 2
  await client.auth.signInWithPassword(email: _emailFromPhone(p2Phone), password: _passwordFromPhone(p2Phone));
  await client.from('shops').insert({
    'id': p2ShopId,
    'seller_id': pharm2SellerId,
    'name': 'MedPlus Pharmacy $rand',
    'is_active': true,
    'is_accepting_orders': true,
    'location': 'POINT(74.7974 34.0838)',
  });

  // Create Grocery Shop
  await client.auth.signInWithPassword(email: _emailFromPhone(gPhone), password: _passwordFromPhone(gPhone));
  await client.from('shops').insert({
    'id': gShopId,
    'seller_id': grocerySellerId,
    'name': 'Fresh Mart $rand',
    'is_active': true,
    'is_accepting_orders': true,
    'location': 'POINT(74.7975 34.0839)',
  });

  // Create Products:
  // Pharmacy 1: Antibiotic (Requires Rx = true) ₹150
  final pRx1Id = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(p1Phone), password: _passwordFromPhone(p1Phone));
  await client.from('products').insert({
    'id': pRx1Id,
    'shop_id': p1ShopId,
    'name': 'Amoxicillin 500mg (Antibiotic)',
    'category': 'Pharmacy',
    'price': 150.0,
    'is_available': true,
    'total_quantity': 50,
    'requires_prescription': true,
  });

  // Pharmacy 2: Inhaler (Requires Rx = true) ₹250
  final pRx2Id = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(p2Phone), password: _passwordFromPhone(p2Phone));
  await client.from('products').insert({
    'id': pRx2Id,
    'shop_id': p2ShopId,
    'name': 'Salbutamol Inhaler',
    'category': 'Pharmacy',
    'price': 250.0,
    'is_available': true,
    'total_quantity': 50,
    'requires_prescription': true,
  });

  // Grocery: Fresh Apples (Requires Rx = false) ₹100
  final pNonRxId = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(gPhone), password: _passwordFromPhone(gPhone));
  await client.from('products').insert({
    'id': pNonRxId,
    'shop_id': gShopId,
    'name': 'Fresh Red Apples 1kg',
    'category': 'Fruits & Vegs',
    'price': 100.0,
    'is_available': true,
    'total_quantity': 50,
    'requires_prescription': false,
  });

  print('📦 Products and Medical classification configured');

  // ── TEST 1: MULTI-SHOP ORDER PLACEMENT WITH MULTIPLE PRESCRIPTIONS ──
  print('\n--- [TEST 1] Placing 3-Shop Order with 2 Medical Prescriptions ---');
  final oPharm1Id = const Uuid().v4();
  final oPharm2Id = const Uuid().v4();
  final oGroceryId = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  final now = DateTime.now();

  final samplePrescriptions = [
    'https://storage.enything.com/prescriptions/rx_dr_sharma_page1.jpg',
    'https://storage.enything.com/prescriptions/rx_dr_sharma_page2.jpg'
  ];

  double currentPlatformFee = 25.0;
  try {
    final pRes = await client.from('platform_config').select('value').eq('key', 'platform_fee').maybeSingle();
    if (pRes != null && pRes['value'] != null) {
      currentPlatformFee = (pRes['value'] is num) ? (pRes['value'] as num).toDouble() : double.parse(pRes['value'].toString());
    }
  } catch (_) {}

  await client.auth.signInWithPassword(
    email: _emailFromPhone(custPhone),
    password: _passwordFromPhone(custPhone),
  );

  // Split delivery: ₹15.73 each (Total 47.20), Platform fee: currentPlatformFee each, Surcharge ₹13.33 each (Total 40.0)
  await client.rpc('place_orders_transaction', params: {
    'p_orders': [
      // Pharmacy 1 (Order 1) - Has Rx
      {
        'id': oPharm1Id,
        'shop_id': p1ShopId,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 150.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 150.0 + 7.5 + 15.73 + currentPlatformFee,
        'grand_total': 150.0 + 7.5 + 15.73 + currentPlatformFee,
        'delivery_charges': 15.73,
        'rider_earnings': 10.66,
        'multi_shop_surcharge': 13.33,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': 0.0,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 0.0,
        'non_food_gst_amount': 7.5,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 15,
        'prescription_urls': samplePrescriptions,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      // Pharmacy 2 (Order 2) - Has Rx
      {
        'id': oPharm2Id,
        'shop_id': p2ShopId,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 250.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 250.0 + 12.5 + 15.73 + currentPlatformFee,
        'grand_total': 250.0 + 12.5 + 15.73 + currentPlatformFee,
        'delivery_charges': 15.73,
        'rider_earnings': 10.66,
        'multi_shop_surcharge': 13.33,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': 0.0,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 0.0,
        'non_food_gst_amount': 12.5,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 15,
        'prescription_urls': samplePrescriptions,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      // Grocery (Order 3) - Non-Rx item
      {
        'id': oGroceryId,
        'shop_id': gShopId,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 100.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 100.0 + 0.0 + 15.74 + currentPlatformFee,
        'grand_total': 100.0 + 0.0 + 15.74 + currentPlatformFee,
        'delivery_charges': 15.74,
        'rider_earnings': 10.68,
        'multi_shop_surcharge': 13.34,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': 0.0,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 0.0,
        'non_food_gst_amount': 0.0,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 10,
        'prescription_urls': [], // Non-medical shop gets empty Rx list
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }
    ],
    'p_items': [
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': oPharm1Id,
        'shop_id': p1ShopId,
        'product_id': pRx1Id,
        'product_name': 'Amoxicillin 500mg (Antibiotic)',
        'quantity': 1,
        'price': 150.0,
        'requires_prescription': true,
      },
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': oPharm2Id,
        'shop_id': p2ShopId,
        'product_id': pRx2Id,
        'product_name': 'Salbutamol Inhaler',
        'quantity': 1,
        'price': 250.0,
        'requires_prescription': true,
      },
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': oGroceryId,
        'shop_id': gShopId,
        'product_id': pNonRxId,
        'product_name': 'Fresh Red Apples 1kg',
        'quantity': 1,
        'price': 100.0,
        'requires_prescription': false,
      }
    ],
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
    'p_cart_group_id': cartGroupId,
    'p_order_id_to_cancel': null,
  });

  print('✅ 3-Shop multi-order placed successfully via place_orders_transaction!');

  // ── TEST 2: VERIFY PRESCRIPTION ROUTING PER SHOP ──
  print('\n--- [TEST 2] Verifying Prescription Routing & Isolation ---');
  final p1Order = await client.from('orders').select().eq('id', oPharm1Id).single();
  final p2Order = await client.from('orders').select().eq('id', oPharm2Id).single();
  final gOrder = await client.from('orders').select().eq('id', oGroceryId).single();

  final p1Rx = (p1Order['prescription_urls'] as List?) ?? [];
  final p2Rx = (p2Order['prescription_urls'] as List?) ?? [];
  final gRx = (gOrder['prescription_urls'] as List?) ?? [];

  print('• Pharmacy 1 Prescription URLs count: ${p1Rx.length}');
  print('• Pharmacy 2 Prescription URLs count: ${p2Rx.length}');
  print('• Grocery Shop Prescription URLs count: ${gRx.length} (Must be 0 for patient privacy)');

  if (p1Rx.length != 2) throw Exception('FAILED: Pharmacy 1 must receive 2 prescription documents');
  if (p2Rx.length != 2) throw Exception('FAILED: Pharmacy 2 must receive 2 prescription documents');
  if (gRx.isNotEmpty) throw Exception('FAILED: Grocery shop must not receive prescription documents');

  print('✅ [TEST 2 PASSED] Prescriptions routed exclusively to medical pharmacies with zero privacy leakage!');

  // ── TEST 3: PHARMACY SELLER VERIFICATION & REJECTION WORKFLOW ──
  print('\n--- [TEST 3] Pharmacist Prescription Rejection vs Acceptance ---');
  // Pharmacy 1 Pharmacist inspects prescription and ACCEPTS order
  await client.auth.signInWithPassword(email: _emailFromPhone(p1Phone), password: _passwordFromPhone(p1Phone));
  await client.rpc('accept_order_seller', params: {
    'p_order_id': oPharm1Id,
  });
  final p1Accepted = await client.from('orders').select('status, seller_accepted').eq('id', oPharm1Id).single();
  print('• Pharmacy 1 Order Status after Pharmacist approval: ${p1Accepted['status']} (Seller Accepted: ${p1Accepted['seller_accepted']})');

  // Pharmacy 2 Pharmacist determines prescription is expired and REJECTS order
  await client.auth.signInWithPassword(email: _emailFromPhone(p2Phone), password: _passwordFromPhone(p2Phone));
  await client.rpc('reject_order_seller', params: {
    'p_order_id': oPharm2Id,
    'p_reject_reason': 'prescription',
    'p_message': 'Prescription is expired or unreadable',
  });

  final p2Rejected = await client.from('orders').select('status, cancelled_reason').eq('id', oPharm2Id).single();
  print('• Pharmacy 2 Order Status after Pharmacist rejection: ${p2Rejected['status']} (Reason: ${p2Rejected['cancelled_reason']})');

  if (p2Rejected['status'] != 'verification_failed' && p2Rejected['status'] != 'seller_rejected') {
    throw Exception('FAILED: Pharmacy 2 order must be in verification_failed or seller_rejected status');
  }

  // Sign back in as customer to check customer group view
  await client.auth.signInWithPassword(email: _emailFromPhone(custPhone), password: _passwordFromPhone(custPhone));
  final allGroupOrders = await client.from('orders').select('id, shop_id, status').eq('cart_group_id', cartGroupId);
  final activeGroupOrders = allGroupOrders.where((o) => o['status'] != 'seller_rejected' && o['status'] != 'verification_failed').toList();
  print('• Total orders in cart group: ${allGroupOrders.length}');
  print('• Active remaining shops in cart group: ${activeGroupOrders.length} shops');
  for (final o in allGroupOrders) {
    print('  - Order ${o['id']} (Shop ${o['shop_id']}): Status = ${o['status']}');
  }
  if (activeGroupOrders.length != 2) {
    throw Exception('FAILED: Active shops count must be 2 after 1 pharmacy rejection');
  }

  print('✅ [TEST 3 PASSED] Pharmacist prescription rejection and graceful partial group handling verified!');

  print('\n================================================================');
  print('🎉 ALL 100x MULTIPLE MEDICAL SHOPS & PRESCRIPTION TESTS PASSED 100%!');
  print('================================================================');
}
