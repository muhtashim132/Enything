import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/auth_provider.dart';
import '../../providers/referral_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_layout.dart';
import '../../widgets/common/premium_animations.dart';

class ReferAndEarnPage extends StatefulWidget {
  const ReferAndEarnPage({super.key});

  @override
  State<ReferAndEarnPage> createState() => _ReferAndEarnPageState();
}

class _ReferAndEarnPageState extends State<ReferAndEarnPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
    });
  }

  void _loadStats() {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id ?? auth.currentUserId;
    if (userId != null) {
      context.read<ReferralProvider>().loadReferralStats(userId);
    }
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id ?? auth.currentUserId;
    if (userId != null) {
      await context.read<ReferralProvider>().loadReferralStats(userId);
    }
  }

  Future<void> _generateCode() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.user?.id ?? auth.currentUserId;
      final displayName = auth.user?.fullName ?? 'User';

      if (userId == null) return;

      await context
          .read<ReferralProvider>()
          .generateReferralCode(userId, displayName);
      _loadStats();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _copyCode(String code, {String? customMsg}) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(customMsg ?? 'Code copied to clipboard!',
            style: GoogleFonts.outfit()),
        backgroundColor: const Color(0xFF2F9E44),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final refProv = context.watch<ReferralProvider>();
    final code = refProv.referralCode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF1E3FD8),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              elevation: 0,
              backgroundColor:
                  isDark ? const Color(0xFF0F172A) : const Color(0xFF1E3FD8),
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    )
                  : const SizedBox.shrink(),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _buildHeroBackground(isDark),
              ),
            ),
            SliverToBoxAdapter(
              child: MaxWidthContainer(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Referral Code Section
                      SlideInWidget(
                        delay: const Duration(milliseconds: 100),
                        child: _buildCodeSection(code, isDark),
                      ),
                      const SizedBox(height: 24),

                      // 2. Live Referral Activity Statistics
                      SlideInWidget(
                        delay: const Duration(milliseconds: 150),
                        child: _buildStatsSection(refProv, isDark),
                      ),
                      const SizedBox(height: 24),

                      // 3. My Earned Reward Coupons
                      SlideInWidget(
                        delay: const Duration(milliseconds: 200),
                        child: _buildRewardsSection(refProv, isDark),
                      ),
                      const SizedBox(height: 32),

                      // 4. How It Works
                      SlideInWidget(
                        delay: const Duration(milliseconds: 250),
                        child: _buildHowItWorks(isDark, refProv.referralBonusAmount),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBackground(bool isDark) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                  : [const Color(0xFF1E3FD8), const Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Decorative blobs
        Positioned(
          top: -50,
          right: -50,
          child: _blob(200, Colors.white, 0.1),
        ),
        Positioned(
          bottom: -40,
          left: -40,
          child: _blob(180, Colors.white, 0.08),
        ),
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.redeem_rounded,
                      size: 64, color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Refer & Earn',
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invite friends and earn rewards together!',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeSection(String? code, bool isDark) {
    if (code == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.withValues(alpha: 0.2)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ],
        ),
        child: Column(
          children: [
            Text(
              'Generate your unique code to start earning rewards for every successful referral.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : PressScaleButton(
                    onTap: _generateCode,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF4A800), Color(0xFFFFD700)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFF4C542).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Generate My Code',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFF4A800).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: const Color(0xFFF4A800).withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 12))
              ],
      ),
      child: Column(
        children: [
          Text(
            'YOUR REFERRAL CODE',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: const Color(0xFFF4A800),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.3),
                  style: BorderStyle.solid),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  code,
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
                GestureDetector(
                  onTap: () => _copyCode(code),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: Color(0xFFF4A800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Share this code with friends to earn exciting rewards!',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: isDark ? Colors.white54 : AppColors.textLight,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Live Statistics Section ───────────────────────────────────────────────

  Widget _buildStatsSection(ReferralProvider refProv, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.15),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_outlined,
                      size: 18, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  Text(
                    'Referral Activity',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (refProv.statsLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF3B82F6)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Joined',
                  value: '${refProv.invitedCount}',
                  icon: Icons.group_add_rounded,
                  color: const Color(0xFF3B82F6),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Ordered',
                  value: '${refProv.completedCount}',
                  icon: Icons.task_alt_rounded,
                  color: const Color(0xFF10B981),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Earned',
                  value: '₹${refProv.totalBonusEarned.toStringAsFixed(0)}',
                  icon: Icons.savings_rounded,
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            refProv.pendingCount > 0
                ? '${refProv.pendingCount} friend${refProv.pendingCount == 1 ? '' : 's'} registered — waiting for their first order delivery to unlock your next ₹${refProv.referralBonusAmount.toStringAsFixed(0)} coupon!'
                : refProv.invitedCount > 0
                    ? 'All friends have completed their first orders! Share with more friends to keep earning.'
                    : 'Share your code to earn ₹${refProv.referralBonusAmount.toStringAsFixed(0)} off for every friend who orders!',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: isDark ? Colors.white60 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Earned Reward Coupons Section ─────────────────────────────────────────

  Widget _buildRewardsSection(ReferralProvider refProv, bool isDark) {
    final coupons = refProv.earnedCoupons;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.15),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.confirmation_number_outlined,
                  size: 20, color: Color(0xFFF4A800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'My Reward Coupons (${coupons.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Copy and paste these codes at checkout to apply discounts to your orders.',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: isDark ? Colors.white60 : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (coupons.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4A800).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.card_giftcard_rounded,
                        color: Color(0xFFF4A800), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No reward coupons yet',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'When a referred friend completes their first order, your discount coupon will appear right here!',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            ...coupons.map((c) => _buildCouponCard(c, isDark)),
        ],
      ),
    );
  }

  Widget _buildCouponCard(ReferralRewardCoupon coupon, bool isDark) {
    final now = DateTime.now();
    int daysLeft = 0;
    if (coupon.validUntil != null) {
      daysLeft = coupon.validUntil!.difference(now).inDays;
      if (daysLeft < 0) daysLeft = 0;
    }

    final bool isActive = !coupon.isUsed && !coupon.isExpired;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.25)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Value Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (isActive ? const Color(0xFF10B981) : Colors.grey)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  '₹${coupon.discountValue.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isActive ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
                Text(
                  'OFF',
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isActive ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Code & Expiry
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      coupon.code,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        decoration: coupon.isUsed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (coupon.isUsed
                                ? Colors.grey
                                : coupon.isExpired
                                    ? Colors.amber
                                    : const Color(0xFF10B981))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        coupon.isUsed
                            ? 'Used'
                            : coupon.isExpired
                                ? 'Expired'
                                : 'Active',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: coupon.isUsed
                              ? Colors.grey
                              : coupon.isExpired
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isActive
                      ? 'Min order ₹${coupon.minOrderAmount.toStringAsFixed(0)} • $daysLeft day${daysLeft == 1 ? '' : 's'} left'
                      : coupon.isUsed
                          ? 'Already redeemed on checkout'
                          : 'Expired',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),

          // Copy Button
          IconButton(
            tooltip: 'Copy Coupon Code',
            icon: Icon(
              Icons.copy_rounded,
              size: 18,
              color: isActive ? const Color(0xFF3B82F6) : Colors.grey,
            ),
            onPressed: () => _copyCode(coupon.code,
                customMsg:
                    'Coupon "${coupon.code}" copied! Paste at checkout.'),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(bool isDark, double bonusAmount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How it works',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildStep(
          isDark,
          icon: Icons.share_rounded,
          title: 'Share Your Code',
          description:
              'Share your unique referral code with friends, family, or colleagues.',
        ),
        _buildStep(
          isDark,
          icon: Icons.person_add_rounded,
          title: 'Friend Signs Up',
          description:
              'They enter your code in the "Referral Code" field while completing their profile.',
        ),
        _buildStep(
          isDark,
          icon: Icons.card_giftcard_rounded,
          title: 'You Both Earn',
          description:
              'When their first order is delivered, you both instantly get a ₹${bonusAmount.toStringAsFixed(0)} discount coupon to redeem on checkout!',
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildStep(bool isDark,
      {required IconData icon,
      required String title,
      required String description,
      bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF1E3FD8), size: 24),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.2),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : AppColors.textLight,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}
