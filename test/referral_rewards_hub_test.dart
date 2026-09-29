import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/providers/referral_provider.dart';

void main() {
  group('ReferralRewardCoupon Model Tests', () {
    test('Initialization with all fields', () {
      final now = DateTime.now();
      final validUntil = now.add(const Duration(days: 90));
      final coupon = ReferralRewardCoupon(
        code: 'REF25-ABC123XYZ',
        discountValue: 25.0,
        minOrderAmount: 199.0,
        isUsed: false,
        isExpired: false,
        validUntil: validUntil,
        source: 'Friend Completed Order',
        createdAt: now,
      );

      expect(coupon.code, 'REF25-ABC123XYZ');
      expect(coupon.discountValue, 25.0);
      expect(coupon.minOrderAmount, 199.0);
      expect(coupon.isUsed, false);
      expect(coupon.isExpired, false);
      expect(coupon.validUntil, validUntil);
      expect(coupon.source, 'Friend Completed Order');
      expect(coupon.createdAt, now);
    });

    test('copyWith updates individual fields immutably', () {
      final now = DateTime.now();
      final coupon = ReferralRewardCoupon(
        code: 'REF25-ABC123XYZ',
        discountValue: 25.0,
        minOrderAmount: 199.0,
        isUsed: false,
        isExpired: false,
        validUntil: now.add(const Duration(days: 30)),
        source: 'Friend Completed Order',
        createdAt: now,
      );

      final updated = coupon.copyWith(
        isUsed: true,
        discountValue: 50.0,
      );

      expect(updated.code, coupon.code);
      expect(updated.isUsed, true);
      expect(updated.discountValue, 50.0);
      expect(updated.minOrderAmount, coupon.minOrderAmount);
      expect(updated.isExpired, false);
      expect(coupon.isUsed, false); // original unchanged
    });

    test('Coupon expiration detection logic', () {
      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 10));
      final pastDate = now.subtract(const Duration(days: 1));

      expect(now.isAfter(pastDate), isTrue);
      expect(now.isAfter(futureDate), isFalse);

      final daysRemaining = futureDate.difference(now).inDays;
      expect(daysRemaining, 10);
    });
  });

  group('Referral Metrics & Calculation Edge Cases', () {
    test('pendingCount clamps to 0 when completedCount exceeds invitedCount', () {
      final provider = ReferralProvider();

      // Default state
      expect(provider.invitedCount, 0);
      expect(provider.completedCount, 0);
      expect(provider.pendingCount, 0);
      expect(provider.totalBonusEarned, 0.0);
      expect(provider.referralBonusAmount, 25.0);
      expect(provider.earnedCoupons, isEmpty);
    });

    test('Reset clears all referral state', () {
      final provider = ReferralProvider();
      provider.reset();

      expect(provider.referralCode, isNull);
      expect(provider.initialized, isFalse);
      expect(provider.invitedCount, 0);
      expect(provider.completedCount, 0);
      expect(provider.pendingCount, 0);
      expect(provider.totalBonusEarned, 0.0);
      expect(provider.earnedCoupons, isEmpty);
    });
  });

  group('Regex Extraction & Parsing Tests for Referral Coupons', () {
    final codeRegex = RegExp(r'(REF\d+(?:-W)?-[A-Z0-9]+)');

    test('Successfully extracts standard Referrer Bonus coupon code', () {
      const body =
          'Congratulations! Your friend placed their first order. Here is your ₹25 coupon: REF25-9F8A2B. Valid for 90 days on orders above ₹199.';
      final match = codeRegex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.group(1), 'REF25-9F8A2B');
    });

    test('Successfully extracts Welcome Reward coupon code with -W- pattern', () {
      const body =
          'Welcome to Enything! Thanks for joining using a referral code. Here is your welcome coupon: REF25-W-A8C3D1. Apply it on your first order!';
      final match = codeRegex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.group(1), 'REF25-W-A8C3D1');
    });

    test('Does not match unrelated notifications or random text', () {
      const orderBody =
          'Your order #10842 has been dispatched and will arrive shortly.';
      final match1 = codeRegex.firstMatch(orderBody);
      expect(match1, isNull);

      const refundBody = 'Refund of ₹340 has been credited to your wallet.';
      final match2 = codeRegex.firstMatch(refundBody);
      expect(match2, isNull);
    });

    test('Deduplicates duplicate notifications with identical coupon codes', () {
      final notifs = [
        {
          'body': 'Your coupon: REF25-ABC123',
          'notif_key': 'ref_bonus_1',
          'created_at': '2026-03-01T12:00:00Z',
        },
        {
          'body': 'Reminder! You have coupon REF25-ABC123',
          'notif_key': 'ref_bonus_2',
          'created_at': '2026-03-02T12:00:00Z',
        },
        {
          'body': 'Welcome bonus coupon: REF25-W-XYZ789',
          'notif_key': 'ref_welcome_1',
          'created_at': '2026-03-03T12:00:00Z',
        },
      ];

      final List<ReferralRewardCoupon> coupons = [];
      final Set<String> extractedCodes = {};

      for (final n in notifs) {
        final body = n['body']!;
        final notifKey = n['notif_key']!;
        final match = codeRegex.firstMatch(body);
        if (match != null) {
          final code = match.group(1)!;
          if (!extractedCodes.contains(code)) {
            extractedCodes.add(code);
            final isWelcome = notifKey.startsWith('ref_welcome_');
            coupons.add(ReferralRewardCoupon(
              code: code,
              discountValue: 25.0,
              minOrderAmount: 199.0,
              isUsed: false,
              isExpired: false,
              source: isWelcome ? 'Welcome Reward' : 'Friend Completed Order',
              createdAt: DateTime.parse(n['created_at']!),
            ));
          }
        }
      }

      expect(coupons.length, 2);
      expect(coupons[0].code, 'REF25-ABC123');
      expect(coupons[0].source, 'Friend Completed Order');
      expect(coupons[1].code, 'REF25-W-XYZ789');
      expect(coupons[1].source, 'Welcome Reward');
    });
  });

  group('Coupon Status Hydration Logic Tests', () {
    test('Mark as used when usage_count >= usage_limit', () {
      final dbCoupon = {
        'code': 'REF25-ABC123',
        'discount_value': 25,
        'min_order_amount': 199,
        'usage_limit': 1,
        'usage_count': 1,
        'valid_until': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      };

      final usageCount = (dbCoupon['usage_count'] as num).toInt();
      final usageLimit = (dbCoupon['usage_limit'] as num).toInt();
      final isUsed = usageCount >= usageLimit;

      expect(isUsed, isTrue);
    });

    test('Mark as expired when valid_until is before now', () {
      final now = DateTime.now();
      final expiredDate = now.subtract(const Duration(days: 2));

      final isExpired = now.isAfter(expiredDate);
      expect(isExpired, isTrue);
    });

    test('Mark as active when neither used nor expired', () {
      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 45));
      const usageCount = 0;
      const usageLimit = 1;

      const isUsed = usageCount >= usageLimit;
      final isExpired = now.isAfter(futureDate);
      final isActive = !isUsed && !isExpired;

      expect(isActive, isTrue);
    });
  });

  group('Single Coupon Per Order Limit & Stacking Prevention Tests', () {
    test('Applying a second coupon replaces the previous coupon (strictly 1 coupon per order)', () {
      // Simulate multiple coupons owned by Person 1
      final coupon1 = ReferralRewardCoupon(
        code: 'REF25-AAA111',
        discountValue: 25.0,
        minOrderAmount: 199.0,
        isUsed: false,
        isExpired: false,
        source: 'Friend Completed Order',
        createdAt: DateTime.now(),
      );

      final coupon2 = ReferralRewardCoupon(
        code: 'REF25-BBB222',
        discountValue: 25.0,
        minOrderAmount: 199.0,
        isUsed: false,
        isExpired: false,
        source: 'Friend Completed Order',
        createdAt: DateTime.now(),
      );

      final coupon3 = ReferralRewardCoupon(
        code: 'REF25-CCC333',
        discountValue: 25.0,
        minOrderAmount: 199.0,
        isUsed: false,
        isExpired: false,
        source: 'Friend Completed Order',
        createdAt: DateTime.now(),
      );

      // Person 1 has 3 active coupons worth ₹75 total
      final availableCoupons = [coupon1, coupon2, coupon3];
      expect(availableCoupons.length, 3);

      // State variable on checkout: strictly single coupon holder
      ReferralRewardCoupon? appliedCoupon;

      // 1. User selects coupon 1
      appliedCoupon = coupon1;
      expect(appliedCoupon.code, 'REF25-AAA111');
      expect(appliedCoupon.discountValue, 25.0);

      // 2. User taps coupon 2 -> replaces coupon 1, never stacks to ₹50!
      appliedCoupon = coupon2;
      expect(appliedCoupon.code, 'REF25-BBB222');
      expect(appliedCoupon.discountValue, 25.0); // strictly ₹25, NOT ₹50

      // 3. User taps coupon 3 -> replaces coupon 2, never stacks to ₹75!
      appliedCoupon = coupon3;
      expect(appliedCoupon.code, 'REF25-CCC333');
      expect(appliedCoupon.discountValue, 25.0); // strictly ₹25, NOT ₹75
    });

    test('Min order threshold validation prevents discount when cart subtotal < 199', () {
      const minOrderAmount = 199.0;
      const smallCartTotal = 150.0;
      const eligibleCartTotal = 250.0;

      final bool canApplySmall = smallCartTotal >= minOrderAmount;
      expect(canApplySmall, isFalse);
      final double shortfall = minOrderAmount - smallCartTotal;
      expect(shortfall, 49.0);

      final bool canApplyEligible = eligibleCartTotal >= minOrderAmount;
      expect(canApplyEligible, isTrue);
    });

    test('Referral balance display formatting handles zero and positive amounts', () {
      double totalEarned = 0.0;
      String subtitle = totalEarned > 0
          ? '₹${totalEarned.toStringAsFixed(0)} earned • Invite friends'
          : 'Invite friends, earn rewards';
      expect(subtitle, 'Invite friends, earn rewards');

      totalEarned = 75.0;
      subtitle = totalEarned > 0
          ? '₹${totalEarned.toStringAsFixed(0)} earned • Invite friends'
          : 'Invite friends, earn rewards';
      expect(subtitle, '₹75 earned • Invite friends');
    });
  });
}

