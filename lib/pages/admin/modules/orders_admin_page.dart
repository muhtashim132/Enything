import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';

class OrdersAdminPage extends StatefulWidget {
  const OrdersAdminPage({super.key});

  @override
  State<OrdersAdminPage> createState() => _OrdersAdminPageState();
}

class _OrdersAdminPageState extends State<OrdersAdminPage> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _activeFilter = 'All';
  final _searchCtrl = TextEditingController();

  static const _filters = ['All', 'Pending', 'Active', 'Delivered', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await _db
          .from('orders')
          // FIX: 'shop_name' column does not exist on shops table; the actual column is 'name'
          .select('*, profiles:customer_id(full_name, phone), shops:shop_id(name)')
          .order('created_at', ascending: false)
          .limit(80);
      _orders = List<Map<String, dynamic>>.from(res);
      _filtered = _orders;
    } catch (e) {
      debugPrint('Orders load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _orders.where((o) {
        final id = o['id'].toString().toLowerCase();
        final profile = o['profiles'] as Map?;
        final name = (profile?['full_name'] ?? '').toString().toLowerCase();
        final status = (o['status'] ?? '').toString().toLowerCase();

        final matchesSearch = q.isEmpty || id.contains(q) || name.contains(q);
        // FIX: Include new dual-acceptance statuses in the right filter buckets
        final matchesFilter = _activeFilter == 'All' ||
            (_activeFilter == 'Pending' && (status == 'pending' || status == 'placed' ||
                status == 'awaiting_acceptance' || status == 'awaiting_payment')) ||
            (_activeFilter == 'Active' && (status == 'confirmed' || status == 'preparing' ||
                status == 'ready_for_pickup' || status == 'picked_up' || status == 'out_for_delivery')) ||
            (_activeFilter == 'Delivered' && status == 'delivered') ||
            (_activeFilter == 'Cancelled' && (status == 'cancelled' || status == 'seller_rejected' || status == 'partner_rejected'));

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  void _applyFilter(String filter) {
    setState(() => _activeFilter = filter);
    _filter();
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    if (!rbac.can('orders.view') && !rbac.isSuperAdmin) {
      return const ForbiddenPage(fullPage: false);
    }

    return Column(
      children: [
        // ── Search bar ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            style: AdminStyles.body(),
            decoration: InputDecoration(
              hintText: 'Search by order ID or customer...',
              hintStyle: AdminStyles.body(color: AdminColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AdminColors.textMuted, size: 20),
              filled: true,
              fillColor: AdminColors.cardBg,
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
                borderSide: const BorderSide(color: AdminColors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),

        // ── Filter chips ──────────────────────────────────────
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _filters[i];
              final active = _activeFilter == f;
              return GestureDetector(
                onTap: () => _applyFilter(f),
                child: AnimatedContainer(
                  duration: 200.ms,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: active ? AdminGradients.primary : null,
                    color: active ? null : AdminColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: active
                            ? Colors.transparent
                            : AdminColors.cardBorder),
                  ),
                  child: Text(f,
                      style: AdminStyles.caption(
                          color: active
                              ? Colors.white
                              : AdminColors.textSecondary)),
                ),
              );
            },
          ),
        ),

        // ── Order list ────────────────────────────────────────
        Expanded(
          child: _loading
              ? _buildSkeletons()
              : _filtered.isEmpty
                  ? const AdminEmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'No orders found')
                  : RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _loading = true);
                        await _fetch();
                        _filter();
                      },
                      color: AdminColors.primary,
                      backgroundColor: AdminColors.surface,
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _OrderCard(
                          order: _filtered[i],
                          onRefresh: () async {
                            setState(() => _loading = true);
                            await _fetch();
                            _filter();
                          },
                        )
                            .animate()
                            .fadeIn(
                                delay: Duration(milliseconds: i * 35))
                            .slideY(begin: 0.08),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSkeletons() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AdminDecorations.glassCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            SkeletonBox(width: 44, height: 44, radius: 14),
            SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  SkeletonBox(width: 130, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 90, height: 11),
                ])),
            SkeletonBox(width: 60, height: 22, radius: 20),
          ]),
          const SizedBox(height: 14),
          Row(children: List.generate(
              4,
              (j) => Expanded(
                    child: Row(children: [
                      const SkeletonBox(width: 10, height: 10, radius: 5),
                      const SizedBox(width: 4),
                      if (j < 3)
                        Expanded(
                            child: Container(
                                height: 2,
                                color: Colors.white.withValues(alpha: 0.06))),
                    ]),
                  ))),
        ]),
      ).animate().shimmer(duration: 1500.ms),
    );
  }
}

