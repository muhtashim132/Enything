import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/tax_config.dart';

class PlatformConfigProvider extends ChangeNotifier {
  static PlatformConfigProvider? instance;

  SupabaseClient get _db => Supabase.instance.client;

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
  double _maxDeliveryRadiusKm = 15.0;
  double _deliveryRatePerKm = 10.0;
  double _referralBonusAmount = 50.0;
  double _deliveryGstRate = 0.18;
  double _platformFeeGstRate = 0.18;

  final Map<String, double> _categoryCommissionOverrides = {};
  
  // Cache for tax_config table (category -> row data)
  final Map<String, Map<String, dynamic>> _taxConfigCache = {};

  bool _loading = false;
  String? _error;

  // ── Getters ──────────────────────────────────────────────────
  double get commissionPercent => _commissionPercent;
  double get commissionRate => _commissionPercent / 100.0;

  /// The unified commission rate that includes the gateway fee.
  /// If base commission is 5% and gateway is 2.36%, this returns 7.36.
  double get unifiedCommissionPercent => _commissionPercent + (0.0236 * 100);

  double getCommissionPercentForCategory(String category) {
    return _categoryCommissionOverrides[category] ?? _commissionPercent;
  }

  double getCommissionRateForCategory(String category) {
    return getCommissionPercentForCategory(category) / 100.0;
  }

  double get platformFee => _platformFee;
  double get smallCartFee => _smallCartFee;
  double get smallCartThreshold => _smallCartThreshold;
  double get heavyOrderFee => _heavyOrderFee;
  double get heavyOrderThresholdKg => _heavyOrderThresholdKg;
  double get maxDeliveryRadiusKm => _maxDeliveryRadiusKm;
  double get deliveryRatePerKm => _deliveryRatePerKm;
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
          case 'max_delivery_radius_km':
            _maxDeliveryRadiusKm = val;
            break;
          case 'delivery_rate_per_km':
            _deliveryRatePerKm = val;
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

