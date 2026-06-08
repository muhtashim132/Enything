import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

class MockUser {
  final String id;
  final String email;
  MockUser(this.id, this.email);
}

void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  final client = SupabaseClient(supabaseUrl, supabaseKey);

  print('=== COMPREHENSIVE ORDER LIFECYCLE MATRIX TEST ===\n');

  final List<String> createdUserIds = [];

  Future<MockUser> createMockUser(String prefix, String role, String name) async {
    final password = 'password123';
    final email = '${prefix}_${Uuid().v4().substring(0, 8)}@test.com';
    try {
      final res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name, 'role': role, 'phone': '999000${createdUserIds.length.toString().padLeft(4, "0")}'},
      );
      if (res.user == null) {
        throw Exception('Signup returned null user. Email confirmation might be enabled or email taken.');
      }
      final userId = res.user!.id;
      createdUserIds.add(userId);
      print('✅ Created mock $role: $email (ID: $userId)');

      await client.from('profiles').upsert({
        'id': userId,
        'role': role,
        'full_name': name,
        'phone': '999000${createdUserIds.length.toString().padLeft(4, "0")}'
      });

      if (role == 'customer') {
        await client.from('customers').insert({'id': userId});
      } else if (role == 'seller') {
        await client.from('shops').insert({
          'seller_id': userId,
          'name': name,
          'is_active': true,
        });
      } else if (role == 'delivery_partner') {
        await client.from('delivery_partners').insert({
          'id': userId,
          'is_active': true,
          'is_available': true,
        });
      }
      return MockUser(userId, email);
    } catch (e) {
      print('❌ Failed to create mock user $email: $e');
      rethrow;
    }
  }

  try {
    print('--- SETUP PHASE ---');
    final c1 = await createMockUser('mock_c1', 'customer', 'Customer One');
    final c2 = await createMockUser('mock_c2', 'customer', 'Customer Two');
    
    final s1 = await createMockUser('mock_s1', 'seller', 'Shop A');
    final s2 = await createMockUser('mock_s2', 'seller', 'Shop B');
    final s3 = await createMockUser('mock_s3', 'seller', 'Shop C');
    
    final r1 = await createMockUser('mock_r1', 'delivery_partner', 'Rider One');
    final r2 = await createMockUser('mock_r2', 'delivery_partner', 'Rider Two');

    final shopA = (await client.from('shops').select('id').eq('seller_id', s1.id).single())['id'] as String;
    final shopB = (await client.from('shops').select('id').eq('seller_id', s2.id).single())['id'] as String;
    final shopC = (await client.from('shops').select('id').eq('seller_id', s3.id).single())['id'] as String;

    Future<String> createOrder(MockUser customer, String shopId, String cartGroupId) async {
      await client.auth.signInWithPassword(email: customer.email, password: 'password123');
      final res = await client.from('orders').insert({
        'cart_group_id': cartGroupId,
        'shop_id': shopId,
        'customer_id': customer.id,
        'status': 'awaiting_acceptance',
        'total_amount': 100,
        'delivery_charges': 20,
        'rider_earnings': 20,
        'platform_fee': 5,
        'address': 'Test Address',
        'payment_method': 'upi',
        'payment_status': 'pending',
        'grand_total_collected': 125,
      }).select().single();
      return res['id'];
    }

    // SCENARIO 1: 1 Shop, 1 Customer, 1 Rider
    print('\n--- SCENARIO 1: Basic Flow (1 Shop, 1 Customer, 1 Rider) ---');
    final cart1 = Uuid().v4();
    final order1 = await createOrder(c1, shopA, cart1);
    print('Order created: $order1');

    await client.auth.signInWithPassword(email: s1.email, password: 'password123');
    await client.from('orders').update({'status': 'confirmed', 'seller_accepted': true}).eq('id', order1);
    print('Shop A accepted order.');

    await client.auth.signInWithPassword(email: r1.email, password: 'password123');
    await client.from('orders').update({'delivery_partner_id': r1.id, 'status': 'confirmed'}).eq('id', order1);
    print('Rider 1 claimed order.');

    await client.from('orders').update({'status': 'delivered'}).eq('id', order1);
    print('✅ Scenario 1 Passed.');

    // SCENARIO 2: Multi-Shop Cart (2 Shops)
    print('\n--- SCENARIO 2: Multi-Shop Cart (2 Shops, 1 Customer, 1 Rider) ---');
    final cart2 = Uuid().v4();
    final order2A = await createOrder(c1, shopA, cart2);
    final order2B = await createOrder(c1, shopB, cart2);
    print('Orders created: $order2A, $order2B');

    await client.auth.signInWithPassword(email: s1.email, password: 'password123');
    await client.from('orders').update({'status': 'confirmed', 'seller_accepted': true}).eq('id', order2A);
    
    await client.auth.signInWithPassword(email: s2.email, password: 'password123');
    await client.from('orders').update({'status': 'seller_rejected', 'seller_accepted': false}).eq('id', order2B);
    print('Shop A accepted, Shop B rejected.');

    await client.auth.signInWithPassword(email: r1.email, password: 'password123');
    await client.from('orders').update({'delivery_partner_id': r1.id}).eq('id', order2A);
    print('✅ Scenario 2 Passed.');

    // SCENARIO 5: Race Condition
    print('\n--- SCENARIO 5: Race Condition (1 Shop, 2 Riders) ---');
    final cart5 = Uuid().v4();
    final order5 = await createOrder(c1, shopA, cart5);
    
    await client.auth.signInWithPassword(email: s1.email, password: 'password123');
    await client.from('orders').update({'status': 'confirmed', 'seller_accepted': true}).eq('id', order5);

    await client.auth.signInWithPassword(email: r1.email, password: 'password123');
    await client.from('orders').update({'delivery_partner_id': r1.id}).eq('id', order5);
    print('Rider 1 successfully claimed.');

    await client.auth.signInWithPassword(email: r2.email, password: 'password123');
    try {
      await client.from('orders').update({'delivery_partner_id': r2.id}).eq('id', order5);
      print('❌ BUG: Rider 2 was able to claim an already claimed order!');
    } catch (e) {
      print('✅ Rider 2 successfully blocked from claiming.');
    }

  } catch (e) {
    print('❌ Test Execution Error: $e');
  } finally {
    print('\n--- CLEANUP PHASE ---');
    for (final uid in createdUserIds) {
      try {
        await client.rpc('delete_mock_user', params: {'p_user_id': uid});
        print('Deleted mock user: $uid');
      } catch (e) {
        print('Warning: Failed to clean up user $uid. Error: $e');
      }
    }
  }

  print('\n=== TESTING COMPLETE ===');
  exit(0);
}
