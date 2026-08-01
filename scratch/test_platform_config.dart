import 'dart:io';
import 'package:supabase/supabase.dart';
import '../lib/config/supabase_config.dart';

void main() async {
  final client = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
  
  try {
    // Attempt to read
    final data = await client.from('platform_config').select('key, value').eq('key', 'disabled_categories');
    print("Read: $data");
    
    // Auth bypass isn't available easily without a token, but maybe we can just check the schema via RPC if it exists, or via REST.
  } catch (e) {
    print("Error: $e");
  }
  exit(0);
}
