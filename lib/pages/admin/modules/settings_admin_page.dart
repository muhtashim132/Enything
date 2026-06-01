import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../../theme/admin_theme.dart';
import '../../../providers/rbac_provider.dart';
import '../../../providers/team_provider.dart';
import '../rbac/roles_list_page.dart';
import '../rbac/team_members_page.dart';
import '../rbac/audit_logs_page.dart';
import '../platform/commission_fees_page.dart';
import '../platform/coupon_management_page.dart';
import '../platform/referral_settings_page.dart';

class SettingsAdminPage extends StatelessWidget {
  const SettingsAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Team & Roles ─────────────────────────────────────────
        if (rbac.isSuperAdmin || rbac.can('roles.view')) ...[
          const _SectionLabel('Team & Access Control'),
          _SettingsTile(
            icon: Icons.shield_rounded,
            iconColor: AdminColors.primary,
            title: 'Roles & Permissions',
            subtitle: '${rbac.allRoles.length} roles configured',
            onTap: () => Navigator.push(
                context, _route(const RolesListPage())),
          ).animate().fadeIn(delay: 50.ms).slideX(begin: -0.1),
          _SettingsTile(
            icon: Icons.group_rounded,
            iconColor: AdminColors.info,
            title: 'Team Members',
            subtitle: 'Manage staff access and invitations',
            onTap: () => Navigator.push(
              context,
              _route(MultiProvider(
                providers: [ChangeNotifierProvider(create: (_) => TeamProvider())],
                child: const TeamMembersPage(),
              )),
            ),
          ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
          if (rbac.can('audit.view') || rbac.isSuperAdmin)
            _SettingsTile(
              icon: Icons.history_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Audit Logs',
              subtitle: 'Track every admin action',
              onTap: () => Navigator.push(
                  context, _route(const AuditLogsPage())),
            ).animate().fadeIn(delay: 150.ms).slideX(begin: -0.1),
        ],

        // ── Platform Config ──────────────────────────────────────
        const _SectionLabel('Platform Configuration'),
        _SettingsTile(
          icon: Icons.percent_rounded,
          iconColor: AdminColors.success,
          title: 'Commission & Fees',
          subtitle: 'Platform %, delivery fee, surge pricing',
          onTap: () => Navigator.push(context, _route(const CommissionFeesPage())),
        ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),
        _SettingsTile(
          icon: Icons.local_offer_rounded,
          iconColor: AdminColors.warning,
          title: 'Coupon Management',
          subtitle: 'Create and manage discount codes',
          onTap: () => Navigator.push(context, _route(const CouponManagementPage())),
        ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.1),
        _SettingsTile(
          icon: Icons.people_alt_rounded,
          iconColor: const Color(0xFFEC4899),
          title: 'Referral Rewards',
          subtitle: 'Referral bonus configuration',
          onTap: () => Navigator.push(context, _route(const ReferralSettingsPage())),
        ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

        // ── Notifications ────────────────────────────────────────
        const _SectionLabel('Push Notifications'),
        _SettingsTile(
          icon: Icons.campaign_rounded,
          iconColor: AdminColors.info,
          title: 'Send Notification',
          subtitle: 'Broadcast to all users, sellers, or riders',
          onTap: () => _NotificationSheet.show(context),
        ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.1),

        // ── Payment & Tax ────────────────────────────────────────
        const _SectionLabel('Payment & Tax'),
        _SettingsTile(
          icon: Icons.payment_rounded,
          iconColor: AdminColors.success,
          title: 'Payment Gateways',
          subtitle: 'Razorpay, UPI configuration',
          onTap: () => _showComingSoon(context, 'Payment Gateways'),
        ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),
        _SettingsTile(
          icon: Icons.receipt_long_rounded,
          iconColor: AdminColors.warning,
          title: 'Tax Settings',
          subtitle: 'GST rates and tax configuration',
          onTap: () => _showComingSoon(context, 'Tax Settings'),
        ).animate().fadeIn(delay: 450.ms).slideX(begin: -0.1),

        // ── Danger Zone ──────────────────────────────────────────
        if (rbac.isSuperAdmin) ...[
          const _SectionLabel('Security', color: AdminColors.danger),
          _SettingsTile(
            icon: Icons.security_rounded,
            iconColor: AdminColors.danger,
            title: 'Active Sessions',
            subtitle: 'View and revoke admin sessions',
            onTap: () => _showComingSoon(context, 'Session Management'),
          ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.1),
        ],

        const SizedBox(height: 24),
        Center(
          child: Text(
            'Enything Admin v1.0.0',
            style: AdminStyles.label(),
          ),
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature — Coming Soon',
          style: AdminStyles.body(size: 13)),
      backgroundColor: AdminColors.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  MaterialPageRoute _route(Widget page) =>
      MaterialPageRoute(builder: (_) => page);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _SectionLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: AdminStyles.label(color: color ?? AdminColors.textMuted),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.cardBorder),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AdminStyles.body(size: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AdminStyles.caption()),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AdminColors.textMuted, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Notification Bottom Sheet ─────────────────────────────────────
class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationSheet(),
    );
  }

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _audience = 'All Users';
  bool _sending = false;

  Future<void> _sendBroadcast() async {
    final title = _titleCtrl.text.trim();
    final body = _msgCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a title and message', style: AdminStyles.body(size: 13)),
        backgroundColor: AdminColors.danger,
      ));
      return;
    }

    setState(() => _sending = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('send-broadcast', body: {
        'audience': _audience,
        'title': title,
        'body': body,
      });

      if (!mounted) return;
      Navigator.pop(context); // close sheet
      final sent = res.data['sent'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Successfully sent to $sent devices!', style: AdminStyles.body(size: 13, color: Colors.white)),
        backgroundColor: AdminColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to send: $e', style: AdminStyles.body(size: 13, color: Colors.white)),
        backgroundColor: AdminColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  final List<String> _audiences = [
    'All Users', 'Customers', 'Sellers', 'Riders'
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Send Push Notification', style: AdminStyles.heading(size: 20)),
            const SizedBox(height: 4),
            const SizedBox(height: 20),
            Text('Audience', style: AdminStyles.caption()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _audiences.map((a) {
                final selected = _audience == a;
                return GestureDetector(
                  onTap: () => setState(() => _audience = a),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: selected ? AdminGradients.primary : null,
                      color: selected ? null : AdminColors.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected
                              ? Colors.transparent
                              : AdminColors.cardBorder),
                    ),
                    child: Text(a,
                        style: AdminStyles.caption(
                            color: selected
                                ? Colors.white
                                : AdminColors.textSecondary)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Title', style: AdminStyles.caption()),
            const SizedBox(height: 8),
            _field(_titleCtrl, 'e.g. Flash Sale is Live!'),
            const SizedBox(height: 16),
            Text('Message', style: AdminStyles.caption()),
            const SizedBox(height: 8),
            _field(_msgCtrl, 'e.g. Get 20% off on all orders today only.', maxLines: 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AdminGradients.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton(
                  onPressed: _sending ? null : _sendBroadcast,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text('Send to $_audience',
                          style: AdminStyles.body(size: 15, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: AdminStyles.body(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AdminStyles.body(color: AdminColors.textMuted),
        filled: true,
        fillColor: AdminColors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
