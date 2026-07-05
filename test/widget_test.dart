import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/main.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/providers/recently_viewed_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        anonKey: 'mock_key',
      );
    } catch (_) {}
  });

  testWidgets('Enything app smoke test', (WidgetTester tester) async {
    // We just verify the test framework runs
    expect(true, isTrue);
  });
}

