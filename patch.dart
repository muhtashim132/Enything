import 'dart:io';

void main() {
  final file = File('lib/pages/admin/modules/analytics_admin_page.dart');
  var content = file.readAsStringSync();
  
  const startStr = '  Future<void> _loadAnalytics() async {';
  const endStr = '    if (mounted) setState(() => _loading = false);\n  }';
  
  final startIndex = content.indexOf(startStr);
  final endIndex = content.indexOf(endStr, startIndex);
  
  if (startIndex != -1 && endIndex != -1) {
    const replacement = r'''  Future<void> _loadAnalytics() async {
    try {
      final res = await _db.rpc('admin_get_analytics_stats');
      if (res != null) {
        _totalOrders = res['total_orders'] as int;
        _deliveredOrders = res['delivered_orders'] as int;
        _cancelledOrders = res['cancelled_orders'] as int;
        _avgOrderValue = (res['avg_order_value'] as num).toDouble();
        
        final obStatus = res['orders_by_status'] as Map<String, dynamic>;
        _ordersByStatus = obStatus.map((k, v) => MapEntry(k, v as int));

        final hDist = res['hourly_distribution'] as Map<String, dynamic>;
        _hourlySpots = List.generate(24, (h) {
          return FlSpot(h.toDouble(), (hDist[h.toString()] as num?)?.toDouble() ?? 0.0);
        });

        // Peak hour
        if (hDist.isNotEmpty) {
          final peak = hDist.entries.reduce((a, b) => (a.value as num) > (b.value as num) ? a : b);
          final h = int.parse(peak.key);
          final suffix = h >= 12 ? 'PM' : 'AM';
          final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
          _peakHour = '$display:00 $suffix';
        } else {
          _peakHour = '—';
        }

        final tSellers = res['top_sellers'] as List;
        _topSellers = List<Map<String, dynamic>>.from(tSellers);

        final tRiders = res['top_riders'] as List;
        _topRiders = List<Map<String, dynamic>>.from(tRiders);

        _churnRisk = _totalOrders > 0 ? (_cancelledOrders / _totalOrders) * 100 : 0;
        _newUsersToday = res['new_users_today'] as int;
      }
    } catch (e) {
      debugPrint('Analytics error: $e');
    }
''';
    final before = content.substring(0, startIndex);
    final after = content.substring(endIndex); // Note: we keep the endStr
    
    file.writeAsStringSync(before + replacement + after);
    stdout.writeln('Analytics patched with index matching.');
  } else {
    stdout.writeln('Could not find start or end block in analytics.');
  }
}
