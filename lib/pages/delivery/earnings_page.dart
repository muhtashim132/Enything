import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/time_utils.dart';

class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  double _todayEarnings = 0;
  double _totalEarnings = 0;
  int _totalDeliveries = 0;
  double _averageRating = 0.0;
  List<Map<String, dynamic>> _recentDeliveries = [];
  // 7-day earnings: index 0 = 6 days ago, index 6 = today
  List<double> _weeklyEarnings = List.filled(7, 0.0);

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    final auth = context.read<AuthProvider>();
    try {
      // A1: Use the highly optimized get_rider_stats RPC to prevent Payload DDOS
      final stats = await _supabase.rpc('get_rider_stats', params: {'p_rider_id': auth.currentUserId ?? ''});
      
      double today = 0, total = 0;
      int deliveriesCount = 0;
      List<double> weeklyMap = List.filled(7, 0.0);
      
      if (stats != null) {
        today = (stats['today_earnings'] as num?)?.toDouble() ?? 0.0;
        total = (stats['total_earnings'] as num?)?.toDouble() ?? 0.0;
        deliveriesCount = (stats['total_deliveries'] as num?)?.toInt() ?? 0;
        
        final rawWeekly = stats['weekly_earnings'] as List<dynamic>?;
        if (rawWeekly != null && rawWeekly.length == 7) {
          weeklyMap = rawWeekly.map((e) => (e as num).toDouble()).toList();
        }
      }

      // Fetch only the 20 most recent deliveries for the list view to prevent N+1 pixel overloading
      final recentDeliveriesRaw = await _supabase
          .from('orders')
          .select()
          .eq('delivery_partner_id', auth.currentUserId ?? '')
          .eq('status', 'delivered')
          .order('created_at', ascending: false)
          .limit(20);

      final deliveries = recentDeliveriesRaw as List;


      double avgRating = 0.0;
      try {
        final profile = await _supabase
            .from('profiles')
            .select('average_rating')
            .eq('id', auth.currentUserId ?? '')
            .maybeSingle();
        if (profile != null && profile['average_rating'] != null) {
          avgRating = (profile['average_rating'] as num).toDouble();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _todayEarnings = today;
          _totalEarnings = total;
          _totalDeliveries = deliveriesCount;
          _weeklyEarnings = weeklyMap;
          _averageRating = avgRating;
          _recentDeliveries = deliveries.take(20).map((d) {
            return {
              'id': d['id'],
              'amount': ((d['rider_earnings'] ?? d['delivery_charges'] ?? 0.0) as num).toDouble() + ((d['wait_time_penalty'] ?? 0.0) as num).toDouble(),
              'date': d['created_at'],
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('EarningsPage._loadEarnings error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        title: Text('Earnings',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEarnings,
              child: CustomScrollView(
                slivers: [
                  // ── Hero Earnings Card ─────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFF071D6B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'TOTAL EARNINGS',
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${_totalEarnings.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem(
                                      'Today', '₹${_todayEarnings.toInt()}'),
                                  Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white24),
                                  _buildStatItem('Orders', '$_totalDeliveries'),
                                  Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white24),
                                  _buildStatItem('Rating',
                                      '${_averageRating > 0 ? _averageRating.toStringAsFixed(1) : 'New'} ⭐'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Quick Actions ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.account_balance_wallet_rounded,
                              label: 'Withdraw',
                              color: AppColors.secondary,
                              onTap: () {
                                Navigator.pushNamed(
                                    context, AppRoutes.riderWithdrawals);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.analytics_rounded,
                              label: 'Insights',
                              color: Colors.blue,
                              onTap: () {
                                Navigator.pushNamed(
                                    context, AppRoutes.riderInsights);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  SliverToBoxAdapter(
                    child: _buildWeeklyChart(),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),

                  // ── Recent Activity ────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Activity',
                            style: GoogleFonts.outfit(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.riderOrderHistory),
                            child: Text(
                              'View all',
                              style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  _recentDeliveries.isEmpty
                      ? const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Text('No recent deliveries found.'),
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = _recentDeliveries[index];
                              final date =
                                  DateTime.tryParse(item['date'] ?? '')
                                      ?.toIST() ??
                                  DateTime.now();
                              return Container(
                                margin:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.02),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.05),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                          Icons.delivery_dining_rounded,
                                          color: AppColors.primary),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Order #${item['id'].toString().substring(0, 8)}',
                                            style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15),
                                          ),
                                          Text(
                                            DateFormat('MMM dd, hh:mm a')
                                                .format(date),
                                            style: GoogleFonts.outfit(
                                                color: AppColors.textSecondary,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '+₹${item['amount'].toStringAsFixed(0)}',
                                      style: GoogleFonts.outfit(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            childCount: _recentDeliveries.length,
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Weekly Bar Chart ────────────────────────────────────────────────────────
  Widget _buildWeeklyChart() {
    final maxY = _weeklyEarnings.reduce((a, b) => a > b ? a : b);
    final chartMax = maxY < 50 ? 200.0 : (maxY * 1.25).ceilToDouble();

    final dayLabels = List.generate(7, (i) {
      final dt = DateTime.now().subtract(Duration(days: 6 - i));
      return DateFormat('E').format(dt.toIST()); // Mon, Tue…
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last 7 Days',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '₹${_weeklyEarnings.reduce((a, b) => a + b).toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: chartMax,
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMax / 4,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade100,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i < 0 || i >= dayLabels.length) {
                            return const SizedBox.shrink();
                          }
                          final isToday = i == 6;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dayLabels[i],
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isToday
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                  ),
                  barGroups: List.generate(7, (i) {
                    final earning = _weeklyEarnings[i];
                    final isToday = i == 6;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: earning,
                          width: 28,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          gradient: LinearGradient(
                            colors: isToday
                                ? [AppColors.primary, const Color(0xFF071D6B)]
                                : [
                                    AppColors.primary.withValues(alpha: 0.4),
                                    AppColors.primary.withValues(alpha: 0.2)
                                  ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ],
                    );
                  }),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.primary,
                      getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                        '₹${rod.toY.toStringAsFixed(0)}',
                        GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
