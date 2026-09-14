import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/platform_config_provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../theme/admin_theme.dart';

class MaintenanceSettingsPage extends StatefulWidget {
  const MaintenanceSettingsPage({super.key});

  @override
  State<MaintenanceSettingsPage> createState() =>
      _MaintenanceSettingsPageState();
}

class _MaintenanceSettingsPageState extends State<MaintenanceSettingsPage> {
  late TextEditingController _messageCtrl;
  bool _saving = false;
  List<Map<String, dynamic>> _auditHistory = [];
  bool _loadingHistory = true;

  static const int _maxMessageLength = 500;

  static const List<Map<String, String>> _presets = [
    {
      'emoji': '🛠️',
      'label': 'Server Maintenance',
      'message':
          'Scheduled server maintenance in progress. Ordering will resume shortly.',
    },
    {
      'emoji': '💳',
      'label': 'Payment Gateway',
      'message':
          'Payment gateway upgrade in progress. Orders temporarily paused.',
    },
    {
      'emoji': '🌧️',
      'label': 'Weather Emergency',
      'message':
          'Severe weather advisory. Deliveries suspended for safety. We\'ll be back soon!',
    },
    {
      'emoji': '📦',
      'label': 'Inventory Audit',
      'message':
          'Inventory sync in progress. Shopping will resume in a few minutes.',
    },
  ];

