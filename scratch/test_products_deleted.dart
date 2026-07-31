import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final products = await client.from('products').select('name, is_deleted').eq('shop_id', 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce');
  for (final p in products) {
    print('Product: ${p['name']}, is_deleted: ${p['is_deleted']}');
  }
}
