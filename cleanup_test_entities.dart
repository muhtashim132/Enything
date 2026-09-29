// =============================================================================
// Pre-Launch Test Entity Cleanup Script
// =============================================================================
// Purges mock test products and test shops created by automated test runs.
// 
// TEST PRODUCTS: Soft-deleted (is_deleted=true, is_available=false)
// TEST SHOPS: NOT deleted — they may have order history. Only deactivated.
//
// Per AGENTS.md: "Never leave test entities in the live database."
// =============================================================================

import 'package:supabase/supabase.dart';
import 'dart:io';

Future<void> main() async {
  final envFile = File('.env');
  final lines = envFile.readAsLinesSync();
  String? supabaseUrl, anonKey;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_URL=')) {
      supabaseUrl = line.split('=')[1].trim();
    }
    if (line.startsWith('SUPABASE_ANON_KEY=')) {
      anonKey = line.split('=')[1].trim();
    }
  }

  final client = SupabaseClient(supabaseUrl!, anonKey!);

  print('╔══════════════════════════════════════════╗');
  print('║  Pre-Launch Test Entity Cleanup Script   ║');
  print('╚══════════════════════════════════════════╝\n');

  // ── 1. Soft-delete test products ──────────────────────────────────────────
  // Match products whose name contains 'test' (case-insensitive)
  final testProducts = await client
      .from('products')
      .select('id, name, shop_id, is_deleted')
      .or('name.ilike.%test%,name.ilike.%refund test%,name.ilike.%stock test%');

  int deletedCount = 0;
  for (final p in testProducts) {
    final isAlreadyDeleted = p['is_deleted'] == true;
    if (isAlreadyDeleted) {
      print('  ⏭️  Already deleted: "${p['name']}" (${p['id']})');
      continue;
    }
    
    try {
      await client
          .from('products')
          .update({'is_deleted': true, 'is_available': false})
          .eq('id', p['id']);
      print('  ✅ Soft-deleted: "${p['name']}" (Shop: ${p['shop_id']})');
      deletedCount++;
    } catch (e) {
      print('  ❌ Failed to delete "${p['name']}": $e');
    }
  }
  print('\n📦 Products: $deletedCount test products soft-deleted.\n');

  // ── 2. Deactivate test shops ──────────────────────────────────────────────
  // Match shops created by test scripts (name contains "Test Shop" or phone prefixes +919999/+918888)
  final allShops = await client.from('shops').select('id, name, is_active');
  
  int deactivatedCount = 0;
  for (final s in allShops) {
    final name = (s['name'] as String?) ?? '';
    final isTestShop = name.contains('Test Shop') || 
                       name.contains('Shop +919999') || 
                       name.contains('Shop +918888') ||
                       name.startsWith('Test ');
    
    if (!isTestShop) continue;
    
    final isAlreadyInactive = s['is_active'] == false;
    if (isAlreadyInactive) {
      print('  ⏭️  Already inactive: "$name" (${s['id']})');
      continue;
    }
    
    try {
      await client
          .from('shops')
          .update({'is_active': false})
          .eq('id', s['id']);
      print('  ✅ Deactivated: "$name" (${s['id']})');
      deactivatedCount++;
    } catch (e) {
      print('  ❌ Failed to deactivate "$name": $e');
    }
  }
  print('\n🏪 Shops: $deactivatedCount test shops deactivated.\n');

  // ── 3. Verify cleanup ──────────────────────────────────────────────────────
  final remainingTest = await client
      .from('products')
      .select('id, name')
      .eq('is_deleted', false)
      .or('name.ilike.%test%,name.ilike.%refund test%,name.ilike.%stock test%');
  
  final activeTestShops = await client
      .from('shops')
      .select('id, name')
      .eq('is_active', true)
      .or('name.ilike.%test shop%,name.ilike.%Shop +919999%,name.ilike.%Shop +918888%');

  print('═══════════════════════════════════════════');
  print('VERIFICATION:');
  print('  Remaining test products (is_deleted=false): ${remainingTest.length}');
  print('  Active test shops: ${activeTestShops.length}');
  
  if (remainingTest.isEmpty && activeTestShops.isEmpty) {
    print('\n🟢 CLEAN — No test entities will appear to launch users.');
  } else {
    print('\n🟡 WARNING — Some test entities may still be visible:');
    for (final p in remainingTest) {
      print('    Product: "${p['name']}" (${p['id']})');
    }
    for (final s in activeTestShops) {
      print('    Shop: "${s['name']}" (${s['id']})');
    }
  }
  print('═══════════════════════════════════════════');
}
