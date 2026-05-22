import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );
  
  final supabase = Supabase.instance.client;
  
  try {
    print('Testing upsert to phone_otps');
    await supabase.from('phone_otps').upsert({
      'phone': '+917006464241',
      'otp': '123456',
      'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
    }, onConflict: 'phone');
    print('Upsert successful');
  } catch (e) {
    print('Error with upsert: $e');
  }
}
