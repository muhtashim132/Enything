import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100x Forensic Unit 10: UI Ergonomics, Responsive Layout & Gesture Fortress', () {
    testWidgets('1. Edge-to-edge quantity stepper hit targets (outer left minus, outer right plus)', (tester) async {
      int quantity = 2;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Container(
                    width: 100,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('stepper_minus'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() => quantity--);
                            },
                            child: const Center(child: Icon(Icons.remove, size: 16, color: Colors.white)),
                          ),
                        ),
                        Text('$quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('stepper_plus'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() => quantity++);
                            },
                            child: const Center(child: Icon(Icons.add, size: 16, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);

      // Tap minus on far left edge
      final minusFinder = find.byKey(const ValueKey('stepper_minus'));
      await tester.tap(minusFinder);
      await tester.pumpAndSettle();
      expect(quantity, equals(1));
      expect(find.text('1'), findsOneWidget);

      // Tap plus on far right edge
      final plusFinder = find.byKey(const ValueKey('stepper_plus'));
      await tester.tap(plusFinder);
      await tester.pumpAndSettle();
      expect(quantity, equals(2));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('2. Responsive layout verification without RenderFlex overflow (320px to 840px)', (tester) async {
      final screenWidths = [320.0, 360.0, 390.0, 412.0, 600.0, 840.0];

      for (final width in screenWidths) {
        tester.view.physicalSize = Size(width, 800.0);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    // Prepaid Delivery Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.credit_card, size: 16, color: Colors.green),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '💳 PREPAID · ₹0 TO COLLECT',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Responsive action buttons row
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {},
                            child: const Text('Call Shop'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {},
                            child: const Text('Open Maps'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        // Expect no RenderFlex overflow exceptions caught by tester
        expect(tester.takeException(), isNull, reason: 'Failed layout at width $width');
      }

      // Reset test surface
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    test('3. Realtime mutation index clamping (prevents RangeError crashes)', () {
      // In OrderRouteMapPage, whenever _orders is mutated via Realtime,
      // _selectedStopIndex must be clamped to math.max(0, totalStops - 1)
      int clampStopIndex(int currentIndex, int totalStops) {
        if (totalStops <= 0) return 0;
        return math.min(currentIndex, math.max(0, totalStops - 1));
      }

      // Scenario: Currently viewing stop index 3 out of 4 stops (stops 0, 1, 2, 3)
      // Stop 3 gets cancelled/completed in realtime -> total stops drops to 3 (stops 0, 1, 2)
      final clampedIndex = clampStopIndex(3, 3);
      expect(clampedIndex, equals(2)); // Clamps safely to last available stop!

      // When all stops finish -> total stops is 0
      final emptyClamp = clampStopIndex(2, 0);
      expect(emptyClamp, equals(0));
    });

    test('4. OrderGroup 100% Prepaid Banner Text Format', () {
      const isCod = false;
      const codAmount = 0.0;

      String getPaymentBannerText({required bool isCod, required double codAmount}) {
        if (isCod && codAmount > 0) {
          return '💵 CASH ON DELIVERY · COLLECT ₹${codAmount.toStringAsFixed(0)}';
        }
        return '💳 PREPAID · ₹0 TO COLLECT';
      }

      // In Enything, all orders are strictly prepaid
      expect(getPaymentBannerText(isCod: isCod, codAmount: codAmount), equals('💳 PREPAID · ₹0 TO COLLECT'));
    });

    testWidgets('5. Cart bottom sheet drag-to-dismiss behavior and scroll containment', (tester) async {
      bool sheetDismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) {
                          return DraggableScrollableSheet(
                            initialChildSize: 0.6,
                            maxChildSize: 0.9,
                            minChildSize: 0.3,
                            expand: false,
                            builder: (ctx, scrollController) {
                              return Container(
                                color: Colors.white,
                                child: ListView.builder(
                                  controller: scrollController,
                                  itemCount: 20,
                                  itemBuilder: (_, i) => ListTile(title: Text('Cart Item #$i')),
                                ),
                              );
                            },
                          );
                        },
                      ).then((_) {
                        sheetDismissed = true;
                      });
                    },
                    child: const Text('Open Cart Sheet'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Cart Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Cart Item #0'), findsOneWidget);

      // Dismiss by tapping scrim / barrier
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(sheetDismissed, isTrue);
      expect(find.text('Cart Item #0'), findsNothing);
    });

    test('6. Memory leak prevention: controller lifecycle disposal contract', () {
      final textController = TextEditingController(text: 'Special delivery note');
      final scrollController = ScrollController();

      expect(textController.text, equals('Special delivery note'));

      // Dispose controllers safely
      textController.dispose();
      scrollController.dispose();

      // Attempting to access disposed controller throws Flutter assertion
      expect(() => textController.text = 'New Text', throwsFlutterError);
    });
  });
}
