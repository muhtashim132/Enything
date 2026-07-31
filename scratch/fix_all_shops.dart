import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.from('shops').select('id, name').eq('is_active', false).inFilter('verification_status', ['approved', 'verified']);
  if (res.isNotEmpty) {
    for (final row in res) {
      final shopId = row['id'];
      print("Fixing shop ${row['name']} (id: $shopId)");
      try {
        await client.from('shops').update({'is_active': true}).eq('id', shopId);
        print("Update success!");
      } catch(e) {
        print("Update failed: $e");
      }
    }
  } else {
    print("No inactive verified shops found.");
  }
}
