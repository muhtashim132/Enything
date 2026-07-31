import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  final res = await client.from('shops').select('*').eq('is_active', false);
  for (final row in res) {
    print("INACTIVE Shop ${row['name']}: v_status=${row['verification_status']}");
  }
}
