import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  try {
    final response = await http.post(
      Uri.parse('https://www.fast2sms.com/dev/bulkV2'),
      headers: {
        'authorization': 'm3kKbBEze0ldYJ8N6AQaXHuv4DRyrojnVqGC7cghLOFSs9wMx1QNYERH0k3vfziXml7u8hDKtwWpyI1o',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'route': 'q',
        'message': 'Your Enything login OTP is 123456. Do not share this with anyone.',
        'flash': 0,
        'numbers': '7006464241',
      }),
    );
    print('Status code: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
