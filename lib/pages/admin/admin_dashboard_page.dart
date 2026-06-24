import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/rbac_provider.dart';
import '../../providers/notification_provider.dart';
import '../../config/routes.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/common/notification_bell.dart';

import 'modules/overview_admin_page.dart';
import 'modules/orders_admin_page.dart';
import 'modules/users_admin_page.dart';
import 'modules/kyc_review_page.dart';
import 'modules/finance_admin_page.dart';
import 'modules/settings_admin_page.dart';
import 'modules/analytics_admin_page.dart';
import 'modules/complaints_admin_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  final Set<int> _visitedIndices = {0};
  int _openTicketsCount = 0;
  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _bgCtrl =
        AnimationController(duration: const Duration(seconds: 12), vsync: this)
          ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!auth.isAdminVerified) {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.roleSelect, (_) => false);
        return;
      }
      final userId = auth.currentUserId;
      if (userId != null) {
        context.read<RbacProvider>().loadCurrentAdmin(userId);
        context.read<NotificationProvider>().listenAsAdmin(userId);
        context.read<NotificationProvider>().registerFcmToken(userId, 'admin');
      }
      _loadBadges();
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBadges() async {
    try {
      final supabase = Supabase.instance.client;
      int tickets = 0;
      try {
        final t = await supabase.from('support_tickets').select('id').eq('status', 'open');
        tickets = (t as List).length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _openTicketsCount = tickets;
        });
      }
    } catch (_) {}
  }

  void _signOut() {
    // N1 FIX: Clean up notification subscriptions
    context.read<NotificationProvider>().clearFcmSubs();
    context.read<NotificationProvider>().stopListening();
    // APP4 FIX: Clear cart on logout
    context.read<CartProvider>().clear();
    context.read<AuthProvider>().adminSignOut();
    context.read<RbacProvider>().clear();
    Navigator.pushNamedAndRemoveUntil(
        context, AppRoutes.roleSelect, (_) => false);
  }

  // ── Build tabs based on permissions ─────────────────────────────
  List<_NavDef> _buildNavItems(RbacProvider rbac) => [
        const _NavDef(
          icon: Icons.dashboard_rounded,
          activeIcon: Icons.dashboard_rounded,
          label: 'Home',
          visible: true,
        ),
        const _NavDef(
          icon: Icons.tune_outlined,
          activeIcon: Icons.tune_rounded,
          label: 'Settings',
          visible: true,
        ),
        _NavDef(
          icon: Icons.auto_awesome_outlined,
          activeIcon: Icons.auto_awesome_rounded,
          label: 'Analytics',
          visible: rbac.can('analytics.view') || rbac.isSuperAdmin,
        ),
        _NavDef(
          icon: Icons.support_agent_outlined,
          activeIcon: Icons.support_agent_rounded,
          label: 'Support',
          visible: rbac.can('support.view') || rbac.isSuperAdmin,
          badgeCount: _openTicketsCount,
        ),
      ].where((n) => n.visible).toList();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final rbac = context.watch<RbacProvider>();
    final adminName = auth.user?.fullName.split(' ').first ??
        rbac.currentAdmin?.fullName.split(' ').first ??
        'Admin';
    final navItems = _buildNavItems(rbac);
    final safeIndex = _currentIndex.clamp(0, navItems.length - 1);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AdminColors.surface,
    ));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (safeIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _visitedIndices.add(0);
          });
        } else {
          final now = DateTime.now();
          if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // ignore: use_build_context_synchronously
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
      backgroundColor: AdminColors.bg,
      body: Stack(
        children: [
          // Animated gradient background auras
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => Stack(children: [
              Positioned(
                top: -120 + (_bgAnim.value * 40),
                left: -80,
                child: const _Aura(400, AdminColors.primary, 0.12),
              ),
              Positioned(
                bottom: -180 - (_bgAnim.value * 30),
                right: -60,
                child: const _Aura(500, AdminColors.primaryEnd, 0.08),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.4,
                left: MediaQuery.of(context).size.width * 0.3,
                child: const _Aura(250, AdminColors.info, 0.05),
              ),
            ]),
          ),

          SafeArea(
            child: Column(
              children: [
                _Header(
                  adminName: adminName,
                  rbac: rbac,
                  onSignOut: _signOut,
                ),
                Expanded(
                  child: IndexedStack(
                    index: safeIndex,
                    children: navItems.asMap().entries.map((entry) {
                      if (!_visitedIndices.contains(entry.key)) {
                        return const SizedBox.shrink();
                      }
                      return _buildScreen(entry.value.label, adminName, rbac);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildNavBar(navItems, safeIndex),
    ));
  }

  Widget _buildScreen(String label, String adminName, RbacProvider rbac) {
    return switch (label) {
      'Home' => OverviewAdminPage(adminName: adminName),
      'Orders' => const OrdersAdminPage(),
      'Users' => ChangeNotifierProvider.value(
          value: rbac, child: const UsersAdminPage()),
      'KYC' => const KycReviewPage(),
      'Finance' => const FinanceAdminPage(),
      'Settings' => ChangeNotifierProvider.value(
          value: rbac, child: const SettingsAdminPage()),
      'Analytics' => const AnalyticsAdminPage(),
      'Support' => const ComplaintsAdminPage(),
      _ =>
        Center(child: Text('$label — Coming Soon', style: AdminStyles.body())),
    };
  }

  Widget _buildNavBar(List<_NavDef> items, int selected) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: const Border(
            top: BorderSide(color: AdminColors.cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AdminStyles.label(color: AdminColors.primary, size: 10)
                  .copyWith(fontWeight: FontWeight.w700);
            }
            return AdminStyles.label(color: AdminColors.textMuted, size: 10);
          }),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) {
            HapticFeedback.lightImpact();
            setState(() {
              _currentIndex = i;
              _visitedIndices.add(i);
            });
            _loadBadges();
          },
          backgroundColor: Colors.transparent,
          indicatorColor: AdminColors.primary.withValues(alpha: 0.2),
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: items
              .map((n) => NavigationDestination(
                    icon: n.badgeCount > 0
                        ? Badge(
                            label: Text('${n.badgeCount}'),
                            child: Icon(n.icon, color: AdminColors.textMuted),
                          )
                        : Icon(n.icon, color: AdminColors.textMuted),
                    selectedIcon:
                        Icon(n.activeIcon, color: AdminColors.primary),
                    label: n.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ── Header Widget ─────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String adminName;
  final RbacProvider rbac;
  final VoidCallback onSignOut;

  const _Header({
    required this.adminName,
    required this.rbac,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final role = rbac.currentAdmin?.role;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      decoration: BoxDecoration(
        color: AdminColors.surface.withValues(alpha: 0.7),
        border: const Border(
            bottom: BorderSide(color: AdminColors.cardBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Avatar + gradient ring
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              gradient: AdminGradients.primary,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AdminColors.bg,
              child: Text(
                adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A',
                style: GoogleFonts.poppins(
                    color: AdminColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rbac.isSuperAdmin ? 'Super Admin' : adminName,
                  style: AdminStyles.title(size: 15),
                ),
                Row(children: [
                  if (rbac.isSuperAdmin)
                    const AdminBadge(
                        label: 'GOD MODE', color: AdminColors.warning)
                  else if (role != null) ...[
                    AdminBadge(label: role.name, color: AdminColors.primary),
                  ],
                ]),
              ],
            ),
          ),
          if (rbac.loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: AdminColors.primary, strokeWidth: 2),
            )
          else ...[
            const NotificationBell(
              iconColor: AdminColors.textSecondary,
              containerColor: Colors.transparent,
              badgeColor: AdminColors.warning,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded,
                  color: AdminColors.textMuted, size: 20),
              onPressed: onSignOut,
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Background Aura ───────────────────────────────────────────────
class _Aura extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Aura(this.size, this.color, this.opacity);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [color, color.withValues(alpha: 0.0)]),
        ),
      ),
    );
  }
}

// ── Nav Definition ────────────────────────────────────────────────
class _NavDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool visible;
  final int badgeCount;
  const _NavDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.visible,
    this.badgeCount = 0,
  });
}
