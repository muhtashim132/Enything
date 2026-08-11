import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl, anonKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) {
      supabaseUrl = line.split('=')[1].trim();
    }
    if (line.startsWith('SUPABASE_ANON_KEY=')) {
      anonKey = line.split('=')[1].trim();
    }
  }

  final client = SupabaseClient(supabaseUrl!, anonKey!);
  final shops = await client.from('shops').select('id, name, is_active');
  for (var shop in shops) {
    if (['Kamrans Restaurant', 'Raashids shop', 'Albaik'].contains(shop['name'])) {
        print('Shop: ${shop['name']} is_active=${shop['is_active']}');
    }
  }
}
