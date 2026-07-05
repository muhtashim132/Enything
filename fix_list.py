import re

with open('lib/pages/admin/modules/overview_admin_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()

builder_code = """
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == 0) {
                    return GridView.count(
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
                        ).animate().fadeIn(delay: 50.ms).scale(begin: const Offset(0.95, 0.95)),
                        AdminKpiCard(
                          title: 'Total Orders',
                          value: fmt.format(_totalOrders),
                          subtitle: 'All time',
                          icon: Icons.shopping_bag_rounded,
                          gradient: AdminGradients.info,
                          loading: _loading,
                          onTap: () => _handleNav(context, ['orders.view'], 'Orders', const OrdersAdminPage()),
                        ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95)),
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
                        ).animate().fadeIn(delay: 150.ms).scale(begin: const Offset(0.95, 0.95)),
                        AdminKpiCard(
                          title: 'Pending KYC',
                          value: _pendingKyc.toString(),
                          subtitle: 'Awaiting review',
                          icon: Icons.pending_actions_rounded,
                          gradient: AdminGradients.warning,
                          loading: _loading,
                          onTap: () => _handleNav(context, ['sellers.approve', 'riders.approve'], 'KYC Verification', const KycReviewPage()),
                        ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.95, 0.95)),
                        AdminKpiCard(
                          title: 'Withdrawals',
                          value: _pendingWithdrawals.toString(),
                          subtitle: 'Pending approval',
                          icon: Icons.account_balance_wallet_rounded,
                          gradient: AdminGradients.danger,
                          loading: _loading,
                          onTap: () => _handleNav(context, ['finance.view'], 'Finance', const FinanceAdminPage(initialTabIndex: 1)),
                        ).animate().fadeIn(delay: 250.ms).scale(begin: const Offset(0.95, 0.95)),
                        AdminKpiCard(
                          title: 'Commission',
                          value: rupee.format(_commission),
                          subtitle: 'Earned (est.)',
                          icon: Icons.bar_chart_rounded,
                          gradient: AdminGradients.primary,
                          loading: _loading,
                          onTap: () => _handleNav(context, ['finance.view'], 'Finance', const FinanceAdminPage()),
                        ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.95, 0.95)),
                      ],
                    );
                  }
                  
                  if (index == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ]
                    );
                  }
                  
                  if (index == 2) {
                    return const AdminSectionHeader(title: 'Recent Orders');
                  }
                  
                  final listIndex = index - 3;
                  
                  if (_loading) {
                    return _skeletonList()[listIndex];
                  }
                  
                  if (_recentActivity.isEmpty) {
                    return const AdminEmptyState(
                      icon: Icons.receipt_long_rounded,
                      message: 'No orders yet',
                    );
                  }
                  
                  final o = _recentActivity[listIndex];
                  final status = (o['status'] ?? 'placed') as String;
                  final amount =
                      (o['grand_total_collected'] as num?)?.toDouble() ?? 0;
                  final time = o['created_at'] != null
                      ? DateFormat('dd MMM, hh:mm a').format(
                          DateTime.parse(o['created_at'].toString()).toIST())
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
                  ).animate().fadeIn(delay: Duration(milliseconds: 400 + listIndex * 50)).slideY(begin: 0.1);
                },
                childCount: 3 + (_loading ? 5 : (_recentActivity.isEmpty ? 1 : _recentActivity.length)),
              ),
            ),
          ),
        ],
      ),"""

pattern = r"      child: ListView\([\s\S]*?\]\),\n        \],\n      \),"

new_code = re.sub(pattern, builder_code, code)

with open('lib/pages/admin/modules/overview_admin_page.dart', 'w', encoding='utf-8') as f:
    f.write(new_code)
