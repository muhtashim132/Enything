import 'package:supabase/supabase.dart';

void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  final client = SupabaseClient(supabaseUrl, supabaseKey);

  try {
    final res = await client.auth.signUp(
      email: 'testcustomer123@enything.app',
      password: 'password123',
    );
    
    if (res.user != null) {
      print('Signed up as ${res.user!.id}');
      
      try {
        final updateRes = await client.from('customers').upsert({
          'id': res.user!.id,
          'landmark': 'Test Landmark'
        }).select();
        print('Update success: $updateRes');
      } catch (e) {
        print('Update error: $e');
      }
    } else {
      print('Signup failed');
    }
  } catch (e) {
    print('Auth error: $e');
  }
}
