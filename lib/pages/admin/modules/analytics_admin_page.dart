import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../theme/admin_theme.dart';

class AnalyticsAdminPage extends StatefulWidget {
  const AnalyticsAdminPage({super.key});

  @override
  State<AnalyticsAdminPage> createState() => _AnalyticsAdminPageState();
}

class _AnalyticsAdminPageState extends State<AnalyticsAdminPage> {
  final _db = Supabase.instance.client;
  bool _loading = true;

  // Derived stats
  int _totalOrders = 0;
  int _deliveredOrders = 0;
  int _cancelledOrders = 0;
  double _avgOrderValue = 0;
  Map<String, int> _ordersByStatus = {};
  List<FlSpot> _hourlySpots = [];
  List<Map<String, dynamic>> _topSellers = [];
  String _peakHour = '—';
  double _churnRisk = 0;
  int _newUsersToday = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      // Orders
      final orders = await _db.from('orders').select(
          'status, grand_total_collected, total_amount, created_at, shop_id');

      _totalOrders = orders.length;
      _deliveredOrders = orders.where((o) => o['status'] == 'delivered').length;
      _cancelledOrders = orders.where((o) => o['status'] == 'cancelled').length;

      // Average order value
      final totals = orders
          .map((o) =>
              (o['grand_total_collected'] as num?)?.toDouble() ??
              (o['total_amount'] as num?)?.toDouble() ??
              0.0)
          .toList();
      _avgOrderValue = totals.isEmpty
          ? 0
          : totals.reduce((a, b) => a + b) / totals.length;

      // Orders by status
      final statusMap = <String, int>{};
      for (final o in orders) {
        final s = (o['status'] ?? 'unknown') as String;
        statusMap[s] = (statusMap[s] ?? 0) + 1;
      }
      _ordersByStatus = statusMap;

      // Hourly distribution (last 7 days)
      final now = DateTime.now();
      final hourMap = <int, int>{};
      for (final o in orders) {
        if (o['created_at'] == null) continue;
        final d = DateTime.tryParse(o['created_at'].toString());
        if (d != null && now.difference(d).inDays <= 7) {
          hourMap[d.hour] = (hourMap[d.hour] ?? 0) + 1;
        }
      }
      _hourlySpots = List.generate(24, (h) {
        return FlSpot(h.toDouble(), (hourMap[h] ?? 0).toDouble());
      });

      // Peak hour
      if (hourMap.isNotEmpty) {
        final peak = hourMap.entries.reduce((a, b) => a.value > b.value ? a : b);
        final h = peak.key;
        final suffix = h >= 12 ? 'PM' : 'AM';
        final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        _peakHour = '$display:00 $suffix';
      }

