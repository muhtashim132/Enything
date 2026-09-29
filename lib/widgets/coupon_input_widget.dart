import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/coupon_provider.dart';
import '../providers/referral_provider.dart';
import '../theme/app_colors.dart';

class CouponInputWidget extends StatefulWidget {
  final double cartTotal;

  const CouponInputWidget({super.key, required this.cartTotal});

  @override
  State<CouponInputWidget> createState() => _CouponInputWidgetState();
}

class _CouponInputWidgetState extends State<CouponInputWidget>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late AnimationController _successCtrl;
  late Animation<double> _successAnim;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _successAnim = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.easeOutBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final auth = context.read<AuthProvider>();
        final userId = auth.user?.id ?? auth.currentUserId;
        if (userId != null) {
          context.read<ReferralProvider>().loadReferralStats(userId, silent: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply(CouponProvider couponProv) async {
    final applied = await couponProv.validateAndApply(
      code: _controller.text,
      cartTotal: widget.cartTotal,
    );
    if (applied && mounted) {
      _successCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final couponProv = context.watch<CouponProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: couponProv.hasCoupon
                ? AppColors.success.withValues(alpha: 0.4)
                : isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
            width: couponProv.hasCoupon ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: couponProv.hasCoupon
            ? _buildAppliedState(couponProv, isDark)
            : _buildInputState(couponProv, isDark),
      ),
    );
  }

  Widget _buildInputState(CouponProvider couponProv, bool isDark) {
    final refProv = context.watch<ReferralProvider>();
    final activeRewards = refProv.earnedCoupons
        .where((c) => !c.isUsed && !c.isExpired)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'Have a promo code?',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'ENTER CODE',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 13,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0D0D1A)
                      : const Color(0xFFF8F8FC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.discount_rounded,
                      size: 18, color: AppColors.primary),
                ),
                onSubmitted: (_) => _apply(couponProv),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: couponProv.isValidating ? null : () => _apply(couponProv),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: couponProv.isValidating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Apply',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),

        // Error message
        if (couponProv.errorMessage != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 14, color: AppColors.danger),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  couponProv.errorMessage!,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],

        // ── Active Referral Reward Coupons (1-Tap Selection) ──────────────
        if (activeRewards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded,
                        size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Your Referral Rewards (${activeRewards.length} available)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...activeRewards.map(
                    (c) => _buildRewardCouponTile(c, couponProv, isDark)),
                const SizedBox(height: 4),
                Text(
                  '• Strictly 1 referral coupon allowed per order\n• Remaining coupons remain active for future orders',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: isDark
                        ? Colors.white54
                        : const Color(0xFF78350F).withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRewardCouponTile(
    ReferralRewardCoupon coupon,
    CouponProvider couponProv,
    bool isDark,
  ) {
    final bool meetsMinOrder = widget.cartTotal >= coupon.minOrderAmount;
    final bool isApplying =
        couponProv.isValidating && _controller.text == coupon.code;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: meetsMinOrder
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (meetsMinOrder ? const Color(0xFF10B981) : Colors.grey)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '₹${coupon.discountValue.toStringAsFixed(0)} OFF',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: meetsMinOrder ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.code,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  meetsMinOrder
                      ? 'Min order ₹${coupon.minOrderAmount.toStringAsFixed(0)} met • 1 per order'
                      : 'Add ₹${(coupon.minOrderAmount - widget.cartTotal).toStringAsFixed(0)} more to unlock',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: meetsMinOrder
                        ? (isDark ? Colors.white60 : AppColors.textSecondary)
                        : const Color(0xFFD97706),
                    fontWeight:
                        meetsMinOrder ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: (!meetsMinOrder || couponProv.isValidating)
                ? null
                : () async {
                    _controller.text = coupon.code;
                    await _apply(couponProv);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: meetsMinOrder
                    ? const Color(0xFF10B981)
                    : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isApplying
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Apply',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppliedState(CouponProvider couponProv, bool isDark) {
    final coupon = couponProv.appliedCoupon!;
    return ScaleTransition(
      scale: _successAnim,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${coupon.code}" applied!',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  coupon.discountType == 'percent'
                      ? '${coupon.discountValue.toStringAsFixed(0)}% off — saving ₹${coupon.discountAmount.toStringAsFixed(0)}'
                      : '₹${coupon.discountAmount.toStringAsFixed(0)} discount applied',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              couponProv.clearCoupon();
              _controller.clear();
              _successCtrl.reset();
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.white54 : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
