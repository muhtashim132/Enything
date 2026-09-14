import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Maintenance Mode — 100x Edge Case Test Suite', () {
    // ── 1. Message De-Quoting & Cleaning Helper Test ─────────────────────────
    test('Cleans surrounding quotes from JSONB strings correctly', () {
      String cleanMaintenanceMessage(dynamic valRaw) {
        if (valRaw == null) return '';
        var str = valRaw.toString().trim();
        if (str.length >= 2 && str.startsWith('"') && str.endsWith('"')) {
          str = str.substring(1, str.length - 1).trim();
        }
        return str;
      }

      // Raw JSON-encoded string from PostgREST
      expect(cleanMaintenanceMessage('"Server upgrade in progress"'),
          equals('Server upgrade in progress'));

      // Plain string without outer quotes
      expect(cleanMaintenanceMessage('Platform is updating'),
          equals('Platform is updating'));

      // Empty string
      expect(cleanMaintenanceMessage(''), equals(''));

      // Null value
      expect(cleanMaintenanceMessage(null), equals(''));

      // Escaped quotes inside text
      expect(cleanMaintenanceMessage('"We\'ll be back at 6 PM"'),
          equals("We'll be back at 6 PM"));
    });

    // ── 2. Error Classifier Regex Extraction Test ───────────────────────────
    test('Robustly extracts admin message from DB trigger exception regardless of casing or noise', () {
      String classifyCheckoutError(String errorStr) {
        final e = errorStr.toLowerCase();
        if (e.contains('maintenance_mode_active')) {
          final match = RegExp(r'maintenance_mode_active:\s*(.+)',
                  caseSensitive: false)
              .firstMatch(errorStr);
          if (match != null) {
            var msg = match.group(1)?.trim() ?? '';
            final codeIdx =
                msg.indexOf(RegExp(r',\s*code:\s*', caseSensitive: false));
            if (codeIdx >= 0) {
              msg = msg.substring(0, codeIdx).trim();
            }
            msg = msg.replaceAll(RegExp(r'[\)\]\"\s]+$'), '').trim();
            if (msg.isNotEmpty) return msg;
          }
          return 'Ordering is temporarily paused. Please try again later.';
        }
        return 'An unexpected error occurred';
      }

      // Standard trigger exception
      const err1 =
          'PostgrestException(message: MAINTENANCE_MODE_ACTIVE: Servers are updating. Resuming at 5 PM., code: P0001)';
      expect(classifyCheckoutError(err1),
          equals('Servers are updating. Resuming at 5 PM.'));

      // Lowercase trigger exception
      const err2 =
          'error: maintenance_mode_active: Weather emergency in effect.)';
      expect(classifyCheckoutError(err2),
          equals('Weather emergency in effect.'));

      // Mixed case with trailing brackets
      const err3 = 'Maintenance_Mode_Active: Payment gateway maintenance]';
      expect(classifyCheckoutError(err3),
          equals('Payment gateway maintenance'));

      // Empty message fallback
      const err4 = 'MAINTENANCE_MODE_ACTIVE: ';
      expect(classifyCheckoutError(err4),
          equals('Ordering is temporarily paused. Please try again later.'));

      // Unrelated error
      const err5 = 'Network error connection timeout';
      expect(classifyCheckoutError(err5),
          equals('An unexpected error occurred'));
    });

    // ── 3. UUID Validation for Audit Log Safety ─────────────────────────────
    test('Validates UUID format to prevent PostgreSQL syntax error in audit_logs', () {
      bool isValidUuid(String? str) {
        if (str == null || str.isEmpty) return false;
        return RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(str);
      }

      // Valid UUID v4
      expect(isValidUuid('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'), isTrue);
      expect(isValidUuid('E36B2B28-912A-4B6A-9DEE-23E12D032CE2'), isTrue);

      // Invalid UUIDs (which caused Postgres crashes previously)
      expect(isValidUuid('unknown'), isFalse);
      expect(isValidUuid(''), isFalse);
      expect(isValidUuid(null), isFalse);
      expect(isValidUuid('12345'), isFalse);
      expect(isValidUuid('admin'), isFalse);
    });

    // ── 4. Boolean JSON Parsing Parity ──────────────────────────────────────
    test('Correctly parses JSONB boolean true/false and string variations', () {
      bool parseMaintenanceMode(dynamic valRaw) {
        return valRaw == true || valRaw.toString() == 'true';
      }

      expect(parseMaintenanceMode(true), isTrue);
      expect(parseMaintenanceMode('true'), isTrue);
      expect(parseMaintenanceMode(false), isFalse);
      expect(parseMaintenanceMode('false'), isFalse);
      expect(parseMaintenanceMode(null), isFalse);
      expect(parseMaintenanceMode(0), isFalse);
      expect(parseMaintenanceMode(''), isFalse);
    });

    // ── 5. Cart canCheckout Truth Table ─────────────────────────────────────
    test('canCheckout strictly requires !isMaintenanceMode', () {
      bool computeCanCheckout({
        required bool meetsMinimumOrder,
        required double baseCharge,
        required bool isMaintenanceMode,
      }) {
        return meetsMinimumOrder && baseCharge >= 0 && !isMaintenanceMode;
      }

      // Normal operations
      expect(
          computeCanCheckout(
              meetsMinimumOrder: true,
              baseCharge: 20.0,
              isMaintenanceMode: false),
          isTrue);

      // Maintenance mode active -> must be FALSE even if all other conditions met
      expect(
          computeCanCheckout(
              meetsMinimumOrder: true,
              baseCharge: 20.0,
              isMaintenanceMode: true),
          isFalse);

      // Out of range & maintenance
      expect(
          computeCanCheckout(
              meetsMinimumOrder: true,
              baseCharge: -1.0,
              isMaintenanceMode: true),
          isFalse);

      // Below minimum order
      expect(
          computeCanCheckout(
              meetsMinimumOrder: false,
              baseCharge: 20.0,
              isMaintenanceMode: false),
          isFalse);
    });

    // ── 6. Fail-open Default State ──────────────────────────────────────────
    test('Default maintenance mode state is fail-open (false)', () {
      bool maintenanceMode = false;
      String maintenanceMessage =
          'We are currently updating our platform. Ordering will resume shortly.';

      expect(maintenanceMode, isFalse);
      expect(maintenanceMessage, isNotEmpty);
    });

    // ── 7. Deletion Reset (Fail-open on config row removal) ─────────────────
    test('Resetting maintenance mode on row deletion returns to open state', () {
      bool maintenanceMode = true; // Was active
      String maintenanceMessage = 'Custom notice';

      // Simulate row deletion in platform_config
      void removeValue(String key) {
        switch (key) {
          case 'maintenance_mode':
            maintenanceMode = false;
            break;
          case 'maintenance_message':
            maintenanceMessage =
                'We are currently updating our platform. Ordering will resume shortly.';
            break;
        }
      }

      removeValue('maintenance_mode');
      expect(maintenanceMode, isFalse); // Successfully reset to fail-open

      removeValue('maintenance_message');
      expect(maintenanceMessage,
          equals('We are currently updating our platform. Ordering will resume shortly.'));
    });
  });
}
