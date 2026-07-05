// ============================================================================
// referral_provider.dart — Enything Referral Engine
// ============================================================================
//
// Manages:
//   • Referral code generation per user
//   • Applying a referral code at signup
//   • Processing first-order bonus for referrer (DB trigger handles this at
//     DB level via 20260714000001_referral_order_trigger.sql)
//
// Usage:
//   final ref = context.read<ReferralProvider>();
//   await ref.init(userId);
//   final code = ref.referralCode; // null until generated
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralProvider extends ChangeNotifier {
  SupabaseClient get _db => Supabase.instance.client;

  String? _referralCode;
  bool _loading = false;
  bool _initialized = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  String? get referralCode => _referralCode;
  bool get loading => _loading;
  bool get initialized => _initialized;

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> init(String userId) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await _loadReferralCode(userId);
    } catch (e) {
      debugPrint('ReferralProvider.init error: $e');
    } finally {
      _loading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadReferralCode(String userId) async {
    final data = await _db
        .from('referral_codes')
        .select('code')
        .eq('user_id', userId)
        .maybeSingle();
    _referralCode = data?['code'] as String?;
  }

  // ── Referral Code Generation ───────────────────────────────────────────────

  /// Generates and saves a referral code for the user (idempotent).
  /// Returns the code on success, null on failure.
  /// BUG-DB4 FIX: Retries with a numeric suffix if code collision occurs.
  Future<String?> generateReferralCode(String userId, String displayName) async {
    if (_referralCode != null) return _referralCode;
    try {
      final namePart = displayName.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
      final nameCode = namePart.length >= 4
          ? namePart.substring(0, 4)
          : namePart.padRight(4, 'X');
      final idPart = userId.replaceAll('-', '').substring(0, 4).toUpperCase();

      // BUG-DB4 FIX: Retry with suffix if code collision on another user's code
      for (int attempt = 0; attempt < 5; attempt++) {
        final suffix = attempt == 0 ? '' : attempt.toString();
        final code = '$nameCode$idPart$suffix';
        try {
          await _db.from('referral_codes').upsert({
            'user_id': userId,
            'code': code,
          }, onConflict: 'user_id');
          _referralCode = code;
          notifyListeners();
          return code;
        } on PostgrestException catch (e) {
          // Unique violation on 'code' column — another user has this code
          if (e.code == '23505' && attempt < 4) {
            debugPrint('ReferralProvider: code "$code" collision, retrying...');
            continue;
          }
          rethrow;
        }
      }
      return null;
    } catch (e) {
      debugPrint('generateReferralCode error: $e');
      return null;
    }
  }

  // ── Apply Referral at Signup ───────────────────────────────────────────────

  /// Applies a referral code during signup.
  /// Returns true if the code was valid and the referral was recorded.
  Future<bool> applyReferralCode({
    required String referralCode,
    required String newUserId,
  }) async {
    try {
      final codeRow = await _db
          .from('referral_codes')
          .select('user_id')
          .eq('code', referralCode.toUpperCase().trim())
          .maybeSingle();

      if (codeRow == null) return false;
      final referrerId = codeRow['user_id'] as String;
      if (referrerId == newUserId) return false; // Cannot refer yourself

      await _db.from('referrals').insert({
        'referrer_id': referrerId,
        'referred_id': newUserId,
        'referral_code': referralCode.toUpperCase().trim(),
      });

      return true;
    } catch (e) {
      debugPrint('applyReferralCode error: $e');
      return false;
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void reset() {
    _referralCode = null;
    _initialized = false;
    notifyListeners();
  }
}
