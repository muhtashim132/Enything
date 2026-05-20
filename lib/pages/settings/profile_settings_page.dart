import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import 'profile_settings_dialogs.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
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
      appBar: AppBar(
        title: Text('Settings & Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Profile Info
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    user.initials,
                    style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(user.phone, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user.roleDisplay,
                          style: GoogleFonts.outfit(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Role Specific Settings
            if (user.activeSessionRole == 'customer') _buildCustomerSettings(isDark),
            if (user.activeSessionRole == 'seller') _buildSellerSettings(isDark),
            if (user.activeSessionRole == 'delivery_partner') _buildDeliverySettings(isDark),

            const SizedBox(height: 24),
            _buildSectionTitle('General', isDark),
            const SizedBox(height: 16),
            _buildSettingTile(
              icon: Icons.notifications_active_outlined,
              title: 'Notifications',
              subtitle: 'Manage push notifications',
              isDark: isDark,
              onTap: () => showGenericInfoDialog(context, 'Notifications', 'Push notification settings will appear here.'),
            ),
            _buildSettingTile(
              icon: Icons.security_rounded,
              title: 'Privacy & Security',
              subtitle: 'Password, PIN, and biometrics',
              isDark: isDark,
              onTap: () => showGenericInfoDialog(context, 'Privacy & Security', 'Biometrics and PIN lock are active.'),
            ),
            _buildSettingTile(
              icon: Icons.help_outline_rounded,
              title: 'Help & Support',
              subtitle: 'FAQs and contact support',
              isDark: isDark,
              onTap: () => Navigator.pushNamed(context, '/settings/faq-support'),
            ),
            _buildSettingTile(
              icon: Icons.info_outline_rounded,
              title: 'About Enything',
              subtitle: 'App version, Terms, Privacy Policy',
              isDark: isDark,
              onTap: _showAboutBottomSheet,
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, '/auth/role', (_) => false);
                  }
                },
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: Text('Logout', style: GoogleFonts.outfit(color: AppColors.danger, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Text(
                'Enything v1.0.0',
                style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSettings(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Account Settings', isDark),
        const SizedBox(height: 16),
        _buildSettingTile(
          icon: Icons.receipt_long_outlined,
          title: 'My Orders',
          subtitle: 'View your order history',
          isDark: isDark,
          onTap: () => Navigator.pushNamed(context, '/customer/orders'),
        ),

        _buildSettingTile(
          icon: Icons.location_on_outlined,
          title: 'Saved Addresses',
          subtitle: 'Manage delivery locations',
          isDark: isDark,
          onTap: () => showSavedAddressesDialog(context),
        ),
        _buildSettingTile(
          icon: Icons.payment_outlined,
          title: 'Payment Methods',
          subtitle: 'Manage saved cards and UPI',
          isDark: isDark,
          onTap: () => showGenericInfoDialog(context, 'Payment Methods', 'UPI and Cards are managed securely via Razorpay during checkout.'),
        ),
        const SizedBox(height: 24),
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
          isDark: isDark,
          onTap: _showShopDetailsDialog,
        ),
        _buildSettingTile(
          icon: Icons.account_balance_outlined,
          title: 'Payout Settings',
          subtitle: 'Bank accounts for settlements',
          isDark: isDark,
          onTap: () => showPayoutSettingsDialog(context, 'shops', 'seller_id'),
        ),
        const SizedBox(height: 24),
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
          subtitle: 'Update vehicle type and reg no',
          isDark: isDark,
          onTap: _showVehicleDetailsDialog,
        ),
        _buildSettingTile(
          icon: Icons.badge_outlined,
          title: 'Documents',
          subtitle: 'License, Aadhar, and approvals',
          isDark: isDark,
          onTap: () => showDocumentsDialog(context),
        ),
        _buildSettingTile(
          icon: Icons.account_balance_outlined,
          title: 'Bank Details',
          subtitle: 'Manage weekly payout account',
          isDark: isDark,
          onTap: () => showPayoutSettingsDialog(context, 'delivery_partners', 'id'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardTheme.color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
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
                      fontSize: 16,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: isDark ? Colors.grey.shade400 : AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
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
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final res = await Supabase.instance.client.from('shops').select().eq('seller_id', auth.currentUserId ?? '').maybeSingle();
      if (mounted) Navigator.pop(context); // close loader
      if (res != null) {
        final nameCtrl = TextEditingController(text: res['name']);
        final addrCtrl = TextEditingController(text: res['address']);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop Details', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Shop Name')),
                const SizedBox(height: 16),
                TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Shop Address')),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    await Supabase.instance.client.from('shops').update({'name': nameCtrl.text.trim(), 'address': addrCtrl.text.trim()}).eq('id', res['id']);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
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
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final res = await Supabase.instance.client.from('delivery_partners').select().eq('id', auth.currentUserId ?? '').maybeSingle();
      if (mounted) Navigator.pop(context); // close loader
      if (res != null) {
        final typeCtrl = TextEditingController(text: res['vehicle_type'] ?? '');
        final regCtrl = TextEditingController(text: res['vehicle_reg_number'] ?? '');
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehicle Information', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Vehicle Type')),
                const SizedBox(height: 16),
                TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Registration Number')),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    await Supabase.instance.client.from('delivery_partners').update({'vehicle_type': typeCtrl.text.trim(), 'vehicle_reg_number': regCtrl.text.trim()}).eq('id', auth.currentUserId!);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showAboutBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About Enything',
                style: GoogleFonts.outfit(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('Terms of Service', style: GoogleFonts.outfit()),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/legal/terms');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text('Privacy Policy', style: GoogleFonts.outfit()),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/legal/privacy');
              },
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('Version 1.0.0\nMade with ❤️ in India',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
