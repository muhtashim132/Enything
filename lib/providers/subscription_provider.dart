// ============================================================================
// subscription_provider.dart — Enything Pass Subscription + Loyalty Engine
// ============================================================================
//
// Manages:
//   • Loading the user's active subscription from Supabase
//   • Checking free-delivery eligibility for a given order value
//   • Cashback calculation per order
//   • Loyalty points balance + earn / redeem
//   • Referral code generation and application
//
// Usage:
//   final sub = context.read<SubscriptionProvider>();
//   bool freeDelivery = sub.isFreeDelivery(cartSubtotal);
//   double cashback   = sub.cashbackFor(orderValue);
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Plan Data Model ──────────────────────────────────────────────────────────

class SubscriptionPlan {
  final String id;
  final String name;
  final int priceInr;
  final int deliveryFreeThreshold; // 0 = always free delivery
  final double cashbackPercent;
  final int maxAccounts;
  final bool isActive;
  final String? badgeLabel;
  final String badgeColor;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.priceInr,
    required this.deliveryFreeThreshold,
    required this.cashbackPercent,
    required this.maxAccounts,
    required this.isActive,
    this.badgeLabel,
    this.badgeColor = '#1E3FD8',
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> m) {
    return SubscriptionPlan(
      id: m['id'] as String,
      name: m['name'] as String,
      priceInr: (m['price_inr'] as num).toInt(),
      deliveryFreeThreshold: (m['delivery_free_threshold'] as num).toInt(),
      cashbackPercent: (m['cashback_percent'] as num).toDouble(),
      maxAccounts: (m['max_accounts'] as num).toInt(),
      isActive: m['is_active'] as bool? ?? true,
      badgeLabel: m['badge_label'] as String?,
      badgeColor: m['badge_color'] as String? ?? '#1E3FD8',
    );
  }
}

// ── Active Subscription Model ────────────────────────────────────────────────

class ActiveSubscription {
  final String id;
  final SubscriptionPlan plan;
  final DateTime expiresAt;
  final String status;

  const ActiveSubscription({
    required this.id,
    required this.plan,
    required this.expiresAt,
    required this.status,
  });

  bool get isValid => status == 'active' && expiresAt.isAfter(DateTime.now());

  /// Days remaining in the subscription
  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays.clamp(0, 999);
}

// ── Provider ─────────────────────────────────────────────────────────────────

class SubscriptionProvider extends ChangeNotifier {
  final _db = Supabase.instance.client;

  // State
  List<SubscriptionPlan> _plans = [];
  ActiveSubscription? _activeSub;
  int _loyaltyBalance = 0;
  int _lifetimeEarned = 0;
  String? _referralCode;
  bool _loading = false;
  bool _initialized = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  List<SubscriptionPlan> get plans => _plans;
  ActiveSubscription? get activeSub => _activeSub;
  bool get hasActiveSub => _activeSub?.isValid ?? false;
  SubscriptionPlan? get currentPlan => _activeSub?.plan;
  int get loyaltyBalance => _loyaltyBalance;
  int get lifetimeEarned => _lifetimeEarned;
  String? get referralCode => _referralCode;
  bool get loading => _loading;
  bool get initialized => _initialized;

  /// Returns the emoji + tier display for the badge. e.g. "⚡ PASS PRO"
  String get tierDisplay {
    if (!hasActiveSub) return '';
    final name = currentPlan!.name;
    switch (name) {
      case 'Lite':  return '✨ PASS LITE';
      case 'Pro':   return '⚡ PASS PRO';
      case 'Ultra': return '👑 PASS ULTRA';
      default:      return '🎫 PASS';
    }
  }

  // ── Business Logic ─────────────────────────────────────────────────────────

  /// True if the subscription entitles this order to free delivery.
  bool isFreeDelivery(double cartSubtotal) {
    if (!hasActiveSub) return false;
    final threshold = currentPlan!.deliveryFreeThreshold;
    if (threshold == 0) return true;          // Ultra/Pro = always free
    return cartSubtotal >= threshold;         // Lite = free if cart ≥ threshold
  }

