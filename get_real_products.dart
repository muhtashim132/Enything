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
  final shops = await client.from('shops').select('id, name');
  Map<String, String> shopMap = {};
  for (var shop in shops) {
    shopMap[shop['id']] = shop['name'];
  }
  
  final products = await client.from('products').select('id, name, shop_id, is_available');
  for (var product in products) {
    String shopName = shopMap[product['shop_id']] ?? 'Unknown';
    if (!shopName.toLowerCase().contains('test') && !shopName.toLowerCase().contains('medical')) {
        print('Real Shop Product: ${product['name']} in Shop: $shopName');
    }
  }
}
