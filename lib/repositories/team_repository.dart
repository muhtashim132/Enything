import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rbac/admin_user_model.dart';
import '../models/rbac/invitation_model.dart';
import '../models/rbac/permission_model.dart';

class TeamRepository {
  SupabaseClient get _db => Supabase.instance.client;

  // ── Fetch all team members ──────────────────────────────────
  Future<List<AdminUserModel>> fetchTeamMembers() async {
    try {
      final data = await _db
          .from('admin_users')
          .select('*, roles(*)')
          .order('created_at', ascending: false);
      return (data as List)
          .map((u) => AdminUserModel.fromMap(u as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Fallback: two-step query
      final usersData = await _db
          .from('admin_users')
          .select('*')
          .order('created_at', ascending: false);
      final rolesData = await _db.from('roles').select('*');
      final Map<String, Map<String, dynamic>> rolesById = {
        for (final r in (rolesData as List))
          (r['id'] as String): r as Map<String, dynamic>,
      };

      return (usersData as List).map((u) {
        final map = Map<String, dynamic>.from(u as Map<String, dynamic>);
        final rId = map['role_id'] as String?;
        if (rId != null && rolesById.containsKey(rId)) {
          map['roles'] = rolesById[rId];
        }
        return AdminUserModel.fromMap(map);
      }).toList();
    }
  }

  // ── Fetch single team member with permissions ───────────────
  Future<AdminUserModel?> fetchMemberById(String userId) async {
    Map<String, dynamic>? data;
    try {
      data = await _db
          .from('admin_users')
          .select('*, roles(*)')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      final u = await _db
          .from('admin_users')
          .select('*')
          .eq('id', userId)
          .maybeSingle();
      if (u != null) {
        data = Map<String, dynamic>.from(u);
        final rId = data['role_id'] as String?;
        if (rId != null) {
          final r = await _db.from('roles').select('*').eq('id', rId).maybeSingle();
          if (r != null) data['roles'] = r;
        }
      }
    }
    if (data == null) return null;

    final member = AdminUserModel.fromMap(data);

    // Load effective permissions
    try {
      final perms =
          await _db.rpc('get_user_permissions', params: {'p_user_id': userId});
      final permCodes = (perms as List).map((r) => r['code'] as String).toList();

      if (permCodes.isNotEmpty) {
        final permData =
            await _db.from('permissions').select().inFilter('code', permCodes);
        final permList = (permData as List)
            .map((p) => PermissionModel.fromMap(p as Map<String, dynamic>))
            .toList();
        return member.copyWith(effectivePermissions: permList);
      }
    } catch (_) {}
    return member;
  }

  // ── Assign role to team member ──────────────────────────────
  Future<void> assignRole({
    required String userId,
    required String roleId,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      await _db.rpc('admin_assign_member_role', params: {
        'p_user_id': userId,
        'p_role_id': roleId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw Exception('The specified role does not exist or is invalid.');
      }
      rethrow;
    }
    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'role_assigned',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {'role_id': roleId},
    );
  }

  // ── Remove team member permanently ──────────────────────────
  Future<void> removeMember({
    required String userId,
    required String actorId,
    required String actorRole,
  }) async {
    if (userId == actorId) {
      throw Exception('Cannot remove your own account from the team.');
    }
    await _db.rpc('admin_remove_team_member', params: {
      'p_user_id': userId,
    });
    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'team_member_removed',
      entityType: 'admin_user',
      entityId: userId,
      metadata: {'user_id': userId},
    );
  }

  // ── Suspend team member ─────────────────────────────────────
  Future<void> suspendMember({
    required String userId,
    required String actorId,
    required String actorRole,
    String? reason,
  }) async {
    if (userId == actorId) {
      throw Exception('Cannot suspend your own account.');
    }
    await _db.from('admin_users').update({
      'is_suspended': true,
      'is_active': false,
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
    late final Map<String, dynamic> data;
    try {
      data = await _db
          .from('admin_invitations')
          .insert({
            'email': email,
            'role_id': roleId,
            'invited_by': invitedBy,
            'status': 'pending',
            'expires_at':
                DateTime.now().add(const Duration(days: 7)).toIso8601String(),
          })
          .select('*, roles(name)')
          .single();
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('An invitation is already pending for this email.');
      }
      rethrow;
    }

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
    await _db
        .from('admin_invitations')
        .update({'status': 'revoked'}).eq('id', invitationId);
  }

  // ── Delete invitation permanently ───────────────────────────
  Future<void> deleteInvitation(String invitationId) async {
    await _db
        .from('admin_invitations')
        .delete()
        .eq('id', invitationId);
  }

  // ── Add team member by phone ─────────────────────────────────
  Future<Map<String, dynamic>> addTeamMemberByPhone({
    required String phone,
    required String fullName,
    required String roleId,
    required String adminPassword,
    required String actorId,
    required String actorRole,
  }) async {
    final result = await _db.rpc('admin_add_team_member_by_phone', params: {
      'p_phone': phone,
      'p_full_name': fullName,
      'p_role_id': roleId,
      'p_admin_password': adminPassword,
    });

    await _logAudit(
      actorId: actorId,
      actorRole: actorRole,
      action: 'team_member_added_by_phone',
      entityType: 'admin_user',
      metadata: {'phone': phone, 'role_id': roleId, 'full_name': fullName},
    );

    return Map<String, dynamic>.from(result as Map);
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
