import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  // Remote project anon key
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';

  final client = SupabaseClient(supabaseUrl, supabaseKey);

  // We are not logged in, so we test if anon can see anything.
  // Wait, to test user policies, we need to login as a user.
  // Let's just try logging in as a mock user if we knew their email/pass,
  // OR we can just try to fetch all orders without auth to see if RLS is fully blocking.

  try {
    final response = await client.from('orders').select().limit(5);
    print('Orders fetched anonymously: \$response');
  } catch (e) {
    print('Error fetching anonymously: \$e');
  }
}
void main() async { final client = SupabaseClient('https://mmdrgcuaetwohflcvzou.supabase.co', 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p'); final res = await client.from('platform_config').select(); print(res); }
