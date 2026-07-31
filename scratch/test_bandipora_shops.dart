import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.from('shops').select('id, name, address, is_active');
  for (final s in res) {
    final addr = s['address'] as String?;
    if (addr != null && addr.toLowerCase().contains('bandipora')) {
      print('Bandipora Shop: ${s['name']} (ID: ${s['id']})');
    }
  }
}
