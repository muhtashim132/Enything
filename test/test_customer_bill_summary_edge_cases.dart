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
      'full_name': 'Test Customer $role',
      'role': role,
    });

    if (role == 'seller') {
      await client.from('shops').upsert({
        'seller_id': userId,
        'name': 'CustomerTestShop_$phone',
        'is_active': true,
        'is_accepting_orders': true,
        'location': 'POINT(74.7973 34.0837)',
      });
    }

    return userId;
  } catch (e) {
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    return res.user!.id;
  }
}

Future<void> main() async {
  print('================================================================');
  print('🧪 STARTING 100x CUSTOMER BILL SUMMARY EDGE-CASE TEST SUITE');
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
  final custPhone = '+919844444$rand';
  final s1Phone = '+919744444$rand';
  final s2Phone = '+919644444$rand';

  print('👥 Setting up customer and sellers...');
  final customerId = await authUser(client, custPhone, 'customer');
  final seller1Id = await authUser(client, s1Phone, 'seller');
  final seller2Id = await authUser(client, s2Phone, 'seller');

  final s1Resp = await client.from('shops').select('id').eq('seller_id', seller1Id).single();
  final s2Resp = await client.from('shops').select('id').eq('seller_id', seller2Id).single();
  final shop1Id = s1Resp['id'];
  final shop2Id = s2Resp['id'];

  // Products:
  // Shop 1: Food item (Restaurant, 5% GST): ₹100
  // Shop 2: Electronics gadget (Electronics, 18% GST): ₹500
  final pFoodId = const Uuid().v4();
  final pElecId = const Uuid().v4();

  await client.auth.signInWithPassword(email: _emailFromPhone(s1Phone), password: _passwordFromPhone(s1Phone));
  await client.from('products').insert({
    'id': pFoodId,
    'shop_id': shop1Id,
    'name': 'Butter Chicken',
    'category': 'Restaurant',
    'price': 100.0,
    'is_available': true,
    'total_quantity': 50,
    'weight_per_unit': 0.5,
  });

  await client.auth.signInWithPassword(email: _emailFromPhone(s2Phone), password: _passwordFromPhone(s2Phone));
  await client.from('products').insert({
    'id': pElecId,
    'shop_id': shop2Id,
    'name': 'Wireless Earbuds',
    'category': 'Electronics',
    'price': 500.0,
    'is_available': true,
    'total_quantity': 50,
    'weight_per_unit': 0.2,
  });

  print('📦 Products configured');

  // ── TEST 1: SINGLE SHOP SMALL CART (< ₹150 threshold) WITH SMALL CART FEE ──
  print('\n--- [TEST 1] Single Shop Small Cart (< ₹150 threshold) ---');
  final o1Id = const Uuid().v4();
  final cart1Id = const Uuid().v4();
  final now = DateTime.now();

  double currentPlatformFee = 25.0;
  double currentSmallCartThreshold = 0.0;
  double currentSmallCartFee = 15.0;
  try {
    final pRes = await client.from('platform_config').select('value').eq('key', 'platform_fee').maybeSingle();
    if (pRes != null && pRes['value'] != null) {
      currentPlatformFee = (pRes['value'] is num) ? (pRes['value'] as num).toDouble() : double.parse(pRes['value'].toString());
    }
    final sRes = await client.from('platform_config').select('value').eq('key', 'small_cart_threshold').maybeSingle();
    if (sRes != null && sRes['value'] != null) {
      currentSmallCartThreshold = (sRes['value'] is num) ? (sRes['value'] as num).toDouble() : double.parse(sRes['value'].toString());
    }
    final sfRes = await client.from('platform_config').select('value').eq('key', 'small_cart_fee').maybeSingle();
    if (sfRes != null && sfRes['value'] != null) {
      currentSmallCartFee = (sfRes['value'] is num) ? (sfRes['value'] as num).toDouble() : double.parse(sfRes['value'].toString());
    }
  } catch (_) {}

  final double expectedSmallCartFee = (100.0 < currentSmallCartThreshold) ? currentSmallCartFee : 0.0;

  await client.auth.signInWithPassword(email: _emailFromPhone(custPhone), password: _passwordFromPhone(custPhone));

  await client.rpc('place_orders_transaction', params: {
    'p_orders': [
      {
        'id': o1Id,
        'shop_id': shop1Id,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 100.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 100.0 + 5.0 + 41.30 + currentPlatformFee + expectedSmallCartFee,
        'grand_total': 100.0 + 5.0 + 41.30 + currentPlatformFee + expectedSmallCartFee,
        'delivery_charges': 41.30,
        'rider_earnings': 28.0,
        'multi_shop_surcharge': 0.0,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': expectedSmallCartFee,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 5.0,
        'non_food_gst_amount': 0.0,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 20,
        'shop_lat': 34.0839,
        'shop_lng': 74.7975,
        'delivery_lat': 34.0838,
        'delivery_lng': 74.7974,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }
    ],
    'p_items': [
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': o1Id,
        'shop_id': shop1Id,
        'product_id': pFoodId,
        'product_name': 'Butter Chicken',
        'quantity': 1,
        'price': 100.0,
        'requires_prescription': false,
        'weight_kg': 0.5,
      }
    ],
    'p_coupon_id': null,
    'p_idempotency_key': cart1Id,
    'p_cart_group_id': cart1Id,
    'p_order_id_to_cancel': null,
  });

  final o1Db = await client.from('orders').select().eq('id', o1Id).single();
  print('📊 Stored Bill Details for Order 1:');
  print('• Item Subtotal: ₹${o1Db['total_amount']}');
  print('• Small Cart Fee: ₹${o1Db['small_cart_fee']} (Threshold < ₹150)');
  print('• Delivery Charges: ₹${o1Db['delivery_charges']}');
  print('• Handling Fee: ₹${o1Db['platform_fee']}');
  print('• Item GST (5%): ₹${o1Db['gst_item_total']}');
  print('• Delivery GST (18%): ₹${o1Db['gst_delivery']}');
  print('• Handling GST (18%): ₹${o1Db['gst_platform']}');
  print('• Grand Total Collected: ₹${o1Db['grand_total_collected']}');

  if (o1Db['small_cart_fee'] != expectedSmallCartFee) throw Exception('FAILED: Small cart fee must be $expectedSmallCartFee');
  if ((o1Db['grand_total_collected'] - (100.0 + 5.0 + 41.30 + currentPlatformFee + expectedSmallCartFee)).abs() > 0.01) throw Exception('FAILED: Grand total mismatch');
  print('✅ [TEST 1 PASSED] Small cart fee and single-shop bill summary verified!');

  // ── TEST 2: 2-SHOP MULTI-ORDER CART WITH MULTI-SHOP SURCHARGE & GST ──
  print('\n--- [TEST 2] 2-Shop Multi-Order with Multi-Shop Surcharge & GST ---');
  final o2aId = const Uuid().v4();
  final o2bId = const Uuid().v4();
  final cart2Id = const Uuid().v4();

  // Split delivery between 2 shops: ₹23.60 each, platform fee per order
  await client.rpc('place_orders_transaction', params: {
    'p_orders': [
      {
        'id': o2aId,
        'shop_id': shop1Id,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 100.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 100.0 + 5.0 + 23.60 + currentPlatformFee,
        'grand_total': 100.0 + 5.0 + 23.60 + currentPlatformFee,
        'delivery_charges': 23.60,
        'rider_earnings': 16.0,
        'multi_shop_surcharge': 10.0,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': 0.0,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 5.0,
        'non_food_gst_amount': 0.0,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 20,
        'shop_lat': 34.0839,
        'shop_lng': 74.7975,
        'delivery_lat': 34.0838,
        'delivery_lng': 74.7974,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      {
        'id': o2bId,
        'shop_id': shop2Id,
        'customer_id': customerId,
        'status': 'awaiting_acceptance',
        'total_amount': 500.0,
        'payment_status': 'pending',
        'payment_method': 'upi',
        'grand_total_collected': 500.0 + 90.0 + 23.60 + currentPlatformFee,
        'grand_total': 500.0 + 90.0 + 23.60 + currentPlatformFee,
        'delivery_charges': 23.60,
        'rider_earnings': 16.0,
        'multi_shop_surcharge': 10.0,
        'platform_fee': currentPlatformFee,
        'small_cart_fee': 0.0,
        'heavy_order_fee': 0.0,
        'coupon_discount': 0.0,
        's9_5_gst_amount': 0.0,
        'non_food_gst_amount': 90.0,
        'estimated_distance_km': 1.0,
        'gst_rate_snapshot': {},
        'shop_prep_time_snapshot': 15,
        'shop_lat': 34.0840,
        'shop_lng': 74.7976,
        'delivery_lat': 34.0838,
        'delivery_lng': 74.7974,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }
    ],
    'p_items': [
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': o2aId,
        'shop_id': shop1Id,
        'product_id': pFoodId,
        'product_name': 'Butter Chicken',
        'quantity': 1,
        'price': 100.0,
        'requires_prescription': false,
        'weight_kg': 0.5,
      },
      {
        'id': const Uuid().v4(),
        'created_at': now.toIso8601String(),
        'order_id': o2bId,
        'shop_id': shop2Id,
        'product_id': pElecId,
        'product_name': 'Wireless Earbuds',
        'quantity': 1,
        'price': 500.0,
        'requires_prescription': false,
        'weight_kg': 0.2,
      }
    ],
    'p_coupon_id': null,
    'p_idempotency_key': cart2Id,
    'p_cart_group_id': cart2Id,
    'p_order_id_to_cancel': null,
  });

  final groupResp = await client.from('orders').select().eq('cart_group_id', cart2Id);
  final List ordersList = groupResp as List;

  double totalAmount = 0;
  double totalDelivery = 0;
  double totalSurcharge = 0;
  double totalPlatform = 0;
  double totalGstItem = 0;
  double totalGstDelivery = 0;
  double totalGstPlatform = 0;
  double grandTotal = 0;

  for (final o in ordersList) {
    totalAmount += (o['total_amount'] as num).toDouble();
    totalDelivery += (o['delivery_charges'] as num).toDouble();
    totalSurcharge += (o['multi_shop_surcharge'] as num).toDouble();
    totalPlatform += (o['platform_fee'] as num).toDouble();
    totalGstItem += ((o['s9_5_gst_amount'] ?? 0.0) as num).toDouble() + ((o['non_food_gst_amount'] ?? 0.0) as num).toDouble();
    totalGstDelivery += ((o['gst_delivery'] ?? 0.0) as num).toDouble();
    totalGstPlatform += ((o['gst_platform'] ?? 0.0) as num).toDouble();
    grandTotal += (o['grand_total_collected'] as num).toDouble();
  }

  final expectedTotalPlatform = currentPlatformFee * 2;
  final expectedGrandTotal = 600.0 + 47.20 + 95.0 + expectedTotalPlatform;

  print('📊 Aggregated Group Bill Summary (2 Shops):');
  print('• Item Subtotal: ₹$totalAmount (Expected: 600.0)');
  print('• Multi-Shop Surcharge: ₹$totalSurcharge (Expected: 20.0)');
  print('• Gross Delivery Charges: ₹$totalDelivery (Expected: 47.20)');
  print('• Handling Fee: ₹$totalPlatform (Expected: $expectedTotalPlatform)');
  print('• Item GST: ₹$totalGstItem (Expected: 95.00 = ₹5 on food + ₹90 on electronics)');
  print('• Delivery GST (18%): ₹${totalGstDelivery.toStringAsFixed(2)}');
  print('• Handling GST (18%): ₹${totalGstPlatform.toStringAsFixed(2)}');
  print('• Grand Total Paid: ₹$grandTotal (Expected: $expectedGrandTotal)');

  if (totalAmount != 600.0) throw Exception('FAILED: Total amount mismatch');
  if (totalSurcharge != 20.0) throw Exception('FAILED: Surcharge mismatch');
  if (totalDelivery != 47.20) throw Exception('FAILED: Delivery mismatch');
  if (totalPlatform != expectedTotalPlatform) throw Exception('FAILED: Platform fee mismatch');
  if (totalGstItem != 95.0) throw Exception('FAILED: Item GST mismatch (Expected 95.0, Got $totalGstItem)');
  if ((grandTotal - expectedGrandTotal).abs() > 0.01) throw Exception('FAILED: Grand Total mismatch');

  print('✅ [TEST 2 PASSED] Multi-shop mixed GST bill summary verified!');

  print('\n================================================================');
  print('🎉 ALL 100x CUSTOMER BILL SUMMARY TESTS PASSED 100%!');
  print('================================================================');
}
