import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://mmdrgcuaetwohflcvzou.supabase.co',
    'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p',
  );

  try {
    print("=== TEST 1: Admin sets max radius to 15 ===");
    // Simulate Admin Panel saving 15
    await supabase.from('platform_config').upsert({
      'key': 'max_delivery_radius_km',
      'value': 15.0
    });
    print("Radius set to 15 in database.");

    // Customer in Bangalore (trying to search with a large radius)
    final res1 = await supabase.rpc('get_nearby_shops', params: {
      'p_lat': 12.97,
      'p_lng': 77.59,
      'p_radius_km': 5000.0, // Dart client asks for 5000
      'p_limit': 500,
      'p_categories': null
    });
    final shops1 = res1 as List;
    print("Result: Found \${shops1.length} shops in Bangalore.");

    print("\\n=== TEST 2: Admin sets max radius to 5000 ===");
    // Simulate Admin Panel saving 5000
    await supabase.from('platform_config').upsert({
      'key': 'max_delivery_radius_km',
      'value': 5000.0
    });
    print("Radius set to 5000 in database.");

    // Customer in Bangalore (trying to search with a large radius again)
    final res2 = await supabase.rpc('get_nearby_shops', params: {
      'p_lat': 12.97,
      'p_lng': 77.59,
      'p_radius_km': 5000.0, // Dart client asks for 5000
      'p_limit': 500,
      'p_categories': null
    });
    final shops2 = res2 as List;
    print("Result: Found \${shops2.length} shops in Bangalore.");
    if (shops2.isNotEmpty) {
      print("First shop found: \${shops2[0]['name']}");
    }

  } catch (e) {
    print("Error: $e");
  }
}
