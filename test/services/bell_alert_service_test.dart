import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/bell_alert_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await BellAlertService.instance.clearAll();
  });

  test('BellAlertService balances pending orders correctly', () async {
    final service = BellAlertService.instance;
    expect(service.hasPendingOrders, isFalse);

    await service.addPendingOrder('order1');
    expect(service.pendingCount, 1);
    expect(service.hasPendingOrders, isTrue);

    // Duplicate add should be ignored
    await service.addPendingOrder('order1');
    expect(service.pendingCount, 1);

    await service.addPendingOrder('order2');
    expect(service.pendingCount, 2);

    await service.removePendingOrder('order1');
    expect(service.pendingCount, 1);

    await service.removePendingOrder('order2');
    expect(service.pendingCount, 0);
    expect(service.hasPendingOrders, isFalse);
  });

  test('BellAlertService race condition on concurrent adds', () async {
    final service = BellAlertService.instance;
    
    // Fire concurrent requests
    await Future.wait<void>([
      service.addPendingOrder('async1'),
      service.addPendingOrder('async2'),
      service.addPendingOrder('async3'),
    ]);

    expect(service.pendingCount, 3);
    
    await service.clearAll();
    expect(service.pendingCount, 0);
  });
}
