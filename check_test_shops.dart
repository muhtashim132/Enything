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
  
  final res = await client.from('shops').select('id, name, is_active');
  
  print('--- All Remaining Shops ---');
  for (var shop in res) {
    print('ID: ${shop['id']} | Name: ${shop['name']} | Active: ${shop['is_active']}');
  }
  
  final products = await client.from('products').select('id, name, shop_id, is_available');
  print('\n--- All Remaining Products ---');
  for (var product in products) {
     if (product['name'].toString().toLowerCase().contains('test')) {
         print('Test Product found: ${product['name']} (Shop ID: ${product['shop_id']})');
     }
  }
  print('Total products: ${products.length}');
}
