// ============================================================================
// subscription_page.dart — Enything Pass Premium Subscription UI
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  int _selectedPlanIndex = 1; // Pro selected by default
  bool _isSubscribing = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final sub = context.read<SubscriptionProvider>();
      if (auth.currentUserId != null && !sub.initialized) {
        sub.init(auth.currentUserId!);
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _subscribe(String planId) async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUserId == null) return;
    setState(() => _isSubscribing = true);
    HapticFeedback.mediumImpact();
    try {
      final sub = context.read<SubscriptionProvider>();
      final success = await sub.subscribe(
        userId: auth.currentUserId!,
        planId: planId,
      );
      if (!mounted) return;
      if (success) {
        HapticFeedback.heavyImpact();
        _showSuccessDialog();
      } else {
        _showError('Failed to activate subscription. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F1E80), Color(0xFF1E3FD8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryLight.withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                'Welcome to Enything Pass!',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve earned 50 bonus loyalty points!\nFree delivery awaits.',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: Text(
                  'Start Shopping!',
                  style: GoogleFonts.outfit(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final sub = context.watch<SubscriptionProvider>();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
      body: sub.loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildHeroAppBar(isDark),
                if (sub.hasActiveSub)
                  SliverToBoxAdapter(child: _buildActiveBanner(sub)),
                SliverToBoxAdapter(child: _buildLoyaltyCard(sub, isDark)),
                SliverToBoxAdapter(child: _buildPlansSection(sub, isDark)),
                SliverToBoxAdapter(child: _buildComparisonTable(isDark)),
                SliverToBoxAdapter(child: _buildReferralCard(sub, isDark)),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
    );
  }

  // ── Hero App Bar ────────────────────────────────────────────────────────────
  SliverAppBar _buildHeroAppBar(bool isDark) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: AnimatedBuilder(
          animation: _glowController,
          builder: (_, __) {
            final glow = _glowController.value;
            return Container(
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Stack(
                children: [
                  Positioned(
                    top: -30 + (glow * 20),
                    right: -20 + (glow * 15),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.primaryLight.withValues(alpha: 0.3),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -40 + (glow * 10),
                    left: -30,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.accent.withValues(alpha: 0.2),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.5),
                                  width: 1),
                            ),
                            child: Text(
                              '✨ ENYTHING PASS',
                              style: GoogleFonts.outfit(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your\nDelivery Upgrade',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Free delivery · Cashback · Loyalty points',
                            style: GoogleFonts.outfit(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Active Subscription Banner ──────────────────────────────────────────────
  Widget _buildActiveBanner(SubscriptionProvider sub) {
    final plan = sub.currentPlan!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: plan.name == 'Ultra'
              ? [const Color(0xFFD4A017), const Color(0xFFFFCF40)]
              : plan.name == 'Pro'
                  ? [AppColors.primary, AppColors.primaryLight]
                  : [AppColors.textSecondary, AppColors.textLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            plan.name == 'Ultra'
                ? '👑'
                : plan.name == 'Pro'
                    ? '⚡'
                    : '✨',
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active: ${sub.tierDisplay}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${sub.activeSub!.daysRemaining} days remaining',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              'ACTIVE',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loyalty Points Card ────────────────────────────────────────────────────
  Widget _buildLoyaltyCard(SubscriptionProvider sub, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              gradient: AppColors.premiumGoldGradient,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: const Icon(Icons.stars_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Loyalty Points',
                  style: GoogleFonts.outfit(
                    color: isDark
                        ? Colors.white54
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${sub.loyaltyBalance}',
                      style: GoogleFonts.outfit(
                        color: isDark
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'pts = ₹${sub.loyaltyValueInRs.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: AppColors.success,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Lifetime earned',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color:
                      isDark ? Colors.white38 : AppColors.textLight,
                ),
              ),
              Text(
                '${sub.lifetimeEarned} pts',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Colors.white70
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Plans Section ─────────────────────────────────────────────────────────
  Widget _buildPlansSection(SubscriptionProvider sub, bool isDark) {
    if (sub.plans.isEmpty) {
      return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'Choose Your Plan',
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white : AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 340,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sub.plans.length,
            itemBuilder: (ctx, i) {
              final plan = sub.plans[i];
              final isSelected = _selectedPlanIndex == i;
              final isCurrent =
                  sub.hasActiveSub && sub.currentPlan?.id == plan.id;
              return _PlanCard(
                plan: plan,
                isSelected: isSelected,
                isCurrentPlan: isCurrent,
                isDark: isDark,
                onTap: () => setState(() => _selectedPlanIndex = i),
                onSubscribe: () => _subscribe(plan.id),
                isSubscribing: _isSubscribing && isSelected,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Comparison Table ──────────────────────────────────────────────────────
  Widget _buildComparisonTable(bool isDark) {
    final rows = <Map<String, String>>[
      {
        'feature': 'Free Delivery',
        'lite': '≥₹199',
        'pro': '✓ Always',
        'ultra': '✓ Always'
      },
      {
        'feature': 'Cashback',
        'lite': '—',
        'pro': '5%',
        'ultra': '10%'
      },
      {
        'feature': 'Loyalty Points',
        'lite': '1.5× speed',
        'pro': '2× speed',
        'ultra': '3× speed'
      },
      {
        'feature': 'Family Sharing',
        'lite': '—',
        'pro': '—',
        'ultra': '3 accounts'
      },
      {
        'feature': 'Priority Support',
        'lite': '—',
        'pro': '✓',
        'ultra': '✓'
      },
      {
        'feature': 'Exclusive Deals',
        'lite': '—',
        'pro': '✓',
        'ultra': '✓ Best deals'
      },
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Features',
                    style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                for (final tier in ['Lite', 'Pro', 'Ultra'])
                  Expanded(
                    flex: 2,
                    child: Text(
                      tier,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: tier == 'Ultra'
                            ? AppColors.accent
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Data rows
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final isLast = i == rows.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast
                      ? BorderSide.none
                      : BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : AppColors.divider),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      row['feature']!,
                      style: GoogleFonts.outfit(
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  for (final key in ['lite', 'pro', 'ultra'])
                    Expanded(
                      flex: 2,
                      child: Text(
                        row[key]!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: row[key] == '—'
                              ? (isDark
                                  ? Colors.white24
                                  : AppColors.textLight)
                              : key == 'ultra'
                                  ? const Color(0xFFD4A017)
                                  : (isDark
                                      ? Colors.white
                                      : AppColors.primary),
                          fontSize: 12,
                          fontWeight: row[key] != '—'
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Referral Card ─────────────────────────────────────────────────────────
  Widget _buildReferralCard(SubscriptionProvider sub, bool isDark) {
    final code = sub.referralCode;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF1A1D30),
                  const Color(0xFF252840)
                ]
              : [
                  const Color(0xFFEEF0FF),
                  const Color(0xFFE4E6F8)
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.people_alt_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Refer Friends, Earn ₹50',
                style: GoogleFonts.outfit(
                  color:
                      isDark ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Share your code. When your friend places their first order, you BOTH get ₹50 in loyalty points.',
            style: GoogleFonts.outfit(
              color: isDark
                  ? Colors.white60
                  : AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (code != null) ...[
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        const Text('Code copied! Share it with friends.'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBg : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color:
                          AppColors.primary.withValues(alpha: 0.3),
                      width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      code,
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: 4,
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                if (auth.currentUserId == null) return;
                final name = auth.user?.fullName ?? 'User';
                await sub.generateReferralCode(
                    auth.currentUserId!, name);
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate My Referral Code'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Plan Card Widget ─────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isCurrentPlan;
  final bool isDark;
  final bool isSubscribing;
  final VoidCallback onTap;
  final VoidCallback onSubscribe;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isCurrentPlan,
    required this.isDark,
    required this.isSubscribing,
    required this.onTap,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final isUltra = plan.name == 'Ultra';
    final isPro = plan.name == 'Pro';

    const ultraGradient = LinearGradient(
      colors: [Color(0xFF0F1E80), Color(0xFF1E3FD8), Color(0xFF2F58FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    const proGradient = LinearGradient(
      colors: [Color(0xFF1E3FD8), Color(0xFF3D6BFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final cardGradient = isUltra
        ? ultraGradient
        : isPro
            ? proGradient
            : null;

    final List<String> perks = isUltra
        ? [
            '👑 Free delivery always',
            '10% cashback on every order',
            '3× loyalty points speed',
            '3 family accounts',
            'Best exclusive deals'
          ]
        : isPro
            ? [
                '⚡ Free delivery always',
                '5% cashback on every order',
                '2× loyalty points speed',
                'Priority customer support'
              ]
            : [
                '✨ Free delivery ≥₹199',
                '1.5× loyalty points speed',
                'Access to Pass deals'
              ];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 210,
        margin: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
        decoration: BoxDecoration(
          gradient:
              isSelected && cardGradient != null ? cardGradient : null,
          color: isSelected && cardGradient == null
              ? (isDark ? AppColors.darkCard : Colors.white)
              : (!isSelected
                  ? (isDark ? AppColors.darkCard : Colors.white)
                  : null),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? (isUltra ? AppColors.accent : AppColors.primaryLight)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.border),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isUltra ? AppColors.accent : AppColors.primary)
                        .withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge
              if (isUltra || isPro)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUltra
                        ? AppColors.accent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    isPro ? 'MOST POPULAR' : '⭐ BEST VALUE',
                    style: GoogleFonts.outfit(
                      color: isSelected
                          ? (isUltra ? AppColors.accent : Colors.white)
                          : AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                plan.name == 'Ultra'
                    ? '👑'
                    : plan.name == 'Pro'
                        ? '⚡'
                        : '✨',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                'Pass ${plan.name}',
                style: GoogleFonts.outfit(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : AppColors.textPrimary),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${plan.priceInr}',
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: 3, left: 3),
                    child: Text(
                      '/month',
                      style: GoogleFonts.outfit(
                        color: isSelected
                            ? Colors.white60
                            : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Perks list
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: perks
                      .map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              p,
                              style: GoogleFonts.outfit(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : (isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary),
                                fontSize: 11.5,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              // Subscribe button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: isCurrentPlan ? null : onSubscribe,
                  style: TextButton.styleFrom(
                    backgroundColor: isCurrentPlan
                        ? Colors.grey.withValues(alpha: 0.3)
                        : isSelected
                            ? Colors.white
                            : AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isSubscribing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.white,
                          ),
                        )
                      : Text(
                          isCurrentPlan ? 'Current Plan' : 'Subscribe',
                          style: GoogleFonts.outfit(
                            color: isCurrentPlan
                                ? Colors.white54
                                : isSelected
                                    ? AppColors.primary
                                    : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
