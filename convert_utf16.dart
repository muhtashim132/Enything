import 'dart:io';
import 'dart:convert';

void main() {
  var dir = Directory('supabase/migrations');
  var files = dir.listSync().whereType<File>().toList();
  for (var file in files) {
    if (file.path.endsWith('.sql')) {
      var bytes = file.readAsBytesSync();
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        // UTF-16LE BOM
        print('Converting ${file.path}');
        // decode utf-16le
        var stringBuffer = StringBuffer();
        for (int i = 2; i < bytes.length; i += 2) {
          int charCode = bytes[i] | (bytes[i+1] << 8);
          stringBuffer.writeCharCode(charCode);
        }
        file.writeAsStringSync(stringBuffer.toString(), encoding: utf8);
      }
    }
  }
}