      // Top sellers by order count
      final sellerCount = <String, int>{};
      for (final o in orders) {
        final s = o['shop_id']?.toString();
        if (s != null) sellerCount[s] = (sellerCount[s] ?? 0) + 1;
      }
      final topIds = (sellerCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .toList();

      if (topIds.isNotEmpty) {
        final shops = await _db
            .from('shops')
            .select('id, shop_name')
            .inFilter('id', topIds.map((e) => e.key).toList());
        _topSellers = topIds.map((e) {
          final shop = (shops as List).firstWhere(
              (s) => s['id'].toString() == e.key,
              orElse: () => {'shop_name': 'Unknown'});
          return {'name': shop['shop_name'] ?? 'Unknown', 'orders': e.value};
        }).toList();
      }

      // Churn risk: cancelled / total (simple heuristic)
      _churnRisk = _totalOrders > 0 ? (_cancelledOrders / _totalOrders) * 100 : 0;

      // New users today
      final today = DateFormat('yyyy-MM-dd').format(now);
      final todayUsers = await _db
          .from('profiles')
          .select('id')
          .gte('created_at', '${today}T00:00:00');
      _newUsersToday = (todayUsers as List).length;
    } catch (e) {
      debugPrint('Analytics error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _loadAnalytics();
      },
      color: AdminColors.primary,
      backgroundColor: AdminColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── AI Insight Banner ──────────────────────────────
          _AiInsightBanner(
            peakHour: _peakHour,
            churnRisk: _churnRisk,
            loading: _loading,
          ).animate().fadeIn(delay: 50.ms),

          const AdminSectionHeader(title: 'Platform Performance'),

          // ── Stat Cards ─────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [
              AdminKpiCard(
                title: 'Total Orders',
                value: _totalOrders.toString(),
                icon: Icons.receipt_long_rounded,
                gradient: AdminGradients.primary,
                loading: _loading,
              ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Delivery Rate',
                value: _totalOrders > 0
                    ? '${(_deliveredOrders / _totalOrders * 100).toStringAsFixed(1)}%'
                    : '—',
                subtitle: '$_deliveredOrders delivered',
                icon: Icons.check_circle_rounded,
                gradient: AdminGradients.success,
                loading: _loading,
              ).animate().fadeIn(delay: 150.ms).scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'Avg Order Value',
                value: _loading
                    ? '—'
                    : '₹${_avgOrderValue.toStringAsFixed(0)}',
                icon: Icons.bar_chart_rounded,
                gradient: AdminGradients.info,
                loading: _loading,
              ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.95, 0.95)),
              AdminKpiCard(
                title: 'New Users Today',
                value: _loading ? '—' : _newUsersToday.toString(),
                icon: Icons.person_add_rounded,
                gradient: AdminGradients.warning,
                loading: _loading,
              ).animate().fadeIn(delay: 250.ms).scale(begin: const Offset(0.95, 0.95)),
            ],
          ),

          // ── Hourly Orders Chart ────────────────────────────
          const AdminSectionHeader(title: 'Orders by Hour (Last 7 Days)'),
          AdminCard(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            child: _loading
                ? const SizedBox(
                    height: 150,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AdminColors.primary, strokeWidth: 2)))
                : SizedBox(
                    height: 150,
                    child: BarChart(_buildHourlyChart()),
                  ),
          ).animate().fadeIn(delay: 300.ms),

          // ── Order Status Breakdown ─────────────────────────
          const AdminSectionHeader(title: 'Order Status Breakdown'),
          AdminCard(
            child: _loading
                ? const _StatusSkeleton()
                : Column(
                    children: _ordersByStatus.entries.map((e) {
                      final (color, label) = _statusStyle(e.key);
                      final pct = _totalOrders > 0
                          ? e.value / _totalOrders
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              AdminBadge(label: label, color: color),
                              const Spacer(),
                              Text('${e.value}  (${(pct * 100).toStringAsFixed(1)}%)',
                                  style: AdminStyles.caption()),
                            ]),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: color.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation(color),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ).animate().fadeIn(delay: 350.ms),

          // ── Top Sellers ────────────────────────────────────
          if (_topSellers.isNotEmpty || _loading) ...[
            const AdminSectionHeader(title: 'Top Performing Sellers'),
            AdminCard(
              child: _loading
                  ? const _StatusSkeleton()
                  : Column(
                      children: _topSellers.asMap().entries.map((e) {
                        final i = e.key;
                        final s = e.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                gradient: AdminGradients.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: AdminStyles.caption(
                                        color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(s['name'] as String,
                                  style: AdminStyles.body(size: 13)),
                            ),
                            AdminBadge(
                              label: '${s['orders']} orders',
                              color: AdminColors.primary,
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
            ).animate().fadeIn(delay: 400.ms),
          ],

          // ── AI Fraud & Recommendations ─────────────────────
          const AdminSectionHeader(title: 'AI Recommendations'),
          ..._buildAiCards().asMap().entries.map((e) => e.value
              .animate()
              .fadeIn(delay: Duration(milliseconds: 450 + e.key * 60))
              .slideX(begin: -0.05)),
        ],
      ),
    );
  }

  BarChartData _buildHourlyChart() {
    final maxY = _hourlySpots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY > 0 ? maxY + 1 : 5,
      barTouchData: BarTouchData(enabled: true),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 6,
            getTitlesWidget: (v, _) {
              final h = v.toInt();
              final label = h == 0
                  ? '12AM'
                  : h == 12
                      ? '12PM'
                      : h > 12
                          ? '${h - 12}PM'
                          : '${h}AM';
              return Text(label, style: AdminStyles.label());
            },
          ),
        ),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barGroups: _hourlySpots.map((s) {
        final isPeak = s.y == _hourlySpots.fold<double>(0, (m, sp) => sp.y > m ? sp.y : m);
        return BarChartGroupData(
          x: s.x.toInt(),
          barRods: [
            BarChartRodData(
              toY: s.y,
              gradient: isPeak ? AdminGradients.primary : LinearGradient(
                colors: [
                  AdminColors.primary.withOpacity(0.4),
                  AdminColors.primaryEnd.withOpacity(0.4),
                ],
              ),
              width: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        );
      }).toList(),
    );
  }

  List<Widget> _buildAiCards() => [
        _AiCard(
          icon: Icons.schedule_rounded,
          color: AdminColors.primary,
          title: 'Peak Hour Detected',
          body: 'Highest order volume observed at $_peakHour. '
              'Consider scheduling more riders online 30 mins before.',
        ),
        _AiCard(
          icon: Icons.warning_amber_rounded,
          color: AdminColors.warning,
          title: 'Churn Risk: ${_churnRisk.toStringAsFixed(1)}%',
          body: _churnRisk > 20
              ? 'High cancellation rate detected. Consider proactive push notifications '
                  'to customers who placed but cancelled orders recently.'
              : 'Cancellation rate is healthy. Monitor weekly to catch early warning signs.',
        ),
        const _AiCard(
          icon: Icons.security_rounded,
          color: AdminColors.danger,
          title: 'Fraud Detection',
          body: 'Connect Razorpay Fraud Shield for real-time payment anomaly detection. '
              'Currently running in manual review mode.',
        ),
        const _AiCard(
          icon: Icons.rocket_launch_rounded,
          color: AdminColors.success,
          title: 'Recommended Promotion',
          body: 'Launch a "Free Delivery Weekend" campaign targeting inactive users '
              'from the last 14 days to re-engage churned customers.',
        ),
      ];

  (Color, String) _statusStyle(String s) => switch (s) {
        'delivered' => (AdminColors.success, 'Delivered'),
        'cancelled' => (AdminColors.danger, 'Cancelled'),
        'preparing' || 'accepted' => (AdminColors.info, 'Preparing'),
        'out_for_delivery' || 'picked_up' => (AdminColors.info, 'On the Way'),
        _ => (AdminColors.warning, s.replaceAll('_', ' ').toUpperCase()),
      };
}

