import 'package:supabase/supabase.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  print('--- Starting Edge Cases Test for Refunds, Ratings & Reviews ---');
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('.env file not found!');
    exit(1);
  }
  
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl;
  String? supabaseKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
  }

  if (supabaseUrl == null || supabaseKey == null) {
    print('Missing environment variables. Please check your .env file.');
    exit(1);
  }

  final client = SupabaseClient(
    supabaseUrl, 
    supabaseKey, 
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit)
  );
  print('Connected to Supabase');

  try {
    await runTests(client);
    print('\n✅ ALL EDGE CASE TESTS PASSED');
    exit(0);
  } catch (e, st) {
    print('\n❌ TEST FAILED: $e');
    print(st);
    exit(1);
  }
}

Future<void> runTests(SupabaseClient client) async {
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final customerPhone = '+919888888$rand';
  final sellerPhone = '+919888887$rand';

  final customerId = await authUser(client, customerPhone, 'customer');
  final sellerId = await authUser(client, sellerPhone, 'seller');
  
  final shopRec = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shopRec['id'];
  
  final productId = const Uuid().v4();
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.from('products').insert({
    'id': productId,
    'shop_id': shopId,
    'name': 'Refund Test Item',
    'category': 'food',
    'price': 100.0,
    'is_available': true,
    'total_quantity': 50
  });

  // --- SCENARIO 1: Refund processing on seller rejection ---
  print('\n--- SCENARIO 1: Seller Rejection triggers Refund ---');
  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));
  final orderId1 = const Uuid().v4();
  
  await _createDummyOrder(client, orderId1, shopId, customerId, productId);
  
  // Mark as awaiting_payment -> confirmed -> (seller rejects)
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId1'",
    '--linked'
  ]);

  // Seller rejects
  await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
  await client.rpc('reject_order_seller', params: {
    'p_order_id': orderId1,
    'p_reject_reason': 'out_of_stock',
    'p_message': 'Testing refund'
  });

  // Verify refund status
  final checkOrder1 = await client.from('orders').select('status, refund_status').eq('id', orderId1).single();
  if (checkOrder1['status'] != 'seller_rejected') {
    throw Exception('Order 1 status should be seller_rejected, got ${checkOrder1['status']}');
  }
  if (checkOrder1['refund_status'] != 'processing') {
    throw Exception('Order 1 refund_status should be processing, got ${checkOrder1['refund_status']}');
  }
  print('✅ Refund correctly marked as processing on rejection.');

  // --- SCENARIO 2: Ratings and Reviews Edge Cases ---
  print('\n--- SCENARIO 2: Ratings & Reviews Protections ---');
  await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));
  
  // Try to review a cancelled order (should fail)
  print('Attempting to review cancelled order (Should Fail)...');
  bool reviewFailed = false;
  try {
    await client.from('reviews').insert({
      'shop_id': shopId,
      'user_id': customerId,
      'order_id': orderId1,
      'rating': 5,
      'comment': 'Great cancelled order'
    });
  } catch (e) {
    reviewFailed = true;
    print('✅ Review blocked successfully on non-delivered order.');
  }
  if (!reviewFailed) throw Exception('Review was allowed on a cancelled order!');

  // Create a delivered order
  final orderId2 = const Uuid().v4();
  await _createDummyOrder(client, orderId2, shopId, customerId, productId);
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId2'; " +
    "UPDATE orders SET status = 'preparing' WHERE id = '$orderId2'; " +
    "UPDATE orders SET status = 'ready_for_pickup' WHERE id = '$orderId2'; " +
    "UPDATE orders SET status = 'picked_up' WHERE id = '$orderId2'; " +
    "UPDATE orders SET status = 'delivered' WHERE id = '$orderId2';",
    '--linked'
  ]);

  // Submit valid review
  print('Attempting valid review...');
  await client.from('reviews').insert({
    'shop_id': shopId,
    'user_id': customerId,
    'order_id': orderId2,
    'rating': 5,
    'comment': 'Awesome food'
  });
  print('✅ Valid review accepted.');

  // Try duplicate review (Review Bombing protection)
  print('Attempting duplicate review on same order (Should Fail)...');
  bool duplicateFailed = false;
  try {
    await client.from('reviews').insert({
      'shop_id': shopId,
      'user_id': customerId,
      'order_id': orderId2,
      'rating': 1,
      'comment': 'Spam review'
    });
  } catch (e) {
    duplicateFailed = true;
    print('✅ Duplicate review blocked successfully (Review Bombing Protection).');
  }
  if (!duplicateFailed) throw Exception('Duplicate review was allowed! Review bombing is possible.');

  // Try out of bounds rating
  print('Attempting out of bounds rating (Should Fail)...');
  bool boundsFailed = false;
  try {
    final orderId3 = const Uuid().v4();
    await _createDummyOrder(client, orderId3, shopId, customerId, productId);
    await Process.run('supabase', [
      'db', 'query',
      "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId3'; " +
      "UPDATE orders SET status = 'preparing' WHERE id = '$orderId3'; " +
      "UPDATE orders SET status = 'ready_for_pickup' WHERE id = '$orderId3'; " +
      "UPDATE orders SET status = 'picked_up' WHERE id = '$orderId3'; " +
      "UPDATE orders SET status = 'delivered' WHERE id = '$orderId3';",
      '--linked'
    ]);

    await client.from('reviews').insert({
      'shop_id': shopId,
      'user_id': customerId,
      'order_id': orderId3,
      'rating': 6, // OUT OF BOUNDS
      'review_text': 'Too good'
    });
  } catch (e) {
    boundsFailed = true;
    print('✅ Out of bounds rating blocked successfully.');
  }
  if (!boundsFailed) throw Exception('Out of bounds rating (6) was allowed!');

  // --- SCENARIO 3: PIXEL OVERLOADING (MASSIVE PAYLOADS) ---
  print('\n--- SCENARIO 3: Pixel Overloading Stress Test ---');
  final massiveString = 'A' * (5 * 1024 * 1024); // 5 MB payload
  
  print('Attempting to reject order with 5MB message (Should truncate)...');
  bool rejectionBloatFailed = false;
  try {
    final orderId4 = const Uuid().v4();
    await _createDummyOrder(client, orderId4, shopId, customerId, productId);
    await Process.run('supabase', [
      'db', 'query',
      "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId4';",
      '--linked'
    ]);
    
    await client.auth.signInWithPassword(email: _emailFromPhone(sellerPhone), password: _passwordFromPhone(sellerPhone));
    
    await client.rpc('reject_order_seller', params: {
      'p_order_id': orderId4,
      'p_reject_reason': 'other',
      'p_message': massiveString
    });
    
    final savedOrder = await client.from('orders').select('rejection_message').eq('id', orderId4).single();
    final savedMessage = savedOrder['rejection_message'] as String;
    if (savedMessage.length <= 1000) {
      rejectionBloatFailed = true;
      print('✅ Truncated 5MB rejection message successfully to ${savedMessage.length} chars.');
    }
  } catch (e) {
    print('Caught error for 5MB rejection: $e');
  }
  if (!rejectionBloatFailed) throw Exception('5MB Rejection message was NOT truncated!');

  print('Attempting to review with 5MB comment (Should Fail)...');
  bool reviewBloatFailed = false;
  try {
    await client.auth.signInWithPassword(email: _emailFromPhone(customerPhone), password: _passwordFromPhone(customerPhone));
    
    final orderId5 = const Uuid().v4();
    await _createDummyOrder(client, orderId5, shopId, customerId, productId);
    await Process.run('supabase', [
      'db', 'query',
      "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId5'; " +
      "UPDATE orders SET status = 'preparing' WHERE id = '$orderId5'; " +
      "UPDATE orders SET status = 'ready_for_pickup' WHERE id = '$orderId5'; " +
      "UPDATE orders SET status = 'picked_up' WHERE id = '$orderId5'; " +
      "UPDATE orders SET status = 'delivered' WHERE id = '$orderId5';",
      '--linked'
    ]);
    
    await client.from('reviews').insert({
      'shop_id': shopId,
      'user_id': customerId,
      'order_id': orderId5,
      'rating': 5,
      'comment': massiveString
    });
  } catch (e) {
    print('Caught error for 5MB review: $e');
    if (e.toString().contains('reviews_comment_length') || e.toString().contains('check constraint')) {
      reviewBloatFailed = true;
      print('✅ Blocked 5MB review comment successfully.');
    }
  }
  if (!reviewBloatFailed) throw Exception('5MB Review comment was NOT blocked properly! (See error above)');

  print('\nAll scenarios completed successfully.');
}

