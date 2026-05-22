import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  try {
    final apiKey = dotenv.maybeGet('FAST2SMS_API_KEY');
    print('ApiKey from maybeGet: $apiKey');
  } catch (e) {
    print('Error with maybeGet: $e');
  }
}
