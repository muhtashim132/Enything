import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rbac/admin_user_model.dart';
import '../models/rbac/invitation_model.dart';
import '../models/rbac/permission_model.dart';

class TeamRepository {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Fetch all team members ──────────────────────────────────
  Future<List<AdminUserModel>> fetchTeamMembers() async {
    final data = await _db
        .from('admin_users')
        .select('*, roles(*)')
        .order('created_at', ascending: false);
    return (data as List)
        .map((u) => AdminUserModel.fromMap(u as Map<String, dynamic>))
        .toList();
  }

  // ── Fetch single team member with permissions ───────────────
  Future<AdminUserModel?> fetchMemberById(String userId) async {
    final data = await _db
        .from('admin_users')
        .select('*, roles(*)')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;

    final member = AdminUserModel.fromMap(data);

    // Load effective permissions
    final perms = await _db
        .rpc('get_user_permissions', params: {'p_user_id': userId});
    final permCodes = (perms as List).map((r) => r['code'] as String).toList();

    // Fetch full permission objects for those codes
    if (permCodes.isNotEmpty) {
      final permData = await _db
          .from('permissions')
          .select()
          .inFilter('code', permCodes);
      final permList = (permData as List)
          .map((p) => PermissionModel.fromMap(p as Map<String, dynamic>))
          .toList();
      return member.copyWith(effectivePermissions: permList);
    }
    return member;
  }

  // ── Assign role to team member ──────────────────────────────
  Future<void> assignRole({
    required String userId,
    required String roleId,
    required String actorId,
    required String actorRole,
  }) async {
    await _db.from('admin_users').update({'role_id': roleId}).eq('id', userId);
    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'role_assigned',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {'role_id': roleId},
    );
  }

  // ── Suspend team member ─────────────────────────────────────
  Future<void> suspendMember({
    required String userId,
    required String actorId,
    required String actorRole,
    String? reason,
  }) async {
    await _db.from('admin_users').update({
      'is_suspended': true,
      'suspended_at': DateTime.now().toIso8601String(),
      'suspended_by': actorId,
    }).eq('id', userId);
    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'member_suspended',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {'reason': reason ?? ''},
    );
  }

  // ── Reactivate team member ──────────────────────────────────
  Future<void> reactivateMember({
    required String userId,
    required String actorId,
    required String actorRole,
  }) async {
    await _db.from('admin_users').update({
      'is_suspended': false,
      'suspended_at': null,
      'suspended_by': null,
      'is_active': true,
    }).eq('id', userId);
    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'member_reactivated',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {},
    );
  }

  Future<void> resetPassword({
    required String userId,
    required String newPassword,
    required String actorId,
    required String actorRole,
  }) async {
    await _db
        .from('admin_users')
        .update({'admin_password': newPassword}).eq('id', userId);

    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'admin_password_reset',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {},
    );
  }

  // ── Send invitation ─────────────────────────────────────────
  Future<AdminInvitationModel> sendInvitation({
    required String email,
    required String roleId,
    required String invitedBy,
    required String actorRole,
  }) async {
    final data = await _db.from('admin_invitations').insert({
      'email': email,
      'role_id': roleId,
      'invited_by': invitedBy,
      'status': 'pending',
      'expires_at': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
    }).select('*, roles(name)').single();

    await _logAudit(
      actorId: invitedBy,
      actorRole: actorRole,
      action: 'invitation_sent',
      entityType: 'invitation',
      metadata: {'email': email, 'role_id': roleId},
    );

    return AdminInvitationModel.fromMap(data);
  }

  // ── Fetch pending invitations ───────────────────────────────
  Future<List<AdminInvitationModel>> fetchInvitations() async {
    final data = await _db
        .from('admin_invitations')
        .select('*, roles(name)')
        .order('created_at', ascending: false);
    return (data as List)
        .map((i) => AdminInvitationModel.fromMap(i as Map<String, dynamic>))
        .toList();
  }

  // ── Revoke invitation ───────────────────────────────────────
  Future<void> revokeInvitation(String invitationId) async {
    await _db.from('admin_invitations').update({'status': 'revoked'}).eq('id', invitationId);
  }



  Future<void> _logAudit({
    required String actorId,
    required String actorRole,
    required String action,
    String? entityType,
    String? entityId,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      await _db.from('audit_logs').insert({
        'actor_id': actorId,
        'actor_role': actorRole,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': metadata,
      });
    } catch (_) {}
  }
}
