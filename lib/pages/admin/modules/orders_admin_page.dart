import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../config/routes.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';
import '../../../providers/notification_provider.dart';

Map<String, dynamic>? _extractMap(dynamic val) {
  if (val == null) return null;
  if (val is Map) return Map<String, dynamic>.from(val);
  if (val is List && val.isNotEmpty) {
    final first = val.first;
    if (first is Map) return Map<String, dynamic>.from(first);
  }
  return null;
}

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
  int _pendingQuotesCount = 0;
  final _searchCtrl = TextEditingController();

  static const _filters = [
    'All',
    'Pending',
    'Active',
    'Delivered',
    'Cancelled',
    'Bulk 🎉',
  ];

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
          .select(
              '*, profiles:customer_id(full_name, phone), shops:shop_id(id, name, address, category), bulk_orders(*)')
          .order('created_at', ascending: false)
          .limit(80);
      _orders = List<Map<String, dynamic>>.from(res);
      _filtered = _orders;

      try {
        final qRes = await _db
            .from('bulk_quote_requests')
            .select('id')
            .inFilter('quote_status', ['pending_review', 'customer_accepted']);
        _pendingQuotesCount = (qRes as List).length;
      } catch (_) {}
    } catch (e) {
      debugPrint('Orders load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _activeCateringCount => _orders
      .where((o) =>
          (o['order_type'] == 'bulk' || o['order_type'] == 'manual_quote') &&
          o['status'] != 'delivered' &&
          o['status'] != 'bulk_delivered' &&
          o['status'] != 'cancelled' &&
          o['status'] != 'seller_rejected')
      .length;

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _orders.where((o) {
        final id = o['id'].toString().toLowerCase();
        final profile = _extractMap(o['profiles']);
        final name = (profile?['full_name'] ?? '').toString().toLowerCase();
        final status = (o['status'] ?? '').toString().toLowerCase();
        final isBulkOrCatering =
            o['order_type'] == 'bulk' || o['order_type'] == 'manual_quote';

        final matchesSearch = q.isEmpty || id.contains(q) || name.contains(q);
        final matchesFilter = _activeFilter == 'Bulk 🎉'
            ? isBulkOrCatering
            : (!isBulkOrCatering &&
                (_activeFilter == 'All' ||
                    (_activeFilter == 'Pending' &&
                        (status == 'pending' ||
                            status == 'placed' ||
                            status == 'awaiting_acceptance' ||
                            status == 'awaiting_payment')) ||
                    (_activeFilter == 'Active' &&
                        (status == 'confirmed' ||
                            status == 'preparing' ||
                            status == 'ready_for_pickup' ||
                            status == 'picked_up' ||
                            status == 'out_for_delivery')) ||
                    (_activeFilter == 'Delivered' &&
                        (status == 'delivered' || status == 'bulk_delivered')) ||
                    (_activeFilter == 'Cancelled' &&
                        (status == 'cancelled' ||
                            status == 'seller_rejected' ||
                            status == 'partner_rejected' ||
                            status == 'shop_dispute_cancel' ||
                            status == 'payment_failed' ||
                            status == 'timeout' ||
                            status == 'verification_failed'))));

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
        // ── Search bar + Event Quotes Shortcut ───────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: AdminStyles.body(),
                  decoration: InputDecoration(
                    hintText: 'Search order ID or customer...',
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
              const SizedBox(width: 10),
              Builder(
                builder: (context) {
                  final totalAlerts = _pendingQuotesCount + _activeCateringCount;
                  return ElevatedButton.icon(
                    icon: Badge(
                      isLabelVisible: totalAlerts > 0,
                      label: Text('$totalAlerts'),
                      backgroundColor: _pendingQuotesCount > 0
                          ? AdminColors.warning
                          : Colors.purpleAccent,
                      child: const Icon(Icons.receipt_long_rounded, size: 18),
                    ),
                    label: Text(totalAlerts > 0 ? 'Quotes ($totalAlerts)' : 'Quotes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: totalAlerts > 0
                          ? Colors.purple.withValues(alpha: 0.25)
                          : AdminColors.primary,
                      foregroundColor: totalAlerts > 0
                          ? Colors.purpleAccent
                          : Colors.white,
                      side: totalAlerts > 0
                          ? const BorderSide(color: Colors.purpleAccent, width: 1.5)
                          : null,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.adminQuoteReview,
                        arguments: {'initialTab': _activeCateringCount > 0 ? 2 : 0},
                      ).then((_) => _fetch());
                    },
                  );
                },
              ),
            ],
          ),
        ),

        // ── Active Catering & Event Orders Highlight Banner ──
        if (_activeCateringCount > 0 && _activeFilter != 'Bulk 🎉')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.adminQuoteReview,
                  arguments: {'initialTab': 2},
                ).then((_) => _fetch());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade900.withValues(alpha: 0.7),
                      const Color(0xFF1E2138),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.purpleAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration_rounded,
                        color: Colors.purpleAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_activeCateringCount Active Catering & Event Orders',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Managed in dedicated Event Quotes Hub',
                            style: GoogleFonts.outfit(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Open Hub ➔',
                      style: GoogleFonts.outfit(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (_activeFilter == 'Bulk 🎉')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.purpleAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.purpleAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bulk & Catering orders are fully managed in the Quotes & Event Hub.',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.adminQuoteReview,
                        arguments: {'initialTab': 2},
                      ).then((_) => _fetch());
                    },
                    child: const Text('Open Hub ➔',
                        style: TextStyle(color: Colors.purpleAccent)),
                  ),
                ],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                            .fadeIn(delay: Duration(milliseconds: i * 35))
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
          Row(
              children: List.generate(
                  4,
                  (j) => Expanded(
                        child: Row(children: [
                          const SkeletonBox(width: 10, height: 10, radius: 5),
                          const SizedBox(width: 4),
                          if (j < 3)
                            Expanded(
                                child: Container(
                                    height: 2,
                                    color:
                                        Colors.white.withValues(alpha: 0.06))),
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

  static const _cateringTimeline = [
    (Icons.receipt_long_rounded, 'Order Paid'),
    (Icons.restaurant_rounded, 'Kitchen Confirmed'),
    (Icons.inventory_2_rounded, 'Batches Packed'),
    (Icons.local_shipping_rounded, 'Dispatched'),
    (Icons.check_circle_rounded, 'Delivered'),
  ];

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final status = (o['status'] ?? 'placed') as String;
    final profile = _extractMap(o['profiles']);
    final shop = _extractMap(o['shops']);
    final isPaid = (o['payment_status'] ?? '').toString() == 'captured';
    final isBulkOrCatering =
        o['order_type'] == 'bulk' || o['order_type'] == 'manual_quote';
    final amount = (o['grand_total_collected'] as num?)?.toDouble() ??
        (o['total_amount'] as num?)?.toDouble() ??
        0.0;
    final time = o['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(o['created_at'].toString()).toIST())
        : '';

    final (statusColor, statusLabel) = _statusStyle(status,
        isPaid: isPaid, isBulkOrCatering: isBulkOrCatering);
    final timelineStep = isBulkOrCatering
        ? _cateringTimelineStep(status)
        : _timelineStep(status);

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
                  child: Icon(
                    isBulkOrCatering
                        ? Icons.celebration_rounded
                        : Icons.receipt_long_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '#${o['id'].toString().substring(0, 8).toUpperCase()}',
                              style: AdminStyles.body(size: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBulkOrCatering) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.purple.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                o['order_type'] == 'manual_quote'
                                    ? '🍽️ EVENT'
                                    : '🎉 BULK',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purpleAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                          '${profile?['full_name'] ?? 'Customer'}  •  ${shop?['name'] ?? (isBulkOrCatering ? 'No Kitchen Appointed' : 'Shop')}',
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
            secondChild: _buildDetailPanel(
                o, timelineStep, statusColor, status, isBulkOrCatering),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: 250.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(Map<String, dynamic> o, int step, Color statusColor,
      String status, bool isBulkOrCatering) {
    final profile = _extractMap(o['profiles']);
    final shop = _extractMap(o['shops']);
    final bulkMeta = _extractMap(o['bulk_orders']);

    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    String parseStr(dynamic val, [String fallback = '—']) {
      if (val == null) return fallback;
      final s = val.toString().trim();
      return s.isEmpty ? fallback : s;
    }

    final grandTotal = parseNum(o['grand_total_collected']);
    final amount = (o['grand_total_collected'] != null && grandTotal >= 0)
        ? grandTotal
        : parseNum(o['total_amount']);
    final paymentMethod = parseStr(o['payment_method'], 'COD');

    final partnerId = parseStr(o['delivery_partner_id'], 'Not Assigned');
    final safePartnerId = partnerId.length > 8
        ? partnerId.substring(0, 8).toUpperCase()
        : partnerId.toUpperCase();

    String formatTime(dynamic t) {
      if (t == null) return '—';
      try {
        return DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(t.toString()).toIST());
      } catch (_) {
        return '—';
      }
    }

    final activeTimeline = isBulkOrCatering ? _cateringTimeline : _timeline;

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: const Border(top: BorderSide(color: AdminColors.cardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status timeline
          Text(
              isBulkOrCatering
                  ? 'Catering Lifecycle Timeline'
                  : 'Order Timeline',
              style: AdminStyles.label()),
          const SizedBox(height: 12),
          Row(
            children: List.generate(activeTimeline.length, (i) {
              final done = i <= step;
              final (icon, label) = activeTimeline[i];
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
                  if (i < activeTimeline.length - 1)
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

          // ── Catering Operations Hub (Appoint Kitchen, Batches, Fleet Dispatch, Handover) ──
          if (isBulkOrCatering) ...[
            _buildCateringOperationsHub(o, bulkMeta, status),
            const SizedBox(height: 16),
            const Divider(color: AdminColors.cardBorder, height: 1),
            const SizedBox(height: 14),
          ],

          // ── Detailed Info Sections ──────────────────────────

          // Customer Section
          Text('Customer Details',
              style: AdminStyles.title(color: AdminColors.primary, size: 14)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Name',
                value: parseStr(profile?['full_name'] ?? o['customer_name'], 'Unknown')),
            _InfoCell(
                label: 'Phone',
                value: parseStr(profile?['phone'] ?? o['customer_phone'])),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Address',
                value: parseStr(o['address'] ?? o['delivery_address'] ?? o['shipping_address']),
                maxLines: null),
          ]),
          if (parseStr(o['delivery_notes'] ?? o['instructions'], '') != '') ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _InfoCell(
                  label: 'Notes',
                  value: parseStr(o['delivery_notes'] ?? o['instructions']),
                  maxLines: null),
            ]),
          ],

          const SizedBox(height: 16),
          const Divider(color: AdminColors.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Shop Section
          Text('Shop Details',
              style: AdminStyles.title(color: AdminColors.primary, size: 14)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(label: 'Name', value: parseStr(shop?['name'] ?? o['shop_name'], 'Unknown')),
            _InfoCell(label: 'Phone', value: parseStr(o['shop_phone'])),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Prep Time',
                value: '${parseStr(o['shop_prep_time_snapshot'], '30')} mins'),
            _InfoCell(
                label: 'Ready At', value: formatTime(o['order_ready_time'])),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Wait Penalty',
                value:
                    '₹${parseNum(o['wait_time_penalty']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'Net Payout',
                value: '₹${parseNum(o['seller_payout']).toStringAsFixed(2)}'),
          ]),

          const SizedBox(height: 16),
          const Divider(color: AdminColors.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Rider Section
          Text('Rider Details',
              style: AdminStyles.title(color: AdminColors.primary, size: 14)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(label: 'Partner ID', value: safePartnerId),
            _InfoCell(label: 'Phone', value: parseStr(o['rider_phone'])),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Distance',
                value:
                    '${parseNum(o['estimated_distance_km']).toStringAsFixed(2)} km'),
            _InfoCell(
                label: 'Earnings',
                value: '₹${parseNum(o['rider_earnings']).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Arrived At Shop',
                value: formatTime(o['arrived_at_shop_time'])),
          ]),

          const SizedBox(height: 16),
          const Divider(color: AdminColors.cardBorder, height: 1),
          const SizedBox(height: 14),

          // Financial Breakdown
          Text('Financial Breakdown',
              style: AdminStyles.title(color: AdminColors.primary, size: 14)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(label: 'Payment', value: paymentMethod.toUpperCase()),
            _InfoCell(
                label: 'Status',
                value: parseStr(o['payment_status'], 'pending').toUpperCase()),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Item Total',
                value: '₹${parseNum(o['total_amount']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'Delivery Charge',
                value:
                    '₹${parseNum(o['delivery_charges']).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Platform Fee',
                value: '₹${parseNum(o['platform_fee']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'Surcharges',
                value:
                    '₹${(parseNum(o['small_cart_fee']) + parseNum(o['heavy_order_fee']) + parseNum(o['multi_shop_surcharge'])).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'GST (Items)',
                value: '₹${parseNum(o['gst_item_total']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'GST (Delivery+Plat)',
                value:
                    '₹${(parseNum(o['gst_delivery']) + parseNum(o['gst_platform'])).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Enything Comm.',
                value:
                    '₹${parseNum(o['enything_commission']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'TCS + TDS',
                value:
                    '₹${(parseNum(o['tcs_amount']) + parseNum(o['tds_amount'])).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoCell(
                label: 'Discount',
                value:
                    '-₹${parseNum(o['coupon_discount']).toStringAsFixed(2)}'),
            _InfoCell(
                label: 'Grand Total', value: '₹${amount.toStringAsFixed(2)}'),
          ]),

          const SizedBox(height: 16),

          // Action buttons
          Row(children: [
            if (status != 'cancelled' &&
                status != 'delivered' &&
                (context.read<RbacProvider>().can('orders.cancel') ||
                    context.read<RbacProvider>().isSuperAdmin))
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _actioning
                      ? null
                      : () => _cancelOrder(o['id'].toString()),
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
            if (context.read<RbacProvider>().can('orders.refund') ||
                context.read<RbacProvider>().isSuperAdmin)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _actioning
                      ? null
                      : () => _issueRefund(o['id'].toString(), amount),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text('Issue Refund',
                      style: AdminStyles.caption(color: Colors.white)),
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

  // ── Catering Operations Hub UI Component ──────────────────────────────────
  Widget _buildCateringOperationsHub(
      Map<String, dynamic> o, Map<String, dynamic>? bulk, String status) {
    final shop = _extractMap(o['shops']);
    final eventName =
        bulk?['event_name'] ?? o['address_label'] ?? 'Event Catering';
    final deliveryOtp = o['delivery_otp']?.toString() ?? '—';
    final isDelivered = status == 'delivered' || status == 'bulk_delivered';
    final isDispatched = status == 'bulk_dispatched';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16192E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.purpleAccent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.hub_rounded,
                        color: Colors.purpleAccent, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Catering Operations Hub',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  eventName.toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.purpleAccent.shade100,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),

          // ── STEP 1: Kitchen Appointed (1-Tap Direct Appoint) ───────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: status != 'bulk_pending'
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: status != 'bulk_pending'
                    ? Colors.greenAccent.withValues(alpha: 0.25)
                    : Colors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      status != 'bulk_pending'
                          ? Icons.check_circle_rounded
                          : Icons.soup_kitchen_rounded,
                      color: status != 'bulk_pending' ? Colors.greenAccent : Colors.amberAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status != 'bulk_pending'
                                ? (shop != null ? 'Kitchen: ${shop['name']}' : 'Kitchen Appointed & Confirmed 👨‍🍳')
                                : 'No Kitchen Appointed Yet',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            status != 'bulk_pending'
                                ? 'Kitchen confirmed. Food preparation arranged.'
                                : '1-tap to appoint kitchen and begin food prep.',
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    if (status != 'bulk_pending')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Confirmed 👨‍🍳',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (status == 'bulk_pending' && !isDelivered) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _appointKitchenDirectly(o['id'].toString()),
                      icon: const Icon(Icons.soup_kitchen_rounded, size: 16),
                      label: Text(
                        'Appoint Kitchen & Start Cooking 👨‍🍳',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── STEP 2: Food Preparation & Packaging (1-Tap Mark Ready) ─
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (status == 'bulk_ready' || isDispatched || isDelivered)
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (status == 'bulk_ready' || isDispatched || isDelivered)
                    ? Colors.greenAccent.withValues(alpha: 0.25)
                    : Colors.orange.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            (status == 'bulk_ready' || isDispatched || isDelivered)
                                ? Icons.done_all_rounded
                                : Icons.outdoor_grill_rounded,
                            color: (status == 'bulk_ready' || isDispatched || isDelivered)
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (status == 'bulk_ready' || isDispatched || isDelivered)
                                  ? 'All Food Prepared & Ready 🍱'
                                  : 'Dishes Cooking & Packaging 🍳',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (status == 'bulk_ready' || isDispatched || isDelivered)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Ready 🍱',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (status == 'bulk_ready' || isDispatched || isDelivered)
                      ? 'Containers packed and ready for transport.'
                      : 'Dishes are being prepared. Mark ready once fully packed.',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                ),
                if (status != 'bulk_ready' && !isDispatched && !isDelivered) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _markFoodReadyDirectly(o['id'].toString()),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text(
                        'Mark Food Ready 🍱',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── STEP 3: Fleet & Delivery Dispatch (Deliver Myself Only) ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDispatched
                  ? Colors.teal.withValues(alpha: 0.1)
                  : Colors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDispatched
                    ? Colors.teal.withValues(alpha: 0.3)
                    : Colors.purple.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isDispatched
                                ? Icons.local_shipping_rounded
                                : Icons.directions_car_filled_rounded,
                            color: isDispatched ? Colors.tealAccent : Colors.tealAccent.shade200,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isDispatched
                                  ? 'Out for Delivery (In-House Team) 🚗'
                                  : isDelivered
                                      ? 'Delivered Successfully 🎉'
                                      : 'Ready for Venue Dispatch',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: isDispatched
                                    ? Colors.tealAccent
                                    : isDelivered
                                        ? Colors.greenAccent
                                        : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isDispatched)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'In Transit 🚗',
                          style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isDispatched
                      ? 'In-house catering team is delivering food to the venue.'
                      : isDelivered
                          ? 'Delivered to customer at event location.'
                          : 'Transport food directly using in-house catering team/vehicle.',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                ),
                if (!isDispatched && !isDelivered) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _selfDeliverOrder(o),
                      icon: const Icon(Icons.directions_car_filled_rounded, size: 16),
                      label: const Text(
                        'Deliver Myself / Out for Delivery 🚗',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── STEP 4: Handover & Delivery Completion ───────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDelivered
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDelivered
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.amber.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key_rounded,
                          color: Colors.amberAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Handover OTP: $deliveryOtp',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.amberAccent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!isDelivered)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showCompleteDeliveryDialog(o),
                    icon: const Icon(Icons.verified_rounded, size: 15),
                    label: const Text(
                      'Complete Delivery 🎉',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'DELIVERED ✅',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Operations Dialogs & RPC Handlers ─────────────────────────────────────

  Future<void> _appointKitchenDirectly(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_appoint_catering_kitchen', params: {
        'p_order_id': orderId,
        'p_auto_confirm': true,
        'p_total_batches': 1,
      });
      final customerId = widget.order['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '👨‍🍳 Kitchen Confirmed & Cooking!',
          body: 'Your catering kitchen has confirmed your feast order #${orderId.substring(0, 8).toUpperCase()}. Preparation and cooking has started!',
          data: {'order_id': orderId, 'type': 'bulk_order'},
        );
      }
      await widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kitchen appointed & food prep started! 👨‍🍳'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error appointing kitchen: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _markFoodReadyDirectly(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_update_catering_packaging', params: {
        'p_order_id': orderId,
        'p_batches_packed': 1,
        'p_total_batches': 1,
      });
      final customerId = widget.order['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '🍱 All Food Prepared & Ready!',
          body: 'All dishes for your event feast #${orderId.substring(0, 8).toUpperCase()} are freshly prepared, packed, and awaiting dispatch!',
          data: {'order_id': orderId, 'type': 'bulk_order'},
        );
      }
      await widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('All food marked prepared and packed ready! 🍱'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error marking ready: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _selfDeliverOrder(Map<String, dynamic> o) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2138),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.directions_car_filled_rounded,
                color: Colors.tealAccent),
            const SizedBox(width: 8),
            Text('Self / In-House Delivery',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
        content: Text(
          'Mark this catering order as out for delivery with your in-house catering / management team?',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm & Dispatch 🚀'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_dispatch_catering_order', params: {
        'p_order_id': o['id'].toString(),
        'p_dispatch_type': 'admin_self_delivery',
        'p_driver_name': 'In-House Delivery Team',
      });
      final customerId = o['customer_id']?.toString();
      final otp = o['delivery_otp']?.toString() ?? '';
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '🚗 Feast Out for Delivery!',
          body: 'Your event catering feast #${o['id'].toString().substring(0, 8).toUpperCase()} is on its way with the in-house team! Handover OTP: $otp',
          data: {'order_id': o['id'].toString(), 'type': 'bulk_order'},
        );
      }
      await widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order dispatched via In-House Team! 🚚'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error dispatching: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _showCompleteDeliveryDialog(Map<String, dynamic> o) async {
    final expectedOtp = o['delivery_otp']?.toString() ?? '';
    final otpCtrl = TextEditingController(text: expectedOtp);
    bool adminOverride = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (_, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2138),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text('Confirm Handover',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify the 4-digit Delivery Handover OTP from the customer:',
                    style:
                        GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle:
                          const TextStyle(color: Colors.white24, letterSpacing: 6),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: adminOverride,
                        activeColor: Colors.amberAccent,
                        checkColor: Colors.black,
                        onChanged: (val) =>
                            setDlgState(() => adminOverride = val ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Super Admin Override (Bypass OTP check)',
                          style: GoogleFonts.outfit(
                              color: Colors.amberAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child:
                      const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(dlgCtx);
                    setState(() => _actioning = true);
                    try {
                      await _db.rpc('admin_complete_catering_delivery', params: {
                        'p_order_id': o['id'].toString(),
                        'p_otp': otpCtrl.text.trim(),
                        'p_admin_override': adminOverride,
                      });
                      final customerId = o['customer_id']?.toString();
                      if (customerId != null && customerId.isNotEmpty && mounted) {
                        context.read<NotificationProvider>().sendBackgroundPush(
                          targetUserId: customerId,
                          title: '🎉 Event Feast Delivered!',
                          body: 'Your catering feast has been successfully delivered and verified with OTP. Enjoy your event celebration!',
                          data: {'order_id': o['id'].toString(), 'type': 'bulk_order'},
                        );
                      }
                      await widget.onRefresh();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                          content:
                              Text('Catering order delivered successfully! 🎉'),
                          backgroundColor: Colors.green,
                        ));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Error completing delivery: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    }
                    if (mounted) setState(() => _actioning = false);
                  },
                  child: const Text('Confirm Handover ✅'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _cancelOrder(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_cancel_order', params: {'p_order_id': orderId});
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
            style:
                AdminStyles.body(size: 14, color: AdminColors.textSecondary)),
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
                  style: AdminStyles.body(size: 13, color: Colors.white))),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_issue_refund', params: {'p_order_id': orderId});

      await widget.onRefresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Refund of ₹${amount.toStringAsFixed(0)} queued. Status changed to processing.'),
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
        'placed' ||
        'pending' ||
        'awaiting_acceptance' ||
        'awaiting_payment' ||
        'bulk_pending' =>
          0,
        'accepted' ||
        'confirmed' ||
        'preparing' ||
        'bulk_confirmed' ||
        'bulk_preparing' =>
          1,
        'ready_for_pickup' ||
        'rider_assigned' ||
        'bulk_ready' =>
          2,
        'picked_up' ||
        'out_for_delivery' ||
        'bulk_dispatched' =>
          3,
        'delivered' || 'bulk_delivered' => 4,
        _ => 0,
      };

  int _cateringTimelineStep(String status) => switch (status) {
        'bulk_pending' || 'placed' || 'pending' => 0,
        'bulk_confirmed' => 1,
        'bulk_preparing' || 'bulk_ready' => 2,
        'bulk_dispatched' => 3,
        'delivered' || 'bulk_delivered' => 4,
        _ => 0,
      };

  (Color, String) _statusStyle(String status,
      {bool isPaid = false, bool isBulkOrCatering = false}) {
    if (status == 'bulk_pending') {
      return isPaid
          ? (const Color(0xFF8B5CF6), 'Assign Kitchen')
          : (AdminColors.warning, 'Awaiting Payment');
    }
    if (status == 'bulk_confirmed') {
      return (const Color(0xFF3B82F6), 'Kitchen Confirmed');
    }
    if (status == 'bulk_preparing') {
      return (const Color(0xFFF97316), 'Preparing Batches');
    }
    if (status == 'bulk_ready') {
      return (const Color(0xFF10B981), 'Ready for Dispatch');
    }
    if (status == 'bulk_dispatched') {
      return (const Color(0xFF06B6D4), 'Fleet Dispatched');
    }
    return switch (status) {
      'delivered' || 'bulk_delivered' => (AdminColors.success, 'Delivered'),
      'cancelled' ||
      'seller_rejected' ||
      'partner_rejected' ||
      'shop_dispute_cancel' ||
      'payment_failed' ||
      'timeout' ||
      'verification_failed' ||
      'bulk_cancelled' =>
        (AdminColors.danger, 'Cancelled'),
      'preparing' || 'accepted' || 'confirmed' => (
          AdminColors.info,
          'Preparing'
        ),
      'ready_for_pickup' || 'rider_assigned' =>
        (AdminColors.info, 'Ready / Assigned'),
      'picked_up' || 'out_for_delivery' =>
        (AdminColors.info, 'On the Way / Dispatched'),
      _ => (AdminColors.warning, 'Pending'),
    };
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final int? maxLines;
  const _InfoCell(
      {required this.label, required this.value, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AdminStyles.label()),
        const SizedBox(height: 2),
        Text(value,
            style: AdminStyles.body(size: 13),
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis),
      ]),
    );
  }
}
