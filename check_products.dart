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
  final products = await client.from('products').select('name, is_deleted, is_available');
  for (var product in products) {
    if (['pizza', 'chadarya', 'Calvin Klein jeans'].contains(product['name'])) {
        print('Product: ${product['name']} | deleted: ${product['is_deleted']} | available: ${product['is_available']}');
    }
  }
}
