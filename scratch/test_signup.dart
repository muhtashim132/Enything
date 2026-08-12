import 'dart:io';
import 'package:supabase/supabase.dart';
import 'dart:math';

void main() async {
  final envFile = File('.env').readAsStringSync();
  String url = '', key = '';
  for (var line in envFile.split('\n')) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }

  final supabase = SupabaseClient(url, key);
  
  // Random real number email
  final rnd = Random().nextInt(999999);
  final email = '9876\$rnd@auth.enything.app'; 
  final password = 'TestPassword123!';
  
  try {
    final res = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    print('SignUp User ID: \${res.user?.id}');
    print('SignUp Session: \${res.session != null}');
  } catch (e) {
    print('Error: \$e');
  }
}
