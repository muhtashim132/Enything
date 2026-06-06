import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  try {
    final res = await supabase.from('orders').select('id, status, delivery_partner_id').eq('status', 'out_for_delivery');
    print('Orders out for delivery:');
    print(res);
  } catch (e) {
    print('Query failed: $e');
  }
  exit(0);
}
