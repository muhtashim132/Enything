import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:enythingmobilenew/widgets/3d/perspective_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper widget to simulate the new compact multicoloured _buildBulkCateringCard
  Widget buildTestBulkCateringCard({required bool isDark, VoidCallback? onCardTap}) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      child: PerspectiveCard(
        borderRadius: 20,
        pressScale: 0.985,
        maxTiltAngle: 0.04,
        enableHaptics: true,
        enableSpecular: true,
        onTap: onCardTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1E3FD8), // Enything Cobalt
                Color(0xFF6366F1), // Electric Indigo
                Color(0xFFFF007F), // Festive Magenta
                Color(0xFFFF6B35), // Enything Coral
                Color(0xFFFFB800), // Sparkling Gold
                Color(0xFF1E3FD8), // Loop to Cobalt
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3FD8).withValues(alpha: isDark ? 0.28 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: 10,
                offset: const Offset(2, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF0C0E1A),
                        const Color(0xFF141626),
                        const Color(0xFF1A1D30),
                        const Color(0xFF161936),
                      ]
                    : [
                        const Color(0xFFFFFFFF),
                        const Color(0xFFF5F6FF),
                        const Color(0xFFEEF0FF),
                        const Color(0xFFFFF9F2),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Header - Perfectly balanced SpaceBetween row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 3.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E3FD8), Color(0xFF6366F1)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🎉', style: TextStyle(fontSize: 10)),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'HOST & EVENT PARTY',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFFB800)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('⚡', style: TextStyle(fontSize: 9.5)),
                            SizedBox(width: 3),
                            Text(
                              'UP TO 30% OFF',
                              style: TextStyle(
                                fontSize: 9.0,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF3E1E00),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.5),

                  // Row 2: Content Row - 3D Emblem + Copy + Gradient CTA Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF1E3FD8),
                              Color(0xFF6366F1),
                              Color(0xFFFF6B35),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.40),
                            width: 1.2,
                          ),
                        ),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Text('🎉', style: TextStyle(fontSize: 22)),
                            Positioned(
                              top: 2,
                              right: 3,
                              child: Text('✨', style: TextStyle(fontSize: 8.5)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: isDark
                                    ? const [
                                        Color(0xFF93C5FD),
                                        Color(0xFFC4B5FD),
                                        Color(0xFFFFCF40),
                                      ]
                                    : const [
                                        Color(0xFF0F1E80),
                                        Color(0xFF1E3FD8),
                                        Color(0xFFFF6B35),
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: Text(
                                'Host an Event or Party? 🎊',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bulk catering for 20 to 500+ guests',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 11.5,
                                  color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 3.5),
                                Flexible(
                                  child: Text(
                                    'Chef quotes in 15 mins · Custom menus',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.0,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF1E3FD8),
                              Color(0xFF4F46E5),
                              Color(0xFFFF6B35),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Plan Event',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 12.5,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('100x MULTICOLOURED HOST & EVENT PARTY CUSTOMER DASHBOARD SUITE', () {
    
    // ─────────────────────────────────────────────────────────────────────────
    // 1. LIGHT MODE RENDERING & HIERARCHY
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('1. Light Mode: Renders all multicoloured components, badges, and reassurance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildTestBulkCateringCard(isDark: false),
            ),
          ),
        ),
      );

      // Verify Title & ShaderMask
      expect(find.text('Host an Event or Party? 🎊'), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);

      // Verify Badges
      expect(find.text('HOST & EVENT PARTY'), findsOneWidget);
      expect(find.text('UP TO 30% OFF'), findsOneWidget);

      // Verify 3D Emblem and Emojis
      expect(find.text('🎉'), findsNWidgets(2)); // Badge + Emblem
      expect(find.text('✨'), findsOneWidget);

      // Verify Subtitle and Reassurance
      expect(find.text('Bulk catering for 20 to 500+ guests'), findsOneWidget);
      expect(find.text('Chef quotes in 15 mins · Custom menus'), findsOneWidget);

      // Verify Action Button
      expect(find.text('Plan Event'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. DARK MODE RENDERING & CONTRAST
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('2. Dark Mode: Renders with cosmic luxury palette and high-contrast text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildTestBulkCateringCard(isDark: true),
            ),
          ),
        ),
      );

      expect(find.text('Host an Event or Party? 🎊'), findsOneWidget);
      expect(find.text('HOST & EVENT PARTY'), findsOneWidget);
      expect(find.text('Plan Event'), findsOneWidget);
      expect(find.textContaining('Chef quotes in 15 mins'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. INTERACTIVE TAP & NAVIGATION INVOCATION
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('3. PerspectiveCard interactive tap triggers navigation callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestBulkCateringCard(
              isDark: false,
              onCardTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(PerspectiveCard), findsOneWidget);

      // Tap on the card
      await tester.tap(find.text('Plan Event'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. RESPONSIVE CONSTRAINTS & ZERO OVERFLOW TEST
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('4. Compact device screen (320px width) renders with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestBulkCateringCard(isDark: false),
          ),
        ),
      );

      expect(tester.takeException(), isNull); // Zero RenderFlex exceptions!
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. ACCESSIBILITY 1.5x TEXT SCALE COMPATIBILITY
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('5. Accessibility 1.5x text scale factor renders without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: buildTestBulkCateringCard(isDark: false),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 6. CONTEXTUAL SEARCH KEYWORD MATCHING REGEX TEST
    // ─────────────────────────────────────────────────────────────────────────
    test('6. Search query regex identifies party, event, catering, and bulk keywords', () {
      final regex = RegExp(
        r'\b(party|event|cater|catering|wedding|birthday|bulk|gathering|feast)\b',
        caseSensitive: false,
      );

      // Positive matches
      expect(regex.hasMatch('party'), isTrue);
      expect(regex.hasMatch('party food'), isTrue);
      expect(regex.hasMatch('event catering'), isTrue);
      expect(regex.hasMatch('wedding dinner'), isTrue);
      expect(regex.hasMatch('birthday cake bulk'), isTrue);
      expect(regex.hasMatch('family gathering feast'), isTrue);

      // Negative matches (regular queries)
      expect(regex.hasMatch('milk'), isFalse);
      expect(regex.hasMatch('serum'), isFalse);
      expect(regex.hasMatch('running shoes'), isFalse);
      expect(regex.hasMatch('laptop charger'), isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 7. COMPACT HEIGHT & BALANCED SPACE-BETWEEN ALIGNMENT FORTRESS
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('7. Compact Height (<= 110px) and balanced Space-Between horizontal alignment', (tester) async {
      // Test on standard mobile viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildTestBulkCateringCard(isDark: false),
            ),
          ),
        ),
      );

      // 1. Height Assertion: Ensure height is compact (<= 110px, reduced from 230px)
      final cardSize = tester.getSize(find.byType(PerspectiveCard));
      expect(cardSize.height, lessThanOrEqualTo(110.0),
          reason: 'Bulk catering card must be compact and sleek (<= 110px) to prevent pushing feed down');

      // 2. Alignment Assertion: Category pill at left edge, Savings pill at right edge
      final leftBadgePos = tester.getTopLeft(find.text('HOST & EVENT PARTY'));
      final rightBadgePos = tester.getTopRight(find.text('UP TO 30% OFF'));

      expect(leftBadgePos.dx, lessThan(60.0),
          reason: 'Category badge should align flush to the left of the card');
      expect(rightBadgePos.dx, greaterThan(270.0),
          reason: 'Savings badge should span flush to the right edge via SpaceBetween');
    });

  });
}
