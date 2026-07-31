import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  final res = await client.from('shops').select('*').limit(5);
  for (final row in res) {
    print("Shop ${row['name']}: is_active=${row['is_active']}, is_accepting_orders=${row['is_accepting_orders']}, verification_status=${row['verification_status']}");
  }
}
