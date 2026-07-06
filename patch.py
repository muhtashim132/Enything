import sys
import re

def patch_overview():
    with open('lib/pages/admin/modules/overview_admin_page.dart', 'r', encoding='utf-8') as f:
        content = f.read()

    pattern = r'  Future<void> _loadData\(\) async \{.*?if \(mounted\) setState\(\(\) => _loading = false\);\n  \}'
    replacement = """  Future<void> _loadData() async {
    try {
      final res = await _db.rpc('admin_get_overview_stats');
      if (res != null) {
        _totalOrders = res['total_orders'] as int;
        _totalRevenue = (res['total_revenue'] as num).toDouble();
        _totalUsers = res['total_users'] as int;
        _pendingKyc = res['pending_kyc'] as int;
        _pendingWithdrawals = res['pending_withdrawals'] as int;
        
        // Platform commission (dynamic based on config)
        _commission = _totalRevenue * (PlatformConfigProvider.instance?.commissionRate ?? 0.05);

        final spotsRaw = res['revenue_spots'] as List;
        _revenueSpots = spotsRaw.asMap().entries.map((e) {
          final i = e.key;
          final rev = (e.value['revenue'] as num).toDouble();
          return FlSpot(i.toDouble(), rev);
        }).toList();
      }

      // Recent activity — last 10 orders
      final activity = await _db
          .from('orders')
          .select('id, created_at, status, grand_total_collected')
          .order('created_at', ascending: false)
          .limit(10);
      _recentActivity = List<Map<String, dynamic>>.from(activity);
    } catch (e) {
      debugPrint('Overview load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }"""
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    with open('lib/pages/admin/modules/overview_admin_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)

def patch_analytics():
    with open('lib/pages/admin/modules/analytics_admin_page.dart', 'r', encoding='utf-8') as f:
        content = f.read()

    pattern = r'  Future<void> _loadAnalytics\(\) async \{.*?if \(mounted\) setState\(\(\) => _loading = false\);\n  \}'
    replacement = """  Future<void> _loadAnalytics() async {
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
    if (mounted) setState(() => _loading = false);
  }"""
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    with open('lib/pages/admin/modules/analytics_admin_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)

def patch_finance():
    with open('lib/pages/admin/modules/finance_admin_page.dart', 'r', encoding='utf-8') as f:
        content = f.read()

    pattern = r'  Future<void> _fetch\(\) async \{.*?if \(mounted\) setState\(\(\) => _loading = false\);\n  \}'
    replacement = """  Future<void> _fetch() async {
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
  }"""
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)

    pattern2 = r'  Future<void> _loadGstData\(\) async \{.*?if \(mounted\) setState\(\(\) => _loading = false\);\n    \} catch \(e\) \{.*?if \(mounted\) setState\(\(\) => _loading = false\);\n    \}\n  \}'
    replacement2 = """  Future<void> _loadGstData() async {
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
    } catch (e) {
      debugPrint('GstStatement load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }"""
    content = re.sub(pattern2, replacement2, content, flags=re.DOTALL)

    with open('lib/pages/admin/modules/finance_admin_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)

def patch_badges():
    with open('lib/pages/admin/admin_dashboard_page.dart', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Replace the inefficient query
    pattern = r"final unreadTickets = await supabase\.from\('support_tickets'\)\.select\('id'\)\.eq\('status', 'open'\);"
    replacement = "final unreadTickets = await supabase.from('support_tickets').select('id', const FetchOptions(count: CountOption.exact)).eq('status', 'open');"
    content = content.replace(pattern, replacement)

    # Note: _badges['support'] = unreadTickets.length; needs to be updated because unreadTickets is now just a list but it might be empty if we just get count. Wait, count option returns the count in the response!
    # Let's just fix it completely using regex:
    
    pattern2 = r"final unreadTickets = await supabase\.from\('support_tickets'\)\.select\('id'\)\.eq\('status', 'open'\);\n\s*_badges\['support'\] = unreadTickets\.length;"
    replacement2 = """final unreadRes = await supabase.from('support_tickets').select('id', const FetchOptions(count: CountOption.exact)).eq('status', 'open');
      _badges['support'] = unreadRes.count ?? 0;"""
    content = re.sub(pattern2, replacement2, content)
    
    with open('lib/pages/admin/admin_dashboard_page.dart', 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == '__main__':
    patch_overview()
    patch_analytics()
    patch_finance()
    patch_badges()
