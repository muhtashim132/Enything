import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final products = await client.from('products').select('*').eq('shop_id', 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce');
  print('Found ${products.length} products');
  for (final p in products) {
    print('Testing ${p['name']}...');
    try {
      final name = p['name'] ?? '';
      final price = (p['price'] ?? 0.0).toDouble();
      
      // Let's test the specific risky parts
      List<String> imageList = [];
      if (p['images'] != null) {
        if (p['images'] is List) {
          imageList = List<String>.from(p['images']);
        } else if (p['images'] is Map) {
          imageList = List<String>.from(p['images']['urls'] ?? []);
        }
      }
      
      final specialTags = List<String>.from(p['special_tags'] ?? []);
      
      final rating = (p['rating'] ?? 0.0).toDouble();
      
      final variants = (p['variants'] as List<dynamic>?)
              ?.map((v) => v as Map<String, dynamic>)
              .toList() ??
          [];
          
      print('SUCCESS for ${p['name']}');
    } catch (e, st) {
      print('CRASH on ${p['name']}: $e\n$st');
    }
  }
}
