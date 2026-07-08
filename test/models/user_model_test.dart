import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/user_model.dart';

void main() {
  group('UserModel', () {
    group('initials getter', () {
      test('handles standard first and last name', () {
        final user = UserModel(id: '1', role: 'customer', fullName: 'John Doe', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'JD');
      });

      test('handles double spaces between names (BUG-16 Fix)', () {
        final user = UserModel(id: '1', role: 'customer', fullName: 'John  Doe', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'JD');
      });

      test('handles trailing and leading spaces', () {
        final user = UserModel(id: '1', role: 'customer', fullName: '  Alice Smith  ', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'AS');
      });

      test('handles single name', () {
        final user = UserModel(id: '1', role: 'customer', fullName: 'Bob', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'B');
      });

      test('handles empty string', () {
        final user = UserModel(id: '1', role: 'customer', fullName: '', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'U');
      });

      test('handles spaces-only string', () {
        final user = UserModel(id: '1', role: 'customer', fullName: '   ', email: '', phone: '', createdAt: DateTime.now());
        expect(user.initials, 'U');
      });
    });
  });
}
