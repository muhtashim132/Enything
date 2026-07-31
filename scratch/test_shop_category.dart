import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.from('shops').select('id, name, category, location, is_active, is_accepting_orders').eq('name', 'Kamrans Restaurant');
  print(res);
}
