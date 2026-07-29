class AuditLogModel {
  final String id;
  final String? actorId;
  final String? actorRole;
  final String action;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> metadata;
  final String? ipAddress;
  final String? deviceInfo;
  final DateTime createdAt;

  // Joined data (optional)
  final String? actorName;
  final String? actorEmail;

  const AuditLogModel({
    required this.id,
    this.actorId,
    this.actorRole,
    required this.action,
    this.entityType,
    this.entityId,
    required this.metadata,
    this.ipAddress,
    this.deviceInfo,
    required this.createdAt,
    this.actorName,
    this.actorEmail,
  });

  String get actionLabel {
    return action
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    final actorData = map['admin_users'] as Map<String, dynamic>?;

    return AuditLogModel(
      id: map['id'] as String? ?? '',
      actorId: map['actor_id'] as String?,
      actorRole: map['actor_role'] as String?,
      action: map['action'] as String? ?? '',
      entityType: map['entity_type'] as String?,
      entityId: map['entity_id'] as String?,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : {},
      ipAddress: map['ip_address'] as String?,
      deviceInfo: map['device_info'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      actorName: actorData?['full_name'] as String?,
      actorEmail: actorData?['email'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'actor_id': actorId,
        'actor_role': actorRole,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': metadata,
        'ip_address': ipAddress,
        'device_info': deviceInfo,
      };
}
