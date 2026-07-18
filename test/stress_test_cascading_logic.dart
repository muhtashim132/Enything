import 'dart:io';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final envFile = File('.env');
  final lines = await envFile.readAsLines();
  final env = <String, String>{};
  for (var line in lines) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      var value = parts.sublist(1).join('=').trim();
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (value.startsWith("'") && value.endsWith("'")) {
        value = value.substring(1, value.length - 1);
      }
      env[key] = value;
    }
  }
  
  final supabaseUrl = env['SUPABASE_URL'];
  final supabaseKey = env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseKey == null) {
    print('Missing Supabase credentials in .env file.');
    exit(1);
  }

  final client = SupabaseClient(supabaseUrl, supabaseKey);
  
  print('--- Starting Stress Test for Extreme Edge Cases & Pixel Overloading ---');

  // Hardcoded IDs for test setup (these can be random for isolation)
  final customerId = 'c0000000-0000-0000-0000-000000000000';
  final shopId = 's0000000-0000-0000-0000-000000000000';
  final productId = 'p0000000-0000-0000-0000-000000000000';
  final orderId = 'a1111111-1111-1111-1111-111111111111';

  // 1. Setup base data
  print('Setting up base data...');
  try {
    await client.from('users').upsert({'id': customerId, 'email': 'stress@test.com', 'role': 'customer', 'name': 'Stress Test User', 'phone': '+19999999999'});
    await client.from('shops').upsert({'id': shopId, 'owner_id': customerId, 'name': 'Stress Test Shop', 'status': 'active', 'category': 'food'});
    await client.from('products').upsert({'id': productId, 'shop_id': shopId, 'name': 'Stress Test Item', 'price': 100.0, 'total_quantity': 50, 'status': 'active'});
  } catch (e) {
    print('Setup failed: $e');
  }

  // Generate 5MB String
  print('Generating massive string payload (Pixel Overloading)...');
  final massiveString = 'A' * (5 * 1024 * 1024); // 5 Million characters

  // --- Test 1: Massive Rejection Message ---
  print('\n--- SCENARIO 1: Massive Rejection Message ---');
  await _createDummyOrder(client, orderId, shopId, customerId, productId, 'awaiting_acceptance');

  try {
    await client.rpc('reject_order_seller', params: {
      'p_order_id': orderId,
      'p_reject_reason': 'other',
      'p_message': massiveString
    });
    throw Exception('Failed: DB accepted a 5MB rejection message!');
  } catch (e) {
    if (e.toString().contains('orders_rejection_msg_length')) {
      print('✅ Success: DB successfully blocked the 5MB rejection message via constraint.');
    } else {
      throw Exception('Failed with unexpected error: $e');
    }
  }

  // --- Test 2: Massive Review Comment ---
  print('\n--- SCENARIO 2: Massive Review Comment ---');
  
  // Transition order to delivered for valid review status
  await Process.run('supabase', [
    'db', 'query',
    "UPDATE orders SET status = 'confirmed', payment_status = 'captured' WHERE id = '$orderId'; " +
    "UPDATE orders SET status = 'preparing' WHERE id = '$orderId'; " +
    "UPDATE orders SET status = 'ready_for_pickup' WHERE id = '$orderId'; " +
    "UPDATE orders SET status = 'picked_up' WHERE id = '$orderId'; " +
    "UPDATE orders SET status = 'delivered' WHERE id = '$orderId';",
    '--linked'
  ]);

  try {
    await client.from('reviews').insert({
      'shop_id': shopId,
      'user_id': customerId,
      'order_id': orderId,
      'rating': 5,
      'comment': massiveString
    });
    throw Exception('Failed: DB accepted a 5MB review comment!');
  } catch (e) {
    if (e.toString().contains('reviews_comment_length')) {
      print('✅ Success: DB successfully blocked the 5MB review comment via constraint.');
    } else {
      throw Exception('Failed with unexpected error: $e');
    }
  }

  // Clean up
  print('\nCleaning up...');
  await client.from('orders').delete().eq('id', orderId);
  
  print('\n✅ ALL STRESS TESTS PASSED');
  exit(0);
}

Future<void> _createDummyOrder(SupabaseClient client, String orderId, String shopId, String customerId, String productId, String status) async {
  await client.from('orders').delete().eq('id', orderId);
  await client.from('orders').insert({
    'id': orderId,
    'customer_id': customerId,
    'shop_id': shopId,
    'status': status,
    'payment_status': 'captured',
    'total_amount': 100.0,
    'delivery_charges': 0.0,
    'platform_fee': 5.0,
    'gst_platform': 0.9,
    'grand_total_collected': 105.9,
    'payment_method': 'upi',
    'delivery_distance_km': 1.0, 
    'gst_item_total': 0.0
  });

  await client.from('order_items').insert({
    'order_id': orderId,
    'product_id': productId,
    'quantity': 1,
    'unit_price': 100.0,
    'total_price': 100.0,
  });
}
