import 'dart:io';

void main() {
  final file = File('.env');
  if (file.existsSync()) {
    print(file.readAsStringSync());
  } else {
    print('.env not found');
  }
}
