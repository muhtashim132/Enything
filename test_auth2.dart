import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() async {
  await dotenv.load(fileName: ".env");
  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);

  try {
    print('Testing login...');
    final res = await client.auth.signInWithPassword(email: 'mock919999999997@enything.com', password: 'Dummy123');
    print('Login success! User: ${res.user?.id}');
  } catch (e) {
    print('Login failed: $e');
    try {
      print('Trying signup...');
      final res2 = await client.auth.signUp(email: 'mock919999999997@enything.com', password: 'Dummy123', data: {'phone': '+919999999997'});
      print('Signup success! User: ${res2.user?.id}');
    } catch (e2) {
      print('Signup failed: $e2');
    }
  }

  exit(0);
}
