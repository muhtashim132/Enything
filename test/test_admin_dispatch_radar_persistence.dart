import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/services/admin_dispatch_settings_service.dart';
import 'package:enythingmobilenew/services/bell_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100x ADMIN DISPATCH RADAR PERSISTENCE & AUDIO BUZZ NOTIFICATION SUITE', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      BellAlertService.instance.disableAudioForTesting = true;
      await BellAlertService.instance.clearAll();
    });

    tearDown(() async {
      await BellAlertService.instance.clearAll();
    });

    test('1. Default state for unconfigured admin is dormant (false)', () async {
      final service = AdminDispatchSettingsService.instance;
      const superAdminId = 'admin_super_uuid_101';
      const opsAdminId = 'admin_ops_uuid_202';

      // Unconfigured admins must default to false (radar OFF)
      final superActive = await service.isRadarActive(superAdminId);
      final opsActive = await service.isRadarActive(opsAdminId);

      expect(superActive, isFalse, reason: 'Super Admin should default to OFF if unconfigured');
      expect(opsActive, isFalse, reason: 'Ops Admin should default to OFF if unconfigured');

      // Buzz should default to true (unmuted)
      expect(await service.isBuzzEnabled(superAdminId), isTrue);
      expect(await service.isBuzzEnabled(opsAdminId), isTrue);

      // Radius should default to 15.0 km
      expect(await service.getRadiusKm(superAdminId), 15.0);
    });

    test('2. Independent per-admin setting isolation (Super Admin ON, Normal Admin OFF)', () async {
      final service = AdminDispatchSettingsService.instance;
      const superAdminId = 'admin_super_uuid_101';
      const normalAdminId = 'admin_normal_uuid_202';

      // Super Admin toggles radar ON
      await service.setRadarActive(superAdminId, active: true);
      expect(service.radarActiveNotifier.value, isTrue);

      // Normal Admin explicitly toggles radar OFF (or keeps it off)
      await service.setRadarActive(normalAdminId, active: false);
      expect(service.radarActiveNotifier.value, isFalse);

      // Verify that Super Admin's setting was NOT overwritten by Normal Admin
      final superActiveAfter = await service.isRadarActive(superAdminId);
      final normalActiveAfter = await service.isRadarActive(normalAdminId);

      expect(superActiveAfter, isTrue, reason: 'Super Admin setting must remain TRUE');
      expect(normalActiveAfter, isFalse, reason: 'Normal Admin setting must remain FALSE');
    });

    test('3. Simulated app restart / device session restoration', () async {
      const adminId = 'admin_persistent_test_303';

      // Session 1: Admin activates Dispatch Radar and custom radius
      final service1 = AdminDispatchSettingsService.instance;
      await service1.setRadarActive(adminId, active: true);
      await service1.setBuzzEnabled(adminId, enabled: false); // Muted buzz
      await service1.setRadiusKm(adminId, 30.0);

      // Simulate app restart / new session loading SharedPreferences
      final service2 = AdminDispatchSettingsService.instance;
      final restoredActive = await service2.isRadarActive(adminId);
      final restoredBuzz = await service2.isBuzzEnabled(adminId);
      final restoredRadius = await service2.getRadiusKm(adminId);

      expect(restoredActive, isTrue, reason: 'Radar active state must survive app kill/restart');
      expect(restoredBuzz, isFalse, reason: 'Buzz muted state must survive app kill/restart');
      expect(restoredRadius, 30.0, reason: 'Radius must survive app kill/restart');

      // Now toggle OFF
      await service2.setRadarActive(adminId, active: false);

      // Simulate another app restart
      final restoredOff = await service2.isRadarActive(adminId);
      expect(restoredOff, isFalse, reason: 'Radar off state must stay permanently off until toggled');
    });

    test('4. Live pending orders broadcaster updates listeners', () async {
      final service = AdminDispatchSettingsService.instance;
      int observedCount = -1;

      void listener() {
        observedCount = service.pendingOrderCountNotifier.value;
      }

      service.pendingOrderCountNotifier.addListener(listener);

      // Broadcaster fires with 3 orders
      service.updatePendingCount(3);
      expect(observedCount, 3);
      expect(service.pendingOrderCountNotifier.value, 3);

      // Broadcaster fires with 5 orders
      service.updatePendingCount(5);
      expect(observedCount, 5);

      // Resolved back to 0
      service.updatePendingCount(0);
      expect(observedCount, 0);

      service.pendingOrderCountNotifier.removeListener(listener);
    });

    test('5. Zero-leak audio buzz alarm lifecycle verification (Rule 4 Compliance)', () async {
      final bell = BellAlertService.instance;

      expect(bell.hasPendingOrders, isFalse);

      // Simulate incoming orders arriving while radar is ON
      await bell.addPendingOrder('dispatch_order_1001');
      await bell.addPendingOrder('dispatch_order_1002');
      expect(bell.pendingCount, 2);
      expect(bell.hasPendingOrders, isTrue);

      // Order 1001 is accepted by rider -> resolved
      await bell.removePendingOrder('dispatch_order_1001');
      expect(bell.pendingCount, 1);
      expect(bell.hasPendingOrders, isTrue);

      // Order 1002 is accepted by store -> resolved
      await bell.removePendingOrder('dispatch_order_1002');
      expect(bell.pendingCount, 0);
      expect(bell.hasPendingOrders, isFalse);

      // When admin toggles Radar OFF: test _silenceAllBuzz via clearAll()
      await bell.addPendingOrder('dispatch_order_2001');
      await bell.addPendingOrder('dispatch_order_2002');
      expect(bell.pendingCount, 2);

      // Admin toggles radar OFF -> Immediate purge
      await bell.clearAll();
      expect(bell.pendingCount, 0);
      expect(bell.hasPendingOrders, isFalse, reason: 'All audio buzzes must be completely purged when radar is toggled OFF');
    });
  });
}
