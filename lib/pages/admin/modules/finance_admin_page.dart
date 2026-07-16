import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../config/tax_config.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';

class FinanceAdminPage extends StatefulWidget {
  final int initialTabIndex;
  const FinanceAdminPage({super.key, this.initialTabIndex = 0});

  @override
  State<FinanceAdminPage> createState() => _FinanceAdminPageState();
}

class _FinanceAdminPageState extends State<FinanceAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  SupabaseClient get _db => Supabase.instance.client;

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
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _fetch();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await _db.rpc('admin_get_finance_stats');
      if (res != null) {
        _gmv = (res['gmv'] as num).toDouble();
        _pureProfit = (res['pure_profit'] as num).toDouble();
        _sellerPayouts = (res['seller_payouts'] as num).toDouble();
        _riderEarnings = (res['rider_earnings'] as num).toDouble();
        _pendingSettlements = res['pending_settlements'] as int;
      }

      final orders = await _db.from('orders').select(
          'id, grand_total_collected, created_at, status, payment_status, refund_id, refund_status')
          .order('created_at', ascending: false)
          .limit(100);
      _transactions = List<Map<String, dynamic>>.from(orders);

      try {
        final wList = await _db.from('withdrawals').select('*, profiles:user_id(full_name)').order('requested_at', ascending: false).limit(100);
        _withdrawals = List<Map<String, dynamic>>.from(wList);
      } catch (e) {
        debugPrint('Withdrawals error: $e');
        _withdrawals = [];
      }
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
              Tab(text: 'GST Report'),
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
              const _GstStatementTab(),
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

  static bool _isSheetOpen = false;

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
              if (_isSheetOpen) return;
              _isSheetOpen = true;
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (ctx) => _WithdrawalActionSheet(
                  withdrawal: w,
                  onProcessed: onRefresh,
                ),
              ).then((_) => _isSheetOpen = false);
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

// ============================================================================
// GST STATEMENT TAB — Comprehensive Admin GST View for Chartered Accountant
// ============================================================================
//
// DATA SOURCES (all from existing DB columns — no logic changes):
//   orders.s9_5_gst_amount    → S.9(5) Food GST — Enything remits to Govt
//   orders.gst_delivery       → Delivery GST (18% embedded) — Enything remits
//   orders.gst_platform       → Platform Fee GST (18% embedded) — Enything remits
//   orders.enything_commission → Commission; 18% GST on this — Enything remits
//   orders.non_food_gst_amount → Non-food GST — Seller remits (pass-through)
//   orders.tcs_amount         → GST TCS (§52): 1% ONLY on non-food taxable supplies;
//                                0 for §9(5) food & 0% GST categories (fixed)
//   orders.tds_amount         → IT TDS (§194-O): 0.1% on ALL gross sales (new)
//
// CATEGORY GST BREAKDOWN:
//   Fetches order_items (product_id, price, quantity)
//   Fetches products (id, category) — separate query, joined in Dart
//   Applies TaxConfig.gstRateForCategory() per item to compute GST amounts
//   Groups by (GST slab %, category) for the breakdown table
// ============================================================================

// Data class for one category within a GST slab
class _CategoryGstRow {
  final String category;
  final double gstRate;
  final bool isDeemedSupplier; // S.9(5) food category?
  double taxableAmount = 0;
  double gstAmount = 0;
  int itemCount = 0;

  _CategoryGstRow({
    required this.category,
    required this.gstRate,
    required this.isDeemedSupplier,
  });
}

class _GstStatementTab extends StatefulWidget {
  const _GstStatementTab();

  @override
  State<_GstStatementTab> createState() => _GstStatementTabState();
}

