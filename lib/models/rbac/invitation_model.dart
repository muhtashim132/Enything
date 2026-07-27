enum InvitationStatus { pending, accepted, expired, revoked }

class AdminInvitationModel {
  final String id;
  final String email;
  final String roleId;
  final String? roleName;
  final String token;
  final String invitedBy;
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const AdminInvitationModel({
    required this.id,
    required this.email,
    required this.roleId,
    this.roleName,
    required this.token,
    required this.invitedBy,
    required this.status,
    required this.expiresAt,
    this.acceptedAt,
    required this.createdAt,
  });

  bool get isExpired =>
      status == InvitationStatus.expired ||
      (status == InvitationStatus.pending &&
          expiresAt.isBefore(DateTime.now()));

  factory AdminInvitationModel.fromMap(Map<String, dynamic> map) {
    return AdminInvitationModel(
      id: map['id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      roleId: map['role_id'] as String? ?? '',
      roleName: (map['roles'] as Map<String, dynamic>?)?['name'] as String?,
      token: map['token'] as String? ?? '',
      invitedBy: map['invited_by'] as String? ?? '',
      status: _parseStatus(map['status'] as String? ?? 'pending'),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 7)),
      acceptedAt: map['accepted_at'] != null
          ? DateTime.parse(map['accepted_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  static InvitationStatus _parseStatus(String s) {
    switch (s) {
      case 'accepted':
        return InvitationStatus.accepted;
      case 'expired':
        return InvitationStatus.expired;
      case 'revoked':
        return InvitationStatus.revoked;
      default:
        return InvitationStatus.pending;
    }
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'role_id': roleId,
        'invited_by': invitedBy,
        'status': status.name,
        'expires_at': expiresAt.toIso8601String(),
      };
}
