import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/app_categories.dart';

void main() {
  group('Intelligent Dual-Path GST & Tax Compliance Tests', () {
    // 1. PAN Regex Validation
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');

    test('Valid PAN patterns pass', () {
      expect(panRegex.hasMatch('ABCDE1234F'), isTrue);
      expect(panRegex.hasMatch('AAAPL1234C'), isTrue);
      expect(panRegex.hasMatch('ZZZZZ9999Z'), isTrue);
    });

    test('Invalid PAN patterns fail', () {
      expect(panRegex.hasMatch('ABCDE1234'), isFalse); // 9 chars
      expect(panRegex.hasMatch('ABCDE12345'), isFalse); // number at end
      expect(panRegex.hasMatch('12345ABCDE'), isFalse); // starts with numbers
      expect(panRegex.hasMatch('abcde1234f'), isFalse); // lowercase (must be uppercase)
      expect(panRegex.hasMatch(''), isFalse); // empty
    });

    // 2. GSTIN Regex Validation
    final gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

    test('Valid 15-digit GSTIN patterns pass', () {
      expect(gstRegex.hasMatch('07AAAAA0000A1Z5'), isTrue);
      expect(gstRegex.hasMatch('27AAPFU0939F1ZV'), isTrue);
      expect(gstRegex.hasMatch('08ABCDE1234F1Z5'), isTrue);
      expect(gstRegex.hasMatch('29ABCDE1234F2Z8'), isTrue);
    });

    test('Invalid GSTIN patterns fail', () {
      expect(gstRegex.hasMatch('07AAAAA0000A1Z'), isFalse); // 14 chars
      expect(gstRegex.hasMatch('07AAAAA0000A1ZZ5'), isFalse); // 16 chars
      expect(gstRegex.hasMatch('07aaaaa0000a1z5'), isFalse); // lowercase
      expect(gstRegex.hasMatch(''), isFalse); // empty
      expect(gstRegex.hasMatch('07AAAAA0000A1A5'), isFalse); // missing 'Z' in 14th pos
    });

    // 3. Embedded PAN in GSTIN Cross-Verification
    test('Embedded PAN in GSTIN matches entered PAN', () {
      const enteredPan = 'ABCDE1234F';
      const validGst = '07ABCDE1234F1Z5';
      const mismatchedGst = '07XYZWE9999Q1Z5';

      final gstinPanValid = validGst.substring(2, 12);
      expect(gstinPanValid, equals(enteredPan));

      final gstinPanMismatch = mismatchedGst.substring(2, 12);
      expect(gstinPanMismatch, isNot(equals(enteredPan)));
    });

    // 4. Food Category vs Non-Food Category Detection
    bool isFoodCategory(String? categoryName) {
      if (categoryName == null) return false;
      final cat = categoryName.trim().toLowerCase();
      if (cat == 'food' ||
          cat == 'restaurant' ||
          cat == 'fast food' ||
          cat == 'bakery' ||
          cat == 'sweets & mithai' ||
          cat == 'sweets and mithai' ||
          cat == 'tea & coffee' ||
          cat == 'ice cream' ||
          cat == 'paan shop' ||
          cat == 'cafe' ||
          cat == 'beverages') {
        return true;
      }
      return AppCategories.groupFor(categoryName) == CategoryGroup.food;
    }

    test('Food outlets accurately detected as Section 9(5) deemed food platforms', () {
      expect(isFoodCategory('Restaurant'), isTrue);
      expect(isFoodCategory('Fast Food'), isTrue);
      expect(isFoodCategory('Bakery'), isTrue);
      expect(isFoodCategory('Sweets & Mithai'), isTrue);
      expect(isFoodCategory('Tea & Coffee'), isTrue);
      expect(isFoodCategory('Ice Cream'), isTrue);
      expect(isFoodCategory('Paan Shop'), isTrue);
      expect(isFoodCategory('Beverages'), isTrue);
      expect(isFoodCategory('food'), isTrue);
      expect(isFoodCategory('restaurant'), isTrue);
    });

    test('Non-food categories accurately detected as requiring dual-path compliance', () {
      expect(isFoodCategory('Clothing'), isFalse);
      expect(isFoodCategory('Footwear'), isFalse);
      expect(isFoodCategory('Electronics'), isFalse);
      expect(isFoodCategory('Mobile & Repair'), isFalse);
      expect(isFoodCategory('Stationery'), isFalse);
      expect(isFoodCategory('Hardware Store'), isFalse);
      expect(isFoodCategory('Home Decor'), isFalse);
      expect(isFoodCategory('Jewellery'), isFalse);
      expect(isFoodCategory('Sports'), isFalse);
    });

    // 5. Dual-Path Non-Food Validation Decision Matrix
    String? validateDualPathSubmission({
      required bool isFood,
      required bool isGstRegistered,
      required String enteredPan,
      required String gstText,
      required String enrolmentIdText,
      required bool exemptionDeclared,
    }) {
      final pan = enteredPan.trim().toUpperCase();
      if (!panRegex.hasMatch(pan)) {
        return 'Invalid PAN';
      }

      if (isFood) {
        final gst = gstText.trim().toUpperCase();
        if (gst.isNotEmpty) {
          if (!gstRegex.hasMatch(gst)) return 'Invalid GSTIN format';
          if (gst.substring(2, 12) != pan) return 'GSTIN PAN mismatch';
        }
        return null; // Food is valid
      }

      // Non-Food
      if (isGstRegistered) {
        final gst = gstText.trim().toUpperCase();
        if (gst.isEmpty) return 'GSTIN is required for registered non-food businesses';
        if (!gstRegex.hasMatch(gst)) return 'Invalid GSTIN format';
        if (gst.substring(2, 12) != pan) return 'GSTIN PAN mismatch';
        return null; // Registered non-food is valid
      } else {
        if (!exemptionDeclared) return 'Please confirm statutory declaration';
        if (enrolmentIdText.trim().isNotEmpty) {
          final enr = enrolmentIdText.trim();
          if (enr.length < 8 || enr.length > 25) return 'Invalid Enrolment ID';
        }
        return null; // Exempt non-food is valid
      }
    }

    test('Scenario: Food outlet with no GSTIN signs up smoothly', () {
      final result = validateDualPathSubmission(
        isFood: true,
        isGstRegistered: false,
        enteredPan: 'ABCDE1234F',
        gstText: '',
        enrolmentIdText: '',
        exemptionDeclared: false,
      );
      expect(result, isNull);
    });

    test('Scenario: Non-food registered seller without GSTIN is blocked', () {
      final result = validateDualPathSubmission(
        isFood: false,
        isGstRegistered: true,
        enteredPan: 'ABCDE1234F',
        gstText: '',
        enrolmentIdText: '',
        exemptionDeclared: false,
      );
      expect(result, equals('GSTIN is required for registered non-food businesses'));
    });

    test('Scenario: Non-food registered seller with mismatched PAN is blocked', () {
      final result = validateDualPathSubmission(
        isFood: false,
        isGstRegistered: true,
        enteredPan: 'ABCDE1234F',
        gstText: '07XYZWE9999Q1Z5',
        enrolmentIdText: '',
        exemptionDeclared: false,
      );
      expect(result, equals('GSTIN PAN mismatch'));
    });

    test('Scenario: Non-food registered seller with valid GSTIN matching PAN succeeds', () {
      final result = validateDualPathSubmission(
        isFood: false,
        isGstRegistered: true,
        enteredPan: 'ABCDE1234F',
        gstText: '07ABCDE1234F1Z5',
        enrolmentIdText: '',
        exemptionDeclared: false,
      );
      expect(result, isNull);
    });

    test('Scenario: Non-food exempt seller without declaration is blocked', () {
      final result = validateDualPathSubmission(
        isFood: false,
        isGstRegistered: false,
        enteredPan: 'ABCDE1234F',
        gstText: '',
        enrolmentIdText: '',
        exemptionDeclared: false,
      );
      expect(result, equals('Please confirm statutory declaration'));
    });

    test('Scenario: Non-food exempt seller with declaration signs up smoothly without GSTIN', () {
      final result = validateDualPathSubmission(
        isFood: false,
        isGstRegistered: false,
        enteredPan: 'ABCDE1234F',
        gstText: '',
        enrolmentIdText: '27ABCDE1234F0Z1',
        exemptionDeclared: true,
      );
      expect(result, isNull);
    });
  });
}
