import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  // 1. Get Kamrans Restaurant shop_id
  final shopRes = await client.from('shops').select('id, name').eq('name', 'Kamrans Restaurant');
  if (shopRes.isEmpty) {
    print('Shop not found');
    return;
  }
  
  final shopId = shopRes[0]['id'];
  print('Shop ID: $shopId');
  
  // 2. Fetch products for this shop
  final products = await client.from('products').select('*').eq('shop_id', shopId);
  print('Found ${products.length} products');
  for (final p in products.take(5)) {
    print('Product: ${p['name']}, is_available: ${p['is_available']}, category: ${p['category']}');
  }
}
