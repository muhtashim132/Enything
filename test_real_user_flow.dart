import 'package:supabase/supabase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> main() async {
  // Load env to get Supabase URL and ANON KEY
  dotenv.testLoad(fileInput: File('.env').readAsStringSync());
  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('🧪 TESTING REAL USER FLOW (NO MAGIC BYPASS) 🧪');

  final String email = 'real_user_test_${DateTime.now().millisecondsSinceEpoch}@enything.com';
  final String password = 'Password123!';

  try {
    // 1. Sign up a completely normal user (NOT a magic reviewer)
    print('\n1. Signing up normal user: $email');
    final authResponse = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    final userId = authResponse.user!.id;
    print('✅ Sign up successful. UUID: $userId');

    // 2. Create profile & customer row (simulating app flow)
    print('\n2. Creating profile and customer row');
    await supabase.from('profiles').insert({
      'id': userId,
      'full_name': 'Real Test User',
      'role': 'customer',
      'phone': '+918888888888', // Normal phone, NOT ending in 9996
    });
    await supabase.from('customers').insert({
      'id': userId,
      'location': 'POINT(74.6366 34.4225)', // Valid WKT for geography
    });
    print('✅ Profile & Customer created');

    // 3. Find a real shop and product
    print('\n3. Finding a shop and product to order');
    final productData = await supabase
        .from('products')
        .select('id, price, shop_id')
        .limit(1)
        .single();
    final shopId = productData['shop_id'];
    final productId = productData['id'];
    final price = productData['price'];
    print('✅ Found Product: $productId from Shop: $shopId at Price: $price');

    // 4. Create an order directly (simulating checkout)
    print('\n4. Creating order (status: awaiting_acceptance)');
    final orderId = '00000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toString().substring(0, 12)}';
    
    // We need to bypass RLS to insert the order since we don't have all the complex checkout logic here,
    // actually wait, authenticated users CAN insert their own orders. Let's try.
    await supabase.from('orders').insert({
      'id': orderId,
      'shop_id': shopId,
      'customer_id': userId,
      'status': 'awaiting_acceptance',
      'total_amount': price,
      'delivery_charges': 10,
      'platform_fee': 5,
      'tax_amount': 0,
      'grand_total': price + 15,
      'delivery_address': '{"label": "Home", "address": "Test"}',
      'delivery_location': 'POINT(74.6366 34.4225)',
      'seller_accepted': false,
      'partner_accepted': false,
    });
    print('✅ Order $orderId created successfully');

    // 5. Wait 5 seconds (The magic timer is 2 seconds)
    print('\n5. Waiting 5 seconds to ensure NO auto-acceptance occurs...');
    await Future.delayed(const Duration(seconds: 5));

    // 6. Check order status
    print('\n6. Checking order status...');
    final orderCheck = await supabase
        .from('orders')
        .select('status, seller_accepted_at')
        .eq('id', orderId)
        .single();
    
    print('Resulting Status: ${orderCheck['status']}');
    
    if (orderCheck['status'] == 'awaiting_acceptance') {
      print('✅ SUCCESS: Order remained awaiting_acceptance. No logic changed for real users!');
    } else {
      print('❌ ERROR: Order status changed to ${orderCheck['status']}. Real user logic was compromised!');
    }

    // 7. Test RPC directly to ensure it rejects normal users
    print('\n7. Testing magic_reviewer_auto_accept RPC directly (should fail for normal user)');
    try {
      await supabase.rpc('magic_reviewer_auto_accept', params: {
        'p_order_ids': [orderId]
      });
      print('❌ ERROR: RPC succeeded for normal user! This is a severe security flaw.');
    } catch (e) {
      print('✅ SUCCESS: RPC rejected normal user as expected. Error: $e');
    }

  } catch (e) {
    print('\n❌ TEST FAILED with exception: $e');
  } finally {
    exit(0);
  }
}
