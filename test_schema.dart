import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1];
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1];
  }
  
  final client = SupabaseClient(url, key);
  
  try {
    final data = await client.from('orders').select().limit(1);
    if (data.isNotEmpty) {
      print('Orders table columns: ${data[0].keys.toList()}');
    } else {
      print('Orders table is empty, but query succeeded.');
    }
  } catch (e) {
    print('Error: $e');
  }
}
