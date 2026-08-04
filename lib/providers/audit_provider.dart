import 'package:flutter/material.dart';
import '../models/rbac/audit_log_model.dart';
import '../repositories/audit_repository.dart';

class AuditProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  final _repo = AuditRepository();

  List<AuditLogModel> _logs = [];
  bool _loading = false;
  String? _error;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 30;

  // Filters
  String? _filterActorId;
  String? _filterAction;
  String? _filterEntityType;
  DateTime? _filterFrom;
  DateTime? _filterTo;

  List<AuditLogModel> get logs => _logs;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMore => _hasMore;

  // ── Load first page ─────────────────────────────────────────
  Future<void> load({
    String? actorId,
    String? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
  }) async {
    _filterActorId = actorId;
    _filterAction = action;
    _filterEntityType = entityType;
    _filterFrom = from;
    _filterTo = to;
    _offset = 0;
    _logs = [];
    _hasMore = true;
    await _fetch();
  }

  // ── Load next page ──────────────────────────────────────────
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    await _fetch();
  }

  Future<void> _fetch() async {
    _loading = true;
    _error = null;
    safeNotifyListeners();
    try {
      final results = await _repo.fetchLogs(
        actorId: _filterActorId,
        action: _filterAction,
        entityType: _filterEntityType,
        from: _filterFrom,
        to: _filterTo,
        limit: _pageSize,
        offset: _offset,
      );
      _logs.addAll(results);
      _hasMore = results.length == _pageSize;
      _offset += results.length;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    safeNotifyListeners();
  }

  // ── Log an action ───────────────────────────────────────────
  Future<void> log({
    required String actorId,
    required String actorRole,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    await _repo.log(
      actorId: actorId,
      actorRole: actorRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      metadata: metadata,
    );
  }

  void reset() {
    _logs = [];
    _offset = 0;
    _hasMore = true;
    _filterActorId = null;
    _filterAction = null;
    _filterEntityType = null;
    _filterFrom = null;
    _filterTo = null;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
