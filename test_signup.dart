
import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';
  
  final client = SupabaseClient(supabaseUrl, supabaseKey);
  
  try {
    print('1. Attempting signUp...');
    final response = await client.auth.signUp(
        email: 'mock919999999996@enything.com', 
        password: 'Dummy123',
        data: { 'full_name': 'Razorpay Reviewer', 'role': 'customer', 'phone': '+919999999996' }
    );
    print('Signup successful! UID: ' + (response.user?.id ?? 'null'));
    
    print('2. Forcing profile update to mock_id...');
    // We can't change auth.users.id, so we must just use the new UID as the real mock ID!
  } catch (e) {
    print('Signup failed: ' + e.toString());
  }
}

