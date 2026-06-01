import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlatformConfigProvider extends ChangeNotifier {
  static PlatformConfigProvider? instance;

  final _db = Supabase.instance.client;

  PlatformConfigProvider() {
    instance = this;
  }

  // ── Defaults (matches hardcoded constants initially) ────────
  double _commissionPercent = 5.0;
  double _platformFee = 15.0;
  double _smallCartFee = 15.0;
  double _smallCartThreshold = 99.0;
  double _heavyOrderFee = 20.0;
  double _heavyOrderThresholdKg = 10.0;
  double _deliveryDiscountThreshold = 999.0;
  double _deliveryDiscountAmount = 15.0;
  double _maxDeliveryRadiusKm = 9.0;
  double _referralBonusAmount = 50.0;
  double _deliveryGstRate = 0.18;
  double _platformFeeGstRate = 0.18;

  bool _loading = false;
  String? _error;

  // ── Getters ──────────────────────────────────────────────────
  double get commissionPercent => _commissionPercent;
  double get commissionRate => _commissionPercent / 100.0;
  double get platformFee => _platformFee;
  double get smallCartFee => _smallCartFee;
  double get smallCartThreshold => _smallCartThreshold;
  double get heavyOrderFee => _heavyOrderFee;
  double get heavyOrderThresholdKg => _heavyOrderThresholdKg;
  double get deliveryDiscountThreshold => _deliveryDiscountThreshold;
  double get deliveryDiscountAmount => _deliveryDiscountAmount;
  double get maxDeliveryRadiusKm => _maxDeliveryRadiusKm;
  double get referralBonusAmount => _referralBonusAmount;
  double get deliveryGstRate => _deliveryGstRate;
  double get platformFeeGstRate => _platformFeeGstRate;

  bool get loading => _loading;
  String? get error => _error;

  // ── Load Settings ────────────────────────────────────────────
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _db.from('platform_config').select('key, value');
      for (final row in (data as List)) {
        final key = row['key'] as String;
        final valRaw = row['value'];
        final val = double.tryParse(valRaw.toString()) ?? 0.0;

        switch (key) {
          case 'commission_percent':
            _commissionPercent = val;
            break;
          case 'platform_fee':
            _platformFee = val;
            break;
          case 'small_cart_fee':
            _smallCartFee = val;
            break;
          case 'small_cart_threshold':
            _smallCartThreshold = val;
            break;
          case 'heavy_order_fee':
            _heavyOrderFee = val;
            break;
          case 'heavy_order_threshold_kg':
            _heavyOrderThresholdKg = val;
            break;
          case 'delivery_discount_threshold':
            _deliveryDiscountThreshold = val;
            break;
          case 'delivery_discount_amount':
            _deliveryDiscountAmount = val;
            break;
          case 'max_delivery_radius_km':
            _maxDeliveryRadiusKm = val;
            break;
          case 'referral_bonus_amount':
            _referralBonusAmount = val;
            break;
          case 'delivery_gst_rate':
            _deliveryGstRate = val;
            break;
          case 'platform_fee_gst_rate':
            _platformFeeGstRate = val;
            break;
        }
      }
    } catch (e) {
      debugPrint('Failed to load platform config: $e');
      _error = 'Failed to load live config, using defaults.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Update Settings (Admin Only) ────────────────────────────
  Future<bool> updateSetting({
    required String key,
    required String value,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      // Optimistic update
      final doubleVal = double.tryParse(value) ?? 0.0;
      final oldVal = _getValue(key);
      _setValue(key, doubleVal);
      notifyListeners();

      // DB update
      await _db.from('platform_config').upsert({
        'key': key,
        'value': value,
        'updated_by': actorId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');

      // Audit log
      try {
        await _db.from('audit_logs').insert({
          'actor_id': actorId,
          'actor_role': actorRole,
          'action': 'update_platform_config',
          'entity_type': 'platform_config',
          'entity_id': null,
          'metadata': {
            'key': key,
            'old_value': oldVal,
            'new_value': value,
          },
        });
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('Failed to update setting $key: $e');
      // Reload from DB to fix optimistic update if it failed
      await load();
      return false;
    }
  }

  double _getValue(String key) {
    switch (key) {
      case 'commission_percent': return _commissionPercent;
      case 'platform_fee': return _platformFee;
      case 'small_cart_fee': return _smallCartFee;
      case 'small_cart_threshold': return _smallCartThreshold;
      case 'heavy_order_fee': return _heavyOrderFee;
      case 'heavy_order_threshold_kg': return _heavyOrderThresholdKg;
      case 'delivery_discount_threshold': return _deliveryDiscountThreshold;
      case 'delivery_discount_amount': return _deliveryDiscountAmount;
      case 'max_delivery_radius_km': return _maxDeliveryRadiusKm;
      case 'referral_bonus_amount': return _referralBonusAmount;
      case 'delivery_gst_rate': return _deliveryGstRate;
      case 'platform_fee_gst_rate': return _platformFeeGstRate;
      default: return 0.0;
    }
  }

  void _setValue(String key, double val) {
    switch (key) {
      case 'commission_percent': _commissionPercent = val; break;
      case 'platform_fee': _platformFee = val; break;
      case 'small_cart_fee': _smallCartFee = val; break;
      case 'small_cart_threshold': _smallCartThreshold = val; break;
      case 'heavy_order_fee': _heavyOrderFee = val; break;
      case 'heavy_order_threshold_kg': _heavyOrderThresholdKg = val; break;
      case 'delivery_discount_threshold': _deliveryDiscountThreshold = val; break;
      case 'delivery_discount_amount': _deliveryDiscountAmount = val; break;
      case 'max_delivery_radius_km': _maxDeliveryRadiusKm = val; break;
      case 'referral_bonus_amount': _referralBonusAmount = val; break;
      case 'delivery_gst_rate': _deliveryGstRate = val; break;
      case 'platform_fee_gst_rate': _platformFeeGstRate = val; break;
    }
  }
}
