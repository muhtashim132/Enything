import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() async {
  await dotenv.load(fileName: ".env");
  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);

  try {
    print('Attempting to login with new password...');
    final res1 = await client.auth.signInWithPassword(email: 'mock919999999997@enything.com', password: 'Dummy123');
    print('Success! ID: ${res1.user?.id}');
  } catch (e) {
    print('Failed with new password: $e');
    try {
      print('Attempting to login with legacy password...');
      // compute new password from _passwordFromPhone 
      // wait, I don't have the logic here, but let's test if signIn fails.
    } catch (e2) {
      print('Failed legacy: $e2');
    }
  }
  exit(0);
}
