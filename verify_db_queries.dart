import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }

  final supabase = SupabaseClient(url, key);
  print('Connected to Supabase');

  final libDir = Directory('lib');
  final dartFiles = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  final queryPattern = RegExp(r"\.from\('([^']+)'\)\.select\('([^']+)'\)");
  final queryPatternNoSelectArgs = RegExp(r"\.from\('([^']+)'\)\.select\(\)");
  
  Set<String> queriesToTest = {};

  for (var file in dartFiles) {
    final content = file.readAsStringSync();
    
    final matches1 = queryPattern.allMatches(content);
    for (var m in matches1) {
      final table = m.group(1)!;
      final cols = m.group(2)!;
      queriesToTest.add('$table|$cols');
    }
    
    final matches2 = queryPatternNoSelectArgs.allMatches(content);
    for (var m in matches2) {
      final table = m.group(1)!;
      queriesToTest.add('$table|*');
    }
  }

  print('Found ${queriesToTest.length} unique queries to test.');

  int errors = 0;
  for (var q in queriesToTest) {
    final parts = q.split('|');
    final table = parts[0];
    final cols = parts[1];
    
    try {
      if (cols == '*') {
        await supabase.from(table).select().limit(1);
      } else {
        await supabase.from(table).select(cols).limit(1);
      }
    } on PostgrestException catch (e) {
      // 42P01 is undefined_table, 42703 is undefined_column, 42501 is insufficient_privilege
      if (e.code == '42P01' || e.code == '42703' || e.code == '42501' || e.message.contains('permission denied')) {
        print('ERROR in table $table with cols "$cols": ${e.message} (Code: ${e.code})');
        errors++;
      } else {
         // Other postgrest exceptions might be RLS related which is fine.
      }
    } catch (e) {
      print('Unknown error for $table: $e');
    }
  }
  
  print('Audit complete. Found $errors errors.');
  exit(errors > 0 ? 1 : 0);
}