// ── AI Insight Banner ─────────────────────────────────────────────
class _AiInsightBanner extends StatelessWidget {
  final String peakHour;
  final double churnRisk;
  final bool loading;

  const _AiInsightBanner({
    required this.peakHour,
    required this.churnRisk,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AdminColors.primary.withOpacity(0.25),
            AdminColors.primaryEnd.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.primary.withOpacity(0.35)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: AdminGradients.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Insights Active',
                style: AdminStyles.body(
                    size: 13, color: AdminColors.textPrimary)),
            const SizedBox(height: 3),
            Text(
              loading
                  ? 'Crunching your platform data...'
                  : 'Peak: $peakHour  •  Churn risk: ${churnRisk.toStringAsFixed(1)}%  •  Fraud: Manual',
              style: AdminStyles.caption(),
            ),
          ]),
        ),
        const AdminBadge(label: 'LIVE', color: AdminColors.success),
      ]),
    );
  }
}

// ── AI Recommendation Card ────────────────────────────────────────
class _AiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _AiCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AdminDecorations.glassCard(borderColor: color.withOpacity(0.25)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AdminStyles.body(size: 13)),
            const SizedBox(height: 4),
            Text(body,
                style: AdminStyles.caption(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class _StatusSkeleton extends StatelessWidget {
  const _StatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SkeletonBox(width: 80, height: 20, radius: 20),
            Spacer(),
            SkeletonBox(width: 50, height: 13),
          ]),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 6, radius: 4),
        ]),
      )).toList(),
    );
  }
}
