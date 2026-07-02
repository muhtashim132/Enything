

import 'package:supabase/supabase.dart';

void main() async {
  const supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  const supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  
  final client = SupabaseClient(supabaseUrl, supabaseKey);
  
  try {
    print('1. Attempting signInWithPassword...');
    final response = await client.auth.signInWithPassword(email: 'mock919999999996@enything.com', password: 'Dummy123');
    print('Login successful! UID: ${response.user?.id ?? 'null'}');
    
    print('2. Fetching profile...');
    final profile = await client.from('profiles').select().eq('id', response.user!.id).maybeSingle();
    print('Profile: $profile');
  } catch (e) {
    print('Login failed: $e');
  }
}

