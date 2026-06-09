import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // Read .env manually since dotenv.load might need flutter
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }

  final supabase = SupabaseClient(url, key);
  print('Connected to Supabase');

  try {
    // 1. Sign up customer
    print('Signing up customer...');
    final custAuth = await supabase.auth.signUp(
      email: 'customer@enything.app',
      password: 'EnythingCustomer123!',
      data: {'phone': '+911000000001', 'role': 'customer'}
    );
    final custId = custAuth.user!.id;
    print('Customer ID: \');

  } catch (e) {
    print('Error: \');
  }
}

