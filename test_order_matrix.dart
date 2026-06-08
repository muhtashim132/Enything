import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

// Test matrix executor for Enything Orders
void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  final client = SupabaseClient(supabaseUrl, supabaseKey);

  print('=== STARTING ORDER MATRIX INTEGRATION TESTS ===\n');

  try {
    // We will attempt to insert a mock order to test constraints
    final testCartGroupId = Uuid().v4();
    final testShopId = '11111111-1111-1111-1111-111111111111';
    final testCustomerId = '22222222-2222-2222-2222-222222222222';

    print('[Test 1.A] Attempting to insert standard single-shop order...');
    
    // Using dummy UUIDs for testing constraints
    final orderResponse = await client.from('orders').insert({
      'cart_group_id': testCartGroupId,
      'shop_id': testShopId,
      'customer_id': testCustomerId,
      'status': 'awaiting_acceptance',
      'acceptance_deadline': DateTime.now().toUtc().add(Duration(minutes: 2)).toIso8601String(),
      'total_amount': 150.0,
      'delivery_charges': 25.0,
      'rider_earnings': 20.0,
      'platform_fee': 5.0,
      'address': 'Test Address',
      'payment_method': 'upi',
      'payment_status': 'pending',
      'grand_total_collected': 180.0,
      'estimated_distance_km': 3.5,
    }).select().maybeSingle();

    if (orderResponse != null) {
      print("✅ SUCCESS: Inserted Order ID: \${orderResponse['id']}");
      
      // Cleanup
      await client.from('orders').delete().eq('id', orderResponse['id']);
      print('✅ Cleaned up test order.');
    } else {
      print('❌ Failed to insert order (No response)');
    }

  } on PostgrestException catch (e) {
    print("❌ PostgreSQL/RLS Error: ${e.message}");
    print("Details: ${e.details}");
    print("Hint: ${e.hint}");
  } catch (e) {
    print("❌ Unexpected Error: $e");
  }

  print('\n=== TESTING COMPLETE ===');
  exit(0);
}
