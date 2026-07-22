import 'dart:convert';
import 'dart:io';

void main() async {
  final supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
  final supabaseAnonKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';

  print('Testing login...');
  
  final httpClient = HttpClient();
  final request = await httpClient.postUrl(Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'));
  request.headers.set('apikey', supabaseAnonKey);
  request.headers.set('Content-Type', 'application/json');
  
  final body = jsonEncode({
    "email": "mock919999999997@enything.com",
    "password": "Dummy123"
  });
  
  request.write(body);
  
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  
  print('Status: \${response.statusCode}');
  print('Response: \$responseBody');
  
  exit(0);
}
