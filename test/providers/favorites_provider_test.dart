import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/providers/favorites_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeSupabaseClient implements SupabaseClient {
  @override
  SupabaseQueryBuilder from(String table) => FakeQueryBuilder();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryBuilder implements SupabaseQueryBuilder {
  @override
  PostgrestFilterBuilder<dynamic> delete() => FakeFilterBuilder();
  @override
  PostgrestFilterBuilder<dynamic> insert(Object values, {bool defaultToNull = true}) => FakeFilterBuilder();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFilterBuilder implements PostgrestFilterBuilder<dynamic> {
  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) => this;
  @override
  Future<U> then<U>(FutureOr<U> Function(dynamic value) onValue, {Function? onError}) async {
    return onValue([]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('FavoritesProvider Tests', () {
    late FavoritesProvider favoritesProvider;
    late FakeSupabaseClient fakeClient;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeClient = FakeSupabaseClient();
      favoritesProvider = FavoritesProvider(mockClient: fakeClient);
    });

    test('Initial state is empty', () {
      expect(favoritesProvider.favoriteShopIds.isEmpty, true);
      expect(favoritesProvider.favoriteProductIds.isEmpty, true);
    });

    test('Can toggle shop favorite locally', () async {
      // Toggle ON
      await favoritesProvider.toggleShopFavorite('user_1', 'shop_1');
      expect(favoritesProvider.isShopFavorite('shop_1'), true);
      
      // Toggle OFF
      await favoritesProvider.toggleShopFavorite('user_1', 'shop_1');
      expect(favoritesProvider.isShopFavorite('shop_1'), false);
    });

    test('Can toggle product favorite locally', () async {
      // Toggle ON
      await favoritesProvider.toggleProductFavorite('user_1', 'prod_1');
      expect(favoritesProvider.isProductFavorite('prod_1'), true);
      
      // Toggle OFF
      await favoritesProvider.toggleProductFavorite('user_1', 'prod_1');
      expect(favoritesProvider.isProductFavorite('prod_1'), false);
    });
  });
}