class _GstStatementTabState extends State<_GstStatementTab> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _loading = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // ── Enything's GST payable to govt ──
  double _s9_5Gst       = 0; // S.9(5) food deemed-supplier GST
  double _deliveryGst   = 0; // 18% embedded in delivery charge
  double _platformGst   = 0; // 18% embedded in platform fee
  double _commissionGst = 0; // 18% on Enything's commission

  // ── Seller-owned (not Enything's liability) ──
  double _nonFoodGst    = 0; // Passed through to seller; seller remits
  // GST TCS §52: 1% ONLY on taxable non-food supplies. 0 for §9(5) food &
  // 0% GST categories (Fruits/Vegs, Butcher, Fish/Seafood). Enything files GSTR-8.
  double _tcsCollected  = 0;
  // IT TDS §194-O: 0.1% on ALL gross sales. Finance Act 2024 (eff. Oct 1 2024).
  // Enything files Form 26QE by 7th of next month. Seller claims via Form 26AS.
  double _tdsCollected  = 0;

  int _deliveredOrders = 0;

  // ── Category × slab breakdown ──
  // Key = GST slab label  e.g. "0%", "5%", "18%"
  // Value = Map<category, _CategoryGstRow>
  final Map<String, Map<String, _CategoryGstRow>> _slabMap = {};

  // Standard slab display order
  static const _slabOrder = ['0%', '3%', '5%', '18%', '28%'];

  // ── Colors per slab ─────────────────────────────────────────
  static Color _slabColor(String slab) => switch (slab) {
    '0%'  => const Color(0xFF868E96),
    '3%'  => const Color(0xFF51CF66),
    '5%'  => const Color(0xFF4DABF7),
    '18%' => const Color(0xFFF4C542),
    '28%' => const Color(0xFFFF6B6B),
    _     => AdminColors.primary,
  };

  @override
  void initState() {
    super.initState();
    _loadGstData();
  }

  String get _monthLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadGstData();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return;
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadGstData();
  }

  Future<void> _loadGstData() async {
    setState(() => _loading = true);
    try {
      final res = await _db.rpc('admin_get_gst_statement', params: {
        'p_month': _selectedMonth.month,
        'p_year': _selectedMonth.year
      });
      if (res != null) {
        _s9_5Gst = (res['s9_5_gst'] as num).toDouble();
        _deliveryGst = (res['delivery_gst'] as num).toDouble();
        _platformGst = (res['platform_gst'] as num).toDouble();
        _commissionGst = (res['commission_gst'] as num).toDouble();
        _nonFoodGst = (res['non_food_gst'] as num).toDouble();
        _tcsCollected = (res['tcs'] as num).toDouble();
        _tdsCollected = (res['tds'] as num).toDouble();
        _deliveredOrders = res['delivered_orders'] as int;

        _slabMap.clear();
        final grouped = res['grouped_items'] as List;
        for (final item in grouped) {
          final category = item['category'] as String;
          final price = (item['price'] as num).toDouble();
          final qty = item['quantity'] as int;
          final lineBase = price * qty;
          
          final gstRate = TaxConfig.gstRateForCategory(category, itemPrice: price);
          final lineGst = lineBase * gstRate;
          final isDeemedSupplier = TaxConfig.isEnythingDeemedSupplier(category);
          final slab = '${(gstRate * 100).toStringAsFixed(0)}%';

          _slabMap.putIfAbsent(slab, () => {});
          _slabMap[slab]!.putIfAbsent(
            category,
            () => _CategoryGstRow(
              category: category,
              gstRate: gstRate,
              isDeemedSupplier: isDeemedSupplier,
            ),
          );
          _slabMap[slab]![category]!.taxableAmount += lineBase;
          _slabMap[slab]![category]!.gstAmount += lineGst;
          _slabMap[slab]![category]!.itemCount += qty;
        }
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('GstStatement load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // Total Enything must pay to government
  double get _enythingTotalPayable =>
      _s9_5Gst + _deliveryGst + _platformGst + _commissionGst;

  String _f(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(v);
  String _fraw(double v) => v.toStringAsFixed(2);

  // ── Copy full GST report to clipboard ─────────────────────────────────────
  void _copyReport(BuildContext ctx) {
    final sortedSlabs = _slabOrder.where(_slabMap.containsKey).toList()
      ..addAll(_slabMap.keys.where((k) => !_slabOrder.contains(k)));

    double grandTaxable = 0;
    double grandGst = 0;
    for (final s in sortedSlabs) {
      for (final r in _slabMap[s]!.values) {
        grandTaxable += r.taxableAmount;
        grandGst     += r.gstAmount;
      }
    }

    final sb = StringBuffer();
    sb.writeln('ENYTHING — GST STATEMENT');
    sb.writeln('Period   : $_monthLabel');
    sb.writeln('Orders   : $_deliveredOrders delivered');
    sb.writeln('Generated: ${DateTime.now().toString().substring(0, 16)}');
    sb.writeln();
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln("ENYTHING'S GST PAYABLE TO GOVERNMENT");
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln('S.9(5) Food GST (Deemed Supplier)    : ₹${_fraw(_s9_5Gst)}');
    sb.writeln('Delivery Service GST (SAC 9965/9967) : ₹${_fraw(_deliveryGst)}');
    sb.writeln('Platform Fee GST    (SAC 9985)        : ₹${_fraw(_platformGst)}');
    sb.writeln('Commission GST      (18% on comm.)   : ₹${_fraw(_commissionGst)}');
    sb.writeln('──────────────────────────────────────────────');
    sb.writeln('TOTAL ENYTHING GST PAYABLE            : ₹${_fraw(_enythingTotalPayable)}');
    sb.writeln();
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln("SELLER PASS-THROUGH & TAX DEDUCTIONS (NOT ENYTHING'S GST LIABILITY)");
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln('Non-Food Item GST (Seller remits)    : ₹${_fraw(_nonFoodGst)}');
    sb.writeln('GST TCS 1% (§52, non-food only)      : ₹${_fraw(_tcsCollected)}');
    sb.writeln('  (§9(5) food & 0% GST categories exempt from TCS)');
    sb.writeln('IT TDS 0.1% (§194-O, all categories)  : ₹${_fraw(_tdsCollected)}');
    sb.writeln('  (Finance Act 2024, eff. Oct 1 2024. File Form 26QE by 7th.)');
    sb.writeln();
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln('CATEGORY-WISE GST BREAKDOWN');
    sb.writeln('════════════════════════════════════════════════');

    for (final slab in sortedSlabs) {
      final categories  = _slabMap[slab]!;
      final slabTaxable = categories.values.fold<double>(0, (s, r) => s + r.taxableAmount);
      final slabGst     = categories.values.fold<double>(0, (s, r) => s + r.gstAmount);
      sb.writeln();
      sb.writeln('$slab GST SLAB');
      final sorted = categories.values.toList()
        ..sort((a, b) => b.taxableAmount.compareTo(a.taxableAmount));
      for (final row in sorted) {
        final star = row.isDeemedSupplier ? ' [S.9(5) - Enything pays]' : '';
        sb.writeln('  ${row.category}$star');
        sb.writeln('    Items: ${row.itemCount}  Taxable: ₹${_fraw(row.taxableAmount)}  GST: ₹${_fraw(row.gstAmount)}');
      }
      sb.writeln('  ── Slab Total: Taxable ₹${_fraw(slabTaxable)}  |  GST ₹${_fraw(slabGst)}');
    }

    sb.writeln();
    sb.writeln('════════════════════════════════════════════════');
    sb.writeln('GRAND TOTAL: Taxable ₹${_fraw(grandTaxable)}  |  GST ₹${_fraw(grandGst)}');
    sb.writeln('════════════════════════════════════════════════');

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('GST Statement copied ✓',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingSkeleton();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // ── Month Selector ───────────────────────────────────────────────
        _buildMonthSelector(),
        const SizedBox(height: 12),

        // ── Summary banner ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            gradient: AdminGradients.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Enything GST Statement — $_monthLabel',
                    style: AdminStyles.caption(color: Colors.white70)),
                Text(
                  '$_deliveredOrders orders · Enything pays ${_f(_enythingTotalPayable)}',
                  style: AdminStyles.body(color: Colors.white),
                ),
              ]),
              const Icon(Icons.receipt_long_rounded, color: Colors.white54, size: 24),
            ],
          ),
        ).animate().fadeIn(delay: 50.ms),
        const SizedBox(height: 16),

        // ── Card 1: Enything's GST Payable ──────────────────────────────
        _GstSectionCard(
          title: "Enything's GST Payable to Government",
          subtitle: 'File in GSTR-3B by 20th of next month',
          accentColor: AdminColors.danger,
          icon: Icons.account_balance_rounded,
          rows: [
            _GstLineItem('S.9(5) Food GST (5% - Deemed Supplier)', _s9_5Gst,
                tag: 'S.9(5)', tagColor: const Color(0xFF51CF66)),
            _GstLineItem('Delivery GST 18% (SAC 9965/9967)', _deliveryGst),
            _GstLineItem('Platform Fee GST 18% (SAC 9985)', _platformGst),
            _GstLineItem('Commission GST (18% on commission)', _commissionGst),
            const _GstDivider(),
            _GstLineItem('TOTAL PAYABLE TO GOVT', _enythingTotalPayable,
                isBold: true, color: AdminColors.danger),
          ],
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 12),

        // ── Card 2: Seller Pass-Through + TDS (not Enything's liability) ────────
        _GstSectionCard(
          title: "Seller GST Pass-Through & Tax Deductions",
          subtitle: 'Collected on behalf of sellers — NOT Enything\'s liability',
          accentColor: AdminColors.warning,
          icon: Icons.store_rounded,
          rows: [
            _GstLineItem("Non-Food Item GST (Sellers remit via GSTR-1/3B)", _nonFoodGst,
                tag: 'SELLER', tagColor: AdminColors.warning),
            _GstLineItem("GST TCS 1% — §52 (non-food only; 0 for food/exempt)", _tcsCollected,
                tag: 'GSTR-8', tagColor: AdminColors.info),
            _GstLineItem("IT TDS 0.1% — §194-O (all categories, Finance Act 2024)", _tdsCollected,
                tag: '26QE', tagColor: const Color(0xFF4DABF7)),
          ],
        ).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: 16),

        // ── Card 3: Category-wise GST Breakdown ─────────────────────────
        _buildCategoryBreakdown().animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 20),

        // ── Legend ───────────────────────────────────────────────────────
        _buildLegend(),
        const SizedBox(height: 16),

        // ── Copy Button ──────────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: () => _copyReport(context),
          icon: const Icon(Icons.content_copy_rounded, size: 18),
          label: Text(
            'Copy Full GST Statement for CA',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ).animate().fadeIn(delay: 250.ms),
        const SizedBox(height: 8),
        Text(
          '📌  Copy this report and share with your CA via WhatsApp or email.\n'
          '    File GSTR-3B by 20th. File Form 26QE (TDS) by 7th.\n'
          '    Sellers check GSTR-2B after Enything files GSTR-8 by 10th.',
          style: AdminStyles.caption(color: AdminColors.textMuted).copyWith(height: 1.6),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Month Selector Widget ──────────────────────────────────────────────────
  Widget _buildMonthSelector() {
    final isCurrentMonth = _selectedMonth.month == DateTime.now().month &&
        _selectedMonth.year == DateTime.now().year;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: AdminColors.textSecondary),
          onPressed: _prevMonth,
        ),
        Expanded(
          child: Text(
            _monthLabel,
            textAlign: TextAlign.center,
            style: AdminStyles.title(size: 16).copyWith(color: Colors.white),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right_rounded,
            color: isCurrentMonth ? AdminColors.cardBorder : AdminColors.textSecondary,
          ),
          onPressed: _nextMonth,
        ),
      ]),
    );
  }

  // ── Category-wise breakdown ────────────────────────────────────────────────
  Widget _buildCategoryBreakdown() {
    if (_slabMap.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AdminColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AdminColors.cardBorder),
        ),
        child: Column(children: [
          const Icon(Icons.receipt_long_rounded, color: AdminColors.textMuted, size: 40),
          const SizedBox(height: 12),
          Text('No taxable items for $_monthLabel',
              style: AdminStyles.body(color: AdminColors.textMuted)),
          Text('Delivered orders with products will appear here.',
              style: AdminStyles.caption(), textAlign: TextAlign.center),
        ]),
      );
    }

    final sortedSlabs = _slabOrder.where(_slabMap.containsKey).toList()
      ..addAll(_slabMap.keys.where((k) => !_slabOrder.contains(k)));

    double grandTaxable = 0;
    double grandGst = 0;
    for (final s in sortedSlabs) {
      for (final r in _slabMap[s]!.values) {
        grandTaxable += r.taxableAmount;
        grandGst     += r.gstAmount;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: AdminColors.info.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.info.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.category_rounded, color: AdminColors.info, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Category-wise GST Breakdown',
                  style: AdminStyles.body(color: AdminColors.textPrimary)),
              Text('Grouped by GST slab · $_monthLabel',
                  style: AdminStyles.caption(color: AdminColors.textMuted)),
            ])),
          ]),
        ),

        // Slab sections
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (int idx = 0; idx < sortedSlabs.length; idx++) ...[
              _buildSlabSection(sortedSlabs[idx], _slabMap[sortedSlabs[idx]]!),
              if (idx < sortedSlabs.length - 1) ...[
                const SizedBox(height: 8),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 8),
              ],
            ],

            // Grand Total
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              decoration: BoxDecoration(
                gradient: AdminGradients.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('GRAND TOTAL (All Categories)',
                        style: AdminStyles.body(color: Colors.white, size: 13)
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Taxable  ${_f(grandTaxable)}',
                        style: AdminStyles.caption(color: Colors.white70)),
                    Text('GST  ${_f(grandGst)}',
                        style: AdminStyles.body(color: Colors.white, size: 14)
                            .copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSlabSection(String slab, Map<String, _CategoryGstRow> categories) {
    final slabColor    = _slabColor(slab);
    final slabTaxable  = categories.values.fold<double>(0, (s, r) => s + r.taxableAmount);
    final slabGst      = categories.values.fold<double>(0, (s, r) => s + r.gstAmount);
    final sortedCats   = categories.values.toList()
      ..sort((a, b) => b.taxableAmount.compareTo(a.taxableAmount));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Slab header pill
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: slabColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: slabColor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            '$slab GST${slab == '0%' ? ' — EXEMPT' : ''}',
            style: AdminStyles.body(color: slabColor, size: 12)
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Text('GST: ${_f(slabGst)}',
              style: AdminStyles.caption(color: slabColor)
                  .copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(height: 8),

      // Category rows
      ...sortedCats.map((row) => Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 7),
        child: Row(children: [
          // S.9(5) indicator
          if (row.isDeemedSupplier)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.restaurant_rounded,
                  color: Color(0xFF51CF66), size: 12),
            )
          else
            const SizedBox(width: 16),
          // Category name + item count
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.category,
                  style: AdminStyles.body(color: AdminColors.textSecondary, size: 12)),
              Text('${row.itemCount} item${row.itemCount == 1 ? '' : 's'}',
                  style: AdminStyles.caption(color: AdminColors.textMuted).copyWith(fontSize: 10)),
            ]),
          ),
          // Taxable + GST
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_f(row.taxableAmount),
                style: AdminStyles.caption(color: AdminColors.textSecondary)),
            Text(
              '+ ${_f(row.gstAmount)} GST',
              style: AdminStyles.body(color: slabColor, size: 12)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      )),

      // Slab subtotal
      Padding(
        padding: const EdgeInsets.only(left: 16, top: 2),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: slabColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: slabColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Slab total: ${_f(slabTaxable)} taxable  |  ${_f(slabGst)} GST',
              style: AdminStyles.caption(color: slabColor)
                  .copyWith(fontWeight: FontWeight.w700, fontSize: 10),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── Legend ─────────────────────────────────────────────────────────────────
  Widget _buildLegend() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AdminColors.cardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.cardBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Legend', style: AdminStyles.caption(color: AdminColors.textMuted)
          .copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.restaurant_rounded, color: Color(0xFF51CF66), size: 12),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'S.9(5) — Enything is the deemed supplier (restaurant/food). Enything remits GST, not the seller.',
          style: AdminStyles.caption(color: AdminColors.textSecondary).copyWith(fontSize: 10),
        )),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Container(width: 12, height: 12,
            decoration: const BoxDecoration(
                color: Color(0xFF868E96), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(
          '0% — Exempt (fresh produce, meat, fish). No GST charged.',
          style: AdminStyles.caption(color: AdminColors.textSecondary).copyWith(fontSize: 10),
        )),
      ]),
    ]),
  );
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

