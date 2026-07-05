import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../theme/admin_theme.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active Sessions Page
// Super admins can view all active admin logins and revoke them.
// Regular admins can view and revoke their own other sessions.
// ─────────────────────────────────────────────────────────────────────────────

class ActiveSessionsPage extends StatefulWidget {
  const ActiveSessionsPage({super.key});

  @override
  State<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends State<ActiveSessionsPage> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() => _loading = true);
    try {
      // Join with admin_users to get the name/role, and roles table for role name
      final data = await _db.from('admin_sessions').select('''
        id, 
        device_info, 
        logged_in_at, 
        last_seen_at, 
        admin_id,
        admin_users!admin_sessions_admin_id_fkey(full_name, role:roles(name))
      ''').isFilter('revoked_at', null).order('last_seen_at', ascending: false);

      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Failed to load sessions: $e', error: true);
      }
    }
  }

  Future<void> _revokeSession(String sessionId, String adminId) async {
    final authProvider = context.read<AuthProvider>();
    final currentAdminId = authProvider.currentUserId;
    
    // Prevent revoking current session (checked in UI too)
    if (sessionId == authProvider.currentSessionId) {
       _showSnack('You cannot revoke your current active session.', error: true);
       return;
    }

    try {
      await _db.from('admin_sessions').update({
        'revoked_at': DateTime.now().toIso8601String(),
        'revoked_by': currentAdminId,
      }).eq('id', sessionId);

      // Audit Log
      try {
        await _db.from('audit_logs').insert({
          'actor_id': currentAdminId,
          'actor_role': 'admin',
          'action': 'revoke_session',
          'entity_type': 'admin_sessions',
          'entity_id': sessionId,
          'metadata': {'target_admin_id': adminId},
        });
      } catch (_) {}

      setState(() {
        _sessions.removeWhere((s) => s['id'] == sessionId);
      });
      _showSnack('Session revoked successfully.');
    } catch (e) {
      _showSnack('Failed to revoke session: $e', error: true);
    }
  }

  Future<void> _revokeAllOtherSessions() async {
    final authProvider = context.read<AuthProvider>();
    final currentSessionId = authProvider.currentSessionId;
    final currentAdminId = authProvider.currentUserId;

    if (currentSessionId == null) return;

    try {
      // First get IDs to revoke
      final toRevoke = _sessions
          .where((s) => s['id'] != currentSessionId)
          .map((s) => s['id'] as String)
          .toList();

      if (toRevoke.isEmpty) {
        _showSnack('No other active sessions found.');
        return;
      }

      await _db.from('admin_sessions').update({
        'revoked_at': DateTime.now().toIso8601String(),
        'revoked_by': currentAdminId,
      }).inFilter('id', toRevoke);
      
      // Audit Log
      try {
        await _db.from('audit_logs').insert({
          'actor_id': currentAdminId,
          'actor_role': 'admin',
          'action': 'revoke_all_other_sessions',
          'entity_type': 'admin_sessions',
          'metadata': {'revoked_count': toRevoke.length},
        });
      } catch (_) {}

      setState(() {
        _sessions.removeWhere((s) => s['id'] != currentSessionId);
      });
      
      _showSnack('Successfully revoked ${toRevoke.length} other session(s).');
    } catch (e) {
      _showSnack('Failed to revoke sessions: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminStyles.body(size: 13)),
      backgroundColor: error ? AdminColors.danger : AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final currentSessionId = context.watch<AuthProvider>().currentSessionId;
    final rbac = context.watch<RbacProvider>();

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Active Sessions', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AdminColors.textMuted),
            onPressed: _fetchSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Warning Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security_rounded, color: AdminColors.danger, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Revoking a session will immediately log the user out on their next action.',
                          style: AdminStyles.caption(color: AdminColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (rbac.isSuperAdmin && _sessions.length > 1) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _revokeAllOtherSessions,
                      icon: const Icon(Icons.logout_rounded, size: 16, color: AdminColors.danger),
                      label: Text('Revoke All Others', style: AdminStyles.label(color: AdminColors.danger)),
                      style: TextButton.styleFrom(
                        backgroundColor: AdminColors.danger.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 16),

                if (_sessions.isEmpty)
                  const AdminEmptyState(
                    icon: Icons.shield_rounded,
                    message: 'No active sessions found.',
                  )
                else
                  ..._sessions.map((session) {
                    final isCurrent = session['id'] == currentSessionId;
                    return _buildSessionCard(session, isCurrent).animate().fadeIn(delay: 50.ms).slideX(begin: -0.05);
                  }),
              ],
            ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, bool isCurrent) {
    final adminUser = session['admin_users'] as Map<String, dynamic>?;
    final fullName = adminUser?['full_name'] ?? 'Unknown Admin';
    final roleName = adminUser?['role']?['name'] ?? 'No Role';
    
    final loggedInAt = DateTime.parse(session['logged_in_at']);
    final lastSeenAt = DateTime.parse(session['last_seen_at']);
    final deviceInfo = session['device_info'] ?? 'Unknown Device';
    final sessionId = session['id'] as String;
    final adminId = session['admin_id'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent ? AdminColors.primary.withValues(alpha: 0.05) : AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AdminColors.primary.withValues(alpha: 0.3) : AdminColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isCurrent ? AdminColors.primary : AdminColors.surfaceHigh,
                child: Text(
                  fullName.substring(0, 1).toUpperCase(),
                  style: AdminStyles.title(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(fullName, style: AdminStyles.body(size: 15)),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          const AdminBadge(label: 'CURRENT', color: AdminColors.success, fontSize: 9),
                        ],
                      ],
                    ),
                    Text(roleName, style: AdminStyles.caption(color: AdminColors.textMuted)),
                  ],
                ),
              ),
              if (!isCurrent)
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: AdminColors.textMuted, size: 20),
                  tooltip: 'Revoke Session',
                  onPressed: () => _showRevokeDialog(sessionId, adminId, fullName),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AdminColors.cardBorder),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.devices_rounded, size: 16, color: AdminColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(deviceInfo, style: AdminStyles.caption(color: AdminColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logged In', style: AdminStyles.label()),
                    Text(timeago.format(loggedInAt), style: AdminStyles.caption()),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last Seen', style: AdminStyles.label()),
                    Text(timeago.format(lastSeenAt), style: AdminStyles.caption()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRevokeDialog(String sessionId, String adminId, String adminName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Revoke Session?', style: AdminStyles.title()),
        content: Text(
          'This will log $adminName out immediately on their next app interaction.',
          style: AdminStyles.body(color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AdminStyles.body(color: AdminColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _revokeSession(sessionId, adminId);
            },
            child: Text('Revoke', style: AdminStyles.body(color: AdminColors.danger)),
          ),
        ],
      ),
    );
  }
}
