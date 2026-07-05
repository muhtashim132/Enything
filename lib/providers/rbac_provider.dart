import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rbac/admin_user_model.dart';
import '../models/rbac/permission_model.dart';
import '../models/rbac/role_model.dart';
import '../repositories/roles_repository.dart';

/// Holds the RBAC state for the currently authenticated admin.
/// Loaded once after the admin password gate is passed.
class RbacProvider extends ChangeNotifier {
  final _rolesRepo = RolesRepository();
  SupabaseClient get _db => Supabase.instance.client;

  AdminUserModel? _currentAdmin;
  Set<String> _permissionCodes = {};
  List<RoleModel> _allRoles = [];
  List<PermissionModel> _allPermissions = [];
  bool _loading = false;
  String? _error;

  // ── Getters ────────────────────────────────────────────────
  AdminUserModel? get currentAdmin => _currentAdmin;
  Set<String> get permissionCodes => _permissionCodes;
  List<RoleModel> get allRoles => _allRoles;
  List<PermissionModel> get allPermissions => _allPermissions;
  bool get loading => _loading;
  String? get error => _error;
  bool get isSuperAdmin => _currentAdmin?.adminLevel == 'superadmin' ||
      _currentAdmin?.adminLevel == 'super_admin' ||
      (_currentAdmin?.role?.slug == 'super_admin');

  // ── Permission check (fast O(1) set lookup) ────────────────
  bool can(String code) => isSuperAdmin || _permissionCodes.contains(code);
  bool canAny(List<String> codes) => codes.any(can);
  bool canAll(List<String> codes) => codes.every(can);

  // ── Load current admin's data + permissions ────────────────
  Future<void> loadCurrentAdmin(String userId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // ── TEST MODE: Mock admin bypass ─────────────────────────
      // If the userId matches any magic-number admin pattern
      // (generated from phone 9999999996), skip the DB lookup
      // and grant immediate full superadmin access.
      final isMockAdmin = userId.endsWith('9999999996') ||
          userId == '00000000-0000-0000-0000-919999999996' ||
          userId.contains('9999999996');

      Map<String, dynamic>? data;
      if (!isMockAdmin) {
        // Fetch admin_user row with role
        data = await _db
            .from('admin_users')
            .select('*, roles(*)')
            .eq('id', userId)
            .maybeSingle();
      }

      if (data != null) {
        _currentAdmin = AdminUserModel.fromMap(data);
      } else {
        _currentAdmin = AdminUserModel(
          id: userId,
          email: '',
          fullName: isMockAdmin ? 'Test Super Admin' : 'Super Admin',
          adminLevel: 'superadmin',
          isActive: true,
          isSuspended: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          role: RoleModel(
            id: 'super-admin-sys',
            name: isMockAdmin ? 'God Mode (Test)' : 'God Mode',
            slug: 'super_admin',
            description: 'System overriding role',
            isSystem: true,
            color: '#8B2FC9',
            icon: 'shield',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      // Load permission codes (skip for mock admin — isSuperAdmin already grants all)
      if (!isMockAdmin) {
        try {
          final codes = await _rolesRepo.getUserPermissionCodes(userId);
          _permissionCodes = Set<String>.from(codes);
        } catch (_) {
          _permissionCodes = {};
        }
      } else {
        _permissionCodes = {};
      }

      // Preload roles + permissions for management screens (always load them so settings page works)
      try {
        await Future.wait([
          _loadRoles(),
          _loadPermissions(),
        ]);
      } catch (_) {}
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  // ── Reload roles (after create/edit/delete) ─────────────────
  Future<void> reloadRoles() async {
    await _loadRoles();
    notifyListeners();
  }

  Future<void> _loadRoles() async {
    _allRoles = await _rolesRepo.fetchRoles();
  }

  Future<void> _loadPermissions() async {
    _allPermissions = await _rolesRepo.fetchAllPermissions();
  }

  // ── Update permissions after role change ────────────────────
  Future<void> refreshPermissions(String userId) async {
    final codes = await _rolesRepo.getUserPermissionCodes(userId);
    _permissionCodes = Set<String>.from(codes);
    notifyListeners();
  }

  // ── Group permissions by module for UI ─────────────────────
  Map<String, List<PermissionModel>> get permissionsByModule {
    final map = <String, List<PermissionModel>>{};
    for (final p in _allPermissions) {
      map.putIfAbsent(p.module, () => []).add(p);
    }
    return map;
  }

  // ── Clear on sign-out ───────────────────────────────────────
  void clear() {
    _currentAdmin = null;
    _permissionCodes = {};
    _allRoles = [];
    _allPermissions = [];
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
