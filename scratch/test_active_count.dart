
import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
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
  
  final res = await client.rpc('get_trending_keywords_geospatial', params: {
    'p_lat': 34.42,
    'p_lng': 74.64,
    'p_radius_km': 15.0,
    'p_limit': 15,
    'p_disabled_categories': null,
  });

  print('=== GEOSPATIAL TRENDING KEYWORDS FOR BANDIPORA ===');
  print(res);
}




