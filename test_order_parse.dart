import 'package:supabase/supabase.dart';
import 'dart:io';
import 'lib/models/order_model.dart';

Future<void> main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl, serviceRoleKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL='))
      supabaseUrl = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_SERVICE_ROLE='))
      serviceRoleKey = line.split('=')[1].trim();
  }

  final client = SupabaseClient(supabaseUrl!, serviceRoleKey!);

  try {
    final response = await client
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false)
        .limit(10);
    print('Fetched ${response.length} orders');
    for (var o in response) {
      try {
        final model = OrderModel.fromMap(o);
        print('Successfully parsed order ${model.id}');
      } catch (e, st) {
        print('Error parsing order ${o['id']}: $e');
        print(st);
      }
    }
  } catch (e) {
    print('DB Query Failed: $e');
  }
  exit(0);
}
