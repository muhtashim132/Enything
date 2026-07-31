import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  final res = await client.from('shops').select('*');
  for (final row in res) {
    if (row['open_time'] != null) {
      print("Shop ${row['name']}: open=${row['open_time']}, close=${row['close_time']}, is_active=${row['is_active']}, is_accepting_orders=${row['is_accepting_orders']}, v_status=${row['verification_status']}");
    }
  }
}