// ── Order Card with expandable timeline ──────────────────────────
class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function() onRefresh;

  const _OrderCard({required this.order, required this.onRefresh});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;
  bool _actioning = false;
  SupabaseClient get _db => Supabase.instance.client;

  static const _timeline = [
    (Icons.shopping_cart_rounded, 'Order Placed'),
    (Icons.restaurant_rounded, 'Seller Accepted'),
    (Icons.delivery_dining_rounded, 'Rider Assigned'),
    (Icons.local_shipping_rounded, 'Picked Up'),
    (Icons.check_circle_rounded, 'Delivered'),
  ];

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final status = (o['status'] ?? 'placed') as String;
    final profile = o['profiles'] as Map?;
    final shop = o['shops'] as Map?;
    final amount =
        (o['grand_total_collected'] as num?)?.toDouble() ?? (o['total_amount'] as num?)?.toDouble() ?? 0.0;
    final time = o['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(o['created_at'].toString()).toIST())
        : '';

    final (statusColor, statusLabel) = _statusStyle(status);
    final timelineStep = _timelineStep(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AdminDecorations.glassCard(),
      child: Column(
        children: [
          // ── Main row ────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                // Status icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.receipt_long_rounded,
                      color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '#${o['id'].toString().substring(0, 8).toUpperCase()}',
                          style: AdminStyles.body(size: 13)),
                      const SizedBox(height: 2),
                      Text(
                          '${profile?['full_name'] ?? 'Customer'}  •  ${shop?['name'] ?? 'Shop'}', // FIX: use 'name' not 'shop_name'
                          style: AdminStyles.caption(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(time, style: AdminStyles.label()),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹${amount.toStringAsFixed(0)}',
                      style: AdminStyles.body(
                          size: 14, color: AdminColors.success)),
                  const SizedBox(height: 4),
                  AdminBadge(label: statusLabel, color: statusColor),
                ]),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AdminColors.textMuted,
                  size: 18,
                ),
              ]),
            ),
          ),

          // ── Expandable detail panel ──────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildDetailPanel(o, timelineStep, statusColor, status),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: 250.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(Map<String, dynamic> o, int step, Color statusColor, String status) {
    final profile = o['profiles'] as Map?;
    final shop = o['shops'] as Map?;
    final amount = (o['grand_total_collected'] as num?)?.toDouble() ??
        (o['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = (o['payment_method'] ?? 'COD') as String;

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface.withValues(alpha: 0.5),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: const Border(top: BorderSide(color: AdminColors.cardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status timeline
          Text('Order Timeline',
              style: AdminStyles.label()),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_timeline.length, (i) {
              final done = i <= step;
              final (icon, label) = _timeline[i];
              return Expanded(
                child: Row(children: [
                  Column(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: done ? AdminGradients.primary : null,
                        color: done ? null : AdminColors.cardBg,
                        border: done
                            ? null
                            : Border.all(color: AdminColors.cardBorder),
                      ),
                      child: Icon(icon,
                          color: done ? Colors.white : AdminColors.textMuted,
                          size: 14),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 54,
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: AdminStyles.label(
                              color: done
                                  ? AdminColors.textPrimary
                                  : AdminColors.textMuted),
                          maxLines: 2),
                    ),
                  ]),
                  if (i < _timeline.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          gradient: i < step ? AdminGradients.primary : null,
                          color: i < step ? null : AdminColors.cardBg,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ),

          const SizedBox(height: 16),
          const Divider(color: AdminColors.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Info grid
          Row(children: [
            _InfoCell(
                label: 'Customer',
                value: profile?['full_name'] ?? 'Unknown'),
            _InfoCell(
                label: 'Phone',
                value: profile?['phone'] ?? '—'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _InfoCell(
                label: 'Shop',
                value: shop?['name'] ?? 'Unknown'), // FIX: use 'name' not 'shop_name'
            _InfoCell(
                label: 'Payment',
                value: paymentMethod.toUpperCase()),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _InfoCell(
                label: 'Amount',
                value: '₹${amount.toStringAsFixed(0)}'),
            _InfoCell(
                label: 'Payment Status',
                value: (o['payment_status'] ?? 'pending').toString().toUpperCase()),
          ]),

          const SizedBox(height: 16),

          // Action buttons
          Row(children: [
            if (status != 'cancelled' && status != 'delivered' && (context.read<RbacProvider>().can('orders.cancel') || context.read<RbacProvider>().isSuperAdmin))
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _actioning ? null : () => _cancelOrder(o['id'].toString()),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text('Cancel Order', style: AdminStyles.caption()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.danger,
                    side: BorderSide(
                        color: AdminColors.danger.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            if (status != 'cancelled' && status != 'delivered') ...[
              const SizedBox(width: 10),
            ],
            if (context.read<RbacProvider>().can('orders.refund') || context.read<RbacProvider>().isSuperAdmin)
              Expanded(
                child: ElevatedButton.icon(
                onPressed: _actioning ? null : () => _issueRefund(o['id'].toString(), amount),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text('Issue Refund', style: AdminStyles.caption(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.warning,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _cancelOrder(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.from('orders').update({'status': 'cancelled'}).eq('id', orderId);
      await widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cancelled successfully.'),
          backgroundColor: AdminColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AdminColors.danger,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _issueRefund(String orderId, double amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Issue Refund', style: AdminStyles.title()),
        content: Text(
            'Are you sure you want to issue a refund of ₹${amount.toStringAsFixed(0)} for this order?',
            style: AdminStyles.body(size: 14, color: AdminColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AdminStyles.body(size: 13))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.warning,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text('Confirm Refund',
                  style:
                      AdminStyles.body(size: 13, color: Colors.white))),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    
    setState(() => _actioning = true);
    try {
      await _db.from('orders').update({
        'status': 'cancelled',
        'refund_status': 'processing'
      }).eq('id', orderId);
      
      await widget.onRefresh();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Refund of ₹${amount.toStringAsFixed(0)} queued. Status changed to processing.'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error issuing refund: $e'),
          backgroundColor: AdminColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  int _timelineStep(String status) => switch (status) {
        'placed' || 'pending' => 0,
        'accepted' => 1,
        'preparing' => 1,
        'rider_assigned' => 2,
        'picked_up' => 3,
        'out_for_delivery' => 3,
        'delivered' => 4,
        _ => 0,
      };

  (Color, String) _statusStyle(String status) => switch (status) {
        'delivered' => (AdminColors.success, 'Delivered'),
        'cancelled' => (AdminColors.danger, 'Cancelled'),
        'preparing' || 'accepted' => (AdminColors.info, 'Preparing'),
        'picked_up' || 'out_for_delivery' => (AdminColors.info, 'On the Way'),
        _ => (AdminColors.warning, 'Pending'),
      };
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  const _InfoCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AdminStyles.label()),
        const SizedBox(height: 2),
        Text(value,
            style: AdminStyles.body(size: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
