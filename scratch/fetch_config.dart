import 'package:supabase/supabase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() async {
  dotenv.testLoad(fileInput: File('.env').readAsStringSync());
  final client = SupabaseClient(
    dotenv.env['SUPABASE_URL']!,
    dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  final res = await client.from('platform_config').select('*').eq('key', 'platform_fee');
  print('PLATFORM_FEE: $res');
  exit(0);
}
