import 'role_model.dart';
import 'permission_model.dart';

enum AdminStatus { active, suspended, inactive }

class AdminUserModel {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final RoleModel? role;
  final String adminLevel;
  final bool isActive;
  final bool isSuspended;
  final DateTime? suspendedAt;
  final String? suspendedBy;
  final DateTime? lastLoginAt;
  final List<PermissionModel> effectivePermissions;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AdminUserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    this.avatarUrl,
    this.role,
    required this.adminLevel,
    required this.isActive,
    required this.isSuspended,
    this.suspendedAt,
    this.suspendedBy,
    this.lastLoginAt,
    this.effectivePermissions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  AdminStatus get status {
    if (isSuspended) return AdminStatus.suspended;
    if (!isActive) return AdminStatus.inactive;
    return AdminStatus.active;
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  }

  bool hasPermission(String code) =>
      effectivePermissions.any((p) => p.code == code) ||
      adminLevel == 'superadmin';

  factory AdminUserModel.fromMap(Map<String, dynamic> map) {
    RoleModel? role;
    if (map['roles'] != null) {
      role = RoleModel.fromMap(map['roles'] as Map<String, dynamic>);
    } else if (map['admin_level'] == 'superadmin') {
      role = RoleModel(
        id: 'super-admin-sys',
        name: 'God Mode',
        slug: 'super_admin',
        description: 'System overriding role',
        isSystem: true,
        color: '#8B2FC9',
        icon: 'shield',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final perms = (map['effective_permissions'] as List<dynamic>? ?? [])
        .map((p) => PermissionModel.fromMap(p as Map<String, dynamic>))
        .toList();

    return AdminUserModel(
      id: map['id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      role: role,
      adminLevel: map['admin_level'] as String? ?? 'admin',
      isActive: map['is_active'] as bool? ?? true,
      isSuspended: map['is_suspended'] as bool? ?? false,
      suspendedAt: map['suspended_at'] != null
          ? DateTime.parse(map['suspended_at'] as String)
          : null,
      suspendedBy: map['suspended_by'] as String?,
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.parse(map['last_login_at'] as String)
          : null,
      effectivePermissions: perms,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'avatar_url': avatarUrl,
        'role_id': role?.id,
        'admin_level': adminLevel,
        'is_active': isActive,
        'is_suspended': isSuspended,
      };

  AdminUserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
    RoleModel? role,
    String? adminLevel,
    bool? isActive,
    bool? isSuspended,
    DateTime? suspendedAt,
    String? suspendedBy,
    DateTime? lastLoginAt,
    List<PermissionModel>? effectivePermissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      AdminUserModel(
        id: id ?? this.id,
        email: email ?? this.email,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        role: role ?? this.role,
        adminLevel: adminLevel ?? this.adminLevel,
        isActive: isActive ?? this.isActive,
        isSuspended: isSuspended ?? this.isSuspended,
        suspendedAt: suspendedAt ?? this.suspendedAt,
        suspendedBy: suspendedBy ?? this.suspendedBy,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        effectivePermissions: effectivePermissions ?? this.effectivePermissions,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AdminUserModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
