import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

Future<void> main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl, supabaseKey, serviceRoleKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_SERVICE_ROLE=')) serviceRoleKey = line.split('=')[1].trim();
  }

  final client = SupabaseClient(supabaseUrl!, supabaseKey!);
  final serviceClient = SupabaseClient(supabaseUrl, serviceRoleKey!);
  final authClient = SupabaseClient(supabaseUrl, supabaseKey!, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  
  final email = 'test_customer@auth.enything.app';
  final password = 'password123';
  await authClient.auth.signInWithPassword(email: email, password: password);
  final uid = authClient.auth.currentUser!.id;
  
  await serviceClient.from('profiles').upsert({'id': uid, 'full_name': 'Test Customer', 'phone_number': '+910000000000'});
  
  print('Customer ID: $uid');

  final shop = await client.from('shops').select('id').limit(1).maybeSingle();
  final product = await client.from('products').select('id, name, price, category').eq('shop_id', shop?['id']).limit(1).maybeSingle();

  final orderId = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  final price = (product?['price'] ?? 100.0) as double;

  final order = {
    'id': orderId,
    'customer_id': uid,
    'shop_id': shop?['id'],
    'status': 'awaiting_acceptance',
    'total_amount': price,
    'delivery_charges': 10.0,
    'platform_fee': 20.0,
    'gst_item_total': 0.0,
    'gst_delivery': 0.0,
    'gst_platform': 0.0,
    's9_5_gst_amount': 0.0,
    'non_food_gst_amount': 14.95,
    'grand_total_collected': price + 15.0 + 14.95,
  };
  
  final item = {
    'id': const Uuid().v4(),
    'order_id': orderId,
    'product_id': product?['id'],
    'quantity': 1,
    'price': price,
  };

  print('Calling place_orders_transaction using customer authClient...');
  try {
    await authClient.rpc('place_orders_transaction', params: {
      'p_orders': [order],
      'p_items': [item],
      'p_cart_group_id': cartGroupId,
      'p_coupon_id': null,
      'p_idempotency_key': cartGroupId,
    });
    print('RPC succeeded!');
  } catch (e) {
    print('RPC failed: $e');
  }

  print('Querying just created order with anonKey (like TrackOrderPage)...');
  try {
    final response = await authClient.from('orders').select('*').eq('id', orderId).single();
    print('Order found by customer: ${response['id']}');
  } catch(e) {
    print('Customer fetch failed: $e');
  }
}
