import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  for (final file in files) {
    if (file.path.contains('time_utils.dart')) continue;

    String content = file.readAsStringSync();
    bool modified = false;

    // We want to apply .toIST() where DateFormat is used, or replace .toLocal() with .toIST() 
    // when related to DateFormat.
    // However, the safest and most comprehensive way is to replace `.toLocal()` with `.toIST()`
    // everywhere, AND for `DateFormat('...').format(x)` where `x` is `order.createdAt` etc.
    
    // First, let's replace all `.toLocal()` with `.toIST()`
    if (content.contains('.toLocal()')) {
      content = content.replaceAll('.toLocal()', '.toIST()');
      modified = true;
    }

    // Next, check for DateFormat('...').format(order.createdAt) etc that lack .toIST()
    final regex = RegExp(r"DateFormat\([^)]+\)\.format\(([^)]+)\)");
    content = content.replaceAllMapped(regex, (match) {
      final expr = match.group(1)!;
      if (!expr.contains('.toIST()') && !expr.contains('.toLocal()')) {
        modified = true;
        return match.group(0)!.replaceFirst('($expr)', '($expr.toIST())');
      }
      return match.group(0)!;
    });

    if (modified) {
      // Add import if not present
      if (!content.contains('time_utils.dart')) {
        // Find the last import
        final lastImportIdx = content.lastIndexOf(RegExp(r"^import\s+.*?;", multiLine: true));
        if (lastImportIdx != -1) {
          final endOfImport = content.indexOf('\n', lastImportIdx) + 1;
          final levels = file.path.split(Platform.pathSeparator).length - 2;
          final prefix = List.filled(levels, '../').join('');
          content = content.substring(0, endOfImport) + "import '${prefix}utils/time_utils.dart';\n" + content.substring(endOfImport);
        }
      }
      file.writeAsStringSync(content);
      print('Updated: ${file.path}');
    }
  }
}
