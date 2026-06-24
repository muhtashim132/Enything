
import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('https://www.fast2sms.com/dev/bulkV2');
  var client = HttpClient();
  var request = await client.postUrl(url);
  request.headers.set('authorization', 'm3kKbBEze0ldYJ8N6AQaXHuv4DRyrojnVqGC7cghLOFSs9wMx1QNYERH0k3vfziXml7u8hDKtwWpyI1o');
  request.headers.set('Content-Type', 'application/json');
  request.add(utf8.encode(json.encode({
    'route': 'otp',
    'variables_values': '123456',
    'numbers': '9999999999'
  })));
  var response = await request.close();
  var responseBody = await response.transform(utf8.decoder).join();
  print(responseBody);
}

