import 'package:supabase_flutter/supabase_flutter.dart';
void main() {
  final supabase = SupabaseClient('https://xyz.supabase.co', 'abc');
  var q = supabase.from('products').select();
  q = q.overlaps('special_tags', ['#Men', '#Unisex']);
  print('Overlaps method exists and compiles.');
}
