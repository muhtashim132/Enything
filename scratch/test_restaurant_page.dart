import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  final productsData = await client
      .from('products')
      .select()
      .eq('shop_id', 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce')
      .eq('is_available', true)
      .limit(2000);
      
  print('Products: ${(productsData as List).length}');
}
