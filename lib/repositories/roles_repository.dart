import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rbac/role_model.dart';
import '../models/rbac/permission_model.dart';
import '../models/rbac/audit_log_model.dart';

class RolesRepository {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Fetch all roles with their permissions ──────────────────
  Future<List<RoleModel>> fetchRoles() async {
    final data = await _db
        .from('roles')
        .select('*, role_permissions(permissions(*))')
        .order('is_system', ascending: false)
        .order('name');
    return (data as List).map((r) => RoleModel.fromMap(r as Map<String, dynamic>)).toList();
  }

  // ── Fetch a single role ─────────────────────────────────────
  Future<RoleModel?> fetchRoleById(String roleId) async {
    final data = await _db
        .from('roles')
        .select('*, role_permissions(permissions(*))')
        .eq('id', roleId)
        .maybeSingle();
    if (data == null) return null;
    return RoleModel.fromMap(data);
  }

  // ── Create a custom role ────────────────────────────────────
  Future<RoleModel> createRole({
    required String name,
    required String description,
    required String color,
    required List<String> permissionCodes,
  }) async {
    final slug = name.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');

    final roleData = await _db.from('roles').insert({
      'name': name,
      'slug': slug,
      'description': description,
      'is_system': false,
      'color': color,
    }).select().single();

    final roleId = roleData['id'] as String;

    // Fetch permission IDs from codes
    if (permissionCodes.isNotEmpty) {
      final perms = await _db.from('permissions').select('id').inFilter('code', permissionCodes);
      final inserts = (perms as List).map((p) => {
        'role_id': roleId,
        'permission_id': p['id'] as String,
      }).toList();
      if (inserts.isNotEmpty) {
        await _db.from('role_permissions').insert(inserts);
      }
    }

    final createdRole = await fetchRoleById(roleId);
    return createdRole ?? RoleModel.fromMap(roleData);
  }

  // ── Update a custom role ────────────────────────────────────
  Future<void> updateRole({
    required String roleId,
    required String name,
    required String description,
    required String color,
    required List<String> permissionCodes,
  }) async {
    // Only allow editing non-system roles
    await _db.from('roles').update({
      'name': name,
      'description': description,
      'color': color,
    }).eq('id', roleId).eq('is_system', false);

    // Replace permissions: delete all then re-insert
    await _db.from('role_permissions').delete().eq('role_id', roleId);

    if (permissionCodes.isNotEmpty) {
      final perms = await _db.from('permissions').select('id').inFilter('code', permissionCodes);
      final inserts = (perms as List).map((p) => {
        'role_id': roleId,
        'permission_id': p['id'] as String,
      }).toList();
      if (inserts.isNotEmpty) {
        await _db.from('role_permissions').insert(inserts);
      }
    }
  }

  // ── Clone a role ────────────────────────────────────────────
  Future<RoleModel> cloneRole(String sourceRoleId, String newName) async {
    final source = await fetchRoleById(sourceRoleId);
    if (source == null) throw Exception('Source role not found');
    return createRole(
      name: newName,
      description: 'Copy of ${source.description}',
      color: source.color,
      permissionCodes: source.permissions.map((p) => p.code).toList(),
    );
  }

  // ── Delete a custom role ────────────────────────────────────
  Future<void> deleteRole(String roleId) async {
    // Guard: cannot delete system roles
    final role = await _db.from('roles').select('is_system').eq('id', roleId).single();
    if (role['is_system'] == true) throw Exception('Cannot delete system roles');
    await _db.from('roles').delete().eq('id', roleId);
  }

  // ── Fetch all permissions ───────────────────────────────────
  Future<List<PermissionModel>> fetchAllPermissions() async {
    final data = await _db.from('permissions').select().order('module').order('code');
    return (data as List).map((p) => PermissionModel.fromMap(p as Map<String, dynamic>)).toList();
  }

  // ── Get effective permissions for a user ────────────────────
  Future<List<String>> getUserPermissionCodes(String userId) async {
    final data = await _db.rpc('get_user_permissions', params: {'p_user_id': userId});
    return (data as List).map((r) => r['code'] as String).toList();
  }

  // ── Check a single permission ───────────────────────────────
  Future<bool> hasPermission(String userId, String code) async {
    final result = await _db.rpc('has_permission', params: {
      'p_user_id': userId,
      'p_code': code,
    });
    return result as bool? ?? false;
  }

  // ── Log audit event ─────────────────────────────────────────
  Future<void> logAudit(AuditLogModel log) async {
    await _db.from('audit_logs').insert(log.toInsertMap());
  }
}
