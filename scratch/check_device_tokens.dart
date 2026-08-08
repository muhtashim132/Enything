import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  final envFile = File('.env');
  final lines = await envFile.readAsLines();
  String url = '', key = '';
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=').sublist(1).join('=');
    if (line.startsWith('SUPABASE_SERVICE_KEY=')) key = line.split('=').sublist(1).join('=');
    if (line.startsWith('SUPABASE_ANON_KEY=') && key.isEmpty) key = line.split('=').sublist(1).join('=');
  }
  
  final client = SupabaseClient(url, key);
  
  print('\n=== ALL DEVICE TOKENS (recent 20) ===');
  final tokens = await client
      .from('device_tokens')
      .select('user_id, role, platform, updated_at, token')
      .order('updated_at', ascending: false)
      .limit(20);
  
  for (final row in tokens) {
    final token = (row['token'] as String?) ?? '';
    final prefix = token.length > 20 ? token.substring(0, 20) : token;
    print('  user_id: ${row['user_id']}');
    print('  role: ${row['role']}');
    print('  platform: ${row['platform']}');
    print('  updated_at: ${row['updated_at']}');
    print('  token: $prefix...');
    print('  ---');
  }

  print('\n=== DELIVERY PARTNER TOKENS ===');
  final riderTokens = await client
      .from('device_tokens')
      .select('user_id, role, platform, updated_at')
      .or('role.eq.delivery_partner,role.eq.delivery,role.eq.rider');
  
  print('  Found ${riderTokens.length} rider/delivery tokens:');
  for (final row in riderTokens) {
    print('  user_id: ${row['user_id']}, role: ${row['role']}, platform: ${row['platform']}, updated: ${row['updated_at']}');
  }
  
  exit(0);
}
