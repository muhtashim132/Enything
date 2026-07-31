import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final shop = await client.from('shops').select('is_active, verification_status, name').eq('name', 'Kamrans Restaurant').single();
  print('Shop properties: $shop');
}
