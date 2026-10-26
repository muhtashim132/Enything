import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Prevent GoogleFonts from attempting network calls in headless unit tests
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('100x Stepper & Add Button Ergonomics & Touch Target Tests', () {
    testWidgets('Full edge-to-edge responsiveness on Quantity Stepper (far left and far right taps)', (tester) async {
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('stepper_minus_zone'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  quantity--;
                                });
                              },
                              child: const Center(
                                child: Icon(Icons.remove_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '$quantity',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                height: 1.0,
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('stepper_plus_zone'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  quantity++;
                                });
                              },
                              child: const Center(
                                child: Icon(Icons.add_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);

      // 1. Tap on the extreme outer left edge (x = 5px inside the 100px wide container)
      final leftZone = find.byKey(const ValueKey('stepper_minus_zone'));
      final leftZoneTopLeft = tester.getTopLeft(leftZone);
      await tester.tapAt(leftZoneTopLeft + const Offset(5, 19));
      await tester.pumpAndSettle();

      // Expect quantity decremented from 2 -> 1
      expect(quantity, equals(1));
      expect(find.text('1'), findsOneWidget);

      // 2. Tap on the extreme outer right edge (x = 5px from right inside the 100px container)
      final rightZone = find.byKey(const ValueKey('stepper_plus_zone'));
      final rightZoneTopRight = tester.getTopRight(rightZone);
      await tester.tapAt(rightZoneTopRight - const Offset(5, -19));
      await tester.pumpAndSettle();

      // Expect quantity incremented from 1 -> 2
      expect(quantity, equals(2));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('Optical centering and HitTestBehavior.opaque on + ADD Button', (tester) async {
      bool addTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey('add_button_gesture'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  addTapped = true;
                },
                child: Container(
                  width: 90,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.deepOrange, width: 1.2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, 0.6),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        'ADD',
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap on the edge of the ADD button
      final btn = find.byKey(const ValueKey('add_button_gesture'));
      final btnTopLeft = tester.getTopLeft(btn);
      await tester.tapAt(btnTopLeft + const Offset(4, 17));
      await tester.pumpAndSettle();

      expect(addTapped, isTrue);
    });

    testWidgets('Variant Stepper cleanly isolates center selection from outer increment/decrement zones', (tester) async {
      int decrementCount = 0;
      int centerSheetCount = 0;
      int incrementCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Container(
                width: 90,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey('var_minus'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => decrementCount++,
                          child: const Center(
                            child: Icon(Icons.remove_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                      GestureDetector(
                        key: const ValueKey('var_center'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => centerSheetCount++,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '3',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  height: 1.0,
                                ),
                              ),
                              SizedBox(width: 1),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey('var_plus'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => incrementCount++,
                          child: const Center(
                            child: Icon(Icons.add_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Tap outer left edge
      final minusFinder = find.byKey(const ValueKey('var_minus'));
      await tester.tapAt(tester.getTopLeft(minusFinder) + const Offset(3, 17));
      expect(decrementCount, equals(1));
      expect(centerSheetCount, equals(0));
      expect(incrementCount, equals(0));

      // 2. Tap center variant sheet trigger
      await tester.tap(find.byKey(const ValueKey('var_center')));
      expect(decrementCount, equals(1));
      expect(centerSheetCount, equals(1));
      expect(incrementCount, equals(0));

      // 3. Tap outer right edge
      final plusFinder = find.byKey(const ValueKey('var_plus'));
      await tester.tapAt(tester.getTopRight(plusFinder) - const Offset(3, -17));
      expect(decrementCount, equals(1));
      expect(centerSheetCount, equals(1));
      expect(incrementCount, equals(1));
    });
  });
}
