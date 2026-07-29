import 'dart:io';

void main() {
  final checkoutFile = File(
      'e:/Enything/supabase/migrations/20260896000000_100x_unauthenticated_ghost_order_ddos.sql');
  final getNearbyShopsCatsFile = File(
      'e:/Enything/supabase/migrations/20260850000000_get_nearby_shops_categories.sql');
  final geospatialLimitsFile = File(
      'e:/Enything/supabase/migrations/20260820000000_geospatial_limit_caps.sql');
  final trendingFile = File(
      'e:/Enything/supabase/migrations/20271124000001_get_trending_keywords_geospatial.sql');

  String checkoutSql = checkoutFile.readAsStringSync();
  String nearbyShopsSql = getNearbyShopsCatsFile.readAsStringSync();
  String geospatialSql = geospatialLimitsFile.readAsStringSync();
  String trendingSql = trendingFile.readAsStringSync();

  final outSql = StringBuffer();
  outSql.writeln(
      '-- =============================================================================');
  outSql.writeln(
      '-- Migration: 20271124000002_100x_geospatial_admin_radius_fortress.sql');
  outSql.writeln(
      '-- Description: Enforces the admin-defined `max_delivery_radius_km` limit');
  outSql.writeln(
      '--              from `platform_config` across all geospatial and checkout RPCs.');
  outSql.writeln(
      '--              Prevents users from bypassing radius limits via distance spoofing.');
  outSql.writeln(
      '-- =============================================================================');
  outSql.writeln('');

  const radiusLogicPlpgsql = '''
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
''';

  // 1. get_nearby_shops
  final nearbyMatch = RegExp(
          r'CREATE OR REPLACE FUNCTION public\.get_nearby_shops.*?BEGIN',
          dotAll: true)
      .firstMatch(nearbyShopsSql);
  if (nearbyMatch != null) {
    final funcDef = nearbyMatch.group(0)!;
    final rest = nearbyShopsSql.substring(nearbyMatch.end);
    final endIndex = rest.indexOf(r'$$ LANGUAGE plpgsql SECURITY DEFINER;');
    final body = rest.substring(
        0, endIndex + r'$$ LANGUAGE plpgsql SECURITY DEFINER;'.length);

    outSql.writeln('-- 1. get_nearby_shops');
    outSql.writeln(funcDef.replaceFirst('BEGIN', radiusLogicPlpgsql));
    outSql.writeln(body);
    outSql.writeln('');
  }

  // 2. search_shops_geospatial
  final searchShopsMatch = RegExp(
          r'CREATE OR REPLACE FUNCTION public\.search_shops_geospatial.*?BEGIN',
          dotAll: true)
      .firstMatch(geospatialSql);
  if (searchShopsMatch != null) {
    final funcDef = searchShopsMatch.group(0)!;
    final rest = geospatialSql.substring(searchShopsMatch.end);
    final endIndex = rest.indexOf(r'$$ LANGUAGE plpgsql SECURITY DEFINER;');
    final body = rest.substring(
        0, endIndex + r'$$ LANGUAGE plpgsql SECURITY DEFINER;'.length);

    outSql.writeln('-- 2. search_shops_geospatial');
    outSql.writeln(funcDef.replaceFirst('BEGIN', radiusLogicPlpgsql));
    outSql.writeln(body);
    outSql.writeln('');
  }

  // 3. search_products_geospatial
  final searchProductsMatch = RegExp(
          r'CREATE OR REPLACE FUNCTION public\.search_products_geospatial.*?BEGIN',
          dotAll: true)
      .firstMatch(geospatialSql);
  if (searchProductsMatch != null) {
    final funcDef = searchProductsMatch.group(0)!;
    final rest = geospatialSql.substring(searchProductsMatch.end);
    final endIndex = rest.indexOf(r'$$ LANGUAGE plpgsql SECURITY DEFINER;');
    final body = rest.substring(
        0, endIndex + r'$$ LANGUAGE plpgsql SECURITY DEFINER;'.length);

    outSql.writeln('-- 3. search_products_geospatial');
    outSql.writeln(funcDef.replaceFirst('BEGIN', radiusLogicPlpgsql));
    outSql.writeln(body);
    outSql.writeln('');
  }

  // 4. get_trending_keywords_geospatial
  final trendingMatch = RegExp(
          r'CREATE OR REPLACE FUNCTION public\.get_trending_keywords_geospatial.*?\$\$',
          dotAll: true)
      .firstMatch(trendingSql);
  if (trendingMatch != null) {
    String funcDef = trendingMatch.group(0)!;
    funcDef = funcDef
        .replaceFirst('LANGUAGE sql', 'LANGUAGE plpgsql')
        .replaceFirst('STABLE', '');

    final rest = trendingSql.substring(trendingMatch.end);
    final endIndex = rest.indexOf(r'$$;');
    final body = rest.substring(0, endIndex + r'$$;'.length);

    outSql.writeln('-- 4. get_trending_keywords_geospatial');
    outSql.writeln(funcDef);
    outSql.writeln(radiusLogicPlpgsql.replaceFirst('DECLARE', ''));
    outSql.writeln('  RETURN QUERY');
    outSql.write(body.replaceFirst('\$\$;', 'END;\n\$\$;'));
    outSql.writeln('');
  }

  // 5. place_orders_transaction
  final placeOrdersMatch = RegExp(
          r'CREATE OR REPLACE FUNCTION public\.place_orders_transaction.*?SECURITY DEFINER AS \$\$',
          dotAll: true)
      .firstMatch(checkoutSql);
  if (placeOrdersMatch != null) {
    String funcDef = placeOrdersMatch.group(0)!;
    final lastDollarDollar = checkoutSql.lastIndexOf(r'$$');
    final body =
        checkoutSql.substring(placeOrdersMatch.end, lastDollarDollar + 2);

    outSql.writeln('-- 5. place_orders_transaction');
    outSql.writeln(funcDef);

    final beginMatch = RegExp(r'\nBEGIN\n').firstMatch(body);
    if (beginMatch != null) {
      final modifiedBody = body.replaceFirst('BEGIN', '''BEGIN
  -- 100x Fortress: Fetch admin max delivery radius dynamically
  BEGIN SELECT value::numeric INTO v_global_max_radius FROM platform_config WHERE key = 'max_delivery_radius_km'; EXCEPTION WHEN OTHERS THEN v_global_max_radius := 15.0; END;
  v_global_max_radius := GREATEST(COALESCE(v_global_max_radius, 15.0), 0.0);''');

      final finalBody = modifiedBody
          .replaceAll(
              "IF COALESCE(v_order_totals.estimated_distance_km, 0) > 100.0 THEN",
              "IF COALESCE(v_order_totals.estimated_distance_km, 0) > v_global_max_radius THEN")
          .replaceAll(
              "radius is 100km. Claimed: % km', v_order_totals.estimated_distance_km;",
              "radius is % km. Claimed: % km', v_global_max_radius, v_order_totals.estimated_distance_km;");

      final veryFinalBody = finalBody.replaceFirst(
          'v_order jsonb;', 'v_global_max_radius numeric;\\n  v_order jsonb;');

      outSql.writeln(veryFinalBody);
      outSql.writeln(';');
    }
  }

  File('e:/Enything/supabase/migrations/20271124000002_100x_geospatial_admin_radius_fortress.sql')
      .writeAsStringSync(outSql.toString());
  print('Migration file created.');
}