  @override
  void initState() {
    super.initState();
    final config = context.read<PlatformConfigProvider>();
    _messageCtrl = TextEditingController(text: config.maintenanceMessage);
    _loadAuditHistory();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuditHistory() async {
    try {
      final data = await Supabase.instance.client
          .from('audit_logs')
          .select('actor_role, action, metadata, created_at')
          .or('action.eq.enable_maintenance_mode,action.eq.disable_maintenance_mode,action.eq.update_maintenance_message')
          .order('created_at', ascending: false)
          .limit(5);
      if (mounted) {
        setState(() {
          _auditHistory = List<Map<String, dynamic>>.from(data);
          _loadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Audit history load error: $e');
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _toggleMaintenanceMode(bool enable) async {
    final config = context.read<PlatformConfigProvider>();
    final rbac = context.read<RbacProvider>();
    final message = _messageCtrl.text.trim();

    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a message for customers',
            style: AdminStyles.body(size: 13)),
        backgroundColor: AdminColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (enable) {
      // Safety confirmation dialog
      final confirmed = await _showSafetyDialog();
      if (!confirmed) return;
    }

    setState(() => _saving = true);

    final currentAdminId = rbac.currentAdmin?.id ??
        Supabase.instance.client.auth.currentUser?.id ??
        '';
    final currentAdminRole = rbac.currentAdmin?.role?.name ?? 'Super Admin';

    final success = await config.setMaintenanceMode(
      enabled: enable,
      message: message,
      actorId: currentAdminId,
      actorRole: currentAdminRole,
    );

    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            enable
                ? '🔴 Maintenance mode activated — all orders paused'
                : '🟢 Store is back online — orders resumed',
            style: AdminStyles.body(size: 13, color: Colors.white),
          ),
          backgroundColor: enable ? AdminColors.danger : AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        _loadAuditHistory();
      }
    }
  }

  Future<void> _updateMessageNotice() async {
    final config = context.read<PlatformConfigProvider>();
    final rbac = context.read<RbacProvider>();
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) return;

    setState(() => _saving = true);
    final currentAdminId = rbac.currentAdmin?.id ??
        Supabase.instance.client.auth.currentUser?.id ??
        '';
    final currentAdminRole = rbac.currentAdmin?.role?.name ?? 'Admin';

    final success = await config.updateMaintenanceMessage(
      message: message,
      actorId: currentAdminId,
      actorRole: currentAdminRole,
    );

    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Customer notice updated successfully',
              style: AdminStyles.body(size: 13, color: Colors.white)),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        _loadAuditHistory();
      }
    }
  }

  Future<bool> _showSafetyDialog() async {
    bool canConfirm = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!canConfirm) {
            Future.delayed(const Duration(seconds: 3), () {
              if (ctx.mounted) setDialogState(() => canConfirm = true);
            });
          }
          return AlertDialog(
            backgroundColor: AdminColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AdminColors.danger, size: 28),
                const SizedBox(width: 10),
                Text('Pause All Orders?',
                    style: AdminStyles.heading(size: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will immediately block ALL new customer orders across the entire platform.',
                  style: AdminStyles.body(size: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  '• Existing orders will continue processing normally\n'
                  '• Customers will see your maintenance message\n'
                  '• The database trigger will reject any order attempts',
                  style:
                      AdminStyles.caption(color: AdminColors.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: AdminStyles.body(
                        size: 14, color: AdminColors.textSecondary)),
              ),
              AnimatedOpacity(
                opacity: canConfirm ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: ElevatedButton(
                  onPressed:
                      canConfirm ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    canConfirm ? 'Confirm — Pause Orders' : 'Wait 3s...',
                    style: AdminStyles.body(size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<PlatformConfigProvider>();
    final isActive = config.isMaintenanceMode;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Store Status & Maintenance', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: config.loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AdminColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Live Status Banner ─────────────────────────────────
                _buildStatusBanner(isActive),
                const SizedBox(height: 20),

                // ── Master Toggle Card ────────────────────────────────
                _buildToggleCard(config, isActive),
                const SizedBox(height: 20),

                // ── Message Editor ────────────────────────────────────
                _buildMessageCard(config),
                const SizedBox(height: 20),

                // ── Quick Presets ─────────────────────────────────────
                _buildPresetsCard(),
                const SizedBox(height: 20),

                // ── Live Customer Preview ─────────────────────────────
                _buildCustomerPreview(isActive),
                const SizedBox(height: 20),

                // ── Audit Trail ───────────────────────────────────────
                _buildAuditSection(),
                const SizedBox(height: 40),
              ],
            ).animate().fadeIn(duration: 300.ms),
    );
  }

  Widget _buildStatusBanner(bool isActive) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [const Color(0xFF7F1D1D), const Color(0xFF991B1B)]
              : [const Color(0xFF064E3B), const Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? AdminColors.danger.withValues(alpha: 0.5)
              : AdminColors.success.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isActive ? AdminColors.danger : AdminColors.success)
                .withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                isActive ? '🔴' : '🟢',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Maintenance Active' : 'Store Online',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? 'All new customer orders are blocked'
                      : 'Normal operations — customers can order',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.1);
  }

  Widget _buildToggleCard(PlatformConfigProvider config, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Master Control', style: AdminStyles.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Toggle to pause or resume all customer orders instantly',
            style: AdminStyles.caption(color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isActive
                      ? 'Orders Paused — Tap to Resume'
                      : 'Store Online — Tap to Pause',
                  style: AdminStyles.body(
                    size: 14,
                    color: isActive ? AdminColors.danger : AdminColors.success,
                  ),
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: AdminColors.primary, strokeWidth: 2),
                )
              else
                Switch.adaptive(
                  value: isActive,
                  activeTrackColor: AdminColors.danger,
                  inactiveTrackColor:
                      AdminColors.success.withValues(alpha: 0.3),
                  onChanged: (val) => _toggleMaintenanceMode(val),
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1);
  }

  Widget _buildMessageCard(PlatformConfigProvider config) {
    final hasMessageChanged =
        _messageCtrl.text.trim() != config.maintenanceMessage &&
            _messageCtrl.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer Notice', style: AdminStyles.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'This message is displayed on customer Cart, Checkout, and Home pages',
            style: AdminStyles.caption(color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            maxLength: _maxMessageLength,
            style: AdminStyles.body(size: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'e.g. We are upgrading our servers. Orders will resume at 6 PM.',
              hintStyle: AdminStyles.body(color: AdminColors.textMuted),
              filled: true,
              fillColor: AdminColors.bg,
              counterStyle: AdminStyles.caption(
                  color: AdminColors.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AdminColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          if (hasMessageChanged) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _updateMessageNotice,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: Text('Save Customer Notice',
                    style: AdminStyles.body(size: 13, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildPresetsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Presets', style: AdminStyles.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Tap to fill in a preset message',
            style: AdminStyles.caption(color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              return GestureDetector(
                onTap: () {
                  _messageCtrl.text = p['message']!;
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AdminColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p['emoji']!,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          p['label']!,
                          style: AdminStyles.body(size: 12.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1);
  }

  Widget _buildCustomerPreview(bool isActive) {
    final msg = _messageCtrl.text.trim().isEmpty
        ? 'Your maintenance message will appear here...'
        : _messageCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Customer Preview',
              style: AdminStyles.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'How customers will see the maintenance banner',
            style: AdminStyles.caption(color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),
          // Mock customer banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isActive
                    ? [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)]
                    : [const Color(0xFFE5E7EB), const Color(0xFFD1D5DB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isActive ? '⚠️' : '💤',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ordering Temporarily Paused',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF78350F),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1);
  }

  Widget _buildAuditSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Activity', style: AdminStyles.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Last 5 maintenance mode changes',
            style: AdminStyles.caption(color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),
          if (_loadingHistory)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AdminColors.primary, strokeWidth: 2),
              ),
            )
          else if (_auditHistory.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No maintenance mode changes recorded yet',
                  style:
                      AdminStyles.caption(color: AdminColors.textMuted),
                ),
              ),
            )
          else
            ..._auditHistory.map((entry) {
              final action = entry['action'] as String?;
              final isEnable = action == 'enable_maintenance_mode';
              final isUpdateMsg = action == 'update_maintenance_message';
              final createdAt = entry['created_at'] as String?;
              final role = entry['actor_role'] ?? 'Admin';
              final timeStr = createdAt != null
                  ? _formatAuditTime(DateTime.parse(createdAt))
                  : 'Unknown time';

              final IconData iconData = isUpdateMsg
                  ? Icons.edit_note_rounded
                  : isEnable
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded;

              final Color iconColor = isUpdateMsg
                  ? AdminColors.info
                  : isEnable
                      ? AdminColors.danger
                      : AdminColors.success;

              final String actionTitle = isUpdateMsg
                  ? 'Notice Updated'
                  : isEnable
                      ? 'Orders Paused'
                      : 'Store Resumed';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      iconData,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actionTitle,
                            style: AdminStyles.body(size: 12.5),
                          ),
                          Text(
                            '$role • $timeStr',
                            style: AdminStyles.caption(
                                color: AdminColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1);
  }

  String _formatAuditTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
