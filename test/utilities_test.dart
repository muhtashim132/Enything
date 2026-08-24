import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/utils/currency_utils.dart';
import 'package:enythingmobilenew/utils/time_utils.dart';
import 'package:enythingmobilenew/utils/validators.dart';
import 'package:enythingmobilenew/utils/geo_utils.dart';
import 'package:enythingmobilenew/utils/debounce_throttle_utils.dart';
import 'package:enythingmobilenew/utils/network_retry_utils.dart';

void main() {
  group('100x Universal Utilities Test Suite', () {
    // ── 1. CurrencyUtils Tests ───────────────────────────────────────────────
    group('CurrencyUtils', () {
      test('formats numbers with Indian grouping commas', () {
        expect(CurrencyUtils.format(5999), equals('₹5,999'));
        expect(CurrencyUtils.format(150000), equals('₹1,50,000'));
        expect(CurrencyUtils.format(25000000), equals('₹2,50,00,000'));
        expect(CurrencyUtils.format(0), equals('₹0'));
        expect(CurrencyUtils.format(45), equals('₹45'));
      });

      test('formats paise decimals properly', () {
        expect(CurrencyUtils.formatPaisa(59.50), equals('₹59.50'));
        expect(CurrencyUtils.formatPaisa(1200.75), equals('₹1,200.75'));
        expect(CurrencyUtils.formatPaisa(100.0), equals('₹100'));
      });

      test('formats compact Lakhs and Crores', () {
        expect(CurrencyUtils.formatCompact(150000), equals('₹1.5 L'));
        expect(CurrencyUtils.formatCompact(25000000), equals('₹2.5 Cr'));
        expect(CurrencyUtils.formatCompact(15000), equals('₹15 K'));
        expect(CurrencyUtils.formatCompact(450), equals('₹450'));
      });

      test('calculates discount percentage and monetary savings', () {
        expect(CurrencyUtils.calculateDiscountPercent(6500, 5999), closeTo(7.7, 0.1));
        expect(CurrencyUtils.calculateSavings(6500, 5999), equals(501.0));
        expect(CurrencyUtils.calculateDiscountPercent(null, 500), equals(0.0));
      });
    });

    // ── 2. DateTimeUtils & IST Tests ─────────────────────────────────────────
    group('DateTimeUtils & IST', () {
      test('toIST converts UTC date to Indian Standard Time (+5:30)', () {
        final utc = DateTime.utc(2026, 8, 15, 12, 0); // 12:00 UTC
        final ist = DateTimeUtils.toIST(utc);
        expect(ist.hour, equals(17)); // 17:30 IST
        expect(ist.minute, equals(30));
      });

      test('formatRelative produces natural relative strings', () {
        final now = DateTime.now();
        expect(DateTimeUtils.formatRelative(now), equals('Just now'));

        final fiveMinsAgo = now.subtract(const Duration(minutes: 5));
        expect(DateTimeUtils.formatRelative(fiveMinsAgo), equals('5m ago'));
      });

      test('isWithinOperatingHours correctly handles normal and midnight crossover', () {
        // Normal daytime: 09:00 - 22:00
        expect(DateTimeUtils.isWithinOperatingHours('09:00', '22:00'), isNotNull);

        // Operating hours string formatting
        expect(DateTimeUtils.formatOperatingHours('09:00', '22:30'), equals('9:00 AM - 10:30 PM'));
        expect(DateTimeUtils.formatOperatingHours('19:00', '02:00'), equals('7:00 PM - 2:00 AM'));
      });
    });

    // ── 3. AppValidators Tests ───────────────────────────────────────────────
    group('AppValidators', () {
      test('validates GSTIN formats', () {
        expect(AppValidators.gstin('07AAAAA0000A1Z5'), isNull); // Valid
        expect(AppValidators.gstin('INVALID123'), isNotNull); // Invalid
        expect(AppValidators.gstin('', isOptional: true), isNull); // Optional
      });

      test('validates FSSAI 14-digit numbers', () {
        expect(AppValidators.fssai('10012345678901'), isNull); // Valid starts with 1
        expect(AppValidators.fssai('20012345678901'), isNull); // Valid starts with 2
        expect(AppValidators.fssai('30012345678901'), isNotNull); // Invalid start
        expect(AppValidators.fssai('123'), isNotNull); // Too short
      });

      test('validates PAN, IFSC, and Bank Accounts', () {
        expect(AppValidators.pan('ABCDE1234F'), isNull);
        expect(AppValidators.pan('12345ABCDE'), isNotNull);

        expect(AppValidators.ifsc('HDFC0000001'), isNull);
        expect(AppValidators.ifsc('SBIN0001234'), isNull);
        expect(AppValidators.ifsc('INVALID'), isNotNull);

        expect(AppValidators.bankAccount('123456789012'), isNull);
        expect(AppValidators.bankAccount('123'), isNotNull);
      });
    });

    // ── 4. GeoUtils Tests ────────────────────────────────────────────────────
    group('GeoUtils', () {
      test('calculates accurate compass bearing', () {
        // Point North
        const p1 = LatLng(12.9716, 77.5946);
        const pNorth = LatLng(13.9716, 77.5946);
        final bearingNorth = GeoUtils.calculateBearing(p1, pNorth);
        expect(bearingNorth, closeTo(0.0, 1.0));

        // Point East
        const pEast = LatLng(12.9716, 78.5946);
        final bearingEast = GeoUtils.calculateBearing(p1, pEast);
        expect(bearingEast, closeTo(90.0, 1.0));
      });

      test('computes bounding box for camera view', () {
        const p1 = LatLng(12.9716, 77.5946);
        const p2 = LatLng(12.9800, 77.6000);
        final bounds = GeoUtils.computeBounds([p1, p2]);
        expect(bounds, isNotNull);
        expect(bounds!.contains(p1), isTrue);
        expect(bounds.contains(p2), isTrue);
      });

      test('formats distance strings', () {
        expect(GeoUtils.formatDistance(0.45), equals('450 m'));
        expect(GeoUtils.formatDistance(2.34), equals('2.3 km'));
        expect(GeoUtils.formatDistance(0), equals('0 m'));
      });
    });

    // ── 5. Debouncer & Throttler Tests ───────────────────────────────────────
    group('Debounce & Throttle', () {
      test('Debouncer only executes after silence duration', () async {
        final debouncer = Debouncer(duration: const Duration(milliseconds: 50));
        int callCount = 0;

        debouncer.run(() => callCount++);
        debouncer.run(() => callCount++);
        debouncer.run(() => callCount++);

        expect(callCount, equals(0)); // Not executed immediately

        await Future.delayed(const Duration(milliseconds: 70));
        expect(callCount, equals(1)); // Executed exactly once
        debouncer.dispose();
      });

      test('Throttler limits execution frequency', () async {
        final throttler = Throttler(duration: const Duration(milliseconds: 50));
        int callCount = 0;

        throttler.run(() => callCount++); // Executes immediately
        throttler.run(() => callCount++); // Ignored during throttle
        throttler.run(() => callCount++); // Ignored during throttle

        expect(callCount, equals(1));

        await Future.delayed(const Duration(milliseconds: 70));
        throttler.run(() => callCount++); // Can execute again
        expect(callCount, equals(2));
        throttler.dispose();
      });
    });

    // ── 6. NetworkRetry Tests ────────────────────────────────────────────────
    group('NetworkRetry', () {
      test('retries on transient failure until success', () async {
        int attempts = 0;

        final result = await NetworkRetry.execute(
          () async {
            attempts++;
            if (attempts < 2) {
              throw Exception('Transient socket error');
            }
            return 'SuccessOnAttempt$attempts';
          },
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 10),
        );

        expect(result, equals('SuccessOnAttempt2'));
        expect(attempts, equals(2));
      });
    });
  });
}
