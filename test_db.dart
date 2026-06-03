import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  try {
    final orders = await supabase.from('orders').select('id, status, payment_status, grand_total_collected');
    print('Orders: $orders');
    
    final support = await supabase.from('support_tickets').select('id, status');
    print('Support tickets: $support');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
