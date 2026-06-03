import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1];
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1];
  }
  
  final res = await http.get(
    Uri.parse('$url/rest/v1/orders?limit=1'),
    headers: {
      'apikey': key,
      'Authorization': 'Bearer $key',
    },
  );
  
  print('Status: ${res.statusCode}');
  print('Body: ${res.body}');
}
