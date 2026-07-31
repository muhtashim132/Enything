import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.rpc('search_products_geospatial', params: {
    'p_lat': 34.0837,
    'p_lng': 74.7974,
    'p_radius_km': 15.0,
    'p_categories': ['Restaurant']
  });
  print('Geospatial products: ${(res as List).length}');
}
