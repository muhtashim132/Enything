import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  try {
    final res = await client.rpc('update_shop_kyc', params: {
      'p_shop_id': 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
      'p_status': 'approved',
      'p_notes': 'Fixed by bot'
    });
    print('RPC Result: $res');
  } catch (e) {
    print('RPC Error: $e');
  }
}