  /// Returns the cashback amount (in ₹) for this order value.
  double cashbackFor(double orderValue) {
    if (!hasActiveSub) return 0.0;
    return orderValue * (currentPlan!.cashbackPercent / 100.0);
  }

  /// Returns loyalty points earned for an order (1 point per ₹10 spent base).
  int pointsForOrder(double orderValue) {
    const pointsPerRupee = 0.1; // 1 pt per ₹10
    final multiplier = hasActiveSub
        ? (currentPlan!.name == 'Ultra' ? 3.0 : currentPlan!.name == 'Pro' ? 2.0 : 1.5)
        : 1.0;
    return (orderValue * pointsPerRupee * multiplier).floor();
  }

  /// Points value in ₹ (1 point = ₹0.10)
  double get loyaltyValueInRs => _loyaltyBalance * 0.10;

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> init(String userId) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await Future.wait([
        _loadPlans(),
        _loadActiveSub(userId),
        _loadLoyaltyBalance(userId),
        _loadReferralCode(userId),
      ]);
    } catch (e) {
      debugPrint('SubscriptionProvider.init error: $e');
    } finally {
      _loading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadPlans() async {
    final data = await _db
        .from('subscription_plans')
        .select()
        .eq('is_active', true)
        .order('price_inr');
    _plans = (data as List).map((m) => SubscriptionPlan.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<void> _loadActiveSub(String userId) async {
    final data = await _db
        .from('subscriptions')
        .select('*, subscription_plans(*)')
        .eq('user_id', userId)
        .eq('status', 'active')
        .gt('expires_at', DateTime.now().toIso8601String())
        .maybeSingle();
    if (data != null) {
      final plan = SubscriptionPlan.fromMap(data['subscription_plans'] as Map<String, dynamic>);
      _activeSub = ActiveSubscription(
        id: data['id'] as String,
        plan: plan,
        expiresAt: DateTime.parse(data['expires_at'] as String),
        status: data['status'] as String,
      );
    } else {
      _activeSub = null;
    }
  }

  Future<void> _loadLoyaltyBalance(String userId) async {
    final data = await _db
        .from('loyalty_points')
        .select('balance, lifetime_earned')
        .eq('user_id', userId)
        .maybeSingle();
    if (data != null) {
      _loyaltyBalance = (data['balance'] as num).toInt();
      _lifetimeEarned = (data['lifetime_earned'] as num).toInt();
    } else {
      _loyaltyBalance = 0;
      _lifetimeEarned = 0;
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

  // ── Subscribe ──────────────────────────────────────────────────────────────

  /// Activates a subscription plan for the given user.
  /// [razorpaySubId] is optional — pass it when using Razorpay recurring billing.
  Future<bool> subscribe({
    required String userId,
    required String planId,
    String? razorpaySubId,
  }) async {
    try {
      // Cancel any existing active subscription first
      await _db
          .from('subscriptions')
          .update({'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .eq('status', 'active');

      // Create new subscription (30-day billing period)
      final expiresAt = DateTime.now().add(const Duration(days: 30));
      await _db.from('subscriptions').insert({
        'user_id': userId,
        'plan_id': planId,
        'status': 'active',
        'expires_at': expiresAt.toIso8601String(),
        'razorpay_sub_id': razorpaySubId,
        'payment_method': razorpaySubId != null ? 'razorpay' : 'manual',
      });

      // Award signup bonus loyalty points (50 points)
      await earnPoints(
        userId: userId,
        points: 50,
        type: 'earn_signup',
        description: 'Bonus for subscribing to Enything Pass',
      );

      await _loadActiveSub(userId);
      await _loadLoyaltyBalance(userId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('subscribe error: $e');
      return false;
    }
  }

  /// Cancels the user's active subscription.
  Future<bool> cancelSubscription(String userId) async {
    try {
      await _db
          .from('subscriptions')
          .update({'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .eq('status', 'active');
      _activeSub = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('cancelSubscription error: $e');
      return false;
    }
  }

  // ── Loyalty ────────────────────────────────────────────────────────────────

  /// Earns loyalty points for an order (call this after order is delivered).
  Future<int> earnPoints({
    required String userId,
    required int points,
    required String type,
    required String description,
    String? orderId,
  }) async {
    try {
      final result = await _db.rpc('add_loyalty_points', params: {
        'p_user_id': userId,
        'p_points': points,
        'p_type': type,
        'p_description': description,
        'p_order_id': orderId,
      });
      _loyaltyBalance = (result as num).toInt();
      if (points > 0) _lifetimeEarned += points;
      notifyListeners();
      return _loyaltyBalance;
    } catch (e) {
      debugPrint('earnPoints error: $e');
      return _loyaltyBalance;
    }
  }

  /// Redeems loyalty points (call this at checkout).
  /// Returns the ₹ discount amount applied.
  Future<double> redeemPoints({
    required String userId,
    required int pointsToRedeem,
    required String orderId,
  }) async {
    if (pointsToRedeem <= 0 || pointsToRedeem > _loyaltyBalance) return 0.0;
    // Each 10 points = ₹1 discount
    const pointsPerRupee = 10;
    final discountRs = pointsToRedeem / pointsPerRupee;

    final newBalance = await earnPoints(
      userId: userId,
      points: -pointsToRedeem,
      type: 'redeem',
      description: 'Redeemed $pointsToRedeem points for ₹${discountRs.toStringAsFixed(0)} off',
      orderId: orderId,
    );
    debugPrint('Redeemed $pointsToRedeem pts → ₹$discountRs off. New balance: $newBalance');
    return discountRs;
  }

  // ── Referral ───────────────────────────────────────────────────────────────

  /// Generates and saves a referral code for the user (if not already created).
  Future<String?> generateReferralCode(String userId, String displayName) async {
    if (_referralCode != null) return _referralCode;
    try {
      // Build code: first 5 chars of name (uppercase) + last 4 chars of userId
      final namePart = displayName.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
      final nameCode = namePart.length >= 4 ? namePart.substring(0, 4) : namePart.padRight(4, 'X');
      final idPart = userId.replaceAll('-', '').substring(0, 4).toUpperCase();
      final code = '$nameCode$idPart';

      await _db.from('referral_codes').upsert({
        'user_id': userId,
        'code': code,
      }, onConflict: 'user_id');
      _referralCode = code;
      notifyListeners();
      return code;
    } catch (e) {
      debugPrint('generateReferralCode error: $e');
      return null;
    }
  }

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
      if (referrerId == newUserId) return false; // Can't refer yourself

      await _db.from('referrals').insert({
        'referrer_id': referrerId,
        'referred_id': newUserId,
        'referral_code': referralCode.toUpperCase().trim(),
      });

      // Award 50 points to the new user immediately
      await earnPoints(
        userId: newUserId,
        points: 50,
        type: 'earn_referral',
        description: 'Welcome bonus for joining with referral code',
      );

      return true;
    } catch (e) {
      debugPrint('applyReferralCode error: $e');
      return false;
    }
  }

  /// Call this when a referred user places their first delivered order.
  /// Awards ₹50 bonus to the referrer as loyalty points (500 points).
  Future<void> processFriendFirstOrderBonus({
    required String referredUserId,
    required String orderId,
  }) async {
    try {
      final referral = await _db
          .from('referrals')
          .select('id, referrer_id, bonus_paid')
          .eq('referred_id', referredUserId)
          .eq('bonus_paid', false)
          .maybeSingle();
      if (referral == null) return;

      final referrerId = referral['referrer_id'] as String;

      // Mark bonus as paid
      await _db.from('referrals').update({'bonus_paid': true}).eq('id', referral['id']);

      // Award 500 points (= ₹50) to the referrer
      await earnPoints(
        userId: referrerId,
        points: 500,
        type: 'earn_referral',
        description: 'Referral bonus — your friend placed their first order!',
        orderId: orderId,
      );
    } catch (e) {
      debugPrint('processFriendFirstOrderBonus error: $e');
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void reset() {
    _activeSub = null;
    _loyaltyBalance = 0;
    _lifetimeEarned = 0;
    _referralCode = null;
    _initialized = false;
    notifyListeners();
  }
}