        if (key.startsWith('commission_percent_')) {
          final category = key.replaceFirst('commission_percent_', '');
          _categoryCommissionOverrides[category] = val;
        }
      }

      // ── Load Tax Config ──────────────────────────────────────────
      final taxData = await _db.from('tax_config').select();
      _taxConfigCache.clear();
      for (final row in (taxData as List)) {
        _taxConfigCache[row['category'] as String] = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('Failed to load platform config: $e');
      _error = 'Failed to load live config, using defaults.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── GST Rate Helper (DB-driven) ──────────────────────────────────────────
  
  /// Returns the GST rate for a given category.
  /// Reads from the `tax_config` DB cache if available.
  /// Falls back to the hardcoded `TaxConfig` rules.
  double getGstRate(String category, {double? itemPrice}) {
    if (_taxConfigCache.containsKey(category)) {
      final row = _taxConfigCache[category]!;
      // For price-slab categories, we use the DB's slab threshold/rate if present
      if ((category == 'Clothing' || category == 'Footwear') && itemPrice != null) {
        final thresholdRaw = row['slab_threshold'];
        final highRateRaw  = row['slab_high_rate'];
        
        final threshold = thresholdRaw != null 
            ? double.tryParse(thresholdRaw.toString()) ?? TaxConfig.defaultSlabThreshold
            : TaxConfig.defaultSlabThreshold;
            
        final highRate = highRateRaw != null
            ? double.tryParse(highRateRaw.toString()) ?? TaxConfig.defaultSlabHighRate
            : TaxConfig.defaultSlabHighRate;
            
        return itemPrice > threshold 
            ? highRate 
            : (double.tryParse(row['gst_rate'].toString()) ?? 0.05);
      }
      return double.tryParse(row['gst_rate'].toString()) ?? 0.18;
    }
    // Fallback to code defaults if DB row is missing entirely
    return TaxConfig.gstRateForCategory(category, itemPrice: itemPrice);
  }

  /// Returns whether a category is an Enything Deemed Supplier (S.9(5)).
  /// Reads from `tax_config` DB cache first, falls back to `TaxConfig` code default.
  bool getIsDeemedSupplier(String category) {
    if (_taxConfigCache.containsKey(category)) {
      final val = _taxConfigCache[category]!['is_deemed_supplier'];
      if (val != null) return val as bool;
    }
    return TaxConfig.isEnythingDeemedSupplier(category);
  }

  // ── Update Settings (Admin Only) ────────────────────────────
  Future<bool> updateSetting({
    required String key,
    required String value,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      if (value.isEmpty) {
        // Delete key (revert to default)
        final oldVal = _getValue(key);
        _removeValue(key);
        notifyListeners();

        await _db.from('platform_config').delete().eq('key', key);

        try {
          await _db.from('audit_logs').insert({
            'actor_id': actorId,
            'actor_role': actorRole,
            'action': 'delete_platform_config',
            'entity_type': 'platform_config',
            'entity_id': null,
            'metadata': {
              'key': key,
              'old_value': oldVal,
            },
          });
        } catch (_) {}

        return true;
      }

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

      await _sendConfigChangeNotification(key, oldVal.toString(), value);

      return true;
    } catch (e) {
      debugPrint('Failed to update setting $key: $e');
      // Reload from DB to fix optimistic update if it failed
      await load();
      return false;
    }
  }

  Future<void> _sendConfigChangeNotification(String key, String oldVal, String newVal) async {
    String? audience;
    String? title;
    String? body;

    if (key.startsWith('commission_percent')) {
      audience = 'Sellers';
      String catSuffix = '';
      if (key.startsWith('commission_percent_')) {
        catSuffix = ' for ${key.replaceFirst('commission_percent_', '')}';
      }
      title = '📢 Commission Rate Updated';
      body = 'Platform commission$catSuffix has changed from $oldVal% to $newVal%. '
             'New orders will use the updated rate.';
    } else {
      switch (key) {
        case 'platform_fee':
          audience = 'Customers';
          title = '📢 Handling Fee Updated';
          body = 'The platform handling fee is now ₹$newVal per order.';
          break;
      case 'delivery_rate_per_km':
        audience = 'Customers';
        title = '📢 Delivery Rates Updated';
        body = 'Delivery is now ₹$newVal/km. '
               'e.g. 3km = ₹${(3 * double.parse(newVal)).toStringAsFixed(0)}.';
        break;
      case 'max_delivery_radius_km':
        audience = 'All Users';
        title = '📢 Delivery Zone Expanded';
        body = 'We now deliver up to ${newVal}km from your location!';
        break;
      default:
        return;
      }
    }

    try {
      await _db.functions.invoke('send-broadcast', body: {
        'audience': audience,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('Config notification failed (non-fatal): $e');
    }
  }

  /// Per-km delivery charge: ceil(distanceKm) × ratePerKm.
  /// Returns -1 if beyond maxDeliveryRadiusKm.
  double calculateDeliveryCharge(double distanceKm) {
    if (distanceKm > _maxDeliveryRadiusKm) return -1;
    final km = distanceKm.ceil().clamp(1, _maxDeliveryRadiusKm.ceil().toInt());
    return km * _deliveryRatePerKm;
  }

  double _getValue(String key) {
    if (key.startsWith('commission_percent_')) {
      final cat = key.replaceFirst('commission_percent_', '');
      return _categoryCommissionOverrides[cat] ?? _commissionPercent;
    }
    switch (key) {
      case 'commission_percent': return _commissionPercent;
      case 'platform_fee': return _platformFee;
      case 'small_cart_fee': return _smallCartFee;
      case 'small_cart_threshold': return _smallCartThreshold;
      case 'heavy_order_fee': return _heavyOrderFee;
      case 'heavy_order_threshold_kg': return _heavyOrderThresholdKg;
      case 'max_delivery_radius_km': return _maxDeliveryRadiusKm;
      case 'delivery_rate_per_km': return _deliveryRatePerKm;
      case 'referral_bonus_amount': return _referralBonusAmount;
      case 'delivery_gst_rate': return _deliveryGstRate;
      case 'platform_fee_gst_rate': return _platformFeeGstRate;
      default: return 0.0;
    }
  }

  void _setValue(String key, double val) {
    if (key.startsWith('commission_percent_')) {
      final cat = key.replaceFirst('commission_percent_', '');
      _categoryCommissionOverrides[cat] = val;
      return;
    }
    switch (key) {
      case 'commission_percent': _commissionPercent = val; break;
      case 'platform_fee': _platformFee = val; break;
      case 'small_cart_fee': _smallCartFee = val; break;
      case 'small_cart_threshold': _smallCartThreshold = val; break;
      case 'heavy_order_fee': _heavyOrderFee = val; break;
      case 'heavy_order_threshold_kg': _heavyOrderThresholdKg = val; break;
      case 'max_delivery_radius_km': _maxDeliveryRadiusKm = val; break;
      case 'delivery_rate_per_km': _deliveryRatePerKm = val; break;
      case 'referral_bonus_amount': _referralBonusAmount = val; break;
      case 'delivery_gst_rate': _deliveryGstRate = val; break;
      case 'platform_fee_gst_rate': _platformFeeGstRate = val; break;
    }
  }

  void _removeValue(String key) {
    if (key.startsWith('commission_percent_')) {
      final cat = key.replaceFirst('commission_percent_', '');
      _categoryCommissionOverrides.remove(cat);
    }
  }
}