Future<void> _createDummyOrder(SupabaseClient client, String orderId, String shopId, String customerId, String productId) async {
  final now = DateTime.now().toUtc();
  final cartGroupId = const Uuid().v4();
  
  final order = {
    'id': orderId,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'cart_group_id': cartGroupId,
    'shop_id': shopId,
    'customer_id': customerId,
    'status': 'awaiting_payment',
    'total_amount': 100.0,
    'delivery_address': 'Test Address',
    'payment_status': 'pending',
    'payment_method': 'upi',
    'grand_total_collected': 135.5,
    'delivery_charges': 15.0,
    'rider_earnings': 15.0,
    'platform_fee': 2.5,
    'estimated_distance_km': 1.0,
    'gst_item_total': 18.0,
    's9_5_gst_amount': 0.0,
    'non_food_gst_amount': 18.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    'enything_commission': 0.0,
    'seller_payout': 100.0,
  };

  final item = {
    'id': const Uuid().v4(),
    'created_at': now.toIso8601String(),
    'order_id': orderId,
    'shop_id': shopId,
    'product_id': productId,
    'product_name': 'Test Item',
    'quantity': 1,
    'price': 100.0,
    'requires_prescription': false,
    'weight_kg': 0.5,
  };

  await client.rpc('place_orders_transaction', params: {
    'p_orders': [order],
    'p_items': [item],
    'p_cart_group_id': cartGroupId,
    'p_coupon_id': null,
    'p_idempotency_key': cartGroupId,
    'p_order_id_to_cancel': null,
  });
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
    } catch (e2) {
      throw Exception('Failed to auth user $phone: $e2');
    }
  }

  if (userId == null) throw Exception('Failed to get user id for $phone');

  final uniquePhone = phone.contains('9888888') 
      ? '+9198888${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}' 
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
  }
  return userId;
}

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
