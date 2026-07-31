import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.rpc('run_sql', params: {'query': "SELECT prosrc FROM pg_proc WHERE proname = 'search_shops_geospatial';"});
  print(res);
}
