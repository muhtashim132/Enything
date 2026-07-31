import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.rpc('get_feed_products', params: {
    'p_shop_ids': ['e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce'],
    'p_limit_per_shop': 5,
    'p_categories': ['Restaurant']
  });
  print(res);
}