/// A GST section card (e.g. Enything Payable / Seller Pass-Through)
class _GstSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accentColor;
  final IconData icon;
  final List<Widget> rows;

  const _GstSectionCard({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminColors.cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accentColor.withValues(alpha: 0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AdminStyles.body(color: AdminColors.textPrimary)),
            Text(subtitle, style: AdminStyles.caption(color: AdminColors.textMuted)),
          ])),
        ]),
      ),
      // Rows
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(children: rows),
      ),
    ]),
  );
}

/// A single GST line item row
class _GstLineItem extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? color;
  final String? tag;
  final Color? tagColor;

  const _GstLineItem(
    this.label,
    this.value, {
    this.isBold = false,
    this.color,
    this.tag,
    this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? (isBold ? AdminColors.textPrimary : AdminColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(
            label,
            style: AdminStyles.body(color: displayColor, size: 12).copyWith(
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        if (tag != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (tagColor ?? Colors.white).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              tag!,
              style: AdminStyles.caption(color: tagColor ?? Colors.white).copyWith(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: AdminStyles.body(color: displayColor, size: isBold ? 15 : 13).copyWith(
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}

class _GstDivider extends StatelessWidget {
  const _GstDivider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: Divider(color: Colors.white12, height: 1),
  );
}

// ── Shared skeleton loader ────────────────────────────────────────────────────
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
  SupabaseClient get _db => Supabase.instance.client;
  final _txnIdCtrl = TextEditingController();
  
  bool _processing = false;
  bool _loadingDetails = true;
  double _totalEarned = 0;
  double _totalWithdrawn = 0;
  double _availableBalance = 0;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }
  
  @override
  void dispose() {
    _txnIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String status) async {
    if (status == 'processed' && _txnIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a Transaction ID or Receipt', style: AdminStyles.body(color: Colors.white)),
        backgroundColor: AdminColors.warning,
      ));
      return;
    }
    setState(() => _processing = true);
    try {
      await _db.rpc('admin_process_withdrawal', params: {
        'p_withdrawal_id': widget.withdrawal['id'],
        'p_status': status,
        'p_transaction_id': status == 'processed' ? _txnIdCtrl.text.trim() : null,
      });
      widget.onProcessed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating withdrawal: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  Future<void> _loadUserDetails() async {
    try {
      final w = widget.withdrawal;
      final userId = w['user_id'];
      final role = w['user_role'];

      // Securely fetch exact calculated balances via DB RPCs to prevent OOM
      if (role == 'seller') {
        final shopRes = await _db.from('shops').select('id').eq('seller_id', userId).maybeSingle();
        if (shopRes != null) {
          final balanceRes = await _db.rpc('get_seller_balance', params: {
            'p_shop_id': shopRes['id'],
          });
          if (balanceRes != null) {
            _totalEarned = (balanceRes['total_earned'] as num).toDouble();
            _totalWithdrawn = (balanceRes['total_paid'] as num).toDouble();
            _availableBalance = (balanceRes['available_balance'] as num).toDouble();
          }
        }
      } else if (role == 'delivery_partner') {
        final balanceRes = await _db.rpc('get_rider_balance', params: {
          'p_rider_id': userId,
        });
        if (balanceRes != null) {
          _totalEarned = (balanceRes['total_earned'] as num).toDouble();
          _totalWithdrawn = (balanceRes['total_paid'] as num).toDouble();
          _availableBalance = (balanceRes['available_balance'] as num).toDouble();
        }
      }

    } catch (e) {
      debugPrint('Error loading user details: $e');
    }
    if (mounted) setState(() => _loadingDetails = false);
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
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 48),
      decoration: const BoxDecoration(
        color: AdminColors.surface,
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
          
          if (_loadingDetails)
             const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.primary)))
          else ...[
             const SizedBox(height: 12),
             _DetailRow('Max Allowed (Earnings)', '₹${_totalEarned.toStringAsFixed(0)}'),
             const SizedBox(height: 12),
             _DetailRow('Withdrawn Till Date', '₹${_totalWithdrawn.toStringAsFixed(0)}'),
             const SizedBox(height: 12),
             _DetailRow('Available Balance', '₹${_availableBalance.toStringAsFixed(0)}', highlight: _availableBalance >= amount),
          ],
          
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
              TextField(
                controller: _txnIdCtrl,
                style: AdminStyles.body(),
                decoration: InputDecoration(
                  labelText: 'Transaction ID / Receipt (Required)',
                  labelStyle: AdminStyles.caption(),
                  filled: true,
                  fillColor: AdminColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
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

