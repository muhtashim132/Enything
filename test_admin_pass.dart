import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  try {
    final res = await client.from('admin_users').select('id, admin_password');
    print('Admins: $res');
  } catch(e) {
    print(e);
  }
  exit(0);
}
