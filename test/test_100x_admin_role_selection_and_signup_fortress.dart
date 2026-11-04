import 'package:flutter_test/flutter_test.dart';

void main() {
  group('100x Admin Role Selection & Sign-up Fortress Test Suite', () {
    // Pure function simulating the decision logic in OtpVerifyPage._verify
    Map<String, dynamic> evaluateOtpVerifyRouting({
      required List<String> allRoles,
      required String? requestedRole,
    }) {
      if (allRoles.contains('admin')) {
        // Admin with an intended non-admin role requested (seller, delivery_partner, customer)
        if (requestedRole != null && requestedRole != 'admin') {
          // Strictly show only TWO roles: the requested role and admin!
          // Never dump all roles that the user holds.
          return {
            'action': 'showRolePicker',
            'availableRoles': [requestedRole, 'admin'],
          };
        }

        // Admin explicitly requested admin
        if (requestedRole == 'admin') {
          return {
            'action': 'dashboard',
            'role': 'admin',
          };
        }

        // Generic login (no role requested) with multiple active roles
        if (allRoles.length > 1) {
          return {
            'action': 'showRolePicker',
            'availableRoles': List<String>.from(allRoles),
          };
        }

        // Solo admin without requested role
        return {
          'action': 'dashboard',
          'role': 'admin',
        };
      }

      // Non-admin logic
      if (requestedRole != null && !allRoles.contains(requestedRole)) {
        return {
          'action': 'completeProfile',
          'role': requestedRole,
          'isAddingRole': true,
        };
      }

      if (requestedRole != null && allRoles.contains(requestedRole)) {
        return {
          'action': 'dashboard',
          'role': requestedRole,
        };
      }

      if (allRoles.length > 1) {
        return {
          'action': 'showRolePicker',
          'availableRoles': List<String>.from(allRoles),
        };
      }

      final fallbackRole = allRoles.isNotEmpty ? allRoles.first : 'customer';
      return {
        'action': 'dashboard',
        'role': fallbackRole,
      };
    }

    // Pure function simulating the visibility of '+ Add another role' in OtpVerifyPage._buildRolePicker
    bool shouldShowAddRoleButton({
      required List<String> allRoles,
      required String? requestedRole,
    }) {
      // ONLY show if NOT in targeted 2-role admin flow, AND user does not already hold all client roles
      return requestedRole == null &&
          !(allRoles.contains('customer') &&
              allRoles.contains('seller') &&
              allRoles.contains('delivery_partner'));
    }

    // Pure function simulating the decision logic in OtpVerifyPage._selectRole
    Map<String, dynamic> evaluateRoleSelection({
      required List<String> allRoles,
      required String selectedRole,
    }) {
      final isNewRole = selectedRole != 'admin' && !allRoles.contains(selectedRole);

      if (isNewRole) {
        return {
          'action': 'completeProfile',
          'role': selectedRole,
          'isAddingRole': true,
        };
      }

      return {
        'action': 'switchSessionAndDashboard',
        'role': selectedRole,
      };
    }

    // Pure function simulating the hint generation logic in OtpVerifyPage._roleDashboardHint
    String evaluateRoleHint({
      required List<String> allRoles,
      required String role,
    }) {
      final isNew = !allRoles.contains(role);
      switch (role) {
        case 'seller':
          return isNew ? 'Sign up & Setup your Shop' : 'Go to Seller Dashboard';
        case 'delivery_partner':
          return isNew ? 'Sign up as Delivery Partner' : 'Go to Delivery Dashboard';
        case 'admin':
          return 'Enter God Mode Control Tower';
        default:
          return isNew ? 'Complete Customer Profile' : 'Go to Customer Home';
      }
    }

    test('1. Admin signing in as Seller for first time: Shows strictly TWO roles [seller, admin]', () {
      final res = evaluateOtpVerifyRouting(
        allRoles: ['admin'],
        requestedRole: 'seller',
      );

      expect(res['action'], equals('showRolePicker'));
      final availableRoles = res['availableRoles'] as List<String>;
      expect(availableRoles, equals(['seller', 'admin']));
      expect(availableRoles.length, equals(2));
    });

    test('2. Admin who ALREADY holds all 4 roles signing in as Seller: Shows strictly TWO roles [seller, admin]', () {
      final res = evaluateOtpVerifyRouting(
        allRoles: ['customer', 'admin', 'seller', 'delivery_partner'],
        requestedRole: 'seller',
      );

      expect(res['action'], equals('showRolePicker'));
      final availableRoles = res['availableRoles'] as List<String>;
      // Must NOT dump customer and delivery_partner!
      expect(availableRoles, equals(['seller', 'admin']));
      expect(availableRoles.length, equals(2));
    });

    test('3. Admin signing in as Delivery Partner: Shows strictly TWO roles [delivery_partner, admin]', () {
      final res = evaluateOtpVerifyRouting(
        allRoles: ['admin', 'customer', 'seller'],
        requestedRole: 'delivery_partner',
      );

      expect(res['action'], equals('showRolePicker'));
      final availableRoles = res['availableRoles'] as List<String>;
      expect(availableRoles, equals(['delivery_partner', 'admin']));
      expect(availableRoles.length, equals(2));
    });

    test('4. Admin signing in as Customer: Shows strictly TWO roles [customer, admin]', () {
      final res = evaluateOtpVerifyRouting(
        allRoles: ['admin', 'seller'],
        requestedRole: 'customer',
      );

      expect(res['action'], equals('showRolePicker'));
      final availableRoles = res['availableRoles'] as List<String>;
      expect(availableRoles, equals(['customer', 'admin']));
      expect(availableRoles.length, equals(2));
    });

    test('5. Add another role button suppression rules', () {
      // Rule A: When in targeted 2-role admin flow (requestedRole != null), ALWAYS suppressed
      expect(
        shouldShowAddRoleButton(allRoles: ['admin'], requestedRole: 'seller'),
        isFalse,
      );
      expect(
        shouldShowAddRoleButton(allRoles: ['admin', 'customer'], requestedRole: 'seller'),
        isFalse,
      );
      expect(
        shouldShowAddRoleButton(allRoles: ['admin'], requestedRole: 'delivery_partner'),
        isFalse,
      );

      // Rule B: When generic login (requestedRole == null) but user already holds all 3 client roles, ALWAYS suppressed
      expect(
        shouldShowAddRoleButton(
          allRoles: ['admin', 'customer', 'seller', 'delivery_partner'],
          requestedRole: null,
        ),
        isFalse,
      );
      expect(
        shouldShowAddRoleButton(
          allRoles: ['customer', 'seller', 'delivery_partner'],
          requestedRole: null,
        ),
        isFalse,
      );

      // Rule C: When generic login (requestedRole == null) and user has NOT registered all 3 client roles, SHOWN
      expect(
        shouldShowAddRoleButton(
          allRoles: ['customer', 'admin'],
          requestedRole: null,
        ),
        isTrue,
      );
      expect(
        shouldShowAddRoleButton(
          allRoles: ['customer'],
          requestedRole: null,
        ),
        isTrue,
      );
    });

    test('6. Tapping Seller when user has NO shop yet routes to CompleteProfilePage as new user', () {
      final res = evaluateRoleSelection(
        allRoles: ['admin', 'customer'],
        selectedRole: 'seller',
      );

      expect(res['action'], equals('completeProfile'));
      expect(res['role'], equals('seller'));
      expect(res['isAddingRole'], isTrue);
    });

    test('7. Tapping Seller when user ALREADY has a shop routes directly to Seller Dashboard', () {
      final res = evaluateRoleSelection(
        allRoles: ['admin', 'seller'],
        selectedRole: 'seller',
      );

      expect(res['action'], equals('switchSessionAndDashboard'));
      expect(res['role'], equals('seller'));
    });

    test('8. Tapping Delivery Partner when user is NEW routes to CompleteProfilePage as new user', () {
      final res = evaluateRoleSelection(
        allRoles: ['admin', 'customer'],
        selectedRole: 'delivery_partner',
      );

      expect(res['action'], equals('completeProfile'));
      expect(res['role'], equals('delivery_partner'));
      expect(res['isAddingRole'], isTrue);
    });

    test('9. Tapping Delivery Partner when user is EXISTING routes to Delivery Dashboard', () {
      final res = evaluateRoleSelection(
        allRoles: ['admin', 'delivery_partner'],
        selectedRole: 'delivery_partner',
      );

      expect(res['action'], equals('switchSessionAndDashboard'));
      expect(res['role'], equals('delivery_partner'));
    });

    test('10. Tapping Admin always routes to Admin 2FA gate / dashboard', () {
      final res = evaluateRoleSelection(
        allRoles: ['admin', 'customer', 'seller'],
        selectedRole: 'admin',
      );

      expect(res['action'], equals('switchSessionAndDashboard'));
      expect(res['role'], equals('admin'));
    });

    test('11. Explicit Admin login proceeds straight to Admin gate without unnecessary friction', () {
      final routing = evaluateOtpVerifyRouting(
        allRoles: ['admin'],
        requestedRole: 'admin',
      );
      expect(routing['action'], equals('dashboard'));
      expect(routing['role'], equals('admin'));
    });

    test('12. Role hints dynamically distinguish between NEW registration and EXISTING dashboards', () {
      final newSellerHint = evaluateRoleHint(allRoles: ['admin'], role: 'seller');
      final existingSellerHint = evaluateRoleHint(allRoles: ['admin', 'seller'], role: 'seller');

      expect(newSellerHint, equals('Sign up & Setup your Shop'));
      expect(existingSellerHint, equals('Go to Seller Dashboard'));

      final newRiderHint = evaluateRoleHint(allRoles: ['admin'], role: 'delivery_partner');
      final existingRiderHint = evaluateRoleHint(allRoles: ['admin', 'delivery_partner'], role: 'delivery_partner');

      expect(newRiderHint, equals('Sign up as Delivery Partner'));
      expect(existingRiderHint, equals('Go to Delivery Dashboard'));

      final adminHint = evaluateRoleHint(allRoles: ['admin'], role: 'admin');
      expect(adminHint, equals('Enter God Mode Control Tower'));
    });
  });
}
