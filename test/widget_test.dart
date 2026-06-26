import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/main.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/providers/recently_viewed_provider.dart';

void main() {
  testWidgets('Enything app smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(EnythingApp(
      cartProvider: CartProvider(),
      configProvider: PlatformConfigProvider(),
      recentlyViewedProvider: RecentlyViewedProvider(),
    ));
    // Verify splash screen appears
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

