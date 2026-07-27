import 'package:flutter/material.dart';
import 'permission_model.dart';

enum RoleType { system, custom }

class RoleModel {
  final String id;
  final String name;
  final String slug;
  final String description;
  final bool isSystem;
  final String color;
  final String icon;
  final List<PermissionModel> permissions;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.isSystem,
    required this.color,
    required this.icon,
    this.permissions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  RoleType get type => isSystem ? RoleType.system : RoleType.custom;
  int get permissionCount => permissions.length;

  bool hasPermission(String code) => permissions.any((p) => p.code == code);

  Color get badgeColor {
    try {
      final hex = color.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF8B2FC9);
    }
  }

  factory RoleModel.fromMap(Map<String, dynamic> map) {
    final perms = (map['role_permissions'] as List<dynamic>? ?? [])
        .map((rp) {
          final permMap = rp is Map<String, dynamic> ? rp['permissions'] : null;
          if (permMap == null) return null;
          return PermissionModel.fromMap(permMap as Map<String, dynamic>);
        })
        .whereType<PermissionModel>()
        .toList();

    return RoleModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String? ?? '',
      isSystem: map['is_system'] as bool? ?? false,
      color: map['color'] as String? ?? '#8B2FC9',
      icon: map['icon'] as String? ?? 'shield',
      permissions: perms,
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
        'name': name,
        'slug': slug,
        'description': description,
        'is_system': isSystem,
        'color': color,
        'icon': icon,
      };

  RoleModel copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    bool? isSystem,
    String? color,
    String? icon,
    List<PermissionModel>? permissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      RoleModel(
        id: id ?? this.id,
        name: name ?? this.name,
        slug: slug ?? this.slug,
        description: description ?? this.description,
        isSystem: isSystem ?? this.isSystem,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        permissions: permissions ?? this.permissions,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RoleModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
