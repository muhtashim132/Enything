import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

void main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.substring('SUPABASE_URL='.length).trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.substring('SUPABASE_ANON_KEY='.length).trim();
  }

  final supabase = SupabaseClient(url, key);
  const uuid = Uuid();
  print('Connected to Supabase');

  try {
    // 1. Setup Test Users
    final runId = uuid.v4().substring(0, 8);
    final cEmail = 'customer_$runId@eny.com';
    final sEmail = 'seller_$runId@eny.com';
    final rEmail = 'rider_$runId@eny.com';

    print('--> Registering Users');
    final cAuth = await supabase.auth.signUp(email: cEmail, password: 'Password123!', data: {'role': 'customer', 'phone': '+91111111$runId'});
    final sAuth = await supabase.auth.signUp(email: sEmail, password: 'Password123!', data: {'role': 'seller', 'phone': '+91222222$runId'});
    final rAuth = await supabase.auth.signUp(email: rEmail, password: 'Password123!', data: {'role': 'delivery_partner', 'phone': '+91333333$runId'});

    final cId = cAuth.user?.id;
    final sId = sAuth.user?.id;
    final rId = rAuth.user?.id;

    if (cId == null || sId == null || rId == null) {
      throw Exception('Failed to get user IDs: cId=$cId, sId=$sId, rId=$rId');
    }
    print('Users Created. Customer: $cId, Seller: $sId, Rider: $rId');

    // 2. KYC / Profile Setup
    print('--> Setting up Profiles & KYC');
    // Seller creates shop
    try {
      await supabase.from('shops').insert({
        'seller_id': sId,
        'shop_name': 'Test Shop $runId',
        'is_active': true,
        'verification_status': 'verified',
      });
      print('Shop created');
    } catch(e) { print('Shop creation error (expected if RLS strict): $e'); }
    
    // Rider creates profile
    try {
      await supabase.from('delivery_partners').insert({
        'id': rId,
        'is_active': true,
        'verification_status': 'verified',
      });
      print('Rider profile created');
    } catch(e) { print('Rider profile creation error: $e'); }

    // 3. Seller adds product
    print('--> Seller adds products');
    String? pId1;
    String? pId2;
    try {
      // First, get the shop id
      final shopRes = await supabase.from('shops').select('id').eq('seller_id', sId).maybeSingle();
      if (shopRes == null) throw Exception('Shop not found');
      final shopId = shopRes['id'];

      // Sign in as seller to bypass RLS for product creation
      await supabase.auth.signInWithPassword(email: sEmail, password: 'Password123!');

      final prod1 = await supabase.from('products').insert({
        'shop_id': shopId,
        'name': 'Product 1',
        'price': 100,
        'is_active': true
      }).select('id').single();
      pId1 = prod1['id'];

      final prod2 = await supabase.from('products').insert({
        'shop_id': shopId,
        'name': 'Product 2',
        'price': 150,
        'is_active': true
      }).select('id').single();
      pId2 = prod2['id'];
      print('Products added: $pId1, $pId2');
    } catch(e) { print('Product addition error: $e'); }

    // 4. Customer makes an order
    print('--> Customer making order');
    String? orderId;
    try {
      // Login as customer
      await supabase.auth.signInWithPassword(email: cEmail, password: 'Password123!');
      
      final shopRes = await supabase.from('shops').select('id').eq('seller_id', sId).single();
      final shopId = shopRes['id'];

      final orderRes = await supabase.from('orders').insert({
        'customer_id': cId,
        'shop_id': shopId,
        'total_amount': 250,
        'status': 'pending',
        'cart_group_id': uuid.v4(),
        'delivery_charges': 50,
        'enything_commission': 25
      }).select('id').single();
      orderId = orderRes['id'];
      print('Order created: $orderId');
      
      await supabase.from('order_items').insert([
        {'order_id': orderId, 'product_id': pId1, 'quantity': 1, 'price': 100},
        {'order_id': orderId, 'product_id': pId2, 'quantity': 1, 'price': 150},
      ]);
      print('Order items added');
    } catch(e) { print('Order creation error: $e'); }

    // 5. Rider accepts order
    print('--> Rider accepting order');
    try {
      await supabase.auth.signInWithPassword(email: rEmail, password: 'Password123!');
      await supabase.from('orders').update({
        'delivery_partner_id': rId,
        'status': 'accepted_by_rider'
      }).eq('id', orderId!);
      print('Order accepted by rider');
    } catch(e) { print('Rider acceptance error: $e'); }

    // 6. Deliver Order
    print('--> Rider delivering order');
    try {
      await supabase.from('orders').update({
        'status': 'delivered'
      }).eq('id', orderId!);
      print('Order delivered');
    } catch(e) { print('Order delivery error: $e'); }

  } catch (e) {
    print('Fatal Error: $e');
  }
}
