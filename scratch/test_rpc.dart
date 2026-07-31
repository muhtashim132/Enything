import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  final res = await client.rpc('get_nearby_shops', params: {
    'p_lat': 34.0,
    'p_lng': 74.0,
    'p_radius_km': 50.0,
    'p_limit': 100,
  });
  print(res.length);
}
