import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://mmdrgcuaetwohflcvzou.supabase.co',
    'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p',
  );

  try {
    print("Testing get_nearby_shops from Bangalore...");
    final res = await supabase.rpc('get_nearby_shops', params: {
      'p_lat': 12.97,
      'p_lng': 77.59,
      'p_radius_km': 5000.0,
      'p_limit': 500,
      'p_categories': null
    });

    final shops = res as List;
    print("Found \${shops.length} shops in Bangalore!");
    for (var shop in shops) {
      print("- \${shop['name']}");
    }
    
    print("---");
    print("Testing get_nearby_shops from Bandipora (local)...");
    final res2 = await supabase.rpc('get_nearby_shops', params: {
      'p_lat': 34.42,
      'p_lng': 74.65,
      'p_radius_km': 50.0,
      'p_limit': 500,
      'p_categories': null
    });
    print("Found \${(res2 as List).length} shops locally in Bandipora!");
    for (var shop in res2 as List) {
      print("- \${shop['name']}");
    }
    
  } catch (e) {
    print("Error: $e");
  }
  exit(0);
}
