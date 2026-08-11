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
  final products = await client.from('products').select('*').limit(5);
  print(products[0].keys.toList());
  for (var p in products) {
    print('Product: ${p['name']}');
    if (p.containsKey('variants')) {
       print('Variants: ${p['variants']}');
    }
  }
}
