import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/widgets/seller/seller_deductible_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SellerDeductibleBreakdown Math & Statutory Rules', () {
    test('Standard retail goods (Clothing 5% GST): Net base = 92.04%, Net with GST = 97.04%', () {
      final b = SellerDeductibleBreakdown.fromCategory('Clothing', null);

      expect(b.category, 'Clothing');
      expect(b.commissionPercent, 5.0);
      expect(b.gatewayPercent, closeTo(2.36, 0.001));
      expect(b.tdsPercent, closeTo(0.10, 0.001));
      expect(b.tcsPercent, closeTo(0.50, 0.001));
      expect(b.totalDeductiblePercent, closeTo(7.96, 0.001));
      expect(b.netPayoutPercent, closeTo(92.04, 0.001));
      expect(b.categoryGstPercent, 5.0);
      expect(b.gstPassthroughPercent, 5.0);
      expect(b.netPayoutWithGstPercent, closeTo(97.04, 0.001));
      expect(b.isFoodDeemedSupplier, isFalse);
      expect(b.isExemptProduce, isFalse);
    });

    test('Section 9(5) Food (Restaurant): Net with GST is identical to Net base (92.54%)', () {
      final b = SellerDeductibleBreakdown.fromCategory('Restaurant', null);

      expect(b.category, 'Restaurant');
      expect(b.commissionPercent, 5.0);
      expect(b.gatewayPercent, closeTo(2.36, 0.001));
      expect(b.tdsPercent, closeTo(0.10, 0.001));
      expect(b.tcsPercent, 0.0);
      expect(b.totalDeductiblePercent, closeTo(7.46, 0.001));
      expect(b.netPayoutPercent, closeTo(92.54, 0.001));
      expect(b.categoryGstPercent, 5.0);
      expect(b.gstPassthroughPercent, 0.0, reason: 'Section 9(5) food has 0% GST passthrough (Enything remits)');
      expect(b.netPayoutWithGstPercent, closeTo(92.54, 0.001), reason: 'Net payout with GST must equal net payout base');
      expect(b.isFoodDeemedSupplier, isTrue);
      expect(b.isExemptProduce, isFalse);
    });

    test('All other food categories (Fast Food, Bakery, Sweets) have identical Net Payout with GST', () {
      final foodCategories = ['Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop'];
      for (final cat in foodCategories) {
        final b = SellerDeductibleBreakdown.fromCategory(cat, null);
        expect(b.isFoodDeemedSupplier, isTrue);
        expect(b.gstPassthroughPercent, 0.0);
        expect(b.netPayoutWithGstPercent, equals(b.netPayoutPercent));
      }
    });

    test('Genuinely exempt fresh produce (Fruits & Vegs 0% GST) has identical Net Payout (92.54%)', () {
      final b = SellerDeductibleBreakdown.fromCategory('Fruits & Vegs', null);

      expect(b.category, 'Fruits & Vegs');
      expect(b.commissionPercent, 5.0);
      expect(b.gatewayPercent, closeTo(2.36, 0.001));
      expect(b.tdsPercent, closeTo(0.10, 0.001));
      expect(b.tcsPercent, 0.0);
      expect(b.totalDeductiblePercent, closeTo(7.46, 0.001));
      expect(b.netPayoutPercent, closeTo(92.54, 0.001));
      expect(b.categoryGstPercent, 0.0);
      expect(b.gstPassthroughPercent, 0.0);
      expect(b.netPayoutWithGstPercent, closeTo(92.54, 0.001));
      expect(b.isFoodDeemedSupplier, isFalse);
      expect(b.isExemptProduce, isTrue);
    });

    test('Electronics (18% GST): Net base = 92.04%, Net with GST = 110.04%', () {
      final b = SellerDeductibleBreakdown.fromCategory('Electronics', null);

      expect(b.category, 'Electronics');
      expect(b.totalDeductiblePercent, closeTo(7.96, 0.001));
      expect(b.netPayoutPercent, closeTo(92.04, 0.001));
      expect(b.categoryGstPercent, 18.0);
      expect(b.gstPassthroughPercent, 18.0);
      expect(b.netPayoutWithGstPercent, closeTo(110.04, 0.001));
    });

    test('Manual calculation model works with custom commission overrides and GST', () {
      const customComm = 10.0;
      final gw = TaxConfig.effectiveGatewayDeductionPercent * 100;
      const tds = TaxConfig.itTdsRate * 100;
      final tcs = TaxConfig.tcsRateForCategory('Clothing') * 100;
      final total = customComm + gw + tds + tcs;
      final net = 100.0 - total;
      const gst = 5.0;

      final b = SellerDeductibleBreakdown(
        category: 'Clothing',
        commissionPercent: customComm,
        gatewayPercent: gw,
        tdsPercent: tds,
        tcsPercent: tcs,
        totalDeductiblePercent: total,
        netPayoutPercent: net,
        categoryGstPercent: gst,
        gstPassthroughPercent: gst,
        netPayoutWithGstPercent: net + gst,
        isFoodDeemedSupplier: false,
        isExemptProduce: false,
      );

      expect(b.commissionPercent, 10.0);
      expect(b.totalDeductiblePercent, closeTo(12.96, 0.001));
      expect(b.netPayoutPercent, closeTo(87.04, 0.001));
      expect(b.netPayoutWithGstPercent, closeTo(92.04, 0.001));
    });
  });

  group('SellerDeductibleCard Widget Tests', () {
    testWidgets('Renders compact mode without layout overflow on 320px screen and shows with-GST row', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 600 * 3);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = PlatformConfigProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<PlatformConfigProvider>.value(
          value: config,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SellerDeductibleCard(
                    category: 'Clothing',
                    isCompact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Total Deductible:'), findsOneWidget);
      expect(find.text('7.96%'), findsOneWidget);
      expect(find.text('Estimated Net Payout (Base):'), findsOneWidget);
      expect(find.text('92.04%'), findsOneWidget);
      expect(find.text('Estimated Net Payout (with GST)*:'), findsOneWidget);
      expect(find.text('97.04%'), findsOneWidget);
      expect(find.text('Commission'), findsOneWidget);
      expect(find.text('Gateway (Online)'), findsOneWidget);
      expect(find.text('TDS (§194-O)'), findsOneWidget);
      expect(find.text('TCS (§52)'), findsOneWidget);
    });

    testWidgets('Renders expanded mode with Net Payout with GST row', (tester) async {
      final config = PlatformConfigProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<PlatformConfigProvider>.value(
          value: config,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SellerDeductibleCard(
                    category: 'Restaurant',
                    isCompact: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Platform Fees & Deductibles'), findsOneWidget);
      expect(find.text('Total Deductions'), findsOneWidget);
      expect(find.text('7.46%'), findsOneWidget);
      expect(find.text('Estimated Net Payout (Base Only)'), findsOneWidget);
      expect(find.text('92.54%'), findsWidgets);
      expect(find.text('GST Passthrough to Seller'), findsOneWidget);
      expect(find.text('0.00% (ECO §9(5))'), findsOneWidget);
      expect(find.text('Estimated Net Payout (with GST)'), findsOneWidget);
    });
  });
}
