import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesProvider extends ChangeNotifier {
  SupabaseClient get _supabase => Supabase.instance.client;

  // Storing sets of IDs for quick lookup
  final Set<String> _favoriteProductIds = {};
  final Set<String> _favoriteShopIds = {};

  bool _isLoading = false;

  Set<String> get favoriteProductIds => _favoriteProductIds;
  Set<String> get favoriteShopIds => _favoriteShopIds;
  bool get isLoading => _isLoading;

  bool isProductFavorite(String productId) => _favoriteProductIds.contains(productId);
  bool isShopFavorite(String shopId) => _favoriteShopIds.contains(shopId);

  Future<void> fetchFavorites(String userId) async {
    _isLoading = true;
    notifyListeners();

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
    } catch (e) {
      debugPrint('Error fetching favorites: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleProductFavorite(String userId, String productId) async {
    final isFav = isProductFavorite(productId);

    // Optimistic UI update
    if (isFav) {
      _favoriteProductIds.remove(productId);
    } else {
      _favoriteProductIds.add(productId);
    }
    notifyListeners();

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
      } else {
        _favoriteProductIds.remove(productId);
      }
      notifyListeners();
    }
  }

  Future<void> toggleShopFavorite(String userId, String shopId) async {
    final isFav = isShopFavorite(shopId);

    // Optimistic UI update
    if (isFav) {
      _favoriteShopIds.remove(shopId);
    } else {
      _favoriteShopIds.add(shopId);
    }
    notifyListeners();

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
      } else {
        _favoriteShopIds.remove(shopId);
      }
      notifyListeners();
    }
  }
  
  void clear() {
    _favoriteProductIds.clear();
    _favoriteShopIds.clear();
    notifyListeners();
  }
}
