import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';

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
  double _pureProfit = 0;
  double _sellerPayouts = 0;
  double _riderEarnings = 0;
  int _pendingSettlements = 0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _withdrawals = [];

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
          'grand_total_collected, seller_payout, rider_earnings, enything_commission, created_at, status, id, refund_id, refund_status, gst_item_total, gst_delivery, gst_platform, payment_status, platform_fee, delivery_charges, multi_shop_surcharge, gateway_deduction');
      
      final wList = await _db.from('withdrawals').select('*, profiles:user_id(full_name)').order('requested_at', ascending: false);
      _withdrawals = List<Map<String, dynamic>>.from(wList);
      _transactions = List<Map<String, dynamic>>.from(orders)
        ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
      // Calculate KPIs: Exclude cancelled orders for GMV/Commission
      final nonCancelled = orders.where((o) => o['status'] != 'cancelled').toList();
      _gmv = nonCancelled.fold<double>(
          0, (s, o) => s + ((o['grand_total_collected'] as num?)?.toDouble() ?? 0));
      _pureProfit = nonCancelled.fold<double>(0, (s, o) {
        final comm = (o['enything_commission'] as num?)?.toDouble() ?? 0;
        final platFee = (o['platform_fee'] as num?)?.toDouble() ?? 0;
        final gstPlat = (o['gst_platform'] as num?)?.toDouble() ?? 0;
        final delCharge = (o['delivery_charges'] as num?)?.toDouble() ?? 0;
        final multiSurcharge = (o['multi_shop_surcharge'] as num?)?.toDouble() ?? 0;
        final gstDel = (o['gst_delivery'] as num?)?.toDouble() ?? 0;
        final riderEarn = (o['rider_earnings'] as num?)?.toDouble() ?? 0;
        final gatewayDed = (o['gateway_deduction'] as num?)?.toDouble() ?? 0;
        
        final profit = comm + (platFee - gstPlat) + (delCharge + multiSurcharge - gstDel - riderEarn) - gatewayDed;
        return s + profit;
      });

      // Seller and Rider earnings match their own dashboards (only delivered orders)
      final delivered = orders.where((o) => o['status'] == 'delivered').toList();
      _sellerPayouts = delivered.fold<double>(
          0, (s, o) => s + ((o['seller_payout'] as num?)?.toDouble() ?? 0));
      _riderEarnings = delivered.fold<double>(
          0, (s, o) => s + ((o['rider_earnings'] as num?)?.toDouble() ?? 0));
      _pendingSettlements = orders.where((o) => o['status'] == 'delivered').length;
    } catch (e) {
      debugPrint('Finance load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('finance.view')) {
      return const ForbiddenPage(fullPage: false);
    }
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
              _FinanceKpi('Pure Profit', _loading ? '—' : rupee.format(_pureProfit),
                  Icons.account_balance_wallet_rounded, AdminGradients.success),
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
              _WithdrawalsTab(withdrawals: _withdrawals, loading: _loading, onRefresh: _fetch),
              _RefundsTab(transactions: _transactions, loading: _loading),
              _TaxesTab(transactions: _transactions, loading: _loading),
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
                .format(DateTime.parse(t['created_at'].toString()).toIST())
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
                  color: statusColor.withValues(alpha: 0.15),
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

class _WithdrawalsTab extends StatelessWidget {
  final List<Map<String, dynamic>> withdrawals;
  final bool loading;
  final VoidCallback onRefresh;

  const _WithdrawalsTab({required this.withdrawals, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingSkeleton();

    if (withdrawals.isEmpty) {
      return const AdminEmptyState(icon: Icons.account_balance_wallet_rounded, message: 'No withdrawals yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: withdrawals.length,
      itemBuilder: (_, i) {
        final w = withdrawals[i];
        final amount = (w['amount'] as num?)?.toDouble() ?? 0;
        final status = (w['status'] ?? 'pending') as String;
        final role = (w['user_role'] ?? 'user') as String;
        final name = (w['profiles']?['full_name'] ?? 'Unknown');
        final time = w['requested_at'] != null
            ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(w['requested_at'].toString()).toIST())
            : '';
        
        final (statusColor, statusLabel) = switch (status) {
          'approved' || 'processed' => (AdminColors.success, 'Processed'),
          'rejected' => (AdminColors.danger, 'Rejected'),
          _ => (AdminColors.warning, 'Pending'),
        };

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (ctx) => _WithdrawalActionSheet(
                  withdrawal: w,
                  onProcessed: onRefresh,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AdminDecorations.glassCard(),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: AdminColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.money_rounded, color: AdminColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: AdminStyles.body(size: 13)),
                    Text('$role • $time', style: AdminStyles.caption()),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹${amount.toStringAsFixed(0)}', style: AdminStyles.body(size: 14)),
                  const SizedBox(height: 4),
                  AdminBadge(label: statusLabel, color: statusColor),
                ]),
              ]),
            ),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).slideY(begin: 0.08);
      },
    );
  }
}

