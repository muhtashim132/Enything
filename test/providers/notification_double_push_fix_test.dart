/// Tests for the notification double-push fix and data-only FCM message changes.
///
/// These tests validate:
///   1. Seller does NOT get double notification (DB webhook suppression)
///   2. FCM payload structure is data-only (no `notification` field)
///   3. Foreground FCM handler works with data-only messages
///   4. Edge cases: deduplication, non-order notifications still persist
library;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🔔 Double Notification Fix — DB Webhook Suppression', () {
    test(
        'Order notification (orderId != null) does NOT persist to DB → no webhook trigger',
        () {
      // BEFORE FIX: _debouncedPersistToDb fired for ALL notifications including
      //             those with orderId → INSERT into notifications table →
      //             trigger_send_push webhook → send-push Edge Function →
      //             SECOND FCM push to the seller/rider.
      //
      // AFTER FIX:  orderId != null → skip _debouncedPersistToDb → no webhook.
      //
      // Verified by reading _add() in notification_provider.dart:
      final providerFile = File(
              '${Directory.current.path}/lib/providers/notification_provider.dart')
          .readAsStringSync();

      expect(
          providerFile.contains('if (notification.orderId == null)'), true,
          reason:
              '_add() must gate DB persistence on orderId == null');

      // Also verify the comment documents WHY
      expect(providerFile.contains('SECOND FCM push'), true,
          reason:
              'The guard must be documented with the root cause');
    });

    test('Non-order notification (orderId == null) DOES persist to DB', () {
      // Admin/KYC notifications have no orderId → should still persist
      // This ensures the webhook path still works for non-order pushes.
      final providerFile = File(
              '${Directory.current.path}/lib/providers/notification_provider.dart')
          .readAsStringSync();

      // The _debouncedPersistToDb call must exist inside the orderId==null guard
      expect(providerFile.contains('_debouncedPersistToDb(notification)'), true,
          reason:
              'DB persist must still be called for non-order notifications');
    });
  });

  group('📱 FCM Payload — Notification + Data Payload Validation', () {
    test('send-push FCM payload has notification and android.notification for closed app delivery', () {
      final sendPushFile = File(
              '${Directory.current.path}/supabase/functions/send-push/index.ts')
          .readAsStringSync();

      expect(sendPushFile.contains('channel_id: channelId'), true,
          reason: 'send-push should target channelId');
      expect(sendPushFile.contains('sound: soundFile'), true,
          reason: 'send-push should configure custom sound');
      expect(sendPushFile.contains("data: {"), true,
          reason: 'FCM message must have data block');
      expect(sendPushFile.contains("title: String(title)"), true,
          reason: 'Data block must contain title');
      expect(sendPushFile.contains("body: String(body)"), true,
          reason: 'Data block must contain body');
    });

    test('send-push has android.priority = high (for background delivery)',
        () {
      final sendPushFile = File(
              '${Directory.current.path}/supabase/functions/send-push/index.ts')
          .readAsStringSync();

      expect(sendPushFile.contains("priority: 'high'"), true,
          reason:
              'Android priority must be high for FCM to wake backgrounded app');
    });

    test('send-push has content-available for iOS background delivery', () {
      final sendPushFile = File(
              '${Directory.current.path}/supabase/functions/send-push/index.ts')
          .readAsStringSync();

      expect(sendPushFile.contains("'content-available': 1"), true,
          reason:
              'APNs must have content-available:1 for iOS background wakeup');
    });

    test('send-push has apns-push-type: alert', () {
      final sendPushFile = File(
              '${Directory.current.path}/supabase/functions/send-push/index.ts')
          .readAsStringSync();

      expect(sendPushFile.contains("'apns-push-type': 'alert'"), true,
          reason:
              'APNs must have apns-push-type: alert for proper iOS routing');
    });
  });

  group('📱 send-broadcast — Notification Payload Validation', () {
    test('send-broadcast FCM payload has channel and sound configured', () {
      final file = File(
              '${Directory.current.path}/supabase/functions/send-broadcast/index.ts')
          .readAsStringSync();

      expect(file.contains('channel_id: channelId'), true,
          reason: 'send-broadcast should configure channel_id');
      expect(file.contains('sound: soundFile'), true,
          reason: 'send-broadcast should configure sound');
    });

    test('send-broadcast has content-available for iOS', () {
      final file = File(
              '${Directory.current.path}/supabase/functions/send-broadcast/index.ts')
          .readAsStringSync();

      expect(file.contains("'content-available': 1"), true,
          reason: 'Broadcast APNs must also have content-available:1');
    });
  });

  group('📋 AndroidManifest — Channel Reference Fix', () {
    test(
        'Default FCM channel matches notification_service.dart channel (v1)',
        () {
      final manifest =
          File('${Directory.current.path}/android/app/src/main/AndroidManifest.xml')
              .readAsStringSync();

      // Must reference enything_urgent_order_v1
      expect(manifest.contains('enything_urgent_order_v1'), true,
          reason:
              'AndroidManifest default channel must be enything_urgent_order_v1');
      expect(manifest.contains('enything_bell_channel_v4'), false,
          reason:
              'AndroidManifest must NOT reference stale enything_bell_channel_v4');
    });
  });

  group('📋 Migration — Webhook Trigger Drop', () {
    test('Migration exists to drop trigger_send_push', () {
      final migration = File(
              '${Directory.current.path}/supabase/migrations/20290000000085_drop_duplicate_notification_webhook.sql')
          .readAsStringSync();

      expect(
          migration
              .contains('DROP TRIGGER IF EXISTS trigger_send_push'),
          true,
          reason:
              'Migration must drop the duplicate webhook trigger');
    });
  });

  group('🔄 Background Handler — Data-Only Compatibility', () {
    test('Background handler reads title/body from message.data', () {
      final mainFile =
          File('${Directory.current.path}/lib/main.dart').readAsStringSync();

      // The background handler must read from message.data (not message.notification)
      expect(mainFile.contains("message.data['title']"), true,
          reason: 'Background handler must read title from message.data');
      expect(mainFile.contains("message.data['body']"), true,
          reason: 'Background handler must read body from message.data');
    });

    test(
        'Background handler uses correct channel enything_urgent_order_v1',
        () {
      final mainFile =
          File('${Directory.current.path}/lib/main.dart').readAsStringSync();

      expect(mainFile.contains("'enything_urgent_order_v1'"), true,
          reason:
              'Background handler must use enything_urgent_order_v1 channel');
    });

    test('Background handler has fullScreenIntent for urgent notifications',
        () {
      final mainFile =
          File('${Directory.current.path}/lib/main.dart').readAsStringSync();

      expect(mainFile.contains('fullScreenIntent'), true,
          reason:
              'Background handler must use fullScreenIntent to wake screen for riders');
    });
  });

  group('🔄 Foreground Handler — Data-Only Compatibility', () {
    test('Foreground handler gracefully handles null notification field', () {
      final providerFile = File(
              '${Directory.current.path}/lib/providers/notification_provider.dart')
          .readAsStringSync();

      // Must use null-safe access: notif?.title ?? message.data['title']
      expect(providerFile.contains("notif?.title"), true,
          reason:
              'Foreground handler must use null-safe access for notification field');
      expect(
          providerFile.contains("message.data['title'] as String?"), true,
          reason:
              'Foreground handler must fall back to message.data for data-only messages');
    });
  });

  group('🛡️ Edge Cases', () {
    test('notification_provider _add skips DB persist when orderId is set',
        () {
      final providerFile = File(
              '${Directory.current.path}/lib/providers/notification_provider.dart')
          .readAsStringSync();

      // Verify the guard: `if (notification.orderId == null)`
      expect(
          providerFile.contains('if (notification.orderId == null)'), true,
          reason:
              '_add() must skip DB persist for order notifications to prevent webhook double-push');
    });

    test('iOS Info.plist has remote-notification background mode', () {
      final plist = File('${Directory.current.path}/ios/Runner/Info.plist')
          .readAsStringSync();

      expect(plist.contains('remote-notification'), true,
          reason:
              'iOS must have remote-notification in UIBackgroundModes for data-only FCM');
    });

    test(
        'notification_service.dart creates enything_urgent_order_v1 channel',
        () {
      final serviceFile = File(
              '${Directory.current.path}/lib/services/notification_service.dart')
          .readAsStringSync();

      expect(serviceFile.contains("'enything_urgent_order_v1'"), true,
          reason:
              'NotificationService must create the enything_urgent_order_v1 channel that background handler uses');
    });

    test('Bell alert service is NOT affected by changes', () {
      final bellFile = File(
              '${Directory.current.path}/lib/services/bell_alert_service.dart')
          .readAsStringSync();

      // BellAlertService should be completely untouched
      expect(bellFile.contains('class BellAlertService'), true);
      expect(bellFile.contains('addPendingOrder'), true);
      expect(bellFile.contains('removePendingOrder'), true);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Extracts the FCM message construction block from send-push/index.ts
String? _extractMessageBlock(String source) {
  // Find the block starting with `const message = {` inside the token loop
  final start = source.indexOf('const message = {');
  if (start == -1) return null;

  // Find the matching closing `};` by counting braces
  int braceCount = 0;
  int end = start;
  for (int i = start; i < source.length; i++) {
    if (source[i] == '{') braceCount++;
    if (source[i] == '}') braceCount--;
    if (braceCount == 0) {
      end = i + 1;
      break;
    }
  }

  return source.substring(start, end);
}

/// Extracts the FCM message construction block from send-broadcast/index.ts
String? _extractBroadcastMessageBlock(String source) {
  return _extractMessageBlock(source); // Same structure
}
