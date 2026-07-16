import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

Future<void> main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl, supabaseKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
  }
  final client = SupabaseClient(supabaseUrl!, supabaseKey!, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  
  final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  final customerPhone = '+918888888${rand}1';
  final sellerPhone = '+918888887$rand';
  
  final customerId = await authUser(client, customerPhone, 'customer');
  final sellerId = await authUser(client, sellerPhone, 'seller');
  final shopRec = await client.from('shops').select('id').eq('seller_id', sellerId).single();
  final shopId = shopRec['id'];

  final productId = const Uuid().v4();
  await client.auth.signInWithPassword(email: '${sellerPhone.replaceAll('+', '')}@enything.com', password: sellerPhone.replaceAll('+', ''));
  await client.from('products').insert({
    'id': productId, 'shop_id': shopId, 'name': 'Stock Test', 'category': 'food', 'price': 100.0, 'is_available': true, 'total_quantity': 5
  });

  // Customer places order
  await client.auth.signInWithPassword(email: '${customerPhone.replaceAll('+', '')}@enything.com', password: customerPhone.replaceAll('+', ''));
  final orderId = const Uuid().v4();
  final cartGroupId = const Uuid().v4();
  
  await client.rpc('place_orders_transaction', params: {
    'p_orders': [{
      'id': orderId, 'shop_id': shopId, 'customer_id': customerId, 'status': 'awaiting_acceptance',
      'total_amount': 100.0, 'payment_status': 'pending', 'payment_method': 'cod', 'grand_total_collected': 100.0,
      'delivery_charges': 0.0, 'platform_fee': 0.0, 'small_cart_fee': 0.0, 'heavy_order_fee': 0.0, 'coupon_discount': 0.0
    }],
    'p_items': [{
      'id': const Uuid().v4(), 'order_id': orderId, 'product_id': productId, 'quantity': 2, 'price': 100.0
    }],
    'p_cart_group_id': cartGroupId,
  });

  var prod = await client.from('products').select('total_quantity, is_available').eq('id', productId).single();
  print('Stock after order: ${prod["total_quantity"]} (Expected 3)');

  // Seller rejects
  await client.auth.signInWithPassword(email: '${sellerPhone.replaceAll('+', '')}@enything.com', password: sellerPhone.replaceAll('+', ''));
  await client.rpc('reject_order_seller', params: {'p_order_id': orderId, 'p_reject_reason': 'out_of_stock', 'p_message': 'Sorry'});

  prod = await client.from('products').select('total_quantity, is_available').eq('id', productId).single();
  print('Stock after reject: ${prod["total_quantity"]} (Expected 5)');
  print('Is Available: ${prod["is_available"]}');
}

Future<String> authUser(SupabaseClient client, String phone, String role) async {
  final email = '${phone.replaceAll('+', '')}@enything.com';
  final password = phone.replaceAll('+', '');
  String? userId;
  try {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    userId = res.user?.id;
  } catch (e) {
    final res2 = await client.auth.signUp(email: email, password: password, data: {'phone': phone});
    userId = res2.user?.id;
  }
  if (userId != null) await client.from('profiles').upsert({'id': userId, 'role': role, 'full_name': 'Test $role', 'phone': phone});
  if (role == 'seller') {
    final hasShop = await client.from('shops').select('id').eq('seller_id', userId as Object).maybeSingle();
    if (hasShop == null) await client.from('shops').insert({'seller_id': userId, 'name': 'Shop $phone', 'category': 'food', 'is_active': true, 'is_accepting_orders': true, 'verification_status': 'verified'});
  }
  return userId!;
}
