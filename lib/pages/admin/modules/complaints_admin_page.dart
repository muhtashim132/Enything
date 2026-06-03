import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../widgets/common/star_rating_display.dart';

class ComplaintsAdminPage extends StatefulWidget {
  const ComplaintsAdminPage({super.key});

  @override
  State<ComplaintsAdminPage> createState() => _ComplaintsAdminPageState();
}

class _ComplaintsAdminPageState extends State<ComplaintsAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingComplaints = true;
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadComplaints();
    _loadReviews();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    try {
      // Try reading from a support_tickets or complaints table — graceful fallback
      final res = await _db
          .from('support_tickets')
          .select('*')
          .order('created_at', ascending: false)
          .limit(50);
      _complaints = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      // Table might not exist yet — show empty state
      _complaints = [];
    }
    if (mounted) setState(() => _loadingComplaints = false);
  }

  Future<void> _loadReviews() async {
    try {
      final res = await _db
          .from('reviews')
          .select('*, profiles:user_id(full_name, avatar_url), shops:shop_id(shop_name)')
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
              Tab(text: '🎫 Complaints'),
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
          const AdminBadge(label: 'Table: support_tickets', color: AdminColors.info),
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
    final subject = (complaint['subject'] ?? complaint['title'] ?? 'No subject') as String;
    final body = (complaint['body'] ?? complaint['message'] ?? '') as String;
    final time = complaint['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(complaint['created_at'].toString()).toLocal())
        : '';

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
                  Text(complaint['user_name'] ?? profile?['full_name'] ?? 'Unknown',
                      style: AdminStyles.caption()),
                  const SizedBox(width: 12),
                  const Icon(Icons.phone_rounded,
                      color: AdminColors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(profile?['phone'] ?? '—',
                      style: AdminStyles.caption()),
                ]),
              ],
            ),
          ),

          // Action footer
          if (status != 'resolved' && status != 'closed' && (context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('support.reply') || context.read<RbacProvider>().can('support.close')))
            Container(
              decoration: BoxDecoration(
                color: AdminColors.surface.withValues(alpha: 0.5),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                border:
                    const Border(top: BorderSide(color: AdminColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                if (context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('support.reply'))
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await db
                            .from('support_tickets')
                            .update({'status': 'in_progress'}).eq(
                                'id', complaint['id']);
                        await onRefresh();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.info,
                        side: BorderSide(
                            color: AdminColors.info.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('Start Review',
                          style: AdminStyles.caption(
                              color: AdminColors.info)),
                    ),
                  ),
                if ((context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('support.reply')) && (context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('support.close')))
                  const SizedBox(width: 10),
                if (context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('support.close'))
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await db
                            .from('support_tickets')
                            .update({'status': 'resolved'}).eq(
                                'id', complaint['id']);
                        await onRefresh();
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
    final ratings = reviews
        .map((r) => (r['rating'] as num?)?.toDouble() ?? 0.0)
        .toList();
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
                StarRatingDisplay(rating: avg, size: 18, color: AdminColors.warning),
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
            final comment = (r['comment'] ?? r['review'] ?? '') as String;
            final time = r['created_at'] != null
                ? DateFormat('dd MMM yy')
                    .format(DateTime.parse(r['created_at'].toString()).toLocal())
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
                      backgroundColor: AdminColors.primary.withValues(alpha: 0.2),
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
                          Text(shop?['shop_name'] ?? '',
                              style: AdminStyles.caption()),
                        ],
                      ),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      StarRatingDisplay(rating: rating, size: 14, color: AdminColors.warning),
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
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
