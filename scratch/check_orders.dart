import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final envLines = File('.env').readAsLinesSync();
  String? supabaseUrl;
  String? supabaseKey;
  
  for (var line in envLines) {
    if (line.startsWith('SUPABASE_URL=')) supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) supabaseKey = line.split('=')[1].trim();
  }
  
  final supabase = SupabaseClient(supabaseUrl!, supabaseKey!);
  
  final res = await supabase
      .from('orders')
      .select('id, cart_group_id, shop_id, status, total_amount, platform_fee, multi_shop_surcharge, razorpay_payment_id')
      .order('created_at', ascending: false)
      .limit(10);
      
  print("LATEST ORDERS:");
  for (var r in res) {
    print(r);
  }
}
