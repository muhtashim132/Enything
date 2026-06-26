import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/coupon_provider.dart';
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
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
      ],
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
