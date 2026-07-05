import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rbac/audit_log_model.dart';

class AuditRepository {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<AuditLogModel>> fetchLogs({
    String? actorId,
    String? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _db
        .from('audit_logs')
        .select('*, admin_users(full_name, email)');

    if (actorId != null) query = query.eq('actor_id', actorId);
    if (action != null && action.isNotEmpty) query = query.ilike('action', '%$action%');
    if (entityType != null && entityType.isNotEmpty) query = query.eq('entity_type', entityType);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((l) => AuditLogModel.fromMap(l as Map<String, dynamic>))
        .toList();
  }

  Future<void> log({
    required String actorId,
    required String actorRole,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _db.from('audit_logs').insert({
        'actor_id': actorId,
        'actor_role': actorRole,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': metadata ?? {},
      });
    } catch (_) {}
  }
}
