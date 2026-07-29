import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final envLines = File('.env').readAsLinesSync();
  String? url;
  String? key;
  for (var line in envLines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1];
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1];
  }
  
  final client = SupabaseClient(url!, key!);
  final res = await client.from('delivery_partners').select('id, is_active, verification_status').limit(1);
  print(res);
  exit(0);
}
