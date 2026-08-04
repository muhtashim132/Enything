import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_categories.dart';
import '../config/tax_config.dart';

class PlatformConfigProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  static PlatformConfigProvider? instance;

  SupabaseClient get _db => Supabase.instance.client;

  PlatformConfigProvider() {
    instance = this;
  }

  // ── Defaults (matches hardcoded constants initially) ────────
  double _commissionPercent = 5.0;
  double _platformFee = 20.0;
  double _smallCartFee = 15.0;
  double _smallCartThreshold = 99.0;
  double _heavyOrderFee = 25.0;
  double _multiShopSurcharge = 20.0;
  double _riderCommissionPercent = 80.0;
  double _riderNotificationRadiusKm = 15.0;
  double _heavyOrderThresholdKg = 10.0;
  double _maxDeliveryRadiusKm = 15.0;
  double _deliveryRatePerKm = 10.0;
  double _referralBonusAmount = 50.0;
  double _deliveryGstRate = 0.18;
  double _platformFeeGstRate = 0.18;
  double _waitPenaltyPerMin = 2.0;

  final Map<String, double> _categoryCommissionOverrides = {};
  final Map<String, double> _categoryWaitPenaltyOverrides = {};

  // Cache for tax_config table (category -> row data)
  final Map<String, Map<String, dynamic>> _taxConfigCache = {};

  // ── Category Management (Additive) ──────────────────────────────────────
  /// Set of category names that the admin has disabled.
  final Set<String> _disabledCategories = {};

  /// Admin-created custom categories from the `custom_categories` DB table.
  final List<Map<String, String>> _customCategories = [];

  RealtimeChannel? _platformConfigChannel;
  RealtimeChannel? _taxConfigChannel;
  RealtimeChannel? _customCategoriesChannel;
  Timer? _debounceTimer;

  bool _loading = false;
  bool _isFirstLoad = true;
  String? _error;

  void _debouncedNotifyListeners() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      safeNotifyListeners();
    });
  }

  // ── Category Management Getters (Additive) ──────────────────────────────

  /// Returns true if this category is currently active (not disabled by admin).
  bool isActiveCategory(String name) => !_disabledCategories.contains(name);

  /// All disabled category names.
  Set<String> get disabledCategories => Set.unmodifiable(_disabledCategories);

  /// Returns all active built-in category maps (filtered by disabled set).
  List<Map<String, String>> get activeCategoryMaps {
    final builtIn = AppCategories.all
        .where((c) => !_disabledCategories.contains(c['name']))
        .toList();
    final custom = _customCategories
        .where((c) => !_disabledCategories.contains(c['name']))
        .toList();
    return [...builtIn, ...custom];
  }

  /// All category maps regardless of active status (for admin pages).
  List<Map<String, String>> get allCategoryMaps {
    return [...AppCategories.all, ..._customCategories];
  }

  /// Active category names (for filtering DB queries).
  List<String> get activeCategoryNames =>
      activeCategoryMaps.map((c) => c['name']!).toList();

  /// All category names including custom (for admin commission/tax pages).
  List<String> get allCategoryNames =>
      allCategoryMaps.map((c) => c['name']!).toList();

  /// Custom categories created by admin.
  List<Map<String, String>> get customCategories =>
      List.unmodifiable(_customCategories);

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
  double get multiShopSurcharge => _multiShopSurcharge;
  double get riderCommissionPercent => _riderCommissionPercent;
  double get riderNotificationRadiusKm => _riderNotificationRadiusKm;
  double get heavyOrderThresholdKg => _heavyOrderThresholdKg;
  double get maxDeliveryRadiusKm => _maxDeliveryRadiusKm;
  double get deliveryRatePerKm => _deliveryRatePerKm;
  double get referralBonusAmount => _referralBonusAmount;
  double get deliveryGstRate => _deliveryGstRate;
  double get platformFeeGstRate => _platformFeeGstRate;
  double get waitPenaltyPerMin => _waitPenaltyPerMin;

  double getWaitPenaltyRateForCategory(String category) {
    return _categoryWaitPenaltyOverrides[category] ?? _waitPenaltyPerMin;
  }

  bool get loading => _loading;
  String? get error => _error;

  // ── Load Settings ────────────────────────────────────────────
  Future<void> load({int maxRetries = 3}) async {
    if (_loading) return; // Prevent concurrent loops

    // Always guarantee subscriptions boot up first so network recovery can be caught!
    _setupRealtimeSubscriptions();

    int attempts = 0;
    while (attempts < maxRetries) {
      _loading = true;
      _error = null;
      safeNotifyListeners();

      try {
        final data = await _db.from('platform_config').select('key, value');
        for (final row in (data as List)) {
          final key = row['key'] as String;
          final valRaw = row['value'];
          final val = double.tryParse(valRaw.toString()) ?? 0.0;

          switch (key) {
            case 'commission_percent':
            case 'default_commission_percent':
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
            case 'heavy_order_fee_per_kg':
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
            case 'wait_penalty_per_min':
              _waitPenaltyPerMin = val;
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
            case 'multi_shop_surcharge':
              _multiShopSurcharge = val;
              break;
            case 'rider_commission_percent':
              _riderCommissionPercent = val;
              break;
            case 'rider_notification_radius_km':
              _riderNotificationRadiusKm = val;
              break;
          }

          if (key.startsWith('commission_percent_')) {
            final category = key.replaceFirst('commission_percent_', '');
            _categoryCommissionOverrides[category] = val;
          }

          if (key.startsWith('wait_penalty_per_min_')) {
            final category = key.replaceFirst('wait_penalty_per_min_', '');
            _categoryWaitPenaltyOverrides[category] = val;
          }
        }

        // ── Load Tax Config ──────────────────────────────────────────
        final taxData = await _db.from('tax_config').select();
        _taxConfigCache.clear();
        for (final row in (taxData as List)) {
          _taxConfigCache[row['category'] as String] =
              Map<String, dynamic>.from(row);
        }

        // ── Load Disabled Categories (Additive) ───────────────────────
        // Key stored as 'disabled_categories' with JSON array value e.g. '[]'
        try {
          final dcRow = await _db
              .from('platform_config')
              .select('value')
              .eq('key', 'disabled_categories')
              .maybeSingle();
          _disabledCategories.clear();
          if (dcRow != null && dcRow['value'] != null) {
            final decoded = jsonDecode(dcRow['value'].toString());
            if (decoded is List) {
              _disabledCategories.addAll(decoded.map((e) => e.toString()));
            }
          }
        } catch (e) {
          debugPrint('[CategoryMgmt] Could not load disabled_categories: $e');
        }

        // ── Load Custom Categories (Additive) ────────────────────────
        await _loadCustomCategories();

        _loading = false;
        _isFirstLoad = false;
        safeNotifyListeners();
        return; // Success
      } catch (e) {
        attempts++;
        debugPrint('Failed to load platform config (Attempt $attempts): $e');
        if (attempts >= maxRetries) {
          _error =
              'No internet connection. Using offline pricing. Prices will update automatically when connection is restored.';
          _loading = false;
          safeNotifyListeners();
        } else {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  void _handleReconnect(RealtimeSubscribeStatus status, [Object? error]) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      if (_isFirstLoad) return;
      final jitterMs = Random().nextInt(3000);
      Future.delayed(Duration(milliseconds: jitterMs), () => load());
    }
  }

  void _setupRealtimeSubscriptions() {
    _platformConfigChannel ??= _db
        .channel('public:platform_config')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'platform_config',
          callback: (payload) {
            final newRow = payload.newRecord;
            if (newRow.isNotEmpty) {
              final key = newRow['key'] as String;
              final valRaw = newRow['value'];
              if (key == 'disabled_categories') {
                try {
                  final decoded = jsonDecode(valRaw.toString());
                  if (decoded is List) {
                    _disabledCategories.clear();
                    _disabledCategories.addAll(decoded.map((e) => e.toString()));
                  }
                } catch (e) {
                  debugPrint('[CategoryMgmt] realtime disabled_categories parse error: $e');
                }
              } else {
                final val = double.tryParse(valRaw.toString()) ?? 0.0;
                _setValue(key, val);
              }
            } else if (payload.oldRecord.isNotEmpty) {
              final key = payload.oldRecord['key'] as String;
              _removeValue(key);
            }
            _debouncedNotifyListeners();
          },
        )
        .subscribe(_handleReconnect);

    _taxConfigChannel ??= _db
        .channel('public:tax_config')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tax_config',
          callback: (payload) {
            final newRow = payload.newRecord;
            if (newRow.isNotEmpty) {
              _taxConfigCache[newRow['category'] as String] =
                  Map<String, dynamic>.from(newRow);
            } else if (payload.oldRecord.isNotEmpty) {
              _taxConfigCache.remove(payload.oldRecord['category'] as String);
            }
            _debouncedNotifyListeners();
          },
        )
        .subscribe(_handleReconnect);

    // ── Realtime: custom_categories (Additive) ───────────────────
    _customCategoriesChannel ??= _db
        .channel('public:custom_categories')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'custom_categories',
          callback: (_) async {
            await _loadCustomCategories();
            _debouncedNotifyListeners();
          },
        )
        .subscribe(_handleReconnect);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    if (_platformConfigChannel != null) {
      _db.removeChannel(_platformConfigChannel!);
    }
    if (_taxConfigChannel != null) _db.removeChannel(_taxConfigChannel!);
    if (_customCategoriesChannel != null) {
      _db.removeChannel(_customCategoriesChannel!);
    }
    super.dispose();
  }

  // ── Category Management Helpers (Additive) ────────────────────────────────

  Future<void> _loadCustomCategories() async {
    try {
      final rows = await _db
          .from('custom_categories')
          .select('name, emoji, category_group, image_url')
          .order('sort_order');
      _customCategories.clear();
      for (final row in rows as List) {
        _customCategories.add({
          'name': row['name']?.toString() ?? '',
          'emoji': row['emoji']?.toString() ?? '🏪',
          'group': row['category_group']?.toString() ?? 'retail',
          'image': row['image_url']?.toString() ?? '',
        });
      }
    } catch (e) {
      debugPrint('[CategoryMgmt] Could not load custom_categories: $e');
    }
  }

  /// Toggle a category enabled/disabled.
  /// [categoryName] — the exact name string.
  /// Returns true on success.
  Future<bool> toggleCategory(String categoryName) async {
    try {
      final wasDisabled = _disabledCategories.contains(categoryName);
      if (wasDisabled) {
        _disabledCategories.remove(categoryName);
      } else {
        _disabledCategories.add(categoryName);
      }
      safeNotifyListeners();

      // Persist to platform_config as JSON array
      final actorId = _db.auth.currentUser?.id;
      final jsonVal = jsonEncode(_disabledCategories.toList());
      await _db.from('platform_config').upsert(
        {
          'key': 'disabled_categories',
          'value': jsonVal,
          if (actorId != null) 'updated_by': actorId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'key',
      );
      return true;
    } catch (e) {
      debugPrint('[CategoryMgmt] toggleCategory error: $e');
      // Rollback optimistic update
      if (_disabledCategories.contains(categoryName)) {
        _disabledCategories.remove(categoryName);
      } else {
        _disabledCategories.add(categoryName);
      }
      safeNotifyListeners();
      return false;
    }
  }

  /// Create a new admin category.
  Future<bool> createCategory({
    required String name,
    required String emoji,
    required String group,
    String? imageUrl,
  }) async {
    try {
      final userId = _db.auth.currentUser?.id;
      await _db.from('custom_categories').insert({
        'name': name.trim(),
        'emoji': emoji.trim(),
        'category_group': group,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (userId != null) 'created_by': userId,
      });
      await _loadCustomCategories();
      safeNotifyListeners();
      return true;
    } catch (e) {
      debugPrint('[CategoryMgmt] createCategory error: $e');
      return false;
    }
  }

  /// Delete a custom (admin-created) category by name.
  Future<bool> deleteCustomCategory(String name) async {
    try {
      await _db.from('custom_categories').delete().eq('name', name);
      _customCategories.removeWhere((c) => c['name'] == name);
      _disabledCategories.remove(name); // clean up disabled set too
      safeNotifyListeners();
      return true;
    } catch (e) {
      debugPrint('[CategoryMgmt] deleteCustomCategory error: $e');
      return false;
    }
  }

  /// Returns shop counts per category from the DB (used by admin page).
  Future<Map<String, int>> getCategoryShopCounts() async {
    try {
      final rows = await _db.rpc('get_category_shop_counts');
      final result = <String, int>{};
      for (final row in rows as List) {
        result[row['category']?.toString() ?? ''] =
            (row['shop_count'] as num?)?.toInt() ?? 0;
      }
      return result;
    } catch (e) {
      debugPrint('[CategoryMgmt] getCategoryShopCounts error: $e');
      return {};
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
      if ((category == 'Clothing' || category == 'Footwear') &&
          itemPrice != null) {
        final thresholdRaw = row['slab_threshold'];
        final highRateRaw = row['slab_high_rate'];

        final threshold = thresholdRaw != null
            ? double.tryParse(thresholdRaw.toString()) ??
                TaxConfig.defaultSlabThreshold
            : TaxConfig.defaultSlabThreshold;

        final highRate = highRateRaw != null
            ? double.tryParse(highRateRaw.toString()) ??
                TaxConfig.defaultSlabHighRate
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
        safeNotifyListeners();

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

      // Phase 12 Fix: Prevent negative values or absurdly large values
      if (doubleVal < 0 || doubleVal > 1000000) {
        debugPrint('Invalid boundary for $key: $value');
        return false;
      }

      final oldVal = _getValue(key);
      _setValue(key, doubleVal);
      safeNotifyListeners();

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

  Future<void> _sendConfigChangeNotification(
      String key, String oldVal, String newVal) async {
    String? audience;
    String? title;
    String? body;

    if (key.startsWith('commission_percent') ||
        key.startsWith('default_commission_percent')) {
      audience = 'Sellers';
      String catSuffix = '';
      if (key.startsWith('commission_percent_')) {
        catSuffix = ' for ${key.replaceFirst('commission_percent_', '')}';
      }
      title = '📢 Commission Rate Updated';
      body =
          'Platform commission$catSuffix has changed from $oldVal% to $newVal%. '
          'New orders will use the updated rate.';
    } else if (key.startsWith('wait_penalty_per_min')) {
      String catSuffix = '';
      if (key.startsWith('wait_penalty_per_min_')) {
        catSuffix = ' for ${key.replaceFirst('wait_penalty_per_min_', '')}';
      }
      title = '⏱️ Wait Penalty Updated';
      body =
          'Wait penalty rate$catSuffix has changed from ₹$oldVal/min to ₹$newVal/min.';
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
        case 'rider_notification_radius_km':
          audience = 'Delivery Partners';
          title = '📢 Notification Radius Updated';
          body =
              'You will now receive order alerts up to ${newVal}km from your location.';
          break;
        case 'rider_commission_percent':
          audience = 'Delivery Partners';
          title = '📢 Rider Earnings Updated';
          body = 'Your payout commission has been adjusted to $newVal%.';
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
    if (key.startsWith('wait_penalty_per_min_')) {
      final cat = key.replaceFirst('wait_penalty_per_min_', '');
      return _categoryWaitPenaltyOverrides[cat] ?? _waitPenaltyPerMin;
    }
    switch (key) {
      case 'default_commission_percent':
        return _commissionPercent;
      case 'commission_percent':
        return _commissionPercent; // Legacy
      case 'wait_penalty_per_min':
        return _waitPenaltyPerMin;
      case 'platform_fee':
        return _platformFee;
      case 'small_cart_fee':
        return _smallCartFee;
      case 'small_cart_threshold':
        return _smallCartThreshold;
      case 'heavy_order_fee':
        return _heavyOrderFee;
      case 'heavy_order_fee_per_kg':
        return _heavyOrderFee; // Legacy
      case 'multi_shop_surcharge':
        return _multiShopSurcharge;
      case 'rider_commission_percent':
        return _riderCommissionPercent;
      case 'rider_notification_radius_km':
        return _riderNotificationRadiusKm;
      case 'heavy_order_threshold_kg':
        return _heavyOrderThresholdKg;
      case 'max_delivery_radius_km':
        return _maxDeliveryRadiusKm;
      case 'delivery_rate_per_km':
        return _deliveryRatePerKm;
      case 'referral_bonus_amount':
        return _referralBonusAmount;
      case 'delivery_gst_rate':
        return _deliveryGstRate;
      case 'platform_fee_gst_rate':
        return _platformFeeGstRate;
      default:
        return 0.0;
    }
  }

  void _setValue(String key, double val) {
    if (key.startsWith('commission_percent_')) {
      final cat = key.replaceFirst('commission_percent_', '');
      _categoryCommissionOverrides[cat] = val;
      safeNotifyListeners();
      return;
    }
    if (key.startsWith('wait_penalty_per_min_')) {
      final cat = key.replaceFirst('wait_penalty_per_min_', '');
      _categoryWaitPenaltyOverrides[cat] = val;
      safeNotifyListeners();
      return;
    }
    switch (key) {
      case 'default_commission_percent':
        _commissionPercent = val;
        break;
      case 'commission_percent':
        _commissionPercent = val;
        break; // Legacy
      case 'wait_penalty_per_min':
        _waitPenaltyPerMin = val;
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
      case 'heavy_order_fee_per_kg':
        _heavyOrderFee = val;
        break; // Legacy
      case 'multi_shop_surcharge':
        _multiShopSurcharge = val;
        break;
      case 'rider_commission_percent':
        _riderCommissionPercent = val;
        break;
      case 'rider_notification_radius_km':
        _riderNotificationRadiusKm = val;
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
  }

  void _removeValue(String key) {
    if (key.startsWith('commission_percent_')) {
      final cat = key.replaceFirst('commission_percent_', '');
      _categoryCommissionOverrides.remove(cat);
      return;
    }
    if (key.startsWith('wait_penalty_per_min_')) {
      final cat = key.replaceFirst('wait_penalty_per_min_', '');
      _categoryWaitPenaltyOverrides.remove(cat);
      return;
    }

    // Reset base configurations to default if deleted
    switch (key) {
      case 'default_commission_percent':
        _commissionPercent = 10.0;
        break;
      case 'commission_percent':
        _commissionPercent = 10.0;
        break; // Legacy
      case 'wait_penalty_per_min':
        _waitPenaltyPerMin = 2.0;
        break;
      case 'platform_fee':
        _platformFee = 15.0;
        break;
      case 'small_cart_fee':
        _smallCartFee = 15.0;
        break;
      case 'small_cart_threshold':
        _smallCartThreshold = 99.0;
        break;
      case 'heavy_order_fee':
        _heavyOrderFee = 25.0;
        break;
      case 'heavy_order_fee_per_kg':
        _heavyOrderFee = 25.0;
        break; // Legacy
      case 'multi_shop_surcharge':
        _multiShopSurcharge = 20.0;
        break;
      case 'rider_commission_percent':
        _riderCommissionPercent = 80.0;
        break;
      case 'rider_notification_radius_km':
        _riderNotificationRadiusKm = 15.0;
        break;
      case 'heavy_order_threshold_kg':
        _heavyOrderThresholdKg = 10.0;
        break;
      case 'max_delivery_radius_km':
        _maxDeliveryRadiusKm = 15.0;
        break;
      case 'delivery_rate_per_km':
        _deliveryRatePerKm = 10.0;
        break;
      case 'referral_bonus_amount':
        _referralBonusAmount = 50.0;
        break;
      case 'delivery_gst_rate':
        _deliveryGstRate = 0.18;
        break;
      case 'platform_fee_gst_rate':
        _platformFeeGstRate = 0.18;
        break;
    }
  }
}
