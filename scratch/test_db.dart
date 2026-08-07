import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://mmdrgcuaetwohflcvzou.supabase.co',
    'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p',
  );

  try {
    final shops = await supabase.from('shops').select('id, name, is_active, is_accepting_orders, location, category');
    print('Total shops: \${shops.length}');
    for (var shop in shops) {
      print("- \${shop['name']} | active: \${shop['is_active']} | accepting: \${shop['is_accepting_orders']} | location: \${shop['location']} | cat: \${shop['category']}");
    }
  } catch (e) {
    print('Error: $e');
  }
}
