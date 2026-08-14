import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');

  final inactiveVerifiedShops = await client
      .from('shops')
      .select('id, name, seller_id, is_active, is_accepting_orders, verification_status')
      .eq('is_active', false)
      .inFilter('verification_status', ['approved', 'verified']);

  print('Inactive verified shops count: ${inactiveVerifiedShops.length}');
  for (final s in inactiveVerifiedShops) {
    print('Shop: ${s['name']} (ID: ${s['id']}, SellerID: ${s['seller_id']})');
  }

  final inactiveVerifiedRiders = await client
      .from('delivery_partners')
      .select('id, is_active, is_accepting_orders, verification_status')
      .eq('is_active', false)
      .inFilter('verification_status', ['approved', 'verified']);

  print('Inactive verified riders count: ${inactiveVerifiedRiders.length}');
  for (final r in inactiveVerifiedRiders) {
    print('Rider: ${r['id']}');
  }
}
