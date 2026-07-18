import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  print('--- Starting Core Entities Pixel Overloading Stress Test ---');
  
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('.env file not found!');
    exit(1);
  }
  
  final lines = await envFile.readAsLines();
  final env = <String, String>{};
  for (var line in lines) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      var value = parts.sublist(1).join('=').trim();
      if (value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
      if (value.startsWith("'") && value.endsWith("'")) value = value.substring(1, value.length - 1);
      env[key] = value;
    }
  }

  final supabaseUrl = env['SUPABASE_URL'];
  final supabaseKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseKey == null) {
    print('Missing environment variables. Please check your .env file.');
    exit(1);
  }

  // We are using the ANON/SERVICE key without auth. We will use `Process.run('supabase', ['db', 'query'...])`
  // for the tests to bypass RLS easily, since we only want to test Postgres Check Constraints.
  
  // We are using a 500KB payload. This is small enough to bypass the HTTP 413 Request Entity Too Large 
  // API gateway limit, but large enough to prove our Postgres CHECK constraints successfully block it natively.
  final massiveString = 'A' * (500 * 1024); // 500 KB Payload
  final id = const Uuid().v4();
  
  int passed = 0;
  int failed = 0;

  Future<void> testConstraint(String scenario, String query, String expectedError) async {
    print('\n[Testing] $scenario');
    // Save query to a temp file to avoid hitting shell argument length limits with 5MB strings
    final tempSql = File('temp_query.sql');
    await tempSql.writeAsString(query);
    
    try {
      final res = await Process.run('supabase', ['db', 'query', '-f', 'temp_query.sql', '--linked']);
      if (res.exitCode == 0) {
        print('❌ FAILED: Query succeeded but it should have been blocked!');
        failed++;
      } else {
        if (res.stderr.toString().contains(expectedError) || res.stdout.toString().contains(expectedError)) {
          print('✅ PASSED: Blocked correctly ($expectedError)');
          passed++;
        } else {
          print('⚠️ UNEXPECTED ERROR: ${res.stderr}\n${res.stdout}');
          failed++;
        }
      }
    } finally {
      if (tempSql.existsSync()) tempSql.deleteSync();
    }
  }

  // 1. Profiles Name
  await testConstraint(
    'Profiles Name Constraint (255)',
    "INSERT INTO profiles (id, name, full_name, phone) VALUES ('$id', '$massiveString', 'Test', '+19999999999');",
    'check constraint'
  );

  // 2. Shops Description
  final shopId = const Uuid().v4();
  await testConstraint(
    'Shops Description Constraint (2000)',
    "INSERT INTO shops (id, owner_id, name, description, status) VALUES ('$shopId', '$id', 'Test', '$massiveString', 'active');",
    'check constraint'
  );

  // 3. Products Image URL
  final productId = const Uuid().v4();
  await testConstraint(
    'Products Image URL Constraint (2000)',
    "INSERT INTO products (id, shop_id, name, image_url, price) VALUES ('$productId', '$shopId', 'Test', '$massiveString', 10);",
    'check constraint'
  );

  // 4. Orders Delivery Notes
  final orderId = const Uuid().v4();
  await testConstraint(
    'Orders Delivery Notes Constraint (1000)',
    "INSERT INTO orders (id, shop_id, customer_id, delivery_notes, total_amount, status) VALUES ('$orderId', '$shopId', '$id', '$massiveString', 100, 'pending');",
    'check constraint'
  );

  print('\n----------------------------------------');
  print('TESTS COMPLETED: $passed Passed, $failed Failed');
  if (failed > 0) exit(1);
  exit(0);
}
