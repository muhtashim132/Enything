import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final envFile = File('.env').readAsStringSync();
  String url = '', key = '';
  for (var line in envFile.split('\n')) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }

  final supabase = SupabaseClient(url, key);
  final email = 'mock919999999996@enything.com'; 
  final password = 'Dummy123';
  
  try {
    final res = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    print('User ID: \${res.user?.id}');
    print('Session: \${res.session != null}');
  } catch (e) {
    print('Error: \$e');
  }
}
