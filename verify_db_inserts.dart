import 'dart:io';
import 'dart:convert';
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

  final insertPattern = RegExp(r"\.from\('([^']+)'\)\.insert\(([^)]+)\)");
  final updatePattern = RegExp(r"\.from\('([^']+)'\)\.update\(([^)]+)\)");
  
  Set<String> insertsToTest = {};

  for (var file in dartFiles) {
    final content = file.readAsStringSync();
    
    // We will just try to find the keys used in inserts/updates. 
    // This is a naive regex but might find basic Map literals like {'col1': val, 'col2': val}
    final mapKeysPattern = RegExp(r"'([^']+)'\s*:");
    
    final matches1 = insertPattern.allMatches(content);
    for (var m in matches1) {
      final table = m.group(1)!;
      final args = m.group(2)!;
      final keys = mapKeysPattern.allMatches(args).map((k) => k.group(1)).join(',');
      if (keys.isNotEmpty) {
        insertsToTest.add('$table|$keys');
      }
    }
    
    final matches2 = updatePattern.allMatches(content);
    for (var m in matches2) {
      final table = m.group(1)!;
      final args = m.group(2)!;
      final keys = mapKeysPattern.allMatches(args).map((k) => k.group(1)).join(',');
      if (keys.isNotEmpty) {
        insertsToTest.add('$table|$keys');
      }
    }
  }

  print('Found ${insertsToTest.length} unique insert/updates to test.');

  int errors = 0;
  for (var q in insertsToTest) {
    final parts = q.split('|');
    final table = parts[0];
    final cols = parts[1].split(',');
    
    // We can test if these columns exist by doing a select of these columns!
    // Since we just want to know if the column exists, select is perfect.
    try {
      await supabase.from(table).select(cols.join(',')).limit(1);
    } on PostgrestException catch (e) {
      if (e.code == '42703') { // undefined_column
        print('MISSING COLUMN in $table: ${e.message}');
        errors++;
      } else if (e.code == '42P01') { // undefined_table
        print('MISSING TABLE: $table');
        errors++;
      }
    } catch (e) {
      // ignore other errors
    }
  }
  
  print('Audit complete. Found $errors missing columns/tables in inserts/updates.');
  exit(errors > 0 ? 1 : 0);
}
