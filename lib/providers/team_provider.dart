import 'package:flutter/material.dart';
import '../models/rbac/admin_user_model.dart';
import '../models/rbac/invitation_model.dart';
import '../repositories/team_repository.dart';

class TeamProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  final _repo = TeamRepository();

  List<AdminUserModel> _members = [];
  List<AdminUserModel> _filtered = [];
  List<AdminInvitationModel> _invitations = [];
  bool _loading = false;
  String? _error;
  String _search = '';

  List<AdminUserModel> get members => _filtered;
  List<AdminInvitationModel> get invitations => _invitations;
  bool get loading => _loading;
  String? get error => _error;

  // ── Load ────────────────────────────────────────────────────
  Future<void> loadTeam() async {
    _loading = true;
    _error = null;
    safeNotifyListeners();
    try {
      final results = await Future.wait([
        _repo.fetchTeamMembers(),
        _repo.fetchInvitations(),
      ]);
      _members = results[0] as List<AdminUserModel>;
      _invitations = results[1] as List<AdminInvitationModel>;
      _applySearch();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    safeNotifyListeners();
  }

  // ── Search ──────────────────────────────────────────────────
  void search(String query) {
    _search = query.toLowerCase();
    _applySearch();
    safeNotifyListeners();
  }

  void _applySearch() {
    if (_search.isEmpty) {
      _filtered = List.from(_members);
    } else {
      _filtered = _members.where((m) {
        return m.fullName.toLowerCase().contains(_search) ||
            m.email.toLowerCase().contains(_search) ||
            (m.role?.name.toLowerCase().contains(_search) ?? false);
      }).toList();
    }
  }

  // ── Invite ──────────────────────────────────────────────────
  Future<String?> inviteMember({
    required String email,
    required String roleId,
    required String invitedBy,
    required String actorRole,
  }) async {
    try {
      final inv = await _repo.sendInvitation(
        email: email,
        roleId: roleId,
        invitedBy: invitedBy,
        actorRole: actorRole,
      );
      _invitations.insert(0, inv);
      safeNotifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Assign Role ─────────────────────────────────────────────
  Future<String?> assignRole({
    required String userId,
    required String roleId,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      await _repo.assignRole(
        userId: userId,
        roleId: roleId,
        actorId: actorId,
        actorRole: actorRole,
      );
      await loadTeam();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Suspend ─────────────────────────────────────────────────
  Future<String?> suspendMember({
    required String userId,
    required String actorId,
    required String actorRole,
    String? reason,
  }) async {
    try {
      await _repo.suspendMember(
        userId: userId,
        actorId: actorId,
        actorRole: actorRole,
        reason: reason,
      );
      await loadTeam();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Reactivate ──────────────────────────────────────────────
  Future<String?> reactivateMember({
    required String userId,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      await _repo.reactivateMember(
        userId: userId,
        actorId: actorId,
        actorRole: actorRole,
      );
      await loadTeam();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Reset Password ──────────────────────────────────────────
  Future<String?> resetPassword({
    required String userId,
    required String newPassword,
    required String actorId,
    required String actorRole,
  }) async {
    try {
      await _repo.resetPassword(
        userId: userId,
        newPassword: newPassword,
        actorId: actorId,
        actorRole: actorRole,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Revoke invitation ────────────────────────────────────────
  Future<void> revokeInvitation(String id) async {
    await _repo.revokeInvitation(id);
    _invitations.removeWhere((i) => i.id == id);
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