class _RefundsTab extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool loading;

  const _RefundsTab({required this.transactions, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingSkeleton();

    final refunds = transactions.where((t) {
      final isCancelledAfterPayment = t['status'] == 'cancelled' && t['payment_status'] == 'captured';
      return t['refund_id'] != null || t['refund_status'] != null || isCancelledAfterPayment;
    }).toList();

    if (refunds.isEmpty) {
      return const AdminEmptyState(icon: Icons.undo_rounded, message: 'No refunds yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: refunds.length,
      itemBuilder: (_, i) {
        final t = refunds[i];
        final amount = (t['grand_total_collected'] as num?)?.toDouble() ?? 0;
        final status = (t['refund_status'] ?? 'processing') as String;
        final time = t['created_at'] != null
            ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(t['created_at'].toString()).toIST())
            : '';
        
        final (statusColor, statusLabel) = switch (status) {
          'processed' => (AdminColors.success, 'Processed'),
          'failed' => (AdminColors.danger, 'Failed'),
          _ => (AdminColors.warning, 'Processing'),
        };

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AdminDecorations.glassCard(),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AdminColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.undo_rounded, color: AdminColors.danger, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Order #${t['id'].toString().substring(0, 8).toUpperCase()}', style: AdminStyles.body(size: 13)),
                Text(time, style: AdminStyles.caption()),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${amount.toStringAsFixed(0)}', style: AdminStyles.body(size: 14)),
              const SizedBox(height: 4),
              AdminBadge(label: statusLabel, color: statusColor),
            ]),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).slideY(begin: 0.08);
      },
    );
  }
}

class _TaxesTab extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool loading;

  const _TaxesTab({required this.transactions, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingSkeleton();

    final taxable = transactions.where((t) {
      if (t['status'] == 'cancelled') return false;
      if (t['payment_status'] != 'captured' && t['payment_status'] != 'cod') return false;
      return ((t['gst_item_total'] ?? 0) > 0 || (t['gst_delivery'] ?? 0) > 0 || (t['gst_platform'] ?? 0) > 0);
    }).toList();

    if (taxable.isEmpty) {
      return const AdminEmptyState(icon: Icons.receipt_long_rounded, message: 'No tax records yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: taxable.length,
      itemBuilder: (_, i) {
        final t = taxable[i];
        final gstItem = (t['gst_item_total'] as num?)?.toDouble() ?? 0;
        final gstDel = (t['gst_delivery'] as num?)?.toDouble() ?? 0;
        final gstPlat = (t['gst_platform'] as num?)?.toDouble() ?? 0;
        final totalGst = gstItem + gstDel + gstPlat;
        final time = t['created_at'] != null
            ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(t['created_at'].toString()).toIST())
            : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AdminDecorations.glassCard(),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AdminColors.info.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_rounded, color: AdminColors.info, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Order #${t['id'].toString().substring(0, 8).toUpperCase()}', style: AdminStyles.body(size: 13)),
                Text(time, style: AdminStyles.caption()),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${totalGst.toStringAsFixed(2)}', style: AdminStyles.body(size: 14)),
              const SizedBox(height: 4),
              const AdminBadge(label: 'GST Collected', color: AdminColors.info),
            ]),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).slideY(begin: 0.08);
      },
    );
  }
}

