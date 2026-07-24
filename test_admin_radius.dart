import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  print('Loading .env...');
  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    print('Failed to load environment variables.');
    return;
  }

  print('Initializing Supabase...');
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  final client = Supabase.instance.client;

  print('\n--- Edge Case Test 1: Fetching Nearby Shops with massive radius ---');
  try {
    final res = await client.rpc('get_nearby_shops', params: {
      'p_lat': 12.9716, // Bangalore coordinates
      'p_lng': 77.5946,
      'p_radius_km': 1000.0, // Should be clamped to 15.0 or admin config
      'p_limit': 10,
    });
    print('✅ get_nearby_shops executed successfully. Row count: ${(res as List).length}');
  } catch (e) {
    print('❌ get_nearby_shops failed: $e');
  }

  print('\n--- Edge Case Test 2: Checkout with Spoofed Distance ---');
  try {
    // We send an order with estimated_distance_km = 90.0, which exceeds max admin radius of 15.0
    await client.rpc('place_orders_transaction', params: {
      'p_orders': [{
        'shop_id': '00000000-0000-0000-0000-000000000000',
        'subtotal': 100,
        'tax': 5,
        'delivery_charges': 50,
        'small_cart_fee': 0,
        'total_amount': 155,
        'payment_method': 'cash',
        'address_snapshot': '{"address": "Test"}',
        'customer_notes': '',
        'estimated_distance_km': 90.0 // SPOTTED! Should be rejected
      }],
      'p_items': [],
      'p_cart_group_id': '00000000-0000-0000-0000-000000000001',
    });
    print('❌ place_orders_transaction SUCCEEDED. Security check failed!');
  } catch (e) {
    print('✅ place_orders_transaction REJECTED (Expected). Error: $e');
  }
}
