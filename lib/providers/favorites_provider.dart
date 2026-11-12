import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';

class FavoritesProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  final SupabaseClient? _mockClient;

  FavoritesProvider({SupabaseClient? mockClient}) : _mockClient = mockClient;

  SupabaseClient get _supabase => _mockClient ?? Supabase.instance.client;

  // Storing sets of IDs for quick lookup
  final Set<String> _favoriteProductIds = {};
  final Set<String> _favoriteShopIds = {};

  // Full models cache for instant 0ms UI reflection
  final List<ProductModel> _favoriteProducts = [];
  final List<ShopModel> _favoriteShops = [];
  final Map<String, ShopModel> _productShops = {};

  // Queues to prevent race conditions on rapid toggles
  final Map<String, Future<void>> _productToggleQueues = {};
  final Map<String, Future<void>> _shopToggleQueues = {};

  bool _isLoading = false;

  Set<String> get favoriteProductIds => _favoriteProductIds;
  Set<String> get favoriteShopIds => _favoriteShopIds;
  List<ProductModel> get favoriteProducts =>
      List.unmodifiable(_favoriteProducts);
  List<ShopModel> get favoriteShops => List.unmodifiable(_favoriteShops);
  Map<String, ShopModel> get productShops => _productShops;
  bool get isLoading => _isLoading;

  bool isProductFavorite(String productId) =>
      _favoriteProductIds.contains(productId);
  bool isShopFavorite(String shopId) => _favoriteShopIds.contains(shopId);

  Future<void> fetchFavorites(String userId) async {
    _isLoading = true;
    safeNotifyListeners();

    try {
      final response = await _supabase
          .from('customer_favorites')
          .select('product_id, shop_id')
          .eq('customer_id', userId);

      _favoriteProductIds.clear();
      _favoriteShopIds.clear();

      for (var row in response) {
        if (row['product_id'] != null) {
          _favoriteProductIds.add(row['product_id']);
        }
        if (row['shop_id'] != null) {
          _favoriteShopIds.add(row['shop_id']);
        }
      }

      // 100x HYDRATION: Fetch full models in parallel
      await Future.wait([
        _hydrateProducts(),
        _hydrateShops(),
      ]);
    } catch (e) {
      debugPrint('Error fetching favorites: $e');
    } finally {
      _isLoading = false;
      safeNotifyListeners();
    }
  }

  Future<void> _hydrateProducts() async {
    if (_favoriteProductIds.isEmpty) {
      _favoriteProducts.clear();
      return;
    }
    try {
      final productRes = await _supabase
          .from('products')
          .select()
          .eq('is_deleted', false)
          .inFilter('id', _favoriteProductIds.toList())
          .limit(100);

      final fetched = (productRes as List)
          .map((p) => ProductModel.fromMap(p))
          .toList();

      _favoriteProducts.clear();
      _favoriteProducts.addAll(fetched);

      // Hydrate missing shops for these products
      final missingShopIds = _favoriteProducts
          .map((p) => p.shopId)
          .where((id) => id.isNotEmpty && !_productShops.containsKey(id))
          .toSet()
          .toList();

      if (missingShopIds.isNotEmpty) {
        final shopsRes = await _supabase
            .from('shops')
            .select()
            .inFilter('id', missingShopIds);
        for (final s in (shopsRes as List)) {
          final sm = ShopModel.fromMap(s);
          _productShops[sm.id] = sm;
        }
      }
    } catch (e) {
      debugPrint('Error hydrating favorite products: $e');
    }
  }

  Future<void> _hydrateShops() async {
    if (_favoriteShopIds.isEmpty) {
      _favoriteShops.clear();
      return;
    }
    try {
      final shopRes = await _supabase
          .from('shops')
          .select()
          .inFilter('id', _favoriteShopIds.toList())
          .limit(100);

      final fetched =
          (shopRes as List).map((s) => ShopModel.fromMap(s)).toList();

      _favoriteShops.clear();
      _favoriteShops.addAll(fetched);
    } catch (e) {
      debugPrint('Error hydrating favorite shops: $e');
    }
  }

  Future<void> toggleProductFavorite(String userId, String productId,
      {ProductModel? product, ShopModel? shop}) async {
    final prevFuture = _productToggleQueues[productId] ?? Future.value();

    _productToggleQueues[productId] = prevFuture.then((_) async {
      final isFav = isProductFavorite(productId);

      // Optimistic UI update
      ProductModel? removedProduct;
      if (isFav) {
        _favoriteProductIds.remove(productId);
        final idx = _favoriteProducts.indexWhere((p) => p.id == productId);
        if (idx != -1) {
          removedProduct = _favoriteProducts.removeAt(idx);
        }
      } else {
        _favoriteProductIds.add(productId);
        if (product != null) {
          if (!_favoriteProducts.any((p) => p.id == productId)) {
            _favoriteProducts.insert(0, product);
          }
          if (shop != null) {
            _productShops[product.shopId] = shop;
          }
        }
      }
      safeNotifyListeners();

      // If product model was not provided when adding, fetch it in background
      if (!isFav && product == null) {
        try {
          final res = await _supabase
              .from('products')
              .select()
              .eq('id', productId)
              .eq('is_deleted', false)
              .maybeSingle();
          if (res != null) {
            final pm = ProductModel.fromMap(res);
            if (!_favoriteProducts.any((p) => p.id == productId) &&
                _favoriteProductIds.contains(productId)) {
              _favoriteProducts.insert(0, pm);
              if (!_productShops.containsKey(pm.shopId)) {
                final sRes = await _supabase
                    .from('shops')
                    .select()
                    .eq('id', pm.shopId)
                    .maybeSingle();
                if (sRes != null) {
                  _productShops[pm.shopId] = ShopModel.fromMap(sRes);
                }
              }
              safeNotifyListeners();
            }
          }
        } catch (e) {
          debugPrint('Error background-fetching product $productId: $e');
        }
      }

      try {
        if (isFav) {
          // Remove from DB
          await _supabase
              .from('customer_favorites')
              .delete()
              .eq('customer_id', userId)
              .eq('product_id', productId);
        } else {
          // Add to DB
          await _supabase.from('customer_favorites').insert({
            'customer_id': userId,
            'product_id': productId,
          });
        }
      } catch (e) {
        debugPrint('Error toggling product favorite: $e');
        // Revert on failure
        if (isFav) {
          _favoriteProductIds.add(productId);
          if (removedProduct != null &&
              !_favoriteProducts.any((p) => p.id == productId)) {
            _favoriteProducts.add(removedProduct);
          }
        } else {
          _favoriteProductIds.remove(productId);
          _favoriteProducts.removeWhere((p) => p.id == productId);
        }
        safeNotifyListeners();
      }
    });

    await _productToggleQueues[productId];
  }

  Future<void> toggleShopFavorite(String userId, String shopId,
      {ShopModel? shop}) async {
    final prevFuture = _shopToggleQueues[shopId] ?? Future.value();

    _shopToggleQueues[shopId] = prevFuture.then((_) async {
      final isFav = isShopFavorite(shopId);

      // Optimistic UI update
      ShopModel? removedShop;
      if (isFav) {
        _favoriteShopIds.remove(shopId);
        final idx = _favoriteShops.indexWhere((s) => s.id == shopId);
        if (idx != -1) {
          removedShop = _favoriteShops.removeAt(idx);
        }
      } else {
        _favoriteShopIds.add(shopId);
        if (shop != null) {
          if (!_favoriteShops.any((s) => s.id == shopId)) {
            _favoriteShops.insert(0, shop);
          }
        }
      }
      safeNotifyListeners();

      // If shop model was not provided when adding, fetch it in background
      if (!isFav && shop == null) {
        try {
          final res = await _supabase
              .from('shops')
              .select()
              .eq('id', shopId)
              .maybeSingle();
          if (res != null) {
            final sm = ShopModel.fromMap(res);
            if (!_favoriteShops.any((s) => s.id == shopId) &&
                _favoriteShopIds.contains(shopId)) {
              _favoriteShops.insert(0, sm);
              safeNotifyListeners();
            }
          }
        } catch (e) {
          debugPrint('Error background-fetching shop $shopId: $e');
        }
      }

      try {
        if (isFav) {
          // Remove from DB
          await _supabase
              .from('customer_favorites')
              .delete()
              .eq('customer_id', userId)
              .eq('shop_id', shopId);
        } else {
          // Add to DB
          await _supabase.from('customer_favorites').insert({
            'customer_id': userId,
            'shop_id': shopId,
          });
        }
      } catch (e) {
        debugPrint('Error toggling shop favorite: $e');
        // Revert on failure
        if (isFav) {
          _favoriteShopIds.add(shopId);
          if (removedShop != null &&
              !_favoriteShops.any((s) => s.id == shopId)) {
            _favoriteShops.add(removedShop);
          }
        } else {
          _favoriteShopIds.remove(shopId);
          _favoriteShops.removeWhere((s) => s.id == shopId);
        }
        safeNotifyListeners();
      }
    });

    await _shopToggleQueues[shopId];
  }

  void clear() {
    _favoriteProductIds.clear();
    _favoriteShopIds.clear();
    _favoriteProducts.clear();
    _favoriteShops.clear();
    _productShops.clear();
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
