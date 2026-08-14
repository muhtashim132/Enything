import 'package:supabase/supabase.dart';

void main() async {
  const url = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tZHJnY3VhZXR3b2hmbGN2em91Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzk5NzUxMCwiZXhwIjoyMDkzNTczNTEwfQ.rzX0mupREQDLgTgZLISBocfdtWH-IPVE0bsz7oc_Z8c';

  final client = SupabaseClient(url, serviceKey);

  final res = await client
      .from('shops')
      .select('id, name, seller_id, is_active, is_accepting_orders, verification_status')
      .inFilter('verification_status', ['approved', 'verified']);

  print('Total approved/verified shops: ${res.length}');
  for (final s in res) {
    print('Shop: ${s['name']} (ID: ${s['id']}) -> is_active: ${s['is_active']}, is_accepting_orders: ${s['is_accepting_orders']}');
    if (s['is_active'] == false) {
      print('--> Activating shop ${s['name']}...');
      await client.from('shops').update({'is_active': true}).eq('id', s['id']);
      print('--> Done.');
    }
  }

  // Also check delivery partners
  final riders = await client
      .from('delivery_partners')
      .select('id, is_active, is_accepting_orders, verification_status')
      .inFilter('verification_status', ['approved', 'verified']);

  print('Total approved/verified riders: ${riders.length}');
  for (final r in riders) {
    if (r['is_active'] == false) {
      print('--> Activating rider ${r['id']}...');
      await client.from('delivery_partners').update({'is_active': true}).eq('id', r['id']);
      print('--> Done.');
    }
  }
}
