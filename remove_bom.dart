import 'dart:io';

void main() {
  for (var f in ['20260707000001_pre_release_fixes.sql', '20260708000001_product_gst_engine.sql']) {
    var file = File('d:\\Enything\\supabase\\migrations\\' + f);
    if (!file.existsSync()) continue;
    var bytes = file.readAsBytesSync();
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      file.writeAsBytesSync(bytes.sublist(3));
      print('Removed BOM from \$f');
    }
  }
}
