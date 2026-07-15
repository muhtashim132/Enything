import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

class RecentlyViewedProvider extends ChangeNotifier {
  static const _key = 'recently_viewed_ids';
  static const _maxItems = 50;

  SupabaseClient get _supabase => Supabase.instance.client;

  List<String> _ids = [];         // ordered list of product IDs (most recent first)
  List<ProductModel> _products = [];
  bool _isLoading = false;
  bool _loadedAll = false;

  List<ProductModel> get products => _products;
  bool get isLoading => _isLoading;
  bool get hasItems => _products.isNotEmpty;
  int get totalIdsCount => _ids.length;

  // Called at startup to restore persisted IDs and fetch product data
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = prefs.getStringList(_key) ?? [];
    if (_ids.isNotEmpty) await _fetchProducts();

    // ── FIX: Session Contamination Guard ──
    // Clear recently viewed items instantly when the user signs out
    // to prevent browsing history leaking to the next user on this device.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        clear();
      }
    });
  }

  // Call when a product detail sheet is opened
  Future<void> addProduct(String productId) async {
    // Deduplicate: remove if already present, then insert at front
    _ids.remove(productId);
    _ids.insert(0, productId);

    // Cap to max
    if (_ids.length > _maxItems) {
      _ids = _ids.take(_maxItems).toList();
    }

    // Persist
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids);

    // Refresh product data (non-blocking)
    await _fetchProducts(loadAll: _loadedAll);
  }

  Future<void> loadAll() async {
    if (_loadedAll || _ids.length <= 6) return;
    await _fetchProducts(loadAll: true);
  }

  Future<void> _fetchProducts({bool loadAll = false}) async {
    if (_ids.isEmpty) {
      _products = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final idsToFetch = loadAll ? _ids : _ids.take(6).toList();

      final data = await _supabase
          .from('products')
          .select()
          .inFilter('id', idsToFetch)
          .eq('is_available', true)
          .limit(loadAll ? 50 : 6);

      final fetched = (data as List)
          .map((p) => ProductModel.fromMap(p))
          .toList();

      // Preserve the order matching idsToFetch
      final productMap = {for (final p in fetched) p.id: p};
      _products = idsToFetch
          .map((id) => productMap[id])
          .whereType<ProductModel>()
          .toList();
          
      _loadedAll = loadAll;

      // Prune IDs that were not found in the database ONLY if we loaded all
      if (loadAll) {
        final validIds = _products.map((p) => p.id).toList();
        if (validIds.length != _ids.length) {
          _ids = validIds;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(_key, _ids);
        }
      }

      // Self-healing fallback: If we fetched a subset and all were invalid, 
      // escalate to full fetch to find remaining valid items (prevent pixel blindness).
      if (_products.isEmpty && !loadAll && _ids.isNotEmpty) {
        _isLoading = false; // Prevent infinite loop of loading state if calling again
        await _fetchProducts(loadAll: true);
        return;
      }
    } catch (_) {
      // Non-fatal: silently fail; home page will just not show this section
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _ids = [];
    _products = [];
    _loadedAll = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }
}
