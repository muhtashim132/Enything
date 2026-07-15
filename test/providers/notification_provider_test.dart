import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/providers/notification_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeSupabaseClient implements SupabaseClient {
  @override
  GoTrueClient get auth => FakeGoTrueClient();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGoTrueClient implements GoTrueClient {
  @override
  User? get currentUser => User(
        id: 'user_1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('NotificationProvider Deduplication Tests', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider(mockClient: FakeSupabaseClient());
    });

    test('Initialization with mock client does not throw', () {
      expect(provider, isNotNull);
      expect(provider.notifications.isEmpty, true);
    });
  });
}
