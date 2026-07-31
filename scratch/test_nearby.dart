import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  final res = await client.rpc('get_nearby_shops', params: {
    'p_lat': 34.0837,
    'p_lng': 74.7974,
    'p_radius_km': 5000.0,
    'p_limit': 100,
  });
  final shops = (res as List);
  print("Found ${shops.length} shops from get_nearby_shops");
  for (final s in shops.take(5)) {
    print("${s['name']} - open: ${s['open_time']} close: ${s['close_time']} isActive: ${s['is_active']} isAccepting: ${s['is_accepting_orders']}");
  }
}
