import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p');
  
  try {
    final res = await supabase.rpc('execute_sql', params: {'sql': "SELECT * FROM pg_policies WHERE tablename = 'orders'"});
    for (var policy in res as List) {
      print(policy['policyname']);
      print('cmd: ' + policy['cmd']);
      print('roles: ' + policy['roles'].toString());
      print('qual: ' + (policy['qual'] ?? ''));
      print('with_check: ' + (policy['with_check'] ?? ''));
      print('-------------------');
    }
  } catch (e) {
    print('RPC failed: $e');
  }
  exit(0);
}
