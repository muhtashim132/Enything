import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.from('shops').select('seller_id').eq('name', 'Kamrans Restaurant').single();
  final sellerId = res['seller_id'];
  
  final shops = await client.from('shops').select('id, name').eq('seller_id', sellerId);
  for (final s in shops) {
    print('Seller owns: ${s['name']} (${s['id']})');
  }
}
