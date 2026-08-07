import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://mmdrgcuaetwohflcvzou.supabase.co',
    'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p',
  );

  try {
    final res = await supabase.from('platform_config').select().eq('key', 'max_delivery_radius_km');
    print(res);
  } catch (e) {
    print(e);
  }
}
