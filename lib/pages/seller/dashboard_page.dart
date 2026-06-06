import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/notification_provider.dart';
import '../../config/routes.dart';
import '../../config/app_categories.dart';
import '../../widgets/common/notification_bell.dart';
import 'package:shimmer/shimmer.dart';
import '../../utils/responsive_layout.dart';
class SellerDashboardPage extends StatefulWidget {
  const SellerDashboardPage({super.key});
  @override
  State<SellerDashboardPage> createState() => _SellerDashboardPageState();
}

class _SellerDashboardPageState extends State<SellerDashboardPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _stats = {
    'total_orders': 0,
    'pending_orders': 0,
    'revenue': 0.0,
    'products': 0,
  };
  bool _isLoading = true;
  String _shopBadgeName = 'Seller';
  String _shopEmoji = '🏪';
  bool _shopIsActive = false;
  String _shopRating = '--';

  late AnimationController _bgCtrl;
  late AnimationController _entryCtrl;
  late Animation<double> _bgAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _bgCtrl =
        AnimationController(duration: const Duration(seconds: 6), vsync: this)
          ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    _entryCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));

    _loadStats();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthProvider>();
    try {
      final shopsResp = await _supabase
          .from('shops')
          .select('id, category, categories, is_active, average_rating, verification_status')
          .eq('seller_id', auth.currentUserId ?? '');

      if ((shopsResp as List).isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        _entryCtrl.forward();
        return;
      }

      final shopData = shopsResp.first;
      final verificationStatus = shopData['verification_status'];

      if (verificationStatus == 'pending') {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.sellerPendingVerification, (_) => false);
        }
        return;
      } else if (verificationStatus == null ||
          verificationStatus == 'rejected' ||
          verificationStatus == 'unverified') {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.sellerKycUpload, (_) => false);
        }
        return;
      }
      // 'approved' and 'verified' both proceed to the dashboard normally

      final shopId = shopData['id'];
      _startNotifications(shopId as String);

      final rawCat = shopData['category'] ?? 
          (shopData['categories'] != null && (shopData['categories'] as List).isNotEmpty 
              ? shopData['categories'][0] 
              : 'Other');

      final ordersResp = await _supabase
          .from('orders')
          .select()
          .eq('shop_id', shopId)
          .neq('status', 'cancelled')
          .neq('status', 'seller_rejected');

      final productsResp =
          await _supabase.from('products').select('id').eq('shop_id', shopId);

      final pending =
          (ordersResp as List).where((o) =>
              o['status'] == 'pending' ||
              o['status'] == 'awaiting_acceptance').length;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todaysEarning = ordersResp.fold<double>(
        0,
        (s, o) {
          if (o['status'] != 'delivered') return s;
          final createdAt = DateTime.tryParse(o['created_at'] ?? '')?.toLocal();
          if (createdAt != null && (createdAt.isAfter(todayStart) || createdAt.isAtSameMomentAs(todayStart))) {
            return s + ((o['seller_payout'] as num?)?.toDouble() ?? 0.0);
          }
          return s;
        },
      );

      if (mounted) {
        setState(() {
          _shopBadgeName = rawCat == 'Other' ? 'Store' : rawCat;
          final catInfo = AppCategories.all.firstWhere(
            (c) => c['name'] == rawCat,
            orElse: () => {'name': rawCat, 'emoji': '🏪'},
          );
          _shopEmoji = catInfo['emoji']!;

          _stats = {
            'total_orders': ordersResp.length,
            'pending_orders': pending,
            'todays_earning': todaysEarning,
            'products': (productsResp as List).length,
          };
          _shopIsActive = shopData['is_active'] ?? false;
          final rawRating = shopData['average_rating'];
          _shopRating = rawRating != null
              ? (rawRating as num).toStringAsFixed(1)
              : '--';
          _isLoading = false;
        });
        _entryCtrl.forward();
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading seller stats: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dashboard data. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        _entryCtrl.forward();
      }
    }
  }

  void _startNotifications(String shopId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final auth = context.read<AuthProvider>();
        final userId = auth.currentUserId;
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsSeller(shopId);
        if (userId != null) notifProvider.registerFcmToken(userId, 'seller');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0A0A14) : const Color(0xFFF4F6FB),
        body: MaxWidthContainer(
          child: RefreshIndicator(
            onRefresh: _loadStats,
            color: const Color(0xFF4C6EF5),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
              // ── Animated Hero Header ──────────────────────────────────────
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              elevation: 0,
              backgroundColor: const Color(0xFF0A1260),
              surfaceTintColor: Colors.transparent,
              leading: const SizedBox.shrink(),
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedBuilder(
                  animation: _bgCtrl,
                  builder: (_, __) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(const Color(0xFF0A1260),
                              const Color(0xFF1A2E9E), _bgAnim.value)!,
                          Color.lerp(const Color(0xFF050A3A),
                              const Color(0xFF0D1870), _bgAnim.value)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Decorative blobs
                        Positioned(
                            top: -40,
                            right: -40,
                            child: _blob(200, const Color(0xFF4C6EF5),
                                0.15 + _bgAnim.value * 0.08)),
                        Positioned(
                            bottom: -60,
                            left: -30,
                            child: _blob(180, const Color(0xFFF4C542),
                                0.10 + (1 - _bgAnim.value) * 0.06)),
                        // Stars
                        CustomPaint(
                            size: Size(size.width, 200),
                            painter: _StarPainter(_bgCtrl.value)),
                        // Content
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top bar
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _avatar(auth.user?.initials ?? 'S'),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                    'Hi, ${auth.user?.fullName.split(' ').first ?? 'Seller'}!',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.outfit(
                                                        color: Colors.white,
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.w800)),
                                              ),
                                              _headerIcon(
                                                  isDark
                                                      ? Icons.light_mode_outlined
                                                      : Icons.dark_mode_outlined,
                                                  () => themeProvider.toggleTheme()),
                                              const NotificationBell(
                                                iconColor: Colors.white70,
                                                containerColor: Colors.transparent,
                                                badgeColor: Color(0xFFFF6B6B),
                                              ),
                                              _headerIcon(
                                                  Icons.help_outline_rounded,
                                                  () => Navigator.pushNamed(
                                                      context, AppRoutes.faqSupport)),
                                              _headerIcon(
                                                  Icons.settings_outlined,
                                                  () => Navigator.pushNamed(
                                                      context, AppRoutes.settings)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              _roleBadge('$_shopEmoji  $_shopBadgeName',
                                                  const Color(0xFFF4C542)),
                                              const SizedBox(width: 8),
                                              _statusBadge(_shopIsActive),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Revenue hero number
                                if (!_isLoading)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.pushNamed(context, AppRoutes.analytics),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text("Today's Earning",
                                                    style: GoogleFonts.outfit(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.65),
                                                        fontSize: 13)),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                                  textBaseline: TextBaseline.alphabetic,
                                                  children: [
                                                    Text(
                                                        '₹${(_stats['todays_earning'] as double?)?.toStringAsFixed(0) ?? '0'}',
                                                        style: GoogleFonts.outfit(
                                                            color: Colors.white,
                                                            fontSize: 36,
                                                            fontWeight: FontWeight.w900,
                                                            letterSpacing: -1)),

                                                  ],
                                                ),
                                              ]),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Stat Cards ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _isLoading
                        ? _buildShimmer()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth > 500;
                              if (isWide) {
                                return Row(
                                  children: [
                                    Expanded(
                                        child: _statCard(
                                            'Rating',
                                            '⭐ $_shopRating',
                                            Icons.star_rounded,
                                            const Color(0xFF51CF66),
                                            const Color(0xFF2F9E44))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _statCard(
                                            'Pending',
                                            '${_stats['pending_orders']}',
                                            Icons.pending_actions_rounded,
                                            const Color(0xFFFF8C42),
                                            const Color(0xFFE8590C),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.sellerOrders))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _statCard(
                                            'Orders',
                                            '${_stats['total_orders']}',
                                            Icons.receipt_long_rounded,
                                            const Color(0xFF4C6EF5),
                                            const Color(0xFF364FC7),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.sellerOrders))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _statCard(
                                            'Products',
                                            '${_stats['products']}',
                                            Icons.inventory_2_rounded,
                                            const Color(0xFFCC5DE8),
                                            const Color(0xFF9C36B5),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.manageProducts))),
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: _statCard(
                                            'Rating',
                                            '⭐ $_shopRating',
                                            Icons.star_rounded,
                                            const Color(0xFF51CF66),
                                            const Color(0xFF2F9E44))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _statCard(
                                            'Pending',
                                            '${_stats['pending_orders']}',
                                            Icons.pending_actions_rounded,
                                            const Color(0xFFFF8C42),
                                            const Color(0xFFE8590C),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.sellerOrders))),
                                  ]),
                                  const SizedBox(height: 14),
                                  Row(children: [
                                    Expanded(
                                        child: _statCard(
                                            'Orders',
                                            '${_stats['total_orders']}',
                                            Icons.receipt_long_rounded,
                                            const Color(0xFF4C6EF5),
                                            const Color(0xFF364FC7),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.sellerOrders))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _statCard(
                                            'Products',
                                            '${_stats['products']}',
                                            Icons.inventory_2_rounded,
                                            const Color(0xFFCC5DE8),
                                            const Color(0xFF9C36B5),
                                            onTap: () => Navigator.pushNamed(context, AppRoutes.manageProducts))),
                                  ]),
                                ],
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),

            // ── Quick Actions ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Text('Quick Actions',
                      style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color:
                              isDark ? Colors.white : const Color(0xFF0A0A14))),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _actionTile(
                    icon: Icons.add_box_rounded,
                    gradient: const [Color(0xFF4C6EF5), Color(0xFF364FC7)],
                    title: 'Add New Product',
                    subtitle: 'List items in your catalog',
                    badge: null,
                    isDark: isDark,
                    onTap: () async {
                      await Navigator.pushNamed(context, AppRoutes.addProduct);
                      _loadStats();
                    },
                  ),

                  _actionTile(
                    icon: Icons.insights_rounded,
                    gradient: const [Color(0xFF51CF66), Color(0xFF2F9E44)],
                    title: 'Store Analytics',
                    subtitle: 'Sales & customer trends',
                    badge: null,
                    isDark: isDark,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.analytics),
                  ),
                  _actionTile(
                    icon: Icons.account_balance_outlined,
                    gradient: const [Color(0xFFF4C542), Color(0xFFE8A000)],
                    title: 'CA / Tax Report',
                    subtitle: 'Monthly GST & payout report for your CA',
                    badge: null,
                    isDark: isDark,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.caReport),
                  ),
                  _actionTile(
                    icon: Icons.savings_rounded,
                    gradient: const [Color(0xFF51CF66), Color(0xFF1E8449)],
                    title: 'Withdraw Earnings',
                    subtitle: 'Request payout to your UPI or bank',
                    badge: null,
                    isDark: isDark,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.sellerWithdrawals),
                  ),
                  _actionTile(
                    icon: Icons.settings_outlined,
                    gradient: const [Color(0xFF00B4D8), Color(0xFF0077A8)],
                    title: 'Manage Shop',
                    subtitle: _shopIsActive
                        ? 'Shop is Open — tap to edit settings'
                        : 'Shop is Closed — tap to open or edit',
                    badge: _shopIsActive ? null : 'Closed',
                    isDark: isDark,
                    onTap: () async {
                      await Navigator.pushNamed(
                          context, AppRoutes.shopManagement);
                      setState(() => _isLoading = true);
                      _loadStats(); // refresh after returning
                    },
                  ),
                ]),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _avatar(String initials) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF4C542), Color(0xFFE8A000)]),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFF4C542).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Center(
            child: Text(initials,
                style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w900))),
      );

  Widget _roleBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(label,
            style: GoogleFonts.outfit(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _statusBadge(bool isActive) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.5))),
        child: Text(isActive ? '● Open' : '● Closed',
            style: GoogleFonts.outfit(
                color: isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _headerIcon(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white70, size: 22),
        onPressed: onTap,
        splashRadius: 20,
      );

  Widget _statCard(
      String title, String value, IconData icon, Color light, Color dark, {VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Parse value for count-up animation if it's a number
    final isNumber = int.tryParse(value) != null;
    final intValue = isNumber ? int.parse(value) : null;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: light.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
          border: Border.all(color: light.withValues(alpha: isDark ? 0.15 : 0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [light, dark]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: light.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 16),
          if (isNumber)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: intValue!),
              duration: const Duration(seconds: 1),
              builder: (context, val, child) => Text(val.toString(),
                  style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0A0A14))),
            )
          else
            Text(value,
                style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 2),
          Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required String? badge,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: gradient.first.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF0A0A14))),
              Text(subtitle,
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade600)),
            ]),
          ),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFFFF8C42),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(badge,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
          ],
          Icon(Icons.arrow_forward_ios_rounded,
              size: 15, color: isDark ? Colors.white24 : Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimColor = isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade200;
    final highlight = isDark ? const Color(0xFF2A2A3A) : Colors.grey.shade100;
    
    return Shimmer.fromColors(
      baseColor: shimColor,
      highlightColor: highlight,
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                      color: shimColor,
                      borderRadius: BorderRadius.circular(24)))),
          const SizedBox(width: 14),
          Expanded(
              child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                      color: shimColor,
                      borderRadius: BorderRadius.circular(24)))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                      color: shimColor,
                      borderRadius: BorderRadius.circular(24)))),
          const SizedBox(width: 14),
          Expanded(
              child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                      color: shimColor,
                      borderRadius: BorderRadius.circular(24)))),
        ]),
      ]),
    );
  }

  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    RadialGradient(colors: [color, color.withValues(alpha: 0)]))),
      );
}

class _StarPainter extends CustomPainter {
  final double t;
  _StarPainter(this.t);
  static final _rnd = math.Random(99);
  static final _stars = List.generate(
      30,
      (_) => [
            _rnd.nextDouble(),
            _rnd.nextDouble(),
            _rnd.nextDouble() * 1.2 + 0.4,
            _rnd.nextDouble() * math.pi * 2
          ]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      final tw = (math.sin(t * math.pi * 2 + s[3]) + 1) / 2;
      p.color = Colors.white.withValues(alpha: 0.03 + tw * 0.12);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter o) => o.t != t;
}
