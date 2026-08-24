import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../widgets/common/star_rating_display.dart';
import '../../../utils/time_utils.dart';

class ComplaintsAdminPage extends StatefulWidget {
  const ComplaintsAdminPage({super.key});

  @override
  State<ComplaintsAdminPage> createState() => _ComplaintsAdminPageState();
}

class _ComplaintsAdminPageState extends State<ComplaintsAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _disputes = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingComplaints = true;
  bool _loadingDisputes = true;
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadComplaints();
    _loadDisputes();
    _loadReviews();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    try {
      final res = await _db
          .from('support_tickets')
          .select('*, profiles:user_id(full_name, phone)')
          .order('created_at', ascending: false)
          .limit(50);
      _complaints = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      _complaints = [];
    }
    if (mounted) setState(() => _loadingComplaints = false);
  }

  Future<void> _loadDisputes() async {
    try {
      final res = await _db
          .from('order_disputes')
          .select('*, profiles:customer_id(full_name, phone), shops:shop_id(name), orders:order_id(id, grand_total_collected, status, payment_status, refund_status)')
          .order('created_at', ascending: false)
          .limit(50);
      _disputes = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      _disputes = [];
    }
    if (mounted) setState(() => _loadingDisputes = false);
  }

  Future<void> _loadReviews() async {
    try {
      final res = await _db
          .from('reviews')
          .select(
              '*, profiles:user_id(full_name, avatar_url), shops:shop_id(name)')
          .order('created_at', ascending: false)
          .limit(80);
      _reviews = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      _reviews = [];
    }
    if (mounted) setState(() => _loadingReviews = false);
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('support.view')) {
      return const ForbiddenPage(fullPage: false);
    }
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: AdminColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColors.cardBorder),
          ),
          child: TabBar(
            controller: _tabs,
            indicator: BoxDecoration(
              gradient: AdminGradients.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AdminColors.textMuted,
            labelStyle: AdminStyles.body(size: 13, color: Colors.white),
            unselectedLabelStyle: AdminStyles.body(size: 13),
            tabs: const [
              Tab(text: '🎫 Tickets'),
              Tab(text: '⚖️ Disputes'),
              Tab(text: '⭐ Reviews'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ComplaintsTab(
                complaints: _complaints,
                loading: _loadingComplaints,
                onRefresh: _loadComplaints,
              ),
              _DisputesTab(
                disputes: _disputes,
                loading: _loadingDisputes,
                onRefresh: _loadDisputes,
              ),
              _ReviewsTab(
                reviews: _reviews,
                loading: _loadingReviews,
                onRefresh: _loadReviews,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  COMPLAINTS TAB
// ══════════════════════════════════════════════════════════════════
class _ComplaintsTab extends StatelessWidget {
  final List<Map<String, dynamic>> complaints;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _ComplaintsTab({
    required this.complaints,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return _skelList();

    if (complaints.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AdminEmptyState(
            icon: Icons.support_agent_rounded,
            message: 'No complaints yet',
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Create a `support_tickets` table in Supabase to start tracking customer complaints here.',
              textAlign: TextAlign.center,
              style: AdminStyles.caption(),
            ),
          ),
          const SizedBox(height: 16),
          const AdminBadge(
              label: 'Table: support_tickets', color: AdminColors.info),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AdminColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: complaints.length,
        itemBuilder: (_, i) {
          final c = complaints[i];
          return _ComplaintCard(complaint: c, onRefresh: onRefresh)
              .animate()
              .fadeIn(delay: Duration(milliseconds: i * 40))
              .slideY(begin: 0.08);
        },
      ),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  final Map<String, dynamic> complaint;
  final Future<void> Function() onRefresh;

  const _ComplaintCard({required this.complaint, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final profile = complaint['profiles'] as Map?;
    final status = (complaint['status'] ?? 'open') as String;
    final priority = (complaint['priority'] ?? 'normal') as String;
    final subject =
        (complaint['subject'] ?? complaint['title'] ?? 'No subject') as String;
    final body = (complaint['body'] ?? complaint['message'] ?? '') as String;
    final time = complaint['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(complaint['created_at'].toString()).toIST())
        : '';
    final adminReply = complaint['admin_reply'] as String?;

    Future<void> showReplyDialog() async {
      final ctrl = TextEditingController(text: adminReply ?? '');
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reply to Ticket', style: AdminStyles.title()),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            style: AdminStyles.body(),
            decoration: InputDecoration(
              hintText: 'Type your reply here...',
              hintStyle: AdminStyles.body(color: AdminColors.textMuted),
              filled: true,
              fillColor: AdminColors.cardBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: AdminStyles.body())),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text('Send Reply',
                  style: AdminStyles.body(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true && ctrl.text.trim().isNotEmpty) {
        try {
          await db.from('support_tickets').update({
            'admin_reply': ctrl.text.trim(),
            'status': status == 'open' ? 'in_progress' : status,
          }).eq('id', complaint['id']);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Reply sent successfully'),
                backgroundColor: AdminColors.success));
          }
          await onRefresh();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Error: $e'),
                backgroundColor: AdminColors.danger));
          }
        }
      }
    }

    final (priorityColor, priorityLabel) = switch (priority) {
      'high' || 'urgent' => (AdminColors.danger, 'High'),
      'medium' => (AdminColors.warning, 'Medium'),
      _ => (AdminColors.info, 'Normal'),
    };

    final (statusColor, statusLabel) = switch (status) {
      'resolved' || 'closed' => (AdminColors.success, 'Resolved'),
      'in_progress' => (AdminColors.info, 'In Progress'),
      _ => (AdminColors.warning, 'Open'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AdminDecorations.glassCard(
          borderColor: priorityColor.withValues(alpha: 0.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  AdminBadge(label: priorityLabel, color: priorityColor),
                  const SizedBox(width: 8),
                  AdminBadge(label: statusLabel, color: statusColor),
                  const Spacer(),
                  Text(time, style: AdminStyles.label()),
                ]),
                const SizedBox(height: 10),
                Text(subject, style: AdminStyles.body(size: 14)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body,
                      style: AdminStyles.caption(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.person_rounded,
                      color: AdminColors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(
                      complaint['user_name'] ??
                          profile?['full_name'] ??
                          'Unknown',
                      style: AdminStyles.caption()),
                  const SizedBox(width: 12),
                  const Icon(Icons.phone_rounded,
                      color: AdminColors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(profile?['phone'] ?? '—', style: AdminStyles.caption()),
                ]),
                if (adminReply != null && adminReply.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AdminColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Reply:',
                            style:
                                AdminStyles.label(color: AdminColors.primary)),
                        const SizedBox(height: 4),
                        Text(adminReply,
                            style: AdminStyles.body(
                                size: 13, color: AdminColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action footer
          if (status != 'resolved' &&
              status != 'closed' &&
              (context.read<RbacProvider>().isSuperAdmin ||
                  context.read<RbacProvider>().can('support.reply') ||
                  context.read<RbacProvider>().can('support.close')))
            Container(
              decoration: BoxDecoration(
                color: AdminColors.surface.withValues(alpha: 0.5),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: const Border(
                    top: BorderSide(color: AdminColors.cardBorder)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                if (context.read<RbacProvider>().isSuperAdmin ||
                    context.read<RbacProvider>().can('support.reply'))
                  Expanded(
                    child: OutlinedButton(
                      onPressed: showReplyDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.info,
                        side: BorderSide(
                            color: AdminColors.info.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('Reply',
                          style: AdminStyles.caption(color: AdminColors.info)),
                    ),
                  ),
                if ((context.read<RbacProvider>().isSuperAdmin ||
                        context.read<RbacProvider>().can('support.reply')) &&
                    (context.read<RbacProvider>().isSuperAdmin ||
                        context.read<RbacProvider>().can('support.close')))
                  const SizedBox(width: 10),
                if (context.read<RbacProvider>().isSuperAdmin ||
                    context.read<RbacProvider>().can('support.close'))
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await db.from('support_tickets').update(
                              {'status': 'resolved'}).eq('id', complaint['id']);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Ticket resolved'),
                                    backgroundColor: AdminColors.success));
                          }
                          await onRefresh();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: AdminColors.danger));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.success,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('Mark Resolved',
                          style: AdminStyles.caption(color: Colors.white)
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  DISPUTES TAB
// ══════════════════════════════════════════════════════════════════
class _DisputesTab extends StatelessWidget {
  final List<Map<String, dynamic>> disputes;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _DisputesTab({
    required this.disputes,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return _skelList();

    if (disputes.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AdminEmptyState(
            icon: Icons.balance_rounded,
            message: 'No order disputes filed',
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Customer post-delivery dispute claims and refund requests will appear here for admin review.',
              textAlign: TextAlign.center,
              style: AdminStyles.caption(),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AdminColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: disputes.length,
        itemBuilder: (_, i) {
          final d = disputes[i];
          return _DisputeCard(dispute: d, onRefresh: onRefresh)
              .animate()
              .fadeIn(delay: Duration(milliseconds: i * 40))
              .slideY(begin: 0.08);
        },
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final Future<void> Function() onRefresh;

  const _DisputeCard({required this.dispute, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final profile = dispute['profiles'] as Map?;
    final shop = dispute['shops'] as Map?;
    final status = (dispute['status'] ?? 'pending') as String;
    final reason = (dispute['reason'] ?? 'Other') as String;
    final description = (dispute['description'] ?? '') as String;
    final photoUrls = (dispute['photo_urls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final refundAmount = (dispute['refund_amount_requested'] as num?)?.toDouble() ?? 0.0;
    final orderId = (dispute['order_id'] ?? '').toString();
    final adminNotes = dispute['admin_notes'] as String?;
    final time = dispute['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(dispute['created_at'].toString()).toIST())
        : '';

    final (statusColor, statusLabel) = switch (status) {
      'approved' => (AdminColors.success, 'Approved / Refunded'),
      'partially_approved' => (AdminColors.info, 'Partially Approved'),
      'rejected' => (AdminColors.danger, 'Rejected'),
      _ => (AdminColors.warning, 'Pending Review'),
    };

    Future<void> showResolutionDialog({required bool isApproval}) async {
      final notesCtrl = TextEditingController();
      final refundCtrl = TextEditingController(text: refundAmount.toStringAsFixed(2));

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AdminColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              isApproval ? 'Approve & Issue Refund' : 'Reject Dispute Claim',
              style: AdminStyles.title(color: isApproval ? AdminColors.success : AdminColors.danger),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isApproval) ...[
                    Text('Refund Amount (₹):', style: AdminStyles.label()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: refundCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AdminStyles.body(),
                      decoration: InputDecoration(
                        hintText: 'Enter refund amount',
                        hintStyle: AdminStyles.body(color: AdminColors.textMuted),
                        filled: true,
                        fillColor: AdminColors.cardBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('Admin Resolution Notes:', style: AdminStyles.label()),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    style: AdminStyles.body(),
                    decoration: InputDecoration(
                      hintText: isApproval ? 'Reason for approving refund...' : 'Reason for rejection...',
                      hintStyle: AdminStyles.body(color: AdminColors.textMuted),
                      filled: true,
                      fillColor: AdminColors.cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: AdminStyles.body()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApproval ? AdminColors.success : AdminColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isApproval ? 'Confirm Refund' : 'Confirm Reject',
                  style: AdminStyles.body(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );

      if (confirm == true) {
        try {
          final approvedAmount = double.tryParse(refundCtrl.text.trim()) ?? refundAmount;
          final newStatus = isApproval
              ? (approvedAmount < refundAmount ? 'partially_approved' : 'approved')
              : 'rejected';
          final adminNotes = notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null;

          try {
            await db.rpc('admin_resolve_dispute', params: {
              'p_dispute_id': dispute['id'],
              'p_status': newStatus,
              'p_admin_notes': adminNotes,
              'p_refund_amount': isApproval ? approvedAmount : null,
            });
          } catch (_) {
            // Fallback to direct mutation
            await db.from('order_disputes').update({
              'status': newStatus,
              'admin_notes': adminNotes,
              'resolved_at': DateTime.now().toIso8601String(),
            }).eq('id', dispute['id']);

            if (isApproval && orderId.isNotEmpty) {
              await db.from('orders').update({
                'refund_status': 'processing',
              }).eq('id', orderId);
            }
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(isApproval ? 'Dispute approved and refund marked.' : 'Dispute claim rejected.'),
              backgroundColor: isApproval ? AdminColors.success : AdminColors.warning,
            ));
          }
          await onRefresh();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error resolving dispute: $e'),
              backgroundColor: AdminColors.danger,
            ));
          }
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AdminDecorations.glassCard(borderColor: statusColor.withValues(alpha: 0.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AdminBadge(label: statusLabel, color: statusColor),
                    const SizedBox(width: 8),
                    AdminBadge(label: reason, color: AdminColors.info),
                    const Spacer(),
                    Text(time, style: AdminStyles.label()),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 14, color: AdminColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Order: #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                      style: AdminStyles.body(size: 12, color: Colors.white70),
                    ),
                    const SizedBox(width: 12),
                    if (shop?['name'] != null) ...[
                      const Icon(Icons.storefront_rounded, size: 14, color: AdminColors.textMuted),
                      const SizedBox(width: 4),
                      Text(shop!['name'].toString(), style: AdminStyles.caption()),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 14, color: AdminColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      '${profile?['full_name'] ?? 'Customer'} • ${profile?['phone'] ?? 'No phone'}',
                      style: AdminStyles.caption(),
                    ),
                    const Spacer(),
                    Text(
                      'Claim: ₹${refundAmount.toStringAsFixed(2)}',
                      style: AdminStyles.title(size: 13, color: AdminColors.warning),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminColors.cardBorder),
                    ),
                    child: Text(description, style: AdminStyles.body(size: 12, color: AdminColors.textSecondary)),
                  ),
                ],
                if (photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: photoUrls.length,
                      itemBuilder: (_, pi) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              photoUrls[pi],
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 70,
                                height: 70,
                                color: AdminColors.cardBg,
                                child: const Icon(Icons.broken_image_rounded, size: 24, color: AdminColors.textMuted),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (adminNotes != null && adminNotes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.admin_panel_settings_rounded, size: 14, color: AdminColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Admin Note: $adminNotes',
                          style: AdminStyles.caption(color: AdminColors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
                if (status == 'pending' &&
                    (context.read<RbacProvider>().isSuperAdmin ||
                        context.read<RbacProvider>().can('support.reply'))) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => showResolutionDialog(isApproval: false),
                        icon: const Icon(Icons.close_rounded, size: 14),
                        label: Text('Reject', style: AdminStyles.caption(color: AdminColors.danger)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.danger,
                          side: BorderSide(color: AdminColors.danger.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => showResolutionDialog(isApproval: true),
                        icon: const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                        label: Text('Approve & Refund', style: AdminStyles.caption(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  REVIEWS TAB
// ══════════════════════════════════════════════════════════════════
class _ReviewsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _ReviewsTab({
    required this.reviews,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return _skelList();

    Future<void> deleteReview(String id) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Review',
              style: AdminStyles.title(color: AdminColors.danger)),
          content: Text('Are you sure you want to delete this review?',
              style: AdminStyles.body(color: AdminColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: AdminStyles.body())),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child:
                  Text('Delete', style: AdminStyles.body(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await Supabase.instance.client.from('reviews').delete().eq('id', id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Review deleted successfully'),
                backgroundColor: AdminColors.success));
          }
          await onRefresh();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Error deleting review: $e'),
                backgroundColor: AdminColors.danger));
          }
        }
      }
    }

    if (reviews.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AdminEmptyState(
            icon: Icons.star_outline_rounded,
            message: 'No reviews yet',
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Requires a `reviews` table with columns: rating, comment, user_id, shop_id.',
              textAlign: TextAlign.center,
              style: AdminStyles.caption(),
            ),
          ),
        ],
      );
    }

    // Compute average rating
    final ratings =
        reviews.map((r) => (r['rating'] as num?)?.toDouble() ?? 0.0).toList();
    final avg = ratings.isEmpty
        ? 0.0
        : ratings.reduce((a, b) => a + b) / ratings.length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AdminColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Avg rating summary card
          AdminGradientCard(
            gradient: AdminGradients.primary,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text(avg.toStringAsFixed(1),
                  style: AdminStyles.heading(size: 40)),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                StarRatingDisplay(
                    rating: avg, size: 18, color: AdminColors.warning),
                const SizedBox(height: 4),
                Text('Average from ${reviews.length} reviews',
                    style: AdminStyles.caption(color: Colors.white70)),
              ]),
            ]),
          ).animate().fadeIn(delay: 50.ms),

          const SizedBox(height: 8),

          ...reviews.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            final profile = r['profiles'] as Map?;
            final shop = r['shops'] as Map?;
            final rating = (r['rating'] as num?)?.toDouble() ?? 0.0;
            final comment = (r['comment'] ??
                r['review'] ??
                r['review_text'] ??
                '') as String;
            final time = r['created_at'] != null
                ? DateFormat('dd MMM yy')
                    .format(DateTime.parse(r['created_at'].toString()).toIST())
                : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: AdminDecorations.glassCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          AdminColors.primary.withValues(alpha: 0.2),
                      backgroundImage: profile?['avatar_url'] != null
                          ? NetworkImage(profile!['avatar_url'])
                          : null,
                      child: profile?['avatar_url'] == null
                          ? Text(
                              (profile?['full_name'] ?? 'U')[0].toUpperCase(),
                              style: AdminStyles.body(
                                  size: 14, color: AdminColors.primary))
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?['full_name'] ?? 'Anonymous',
                              style: AdminStyles.body(size: 13)),
                          // FIX: use 'name' not 'shop_name' — shops table column is 'name'
                          Text(shop?['name'] ?? '',
                              style: AdminStyles.caption()),
                        ],
                      ),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StarRatingDisplay(
                              rating: rating,
                              size: 14,
                              color: AdminColors.warning),
                          const SizedBox(height: 2),
                          Text(time, style: AdminStyles.label()),
                        ]),
                  ]),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(comment,
                        style: AdminStyles.body(
                            size: 13, color: AdminColors.textSecondary)),
                  ],
                  if (context.read<RbacProvider>().isSuperAdmin ||
                      context.read<RbacProvider>().can('support.close')) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => deleteReview(r['id'].toString()),
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 16),
                        label:
                            Text('Delete Review', style: AdminStyles.caption()),
                        style: TextButton.styleFrom(
                          foregroundColor: AdminColors.danger,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
                .animate()
                .fadeIn(delay: Duration(milliseconds: 100 + i * 40))
                .slideY(begin: 0.08);
          }),
        ],
      ),
    );
  }
}

// ── Shared skeleton ───────────────────────────────────────────────
Widget _skelList() => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: AdminDecorations.glassCard(),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SkeletonBox(width: 60, height: 20, radius: 20),
                SizedBox(width: 8),
                SkeletonBox(width: 60, height: 20, radius: 20),
                Spacer(),
                SkeletonBox(width: 60, height: 11),
              ]),
              SizedBox(height: 10),
              SkeletonBox(width: double.infinity, height: 14),
              SizedBox(height: 6),
              SkeletonBox(width: 200, height: 11),
            ]),
      ).animate().shimmer(duration: 1500.ms),
    );
