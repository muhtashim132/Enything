
import 'package:supabase/supabase.dart';

void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  
  final client = SupabaseClient(supabaseUrl, supabaseKey);
  
  try {
    print('Fetching user by name...');
    final profiles = await client.from('profiles').select().like('full_name', '%Muhtashim%');
    
    if (profiles.isEmpty) {
        print('Could not find profile by name!');
        return;
    }
    
    final userId = profiles.first['id'];
    print('User ID: $userId');

    print('Fetching shop...');
    final shop = await client.from('shops').select().eq('seller_id', userId).maybeSingle();
    print('Shop verification_status: ${shop?['verification_status']}');

    print('Fetching rider...');
    final rider = await client.from('delivery_partners').select().eq('id', userId).maybeSingle();
    print('Rider verification_status: ${rider?['verification_status']}');

    // Automatically update to verified if they are not
    if (shop != null && shop['verification_status'] != 'verified') {
        print('Updating shop to verified...');
        await client.from('shops').update({'verification_status': 'verified'}).eq('seller_id', userId);
    }
    
    if (rider != null && rider['verification_status'] != 'verified') {
        print('Updating rider to verified...');
        await client.from('delivery_partners').update({'verification_status': 'verified'}).eq('id', userId);
    }

    print('Done!');
  } catch (e) {
    print('Error: $e');
  }
}
