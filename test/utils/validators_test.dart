import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/utils/validators.dart';

void main() {
  group('AppValidators', () {
    group('Email Validation', () {
      test('accepts valid standard emails', () {
        expect(AppValidators.email('test@example.com'), isNull);
        expect(AppValidators.email('user.name+tag@gmail.com'), isNull);
      });

      test('accepts long TLDs (BUG-07 Fix)', () {
        expect(AppValidators.email('info@company.store'), isNull);
        expect(AppValidators.email('hello@creative.photography'), isNull);
      });

      test('rejects invalid emails', () {
        expect(AppValidators.email('invalid-email'), isNotNull);
        expect(AppValidators.email('test@.com'), isNotNull);
        expect(AppValidators.email('@example.com'), isNotNull);
      });

      test('rejects empty input', () {
        expect(AppValidators.email(''), 'Email is required');
        expect(AppValidators.email(null), 'Email is required');
      });
    });

    group('Phone Validation', () {
      test('accepts standard 10-digit Indian numbers', () {
        expect(AppValidators.phone('9876543210'), isNull);
        expect(AppValidators.phone('6123456789'), isNull);
      });

      test('accepts and strips +91 country code (BUG-08 Fix)', () {
        expect(AppValidators.phone('+919876543210'), isNull);
        expect(AppValidators.phone('919876543210'), isNull);
        expect(AppValidators.phone('+91 98765 43210'), isNull);
        expect(AppValidators.phone('91-98765-43210'), isNull);
      });

      test('rejects non-Indian numbers', () {
        expect(AppValidators.phone('5123456789'), isNotNull); // Doesn't start with 6-9
      });

      test('rejects invalid lengths', () {
        expect(AppValidators.phone('987654321'), isNotNull);
        expect(AppValidators.phone('98765432101'), isNotNull);
      });

      test('rejects empty input', () {
        expect(AppValidators.phone(''), 'Phone number is required');
        expect(AppValidators.phone(null), 'Phone number is required');
      });
    });
  });
}
