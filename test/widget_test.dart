import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zappymobilenew/main.dart';
import 'package:zappymobilenew/providers/cart_provider.dart';

void main() {
  testWidgets('Enything app smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(EnythingApp(cartProvider: CartProvider()));
    // Verify splash screen appears
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
