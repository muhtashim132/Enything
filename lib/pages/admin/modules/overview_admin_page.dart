import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../theme/admin_theme.dart';
import 'orders_admin_page.dart';
import 'users_admin_page.dart';
import 'kyc_review_page.dart';
import 'finance_admin_page.dart';

class OverviewAdminPage extends StatefulWidget {
  final String adminName;
  const OverviewAdminPage({super.key, required this.adminName});

  @override
  State<OverviewAdminPage> createState() => _OverviewAdminPageState();
}

class _OverviewAdminPageState extends State<OverviewAdminPage> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  int _totalOrders = 0;
  double _totalRevenue = 0;
  int _totalUsers = 0;
  int _pendingKyc = 0;
  int _pendingWithdrawals = 0;
  double _commission = 0;

  List<Map<String, dynamic>> _recentActivity = [];
  List<FlSpot> _revenueSpots = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Orders count + revenue
      final orders =
          await _db.from('orders').select('grand_total_collected, created_at');
      _totalOrders = orders.length;
      _totalRevenue = orders.fold<double>(
          0,
          (sum, o) =>
              sum + ((o['grand_total_collected'] as num?)?.toDouble() ?? 0));

      // Platform commission (5% of revenue estimate)
      _commission = _totalRevenue * 0.05;

      // Users count
      final users = await _db.from('profiles').select('id');
      _totalUsers = users.length;

      // Pending KYC — shops awaiting approval
      final kyc = await _db
          .from('shops')
          .select('id')
          .eq('verification_status', 'pending');
      _pendingKyc = kyc.length;

      // Pending withdrawals — fallback to 0 if table missing
      try {
        final w =
            await _db.from('withdrawals').select('id').eq('status', 'pending');
        _pendingWithdrawals = w.length;
      } catch (_) {
        _pendingWithdrawals = 0;
      }

      // Recent activity — last 10 orders
      final activity = await _db
          .from('orders')
          .select('id, created_at, status, grand_total_collected')
          .order('created_at', ascending: false)
          .limit(10);
      _recentActivity = List<Map<String, dynamic>>.from(activity);

      // 7-day revenue chart spots
      final now = DateTime.now();
      final spots = <FlSpot>[];
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final dayRevenue = orders.where((o) {
          if (o['created_at'] == null) return false;
          final d = DateTime.tryParse(o['created_at'].toString());
          return d != null &&
              d.year == day.year &&
              d.month == day.month &&
              d.day == day.day;
        }).fold<double>(
            0,
            (sum, o) =>
                sum + ((o['grand_total_collected'] as num?)?.toDouble() ?? 0));
        spots.add(FlSpot((6 - i).toDouble(), dayRevenue));
      }
      _revenueSpots = spots;
    } catch (e) {
      debugPrint('Overview load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  void _openModule(BuildContext context, String title, Widget child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.surface,
            elevation: 0,
            leading: const BackButton(color: Colors.white),
            title: Text(title, style: AdminStyles.title().copyWith(color: Colors.white)),
          ),
          body: child,
        ),
      ),
    );
  }

  void _handleNav(BuildContext context, List<String> requiredPermissions, String title, Widget child) {
    final rbac = context.read<RbacProvider>();
    final hasPerm = rbac.isSuperAdmin || requiredPermissions.any((p) => rbac.can(p));
    if (hasPerm) {
      _openModule(context, title, child);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You do not have permission to access $title.'),
        backgroundColor: AdminColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.compact(locale: 'en_IN');
    final rupee =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _loadData();
      },
      color: AdminColors.primary,
      backgroundColor: AdminColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── KPI Grid ─────────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              AdminKpiCard(
                title: 'Total Revenue',
                value: rupee.format(_totalRevenue),
                subtitle: 'All time',
                icon: Icons.currency_rupee_rounded,
                gradient: AdminGradients.primary,
                loading: _loading,
                onTap: () => _handleNav(context, ['finance.view'], 'Finance', const FinanceAdminPage()),
              )
                  .animate()
                  .fadeIn(delay: 50.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Total Orders',
                value: fmt.format(_totalOrders),
                subtitle: 'All time',
                icon: Icons.shopping_bag_rounded,
                gradient: AdminGradients.info,
                loading: _loading,
                onTap: () => _handleNav(context, ['orders.view'], 'Orders', const OrdersAdminPage()),
              )
                  .animate()
                  .fadeIn(delay: 100.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Active Users',
                value: fmt.format(_totalUsers),
                icon: Icons.people_rounded,
                gradient: AdminGradients.success,
                loading: _loading,
                onTap: () {
                  final rbac = context.read<RbacProvider>();
                  _handleNav(context, ['customers.view', 'sellers.view', 'riders.view'], 'Users', ChangeNotifierProvider.value(value: rbac, child: const UsersAdminPage()));
                },
              )
                  .animate()
                  .fadeIn(delay: 150.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Pending KYC',
                value: _pendingKyc.toString(),
                subtitle: 'Awaiting review',
                icon: Icons.pending_actions_rounded,
                gradient: AdminGradients.warning,
                loading: _loading,
                onTap: () => _handleNav(context, ['sellers.approve', 'riders.approve'], 'KYC Verification', const KycReviewPage()),
              )
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Withdrawals',
                value: _pendingWithdrawals.toString(),
                subtitle: 'Pending approval',
                icon: Icons.account_balance_wallet_rounded,
                gradient: AdminGradients.danger,
                loading: _loading,
                onTap: () => _handleNav(context, ['finance.view'], 'Finance', const FinanceAdminPage()),
              )
                  .animate()
                  .fadeIn(delay: 250.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Commission',
                value: rupee.format(_commission),
                subtitle: 'Earned (est.)',
                icon: Icons.bar_chart_rounded,
                gradient: AdminGradients.primary,
                loading: _loading,
                onTap: () => _handleNav(context, ['finance.view'], 'Finance', const FinanceAdminPage()),
              )
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
            ],
          ),

          // ── Revenue Chart ──────────────────────────────────────
          const AdminSectionHeader(title: '7-Day Revenue'),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AdminColors.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AdminColors.primary.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _loading
                ? const SizedBox(
                    height: 180,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AdminColors.primary, strokeWidth: 2)))
                : SizedBox(
                    height: 180,
                    child: _revenueSpots.isEmpty
                        ? Center(
                            child: Text('No data yet',
                                style: AdminStyles.caption()))
                        : LineChart(_buildChart()),
                  ),
          ).animate().fadeIn(delay: 350.ms),

          // ── Live Activity Feed ─────────────────────────────────
          const AdminSectionHeader(title: 'Recent Orders'),
          if (_loading)
            ..._skeletonList()
          else if (_recentActivity.isEmpty)
            const AdminEmptyState(
              icon: Icons.receipt_long_rounded,
              message: 'No orders yet',
            )
          else
            ..._recentActivity.asMap().entries.map((e) {
              final i = e.key;
              final o = e.value;
              final status = (o['status'] ?? 'placed') as String;
              final amount =
                  (o['grand_total_collected'] as num?)?.toDouble() ?? 0;
              final time = o['created_at'] != null
                  ? DateFormat('dd MMM, hh:mm a').format(
                      DateTime.parse(o['created_at'].toString()).toLocal())
                  : '';

              final (color, label) = switch (status) {
                'delivered' => (AdminColors.success, 'Delivered'),
                'cancelled' => (AdminColors.danger, 'Cancelled'),
                'pending' || 'placed' => (AdminColors.warning, 'Pending'),
                _ => (AdminColors.info, status.toUpperCase()),
              };

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: AdminDecorations.glassCard(),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.receipt_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Order #${o['id'].toString().substring(0, 8).toUpperCase()}',
                            style: AdminStyles.body(size: 13)),
                        Text(time, style: AdminStyles.caption()),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${amount.toStringAsFixed(0)}',
                          style: AdminStyles.body(
                              size: 13, color: AdminColors.success)),
                      const SizedBox(height: 4),
                      AdminBadge(label: label, color: color),
                    ],
                  ),
                ]),
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 400 + i * 50))
                  .slideY(begin: 0.1);
            }),
        ],
      ),
    );
  }

  LineChartData _buildChart() {
    final maxY = _revenueSpots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    final double topY = maxY > 0 ? maxY * 1.3 : 100;

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => const Color(0xFF6C2BD9),
          tooltipRoundedRadius: 12,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final val = spot.y;
              return LineTooltipItem(
                '₹${val.toStringAsFixed(0)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 100,
        getDrawingHorizontalLine: (value) => FlLine(
          color: Colors.white.withValues(alpha: 0.05),
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 46,
            getTitlesWidget: (v, _) {
              final dayIndex = 6 - v.toInt();
              final day = DateTime.now().subtract(Duration(days: dayIndex));
              final isToday = dayIndex == 0;

              return Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('EEE').format(day),
                      style: TextStyle(
                        color: isToday ? Colors.white : AdminColors.textSecondary,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AdminColors.primary,
                          shape: BoxShape.circle,
                        ),
                      )
                  ],
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minY: 0,
      maxY: topY,
      lineBarsData: [
        LineChartBarData(
          spots: _revenueSpots,
          isCurved: true,
          curveSmoothness: 0.4,
          gradient: AdminGradients.primary,
          barWidth: 4,
          isStrokeCapRound: true,
          shadow: Shadow(
            color: AdminColors.primary.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final isToday = index == 6; // last spot (today)
              return FlDotCirclePainter(
                radius: isToday ? 6 : 4,
                color: isToday ? AdminColors.primary : AdminColors.surface,
                strokeColor: isToday ? Colors.white : AdminColors.primary,
                strokeWidth: isToday ? 3 : 2,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AdminColors.primary.withValues(alpha: 0.35),
                AdminColors.primaryEnd.withValues(alpha: 0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _skeletonList() {
    return List.generate(
      5,
      (i) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AdminDecorations.glassCard(),
        child: const Row(children: [
          SkeletonBox(width: 38, height: 38, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 120, height: 13),
              SizedBox(height: 6),
              SkeletonBox(width: 80, height: 11),
            ]),
          ),
          SkeletonBox(width: 55, height: 24, radius: 20),
        ]),
      )
          .animate()
          .shimmer(duration: 1500.ms, delay: Duration(milliseconds: i * 100)),
    );
  }
}
