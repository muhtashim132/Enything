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

class ReferralRewardCoupon {
  final String code;
  final double discountValue;
  final double minOrderAmount;
  final bool isUsed;
  final bool isExpired;
  final DateTime? validUntil;
  final String source; // 'Friend Completed Order' or 'Welcome Reward'
  final DateTime createdAt;

  const ReferralRewardCoupon({
    required this.code,
    required this.discountValue,
    required this.minOrderAmount,
    required this.isUsed,
    required this.isExpired,
    this.validUntil,
    required this.source,
    required this.createdAt,
  });

  ReferralRewardCoupon copyWith({
    String? code,
    double? discountValue,
    double? minOrderAmount,
    bool? isUsed,
    bool? isExpired,
    DateTime? validUntil,
    String? source,
    DateTime? createdAt,
  }) {
    return ReferralRewardCoupon(
      code: code ?? this.code,
      discountValue: discountValue ?? this.discountValue,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      isUsed: isUsed ?? this.isUsed,
      isExpired: isExpired ?? this.isExpired,
      validUntil: validUntil ?? this.validUntil,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ReferralProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  SupabaseClient get _db => Supabase.instance.client;

  String? _referralCode;
  bool _loading = false;
  bool _initialized = false;

  // ── Referral Stats & Earned Coupons State ──────────────────────────────────
  int _invitedCount = 0;
  int _completedCount = 0;
  double _referralBonusAmount = 25.0;
  double _totalBonusEarned = 0.0;
  List<ReferralRewardCoupon> _earnedCoupons = [];
  bool _statsLoading = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  String? get referralCode => _referralCode;
  bool get loading => _loading;
  bool get initialized => _initialized;

  int get invitedCount => _invitedCount;
  int get completedCount => _completedCount;
  int get pendingCount => (_invitedCount - _completedCount).clamp(0, 999999);
  double get referralBonusAmount => _referralBonusAmount;
  double get totalBonusEarned => _totalBonusEarned;
  List<ReferralRewardCoupon> get earnedCoupons => _earnedCoupons;
  bool get statsLoading => _statsLoading;

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> init(String userId) async {
    if (_loading) return;
    _loading = true;
    safeNotifyListeners();
    try {
      await _loadReferralCode(userId);
      await loadReferralStats(userId, silent: true);
    } catch (e) {
      debugPrint('ReferralProvider.init error: $e');
    } finally {
      _loading = false;
      _initialized = true;
      safeNotifyListeners();
    }
  }

  Future<void> _loadReferralCode(String userId) async {
    final data = await _db
        .from('referral_codes')
        .select('code, used_count')
        .eq('user_id', userId)
        .maybeSingle();
    _referralCode = data?['code'] as String?;
    _invitedCount = (data?['used_count'] as num?)?.toInt() ?? 0;
  }

  // ── Live Stats & Earned Coupons Loading ────────────────────────────────────

  Future<void> loadReferralStats(String userId, {bool silent = false}) async {
    if (!silent) {
      _statsLoading = true;
      safeNotifyListeners();
    }

    try {
      // 1. Fetch referral code & used_count
      final codeData = await _db
          .from('referral_codes')
          .select('code, used_count')
          .eq('user_id', userId)
          .maybeSingle();
      if (codeData != null) {
        _referralCode = codeData['code'] as String?;
        _invitedCount = (codeData['used_count'] as num?)?.toInt() ?? 0;
      }

      // 2. Fetch completed referrals where bonus was paid
      final referralsData = await _db
          .from('referrals')
          .select('id, bonus_paid, created_at')
          .eq('referrer_id', userId);
      final refList = (referralsData as List?) ?? [];
      _completedCount = refList.where((r) => r['bonus_paid'] == true).length;

      // 3. Fetch configurable bonus amount from platform_config
      try {
        final configData = await _db
            .from('platform_config')
            .select('value')
            .eq('key', 'referral_bonus_amount')
            .maybeSingle();
        if (configData != null && configData['value'] != null) {
          _referralBonusAmount =
              double.tryParse(configData['value'].toString()) ?? 25.0;
        }
      } catch (e) {
        debugPrint('ReferralProvider: platform_config fetch fallback: $e');
      }

      _totalBonusEarned = _completedCount * _referralBonusAmount;

      // 4. Fetch earned coupon notifications
      final notifsData = await _db
          .from('notifications')
          .select('title, body, notif_key, created_at')
          .eq('user_id', userId)
          .or('notif_key.like.ref_bonus_%,notif_key.like.ref_welcome_%')
          .order('created_at', ascending: false);

      final List<ReferralRewardCoupon> coupons = [];
      final Set<String> extractedCodes = {};
      final codeRegex = RegExp(r'(REF\d+(?:-W)?-[A-Z0-9]+)');

      for (final n in (notifsData as List?) ?? []) {
        final body = (n['body'] ?? '').toString();
        final notifKey = (n['notif_key'] ?? '').toString();
        final match = codeRegex.firstMatch(body);
        if (match != null) {
          final code = match.group(1)!;
          if (!extractedCodes.contains(code)) {
            extractedCodes.add(code);
            final isWelcome = notifKey.startsWith('ref_welcome_');
            coupons.add(ReferralRewardCoupon(
              code: code,
              discountValue: _referralBonusAmount,
              minOrderAmount: 199.0,
              isUsed: false,
              isExpired: false,
              source: isWelcome ? 'Welcome Reward' : 'Friend Completed Order',
              createdAt: DateTime.tryParse(n['created_at']?.toString() ?? '') ??
                  DateTime.now(),
            ));
          }
        }
      }

      // 5. Hydrate current live status from public.coupons
      if (coupons.isNotEmpty) {
        try {
          final couponCodes = coupons.map((c) => c.code).toList();
          final dbCoupons = await _db
              .from('coupons')
              .select(
                  'code, discount_value, min_order_amount, is_active, valid_until, usage_limit, usage_count')
              .inFilter('code', couponCodes);

          final now = DateTime.now();
          for (int i = 0; i < coupons.length; i++) {
            final c = coupons[i];
            final dbMatch = (dbCoupons as List?)
                ?.where((row) => row['code'] == c.code)
                .firstOrNull;
            if (dbMatch != null) {
              final usageCount = (dbMatch['usage_count'] as num?)?.toInt() ?? 0;
              final usageLimit = (dbMatch['usage_limit'] as num?)?.toInt() ?? 1;
              final validUntilStr = dbMatch['valid_until']?.toString();
              final validUntil = validUntilStr != null
                  ? DateTime.tryParse(validUntilStr)
                  : null;
              final isExpired = validUntil != null && now.isAfter(validUntil);
              final isUsed = usageCount >= usageLimit;

              coupons[i] = coupons[i].copyWith(
                discountValue:
                    (dbMatch['discount_value'] as num?)?.toDouble() ??
                        c.discountValue,
                minOrderAmount:
                    (dbMatch['min_order_amount'] as num?)?.toDouble() ??
                        c.minOrderAmount,
                isUsed: isUsed,
                isExpired: isExpired,
                validUntil: validUntil,
              );
            }
          }
        } catch (e) {
          debugPrint('ReferralProvider: error fetching coupon live status: $e');
        }
      }

      _earnedCoupons = coupons;
    } catch (e) {
      debugPrint('ReferralProvider.loadReferralStats error: $e');
    } finally {
      _statsLoading = false;
      safeNotifyListeners();
    }
  }

  // ── Referral Code Generation ───────────────────────────────────────────────

  /// Generates and saves a referral code for the user (idempotent).
  /// Returns the code on success, null on failure.
  /// BUG-DB4 FIX: Retries with a numeric suffix if code collision occurs.
  Future<String?> generateReferralCode(
      String userId, String displayName) async {
    if (_referralCode != null) return _referralCode;
    try {
      final namePart =
          displayName.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
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
          safeNotifyListeners();
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
    _invitedCount = 0;
    _completedCount = 0;
    _totalBonusEarned = 0.0;
    _earnedCoupons = [];
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
