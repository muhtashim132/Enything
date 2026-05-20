import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/admin_theme.dart';

class FinanceAdminPage extends StatefulWidget {
  const FinanceAdminPage({super.key});

  @override
  State<FinanceAdminPage> createState() => _FinanceAdminPageState();
}

class _FinanceAdminPageState extends State<FinanceAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _db = Supabase.instance.client;

  bool _loading = true;
  double _gmv = 0;
  double _commission = 0;
  double _sellerPayouts = 0;
  double _riderEarnings = 0;
  int _pendingSettlements = 0;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final orders = await _db.from('orders').select(
          'grand_total_collected, seller_payout, rider_payout, created_at, status, id');
      _transactions = List<Map<String, dynamic>>.from(orders)
        ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
      _gmv = orders.fold<double>(
          0, (s, o) => s + ((o['grand_total_collected'] as num?)?.toDouble() ?? 0));
      _commission = _gmv * 0.05;
      _sellerPayouts = orders.fold<double>(
          0, (s, o) => s + ((o['seller_payout'] as num?)?.toDouble() ?? 0));
      _riderEarnings = orders.fold<double>(
          0, (s, o) => s + ((o['rider_payout'] as num?)?.toDouble() ?? 0));
      _pendingSettlements = orders.where((o) => o['status'] == 'delivered').length;
    } catch (e) {
      debugPrint('Finance load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final fmt = NumberFormat.compact(locale: 'en_IN');

    return Column(
      children: [
        // ── KPI Strip ──────────────────────────────────────────
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            children: [
              _FinanceKpi('Total GMV', _loading ? '—' : rupee.format(_gmv),
                  Icons.trending_up_rounded, AdminGradients.primary),
              _FinanceKpi('Commission', _loading ? '—' : rupee.format(_commission),
                  Icons.percent_rounded, AdminGradients.success),
              _FinanceKpi('Seller Payouts', _loading ? '—' : rupee.format(_sellerPayouts),
                  Icons.store_rounded, AdminGradients.warning),
              _FinanceKpi('Rider Earnings', _loading ? '—' : rupee.format(_riderEarnings),
                  Icons.delivery_dining_rounded, AdminGradients.info),
              _FinanceKpi('Settlements', _loading ? '—' : fmt.format(_pendingSettlements),
                  Icons.account_balance_rounded, AdminGradients.danger),
            ]
                .asMap()
                .entries
                .map((e) =>
                    e.value.animate().fadeIn(delay: Duration(milliseconds: e.key * 70)).slideX(begin: 0.2))
                .toList(),
          ),
        ),

        // ── Tab bar ────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: AdminColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminColors.cardBorder),
          ),
          child: TabBar(
            controller: _tabs,
            indicator: BoxDecoration(
              gradient: AdminGradients.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AdminColors.textMuted,
            labelStyle: AdminStyles.caption(color: Colors.white),
            unselectedLabelStyle: AdminStyles.caption(),
            tabs: const [
              Tab(text: 'Transactions'),
              Tab(text: 'Withdrawals'),
              Tab(text: 'Refunds'),
              Tab(text: 'Taxes'),
            ],
          ),
        ),

        // ── Tab Content ────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _TransactionsTab(transactions: _transactions, loading: _loading),
              const _ComingSoonTab('Withdrawals', Icons.account_balance_wallet_rounded),
              const _ComingSoonTab('Refunds', Icons.undo_rounded),
              const _ComingSoonTab('Tax Reports', Icons.receipt_long_rounded),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Finance KPI Horizontal Card ───────────────────────────────────
class _FinanceKpi extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final LinearGradient gradient;

  const _FinanceKpi(this.title, this.value, this.icon, this.gradient);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: AdminDecorations.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: AdminStyles.title(size: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(title, style: AdminStyles.caption(color: AdminColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Transactions Tab ──────────────────────────────────────────────
class _TransactionsTab extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool loading;

  const _TransactionsTab({required this.transactions, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AdminDecorations.glassCard(),
          child: const Row(children: [
            SkeletonBox(width: 38, height: 38, radius: 12),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 100, height: 13),
              SizedBox(height: 6),
              SkeletonBox(width: 70, height: 11),
            ])),
            SkeletonBox(width: 55, height: 20, radius: 10),
          ]),
        ).animate().shimmer(duration: 1500.ms),
      );
    }

    if (transactions.isEmpty) {
      return const AdminEmptyState(icon: Icons.receipt_long_rounded, message: 'No transactions yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: transactions.length,
      itemBuilder: (_, i) {
        final t = transactions[i];
        final amount = (t['grand_total_collected'] as num?)?.toDouble() ?? 0;
        final status = (t['status'] ?? 'placed') as String;
        final time = t['created_at'] != null
            ? DateFormat('dd MMM, hh:mm a')
                .format(DateTime.parse(t['created_at'].toString()).toLocal())
            : '';
        final (statusColor, statusLabel) = switch (status) {
          'delivered' => (AdminColors.success, 'Delivered'),
          'cancelled' => (AdminColors.danger, 'Cancelled'),
          _ => (AdminColors.warning, 'Pending'),
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AdminDecorations.glassCard(),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.receipt_rounded, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${t['id'].toString().substring(0, 8).toUpperCase()}',
                    style: AdminStyles.body(size: 13)),
                Text(time, style: AdminStyles.caption()),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${amount.toStringAsFixed(0)}',
                  style: AdminStyles.body(size: 14, color: AdminColors.success)),
              const SizedBox(height: 4),
              AdminBadge(label: statusLabel, color: statusColor),
            ]),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).slideY(begin: 0.08);
      },
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  final String name;
  final IconData icon;
  const _ComingSoonTab(this.name, this.icon);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminColors.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AdminColors.cardBorder),
          ),
          child: Icon(icon, color: AdminColors.primary, size: 48),
        ),
        const SizedBox(height: 16),
        Text('$name — Coming Soon', style: AdminStyles.title(size: 16)),
        const SizedBox(height: 8),
        Text('This module is under development.', style: AdminStyles.caption()),
      ]),
    ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9));
  }
}
