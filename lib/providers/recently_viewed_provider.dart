import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

class RecentlyViewedProvider extends ChangeNotifier {
  static const _key = 'recently_viewed_ids';
  static const _maxItems = 10;

  SupabaseClient get _supabase => Supabase.instance.client;

  List<String> _ids = [];         // ordered list of product IDs (most recent first)
  List<ProductModel> _products = [];
  bool _isLoading = false;

  List<ProductModel> get products => _products;
  bool get isLoading => _isLoading;
  bool get hasItems => _products.isNotEmpty;

  // Called at startup to restore persisted IDs and fetch product data
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = prefs.getStringList(_key) ?? [];
    if (_ids.isNotEmpty) await _fetchProducts();
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
    await _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    if (_ids.isEmpty) {
      _products = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _supabase
          .from('products')
          .select()
          .inFilter('id', _ids)
          .eq('is_available', true)
          .limit(50);

      final fetched = (data as List)
          .map((p) => ProductModel.fromMap(p))
          .toList();

      // Preserve the order matching _ids
      final productMap = {for (final p in fetched) p.id: p};
      _products = _ids
          .map((id) => productMap[id])
          .whereType<ProductModel>()
          .toList();
          
      // Prune IDs that were not found in the database (deleted or inactive)
      final validIds = _products.map((p) => p.id).toList();
      if (validIds.length != _ids.length) {
        _ids = validIds;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_key, _ids);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }
}
