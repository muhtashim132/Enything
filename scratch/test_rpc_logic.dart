import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  // 1. check shop properties
  final shop = await client.from('shops').select('is_active, is_accepting_orders, location, category').eq('name', 'Kamrans Restaurant').single();
  print('Shop properties: $shop');
  
  // 2. call rpc again
  try {
    final res = await client.rpc('search_shops_geospatial', params: {
      'p_lat': 34.0837,
      'p_lng': 74.7974,
      'p_query': null,
      'p_categories': ['Restaurant'],
      'p_radius_km': 15.0,
      'p_limit': 150,
    });
    print('RPC Result: $res');
  } catch (e) {
    print('RPC Error: $e');
  }
}
