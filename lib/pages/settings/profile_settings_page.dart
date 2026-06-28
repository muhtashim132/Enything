import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../widgets/common/role_switcher_card.dart';
import '../../widgets/common/premium_animations.dart';
import 'profile_settings_dialogs.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage>
    with SingleTickerProviderStateMixin {

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: MaxWidthContainer(
        child: CustomScrollView(
          slivers: [
            // ── Premium Hero AppBar ──────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              elevation: 0,
              backgroundColor: isDark
                  ? AppColors.darkBg
                  : AppColors.roleColor(user.activeSessionRole),
              surfaceTintColor: Colors.transparent,
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: PressScaleButton(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _buildHeroCard(user, isDark),
              ),
            ),

            // ── Settings Body ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 🔄 Role Switcher (shown only if user has >1 role)
                  const SlideInWidget(
                    delay: Duration(milliseconds: 80),
                    child: RoleSwitcherCard(),
                  ),

                  // Role-specific settings
                  SlideInWidget(
                    delay: const Duration(milliseconds: 140),
                    child: Builder(builder: (_) {
                      if (user.activeSessionRole == 'customer') {
                        return _buildCustomerSettings(isDark);
                      }
                      if (user.activeSessionRole == 'seller') {
                        return _buildSellerSettings(isDark);
                      }
                      if (user.activeSessionRole == 'delivery_partner') {
                        return _buildDeliverySettings(isDark);
                      }
                      return const SizedBox.shrink();
                    }),
                  ),

                  // General
                  SlideInWidget(
                    delay: const Duration(milliseconds: 200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _buildSectionTitle('General', isDark),
                        const SizedBox(height: 16),
                        _buildSettingTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Notifications',
                          subtitle: 'Manage push notifications',
                          roleColor: AppColors.roleColor(user.activeSessionRole),
                          isDark: isDark,
                          onTap: () => showNotificationSettingsDialog(context),
                        ),
                        _buildSettingTile(
                          icon: Icons.help_outline_rounded,
                          title: 'Help & Support',
                          subtitle: 'FAQs and contact support',
                          roleColor: AppColors.roleColor(user.activeSessionRole),
                          isDark: isDark,
                          onTap: () => Navigator.pushNamed(
                              context, '/settings/faq-support'),
                        ),
                        _buildSettingTile(
                          icon: Icons.contact_support_rounded,
                          title: 'Contact Us',
                          subtitle: 'Email, phone & office address',
                          roleColor: AppColors.roleColor(user.activeSessionRole),
                          isDark: isDark,
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.contactUs),
                        ),
                        _buildSettingTile(
                          icon: Icons.info_outline_rounded,
                          title: 'About Enything',
                          subtitle: 'App version, Terms, Privacy Policy',
                          roleColor: AppColors.roleColor(user.activeSessionRole),
                          isDark: isDark,
                          onTap: () => Navigator.pushNamed(
                              context, AppRoutes.aboutEnything),
                        ),
                        _buildSettingTile(
                          icon: isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          title: isDark ? 'Light Mode' : 'Dark Mode',
                          subtitle: 'Toggle app appearance',
                          roleColor: AppColors.roleColor(user.activeSessionRole),
                          isDark: isDark,
                          onTap: () =>
                              context.read<ThemeProvider>().toggleTheme(),
                        ),
                      ],
                    ),
                  ),

                  // Support Button
                  SlideInWidget(
                    delay: const Duration(milliseconds: 260),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildContactSupportButton(isDark),
                        const SizedBox(height: 16),
                        _buildLogoutButton(auth, isDark),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            'Enything v1.0.0',
                            style: GoogleFonts.outfit(
                                color: AppColors.textLight, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HERO CARD ──────────────────────────────────────────────────────────────
  Widget _buildHeroCard(UserModel user, bool isDark) {
    final roleGradient = AppColors.roleGradient(user.activeSessionRole);
    final hasRating = user.averageRating > 0 && user.totalReviews > 0;

    return Container(
      decoration: BoxDecoration(gradient: roleGradient),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          // Content
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    GlowPulseAvatar(
                      glowColor: Colors.white,
                      radius: 38,
                      bgColor: Colors.white.withValues(alpha: 0.18),
                      child: Text(
                        user.initials,
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.fullName,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (user.phone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              user.phone,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          // Role badge
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter:
                                  ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      user.sessionRoleDisplay,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Rating
                          if (hasRating) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: AppColors.accent, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  user.averageRating.toStringAsFixed(1),
                                  style: GoogleFonts.outfit(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${user.totalReviews} reviews)',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ROLE SETTINGS ──────────────────────────────────────────────────────────

  Widget _buildCustomerSettings(bool isDark) {
    final sub = context.watch<SubscriptionProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Enything Pass Banner (if active) ──────────────────────────────
        if (sub.hasActiveSub) ...[          
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.tierDisplay,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${sub.loyaltyBalance} pts · ${sub.activeSub!.daysRemaining}d remaining',
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.subscription),
                  child: Text(
                    'Manage',
                    style: GoogleFonts.outfit(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        _buildSectionTitle('Account Settings', isDark),
        const SizedBox(height: 16),
        // ── Enything Pass entry ───────────────────────────────────────────
        _buildSettingTile(
          icon: Icons.star_rounded,
          title: sub.hasActiveSub ? sub.tierDisplay : 'Enything Pass',
          subtitle: sub.hasActiveSub
              ? '${sub.loyaltyBalance} loyalty points · Tap to manage'
              : 'Free delivery, cashback & loyalty points',
          roleColor: sub.hasActiveSub
              ? const Color(0xFFD4A017)
              : AppColors.primary,
          isDark: isDark,
          trailing: !sub.hasActiveSub
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: AppColors.ctaGradient,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    'GET PASS',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                )
              : null,
          onTap: () => Navigator.pushNamed(context, AppRoutes.subscription),
        ),
        _buildSettingTile(
          icon: Icons.receipt_long_outlined,
          title: 'My Orders',
          subtitle: 'View your order history',
          roleColor: AppColors.primary,
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/customer/orders'),
        ),
        _buildSettingTile(
          icon: Icons.location_on_outlined,
          title: 'Saved Addresses',
          subtitle: 'Manage delivery locations',
          roleColor: AppColors.primary,
          isDark: isDark,
          onTap: () => showSavedAddressesDialog(context),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSellerSettings(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Shop Management', isDark),
        const SizedBox(height: 16),
        _buildSettingTile(
          icon: Icons.storefront_outlined,
          title: 'Shop Details',
          subtitle: 'Name, description, and categories',
          roleColor: const Color(0xFF9C27B0),
          isDark: isDark,
          onTap: _showShopDetailsDialog,
        ),
        _buildSettingTile(
          icon: Icons.account_balance_outlined,
          title: 'Payout Bank Account',
          subtitle: 'Bank accounts for settlements',
          roleColor: const Color(0xFF9C27B0),
          isDark: isDark,
          onTap: () =>
              showPayoutSettingsDialog(context, 'shops', 'seller_id'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDeliverySettings(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Partner Settings', isDark),
        const SizedBox(height: 16),
        _buildSettingTile(
          icon: Icons.two_wheeler,
          title: 'Vehicle Information',
          subtitle: 'View your vehicle type and reg no',
          roleColor: const Color(0xFF00897B),
          isDark: isDark,
          onTap: _showVehicleDetailsDialog,
        ),
        _buildSettingTile(
          icon: Icons.badge_outlined,
          title: 'Documents',
          subtitle: 'View License, Aadhaar, and PAN',
          roleColor: const Color(0xFF00897B),
          isDark: isDark,
          onTap: () => showDocumentsDialog(context),
        ),
        _buildSettingTile(
          icon: Icons.account_balance_outlined,
          title: 'Payout Bank Account',
          subtitle: 'Manage weekly payout account',
          roleColor: const Color(0xFF00897B),
          isDark: isDark,
          onTap: () =>
              showPayoutSettingsDialog(context, 'delivery_partners', 'id'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── UI COMPONENTS ──────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color roleColor,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return PressScaleButton(
      scaleDown: 0.97,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D30) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border(
            left: BorderSide(color: roleColor, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: roleColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: isDark
                            ? Colors.grey.shade500
                            : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ?? Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactSupportButton(bool isDark) {
    return PressScaleButton(
      onTap: () => Navigator.pushNamed(context, AppRoutes.faqSupport),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need Help?',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Contact our 24/7 support team',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: AppColors.primary, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AuthProvider auth, bool isDark) {
    return PressScaleButton(
      scaleDown: 0.97,
      onTap: () async {
        // Confirm dialog
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark
                ? const Color(0xFF1A1D30)
                : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            title: Text('Logout',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
            content: Text('Are you sure you want to logout?',
                style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Logout',
                    style: GoogleFonts.outfit(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        // Capture navigator before async gap
        final navigator = Navigator.of(context);
        context.read<NotificationProvider>().clearFcmSubs();
        context.read<NotificationProvider>().stopListening();
        context.read<CartProvider>().clear();
        await auth.signOut();
        navigator.pushNamedAndRemoveUntil('/auth/role', (_) => false);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.danger.withValues(alpha: 0.12)
              : AppColors.dangerLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Text(
              'Logout',
              style: GoogleFonts.outfit(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature settings coming soon!'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _showShopDetailsDialog() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator()));
    try {
      final res = await Supabase.instance.client
          .from('shops')
          .select('id, name, address')
          .eq('seller_id', auth.currentUserId ?? '')
          .maybeSingle();
      if (mounted) Navigator.pop(context);
      if (res != null) {
        final nameCtrl = TextEditingController(text: res['name']);
        final addrCtrl = TextEditingController(text: res['address']);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop Details',
                    style: GoogleFonts.outfit(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Shop Name')),
                const SizedBox(height: 16),
                TextField(
                    controller: addrCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Shop Address')),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await Supabase.instance.client
                        .from('shops')
                        .update({
                          'name': nameCtrl.text.trim(),
                          'address': addrCtrl.text.trim()
                        })
                        .eq('id', res['id']);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56)),
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        );
      } else {
        _showComingSoon('Shop not found');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _showVehicleDetailsDialog() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator()));
    try {
      final res = await Supabase.instance.client
          .from('delivery_partners')
          .select('id, vehicle_type, vehicle_reg_number')
          .eq('id', auth.currentUserId ?? '')
          .maybeSingle();
      if (mounted) Navigator.pop(context);
      if (res != null) {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) {
            final isDark =
                Theme.of(ctx).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vehicle Information',
                      style: GoogleFonts.outfit(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  _buildReadOnlyField(
                      'Vehicle Type',
                      res['vehicle_type'] ?? 'Not specified',
                      isDark),
                  const SizedBox(height: 16),
                  _buildReadOnlyField(
                      'Registration Number',
                      res['vehicle_reg_number'] ?? 'Not specified',
                      isDark),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Close',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Vehicle details not found.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Permission denied: Ask admin to grant SELECT on vehicle columns.')),
        );
      }
    }
  }

  Widget _buildReadOnlyField(String label, String value, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
