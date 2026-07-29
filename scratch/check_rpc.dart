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
  final res = await client.rpc('get_nearby_shops', params: {
    'p_lat': 34.0,
    'p_lng': 74.0,
    'p_radius_km': 1000,
    'p_limit': 10
  });
  print(res);
  exit(0);
}
