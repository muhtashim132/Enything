import 'dart:convert';
import 'dart:io';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final envFile = File('.env');
  String supabaseUrl = '';
  String supabaseAnonKey = '';
  for (var line in await envFile.readAsLines()) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseAnonKey = line.split('=')[1].trim();
  }

  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  try {
    final res = await client.auth.signUp(email: 'mock919999999996@enything.com', password: 'Dummy123');
    print('Signed up: ${res.user?.id}');
  } catch (e, st) {
    print('Error: $e');
    print(st);
  }
}
