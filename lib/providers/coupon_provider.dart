import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data class for a validated coupon
class AppliedCoupon {
  final String id;
  final String code;
  final String discountType; // 'flat' or 'percent'
  final double discountValue;
  final double discountAmount;

  const AppliedCoupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
  });
}

class CouponProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  AppliedCoupon? _appliedCoupon;
  bool _isValidating = false;
  String? _errorMessage;

  AppliedCoupon? get appliedCoupon => _appliedCoupon;
  double get discountAmount => _appliedCoupon?.discountAmount ?? 0.0;
  bool get isValidating => _isValidating;
  String? get errorMessage => _errorMessage;
  bool get hasCoupon => _appliedCoupon != null;

  Future<bool> validateAndApply({
    required String code,
    required double cartTotal,
    String? shopId,
  }) async {
    if (code.trim().isEmpty) {
      _errorMessage = 'Please enter a coupon code';
      safeNotifyListeners();
      return false;
    }

    _isValidating = true;
    _errorMessage = null;
    safeNotifyListeners();

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final res = await _supabase
          .from('coupons')
          .select()
          .eq('code', code.trim().toUpperCase())
          .eq('is_active', true)
          .lte('valid_from', now)
          .or('valid_until.is.null,valid_until.gte.$now')
          .maybeSingle();

      if (res == null) {
        _errorMessage = 'Coupon "$code" is invalid or expired';
        _isValidating = false;
        safeNotifyListeners();
        return false;
      }

      // Check minimum order amount
      final minOrder = (res['min_order_amount'] as num?)?.toDouble() ?? 0;
      if (cartTotal < minOrder) {
        _errorMessage =
            'Minimum order ₹${minOrder.toStringAsFixed(0)} required for this coupon';
        _isValidating = false;
        safeNotifyListeners();
        return false;
      }

      // Check usage limit
      final usageLimit = res['usage_limit'] as int?;
      final usedCount = (res['usage_count'] as num?)?.toInt() ?? 0;
      if (usageLimit != null && usedCount >= usageLimit) {
        _errorMessage = 'This coupon has reached its usage limit';
        _isValidating = false;
        safeNotifyListeners();
        return false;
      }

      // Calculate discount
      final discountType = res['discount_type'] as String? ?? 'flat';
      final discountValue = (res['discount_value'] as num?)?.toDouble() ?? 0.0;

      double discount;
      if (discountType == 'percent') {
        discount = (cartTotal * discountValue / 100);
        // Cap at max_discount if provided
        final maxDiscount = (res['max_discount'] as num?)?.toDouble();
        if (maxDiscount != null && discount > maxDiscount) {
          discount = maxDiscount;
        }
      } else {
        discount = discountValue;
      }

      // Discount cannot exceed cart total
      if (discount > cartTotal) discount = cartTotal;

      _appliedCoupon = AppliedCoupon(
        id: res['id'] as String,
        code: res['code'] as String,
        discountType: discountType,
        discountValue: discountValue,
        discountAmount: discount,
      );
      _errorMessage = null;
      _isValidating = false;
      safeNotifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to validate coupon. Please try again.';
      _isValidating = false;
      safeNotifyListeners();
      return false;
    }
  }

  void clearCoupon() {
    _appliedCoupon = null;
    _errorMessage = null;
    safeNotifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
