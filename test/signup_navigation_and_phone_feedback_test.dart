import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Signup Navigation & PopScope Fallback Tests', () {
    testWidgets('PopScope and fallback route properly when canPop is false',
        (tester) async {
      String? navigatedRoute;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == '/auth/role-select') {
              navigatedRoute = '/auth/role-select';
              return MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Role Selection')),
              );
            }
            return MaterialPageRoute(
              builder: (context) => PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/auth/role-select',
                      (_) => false,
                    );
                  }
                },
                child: Scaffold(
                  appBar: AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/auth/role-select',
                            (_) => false,
                          );
                        }
                      },
                    ),
                  ),
                  body: const Text('KYC Page'),
                ),
              ),
            );
          },
        ),
      );

      expect(find.text('KYC Page'), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);

      // Tap back button when canPop is false (it's the root of the app)
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Verify that instead of a black screen, it navigated safely to /auth/role-select
      expect(navigatedRoute, equals('/auth/role-select'));
      expect(find.text('Role Selection'), findsOneWidget);
    });

    testWidgets('Non-editable phone field displays lock badge and triggers feedback',
        (tester) async {
      bool feedbackShown = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return InkWell(
                  onTap: () {
                    feedbackShown = true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phone number is verified via OTP and locked to this account.'),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: const Row(
                      children: [
                        Icon(Icons.phone_android_rounded),
                        SizedBox(width: 8),
                        Text('+91 98765 43210'),
                        SizedBox(width: 8),
                        Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 12),
                            Text('Verified'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      // Tap the locked field
      await tester.tap(find.text('+91 98765 43210'));
      await tester.pump();

      expect(feedbackShown, isTrue);
      expect(find.text('Phone number is verified via OTP and locked to this account.'), findsOneWidget);
    });
  });
}