Widget _loadingSkeleton() {
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

class _WithdrawalActionSheet extends StatefulWidget {
  final Map<String, dynamic> withdrawal;
  final VoidCallback onProcessed;

  const _WithdrawalActionSheet({
    required this.withdrawal,
    required this.onProcessed,
  });

  @override
  State<_WithdrawalActionSheet> createState() => _WithdrawalActionSheetState();
}

class _WithdrawalActionSheetState extends State<_WithdrawalActionSheet> {
  final _db = Supabase.instance.client;
  bool _processing = false;

  Future<void> _updateStatus(String status) async {
    setState(() => _processing = true);
    try {
      await _db.from('withdrawals').update({'status': status}).eq('id', widget.withdrawal['id']);
      widget.onProcessed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating withdrawal: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.withdrawal;
    final amount = (w['amount'] as num?)?.toDouble() ?? 0;
    final status = (w['status'] ?? 'pending') as String;
    final role = (w['user_role'] ?? 'user') as String;
    final name = (w['profiles']?['full_name'] ?? 'Unknown');
    final upi = w['upi_id'];
    final bankAcc = w['bank_account_number'];
    final bankIfsc = w['bank_ifsc'];
    final time = w['requested_at'] != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(w['requested_at'].toString()).toIST())
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      decoration: const BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Withdrawal Request', style: AdminStyles.heading(size: 20)),
          const SizedBox(height: 24),
          
          _DetailRow('User', '$name ($role)'),
          const SizedBox(height: 12),
          _DetailRow('Amount', '₹${amount.toStringAsFixed(0)}', highlight: true),
          const SizedBox(height: 12),
          _DetailRow('Date', time),
          
          const SizedBox(height: 20),
          const Divider(color: AdminColors.cardBorder),
          const SizedBox(height: 20),
          
          Text('Payout Details', style: AdminStyles.title(size: 16)),
          const SizedBox(height: 12),
          
          if (upi != null) _DetailRow('UPI ID', upi),
          if (bankAcc != null) ...[
            _DetailRow('Bank Account', bankAcc),
            const SizedBox(height: 8),
            _DetailRow('IFSC', bankIfsc ?? 'N/A'),
          ],
          if (upi == null && bankAcc == null)
            Text('No payout destination provided.', style: AdminStyles.body(color: AdminColors.warning)),
            
          const SizedBox(height: 32),
          
          if (status == 'pending') ...[
            if (_processing) 
              const Center(child: CircularProgressIndicator(color: AdminColors.primary))
            else ...[
              ElevatedButton(
                onPressed: () => _updateStatus('processed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Mark as Processed', style: AdminStyles.title(size: 14, color: Colors.white)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _updateStatus('rejected'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AdminColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Reject Withdrawal', style: AdminStyles.title(size: 14, color: AdminColors.danger)),
              ),
            ]
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: status == 'rejected' ? AdminColors.danger.withValues(alpha: 0.1) : AdminColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'This request has been ${status.toUpperCase()}',
                style: AdminStyles.body(color: status == 'rejected' ? AdminColors.danger : AdminColors.success),
                textAlign: TextAlign.center,
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _DetailRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AdminStyles.caption(color: AdminColors.textSecondary, size: 14)),
        Text(value, style: highlight ? AdminStyles.title(color: AdminColors.success, size: 14) : AdminStyles.body(color: AdminColors.textPrimary)),
      ],
    );
  }
}
