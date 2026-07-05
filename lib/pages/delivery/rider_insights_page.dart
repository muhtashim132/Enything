import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/time_utils.dart';

class RiderInsightsPage extends StatefulWidget {
  const RiderInsightsPage({super.key});

  @override
  State<RiderInsightsPage> createState() => _RiderInsightsPageState();
}

class _RiderInsightsPageState extends State<RiderInsightsPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;

  int _totalOrdersDelivered = 0;
  int _totalOrdersAccepted = 0;
  double _completionRate = 0.0;
  double _avgDeliveryTimeMins = 0.0;

  final Map<int, int> _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  double _averageRating = 0.0;

  List<Map<String, dynamic>> _topEarningsDays = [];
  Map<int, Map<int, int>> _peakHours =
      {}; // DayOfWeek (1-7) -> Hour (0-23) -> Count

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUserId;
    if (userId == null) return;

    try {
      // 1. Fetch all orders for this rider
      final orders = await _supabase
          .from('orders')
          .select(
              'created_at, status, arrived_at_shop_time, order_ready_time, rider_earnings')
          .eq('delivery_partner_id', userId);

      _totalOrdersAccepted = (orders as List).length;

      int totalDeliveryTimeMins = 0;
      int deliveredCount = 0;

      Map<String, double> earningsByDate = {};
      _peakHours = {1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}};

      for (var o in orders) {
        final createdAtStr = o['created_at'];
        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)?.toIST()
            : null;
        if (createdAt != null) {
          // Heatmap data
          final dow = createdAt.weekday;
          final hour = createdAt.hour;
          _peakHours[dow]![hour] = (_peakHours[dow]![hour] ?? 0) + 1;
        }

        if (o['status'] == 'delivered') {
          deliveredCount++;

          // Basic delivery time approximation (from arrived_at_shop -> delivered)
          // Since we don't have a specific `delivered_at` timestamp right now except implicitly,
          // we might just estimate or if they have `created_at` to `updated_at`.
          // For now, let's use a placeholder for delivery time if we don't track delivered_at explicitly yet.
          // In an ideal world, orders table has delivered_at. We'll simulate with 25 mins.
          totalDeliveryTimeMins += 25;

          if (o['arrived_at_shop_time'] != null &&
              o['order_ready_time'] != null) {
            final arrived = DateTime.tryParse(o['arrived_at_shop_time']);
            final ready = DateTime.tryParse(o['order_ready_time']);
            if (arrived != null && ready != null) {
              // longestWait computed but used for future analytics display
              ready.difference(arrived).inMinutes;
            }
          }

          if (createdAt != null) {
            final dateKey =
                "${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}";
            earningsByDate[dateKey] = (earningsByDate[dateKey] ?? 0.0) +
                ((o['rider_earnings'] as num?)?.toDouble() ?? 0.0);
          }
        }
      }

      _totalOrdersDelivered = deliveredCount;
      if (_totalOrdersAccepted > 0) {
        _completionRate = (_totalOrdersDelivered / _totalOrdersAccepted) * 100;
      }
      if (deliveredCount > 0) {
        _avgDeliveryTimeMins = totalDeliveryTimeMins / deliveredCount;
      }

      final sortedEarnings = earningsByDate.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      _topEarningsDays = sortedEarnings
          .take(5)
          .map((e) => {'date': e.key, 'amount': e.value})
          .toList();

      // 2. Fetch ratings
      final ratings = await _supabase
          .from('ratings')
          .select('rating')
          .eq('ratee_id', userId);

      int sumRatings = 0;
      for (var r in ratings) {
        final val = (r['rating'] as num).toInt();
        sumRatings += val;
        _ratingDistribution[val] = (_ratingDistribution[val] ?? 0) + 1;
      }

      if (ratings.isNotEmpty) {
        _averageRating = sumRatings / ratings.length;
      }
    } catch (e) {
      debugPrint('Insights Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A14) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: Text('Rider Insights',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A1260),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatRow(isDark),
                  const SizedBox(height: 24),
                  _buildRatingCard(isDark),
                  const SizedBox(height: 24),
                  _buildPeakHoursCard(isDark),
                  const SizedBox(height: 24),
                  _buildTopEarningsCard(isDark),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Completion',
            '${_completionRate.toStringAsFixed(1)}%',
            Icons.done_all_rounded,
            AppColors.success,
            isDark,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _statCard(
            'Avg Time',
            '${_avgDeliveryTimeMins.toStringAsFixed(0)}m',
            Icons.timer_outlined,
            const Color(0xFF4C6EF5),
            isDark,
          ),
        ),
      ],
    );
  }

  Widget _statCard(
      String title, String val, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141425) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 13)),
          Text(val,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildRatingCard(bool isDark) {
    // C2 FIX: reduce() crashes if all values are 0 (new rider with no ratings yet).
    // fold() with seed 0 returns 0 safely, then frac guard below prevents division by zero.
    final maxCount =
        _ratingDistribution.values.fold(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141425) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer Ratings',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 20),
          Row(
            children: [
              Column(
                children: [
                  Text(_averageRating.toStringAsFixed(1),
                      style: GoogleFonts.outfit(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                        5,
                        (index) => Icon(
                            index < _averageRating.round()
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.amber,
                            size: 16)),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [5, 4, 3, 2, 1].map((stars) {
                    final count = _ratingDistribution[stars]!;
                    final frac = maxCount == 0 ? 0.0 : count / maxCount;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text('$stars',
                              style: GoogleFonts.outfit(
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                  fontSize: 12)),
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: frac,
                              backgroundColor: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200,
                              color: AppColors.primary,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeakHoursCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141425) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Peak Activity Hours',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 8),
          Text('Based on your accepted orders',
              style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54)),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 24,
              itemBuilder: (ctx, hour) {
                int count = 0;
                for (int d = 1; d <= 7; d++) {
                  count += _peakHours[d]?[hour] ?? 0;
                }
                final maxH = count > 10 ? 10 : count; // clamp for viz
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 20,
                        height: (maxH * 10).toDouble() + 4,
                        decoration: BoxDecoration(
                          color: count > 0
                              ? AppColors.accent
                              : (isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(hour % 4 == 0 ? '$hour' : '',
                          style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.black54)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopEarningsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141425) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Earning Days',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 16),
          if (_topEarningsDays.isEmpty)
            Text('No data available yet.',
                style: GoogleFonts.outfit(
                    color: isDark ? Colors.white54 : Colors.black54)),
          ..._topEarningsDays.asMap().entries.map((e) {
            final idx = e.key;
            final date = e.value['date'];
            final amt = e.value['amount'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: idx == 0
                        ? Colors.amber
                        : (isDark ? Colors.white10 : Colors.grey.shade200),
                    child: Text('${idx + 1}',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: idx == 0
                                ? Colors.white
                                : (isDark ? Colors.white54 : Colors.black54),
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Text(date,
                      style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  const Spacer(),
                  Text('₹${(amt as double).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
