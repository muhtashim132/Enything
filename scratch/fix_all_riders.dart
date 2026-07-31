import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final res = await client.from('delivery_partners').select('id').eq('is_active', false).inFilter('verification_status', ['approved', 'verified']);
  if (res.isNotEmpty) {
    for (final row in res) {
      final id = row['id'];
      print("Fixing rider id: $id");
      try {
        await client.from('delivery_partners').update({'is_active': true}).eq('id', id);
        print("Update success!");
      } catch(e) {
        print("Update failed: $e");
      }
    }
  } else {
    print("No inactive verified riders found.");
  }
}
