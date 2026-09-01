import 'dart:convert';
import 'dart:io';

void main() async {
  const supabaseUrl = 'https://hvtujaatwhyxielrlztr.supabase.co';
  const supabaseAnonKey = 'sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs';

  print('Testing login...');

  final httpClient = HttpClient();
  final request = await httpClient
      .postUrl(Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'));
  request.headers.set('apikey', supabaseAnonKey);
  request.headers.set('Content-Type', 'application/json');

  final body = jsonEncode(
      {"email": "mock919999999997@enything.com", "password": "Dummy123"});

  request.write(body);

  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();

  print('Status: ${response.statusCode}');
  print('Response: $responseBody');

  exit(0);
}
