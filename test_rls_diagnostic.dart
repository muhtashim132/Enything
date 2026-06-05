// Run: dart run test_rls_diagnostic.dart
// This logs in as a test user and checks what orders the RLS allows them to see.
// FILL IN credentials below before running.

import 'package:supabase_flutter/supabase_flutter.dart';

// ── FILL THESE IN ──────────────────────────────────────────────────────────
const supabaseUrl = 'https://mmdrgcuaetwohflcvzou.supabase.co';
const supabaseAnonKey = 'sb_publishable_f4uHzztf4EK76hcL0-bS5A_Ga0G2K6p';

// Add seller & rider credentials here for testing:
const sellerEmail = 'SELLER_EMAIL_HERE';
const sellerPassword = 'SELLER_PASS_HERE';
const riderEmail = 'RIDER_EMAIL_HERE';
const riderPassword = 'RIDER_PASS_HERE';
// ──────────────────────────────────────────────────────────────────────────

void main() async {
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  final supabase = Supabase.instance.client;

  print('=== RLS DIAGNOSTIC TOOL ===\n');

  // ── TEST 1: Check orders as seller ───────────────────────────────────────
  print('--- TEST 1: Seller Login ---');
  final sellerAuth = await supabase.auth.signInWithPassword(
    email: sellerEmail,
    password: sellerPassword,
  );
  print('Seller UID: ${sellerAuth.user?.id}');

  final sellerShops = await supabase.from('shops').select('id, name, seller_id');
  print('Seller shops visible: ${sellerShops.length}');
  for (final s in sellerShops as List) {
    print('  Shop: ${s['name']} (id=${s['id']}, seller_id=${s['seller_id']})');
  }

  final sellerOrders = await supabase
      .from('orders')
      .select('id, status, seller_accepted, shop_id, created_at')
      .order('created_at', ascending: false)
      .limit(10);
  print('Orders visible to seller: ${(sellerOrders as List).length}');
  for (final o in sellerOrders) {
    print('  Order: id=${o['id']?.toString().substring(0, 8)} status=${o['status']} seller_accepted=${o['seller_accepted']}');
  }

  await supabase.auth.signOut();
  print('');

  // ── TEST 2: Check orders as rider ───────────────────────────────────────
  print('--- TEST 2: Rider Login ---');
  final riderAuth = await supabase.auth.signInWithPassword(
    email: riderEmail,
    password: riderPassword,
  );
  print('Rider UID: ${riderAuth.user?.id}');

  final riderProfile = await supabase
      .from('delivery_partners')
      .select('id, is_active, is_available, verification_status')
      .eq('id', riderAuth.user!.id)
      .maybeSingle();
  print('Rider delivery_partner record: $riderProfile');

  final availableOrders = await supabase
      .from('orders')
      .select('id, status, seller_accepted, delivery_partner_id, created_at')
      .isFilter('delivery_partner_id', null)
      .inFilter('status', ['awaiting_acceptance', 'pending', 'confirmed'])
      .limit(10);
  print('Available orders visible to rider: ${(availableOrders as List).length}');
  for (final o in availableOrders) {
    print('  Order: id=${o['id']?.toString().substring(0, 8)} status=${o['status']}');
  }

  await supabase.auth.signOut();
  print('\n=== DONE ===');
}
