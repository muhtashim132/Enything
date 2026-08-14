import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/time_utils.dart';

class AnalyticsPage extends StatefulWidget {
  final String? initialShopId;
  const AnalyticsPage({super.key, this.initialShopId});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;
  String? _selectedShopId;
  List<Map<String, dynamic>> _shops = [];

  double _totalRevenue = 0;
  double _totalPayout = 0;
  double _totalCommission = 0;
  int _totalOrders = 0;
  int _deliveredOrders = 0;
  final List<FlSpot> _revenueSpots = [];
  List<DateTime> _last7DaysDates = [];

  @override
  void initState() {
    super.initState();
    _selectedShopId = widget.initialShopId;
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();

      final shopsResp = await _supabase
          .from('shops')
          .select('id, name')
          .eq('seller_id', auth.currentUserId ?? '');

      final shopsList = List<Map<String, dynamic>>.from(shopsResp as List);

      if (shopsList.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      String shopId = _selectedShopId ?? widget.initialShopId ?? shopsList.first['id'];
      if (!shopsList.any((s) => s['id'] == shopId)) {
        shopId = shopsList.first['id'];
      }

      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final startDate = todayDate.subtract(const Duration(days: 6));

      final orders = await _supabase
          .from('orders')
          .select()
          .eq('shop_id', shopId)
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: true);

      double total = 0;
      double payout = 0;
      double commission = 0;
      int delivered = 0;

      final Map<DateTime, double> dailyRevenue = {};
      final List<DateTime> dates = [];
      for (int i = 6; i >= 0; i--) {
        final d = todayDate.subtract(Duration(days: i));
        dailyRevenue[d] = 0.0;
        dates.add(d);
      }

      for (final order in (orders as List)) {
        final status = order['status'];
        final amount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
        final sp = (order['seller_payout'] as num?)?.toDouble() ?? 0.0;
        final zc = (order['enything_commission'] as num?)?.toDouble() ?? 0.0;

        if (status == 'delivered') {
          total += amount;
          payout += sp;
          commission += zc;
          delivered++;

          final createdAtStr = order['created_at'];
          if (createdAtStr != null) {
            final createdAt = DateTime.tryParse(createdAtStr)?.toIST() ?? now;
            final orderDate =
                DateTime(createdAt.year, createdAt.month, createdAt.day);
            if (dailyRevenue.containsKey(orderDate)) {
              dailyRevenue[orderDate] = dailyRevenue[orderDate]! + amount;
            }
          }
        }
      }

      final List<FlSpot> spots = [];
      for (int i = 0; i < dates.length; i++) {
        spots.add(FlSpot(i.toDouble(), dailyRevenue[dates[i]]!));
      }

      if (mounted) {
        setState(() {
          _shops = shopsList;
          _selectedShopId = shopId;
          _totalRevenue = total;
          _totalPayout = payout;
          _totalCommission = commission;
          _totalOrders = orders.length; // Count of all orders in last 7 days
          _deliveredOrders = delivered;
          _revenueSpots.clear();
          _revenueSpots.addAll(spots);
          _last7DaysDates = dates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Store Analytics'),
            if (_shops.isNotEmpty)
              Text(
                _shops.firstWhere((s) => s['id'] == _selectedShopId, orElse: () => _shops.first)['name'] ?? 'Store',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          if (_shops.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.store_rounded),
              tooltip: 'Switch Shop',
              initialValue: _selectedShopId,
              onSelected: (shopId) {
                setState(() {
                  _selectedShopId = shopId;
                  _isLoading = true;
                });
                _loadAnalytics();
              },
              itemBuilder: (context) => _shops.map((s) {
                final id = s['id'] as String;
                final name = s['name'] as String? ?? 'Shop';
                return PopupMenuItem<String>(
                  value: id,
                  child: Row(
                    children: [
                      Icon(
                        id == _selectedShopId ? Icons.check_circle : Icons.store_outlined,
                        color: id == _selectedShopId ? AppColors.primary : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
      body: MaxWidthContainer(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAnalytics,
                child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Stats
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            'Gross Revenue',
                            '₹${_totalRevenue.toStringAsFixed(0)}',
                            Icons.currency_rupee,
                            AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            'Net Payout',
                            '₹${_totalPayout.toStringAsFixed(0)}',
                            Icons.account_balance_wallet_outlined,
                            AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            'Platform Comm.',
                            '₹${_totalCommission.toStringAsFixed(0)}',
                            Icons.pie_chart_outline,
                            AppColors.danger,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            'Total Orders',
                            '$_totalOrders',
                            Icons.receipt_long_outlined,
                            AppColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            'Delivered',
                            '$_deliveredOrders',
                            Icons.check_circle_outline,
                            AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            'Success Rate',
                            _totalOrders > 0
                                ? '${(_deliveredOrders / _totalOrders * 100).toStringAsFixed(0)}%'
                                : '0%',
                            Icons.trending_up,
                            AppColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Chart
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Revenue Trend',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 200,
                            child: _revenueSpots.isEmpty
                                ? const Center(
                                    child: Text('No data yet',
                                        style: TextStyle(
                                            color: AppColors.textSecondary)))
                                : LineChart(
                                    LineChartData(
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (v) =>
                                            const FlLine(
                                          color: AppColors.divider,
                                          strokeWidth: 1,
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 22,
                                            getTitlesWidget: (v, meta) {
                                              final int index = v.toInt();
                                              if (index < 0 ||
                                                  index >=
                                                      _last7DaysDates.length) {
                                                return const SizedBox.shrink();
                                              }
                                              final date =
                                                  _last7DaysDates[index];
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8.0),
                                                child: Text(
                                                  '${date.day}/${date.month}',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: AppColors
                                                          .textSecondary),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        leftTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: _revenueSpots.isEmpty
                                              ? [const FlSpot(0, 0)]
                                              : _revenueSpots,
                                          isCurved: true,
                                          color: AppColors.primary,
                                          barWidth: 3,
                                          belowBarData: BarAreaData(
                                            show: true,
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                          ),
                                          dotData: FlDotData(
                                            show: true,
                                            getDotPainter:
                                                (spot, percent, bar, index) =>
                                                    FlDotCirclePainter(
                                              radius: 4,
                                              color: AppColors.primary,
                                              strokeWidth: 2,
                                              strokeColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Poppins',
              )),
          Text(title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontFamily: 'Poppins',
              )),
        ],
      ),
    );
  }
}
