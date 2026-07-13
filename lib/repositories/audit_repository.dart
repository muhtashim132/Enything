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
        .select();

    if (actorId != null) query = query.eq('actor_id', actorId);
    if (action != null && action.isNotEmpty) query = query.ilike('action', '%$action%');
    if (entityType != null && entityType.isNotEmpty) query = query.eq('entity_type', entityType);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
        
    final List<Map<String, dynamic>> rawLogs = (data as List).cast<Map<String, dynamic>>();
    
    // Phase 15.1 Fix: Decoupled admin_users fetch to prevent PostgREST FK crashes
    final actorIds = rawLogs.map((l) => l['actor_id']).whereType<String>().toSet().toList();
    Map<String, dynamic> adminMap = {};
    if (actorIds.isNotEmpty) {
      try {
        final admins = await _db.from('admin_users').select('id, full_name, email').inFilter('id', actorIds);
        adminMap = { for (var a in (admins as List).cast<Map<String, dynamic>>()) a['id'] as String: a };
      } catch (e) {
        // Safe fallback if admin_users fails
      }
    }

    return rawLogs.map((l) {
      final log = Map<String, dynamic>.from(l);
      final aId = log['actor_id'] as String?;
      if (aId != null && adminMap.containsKey(aId)) {
        log['admin_users'] = adminMap[aId];
      }
      return AuditLogModel.fromMap(log);
    }).toList();
  }

  Future<void> log({
    required String actorId,
    required String actorRole,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    // Phase 15.2 Fix: Fire-and-forget telemetry to prevent Double Timeout Locks
    _db.from('audit_logs').insert({
      'actor_id': actorId,
      'actor_role': actorRole,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'metadata': metadata ?? {},
    }).catchError((_) => null);
  }
}
