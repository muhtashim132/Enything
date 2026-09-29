import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/models/rbac/role_model.dart';
import '../lib/repositories/roles_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('test roles and permissions loading', () async {
    SharedPreferences.setMockInitialValues({});
    final envFile = File('.env');
    final lines = envFile.readAsLinesSync();
    String? supabaseUrl, supabaseKey;
    for (final line in lines) {
      if (line.startsWith('SUPABASE_URL=')) {
        supabaseUrl = line.split('=')[1].trim();
      }
      if (line.startsWith('SUPABASE_ANON_KEY=')) {
        supabaseKey = line.split('=')[1].trim();
      }
    }

    print('Connecting to $supabaseUrl...');
    await Supabase.initialize(
      url: supabaseUrl!,
      anonKey: supabaseKey!,
    );
    final client = Supabase.instance.client;

    final adminPhone = '+917006464241';
    final adminEmail = '${adminPhone.replaceAll('+', '')}@enything.com';
    final adminPass = adminPhone.replaceAll('+', '');
    try {
      final authRes = await client.auth.signInWithPassword(
        email: adminEmail,
        password: adminPass,
      );
      print('Signed in as: ${authRes.user?.id}');
    } catch (e) {
      print('Sign in note: $e');
    }

    print('\n--- TEST 1: fetch roles simple ---');
    try {
      final r1 = await client.from('roles').select('*');
      print('Found ${r1.length} roles.');
    } catch (e) {
      print('TEST 1 ERROR: $e');
    }

    print('\n--- TEST 2: fetch roles with permissions join ---');
    try {
      final r2 = await client
          .from('roles')
          .select('*, role_permissions(permissions(*))')
          .order('is_system', ascending: false)
          .order('name');
      print('Found ${r2.length} roles with permissions join.');
      for (final r in r2) {
        final parsed = RoleModel.fromMap(r as Map<String, dynamic>);
        print('Parsed Role: ${parsed.name} (${parsed.permissions.length} perms)');
      }
    } catch (e, stack) {
      print('TEST 2 ERROR: $e\n$stack');
    }

    print('\n--- TEST 3: RolesRepository().fetchRoles() ---');
    try {
      final repo = RolesRepository();
      final roles = await repo.fetchRoles();
      print('RolesRepository fetched ${roles.length} roles.');
    } catch (e, stack) {
      print('TEST 3 ERROR: $e\n$stack');
    }
  });
}
