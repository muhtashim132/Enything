import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://dummy.supabase.co', // Need to get the actual URL from the project config
    'dummy_key'
  );
}
