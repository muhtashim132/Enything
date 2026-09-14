import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_categories.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_colors.dart';

/// Calculation model for all seller deductions for a given [category].
class SellerDeductibleBreakdown {
  final String category;
  final double commissionPercent;
  final double gatewayPercent;
  final double tdsPercent;
  final double tcsPercent;
  final double totalDeductiblePercent;
  final double netPayoutPercent;
  final double categoryGstPercent;
  final double gstPassthroughPercent;
  final double netPayoutWithGstPercent;
  final bool isFoodDeemedSupplier;
  final bool isExemptProduce;

  const SellerDeductibleBreakdown({
    required this.category,
    required this.commissionPercent,
    required this.gatewayPercent,
    required this.tdsPercent,
    required this.tcsPercent,
    required this.totalDeductiblePercent,
    required this.netPayoutPercent,
    required this.categoryGstPercent,
    required this.gstPassthroughPercent,
    required this.netPayoutWithGstPercent,
    required this.isFoodDeemedSupplier,
    required this.isExemptProduce,
  });

  factory SellerDeductibleBreakdown.fromCategory(
    String category,
    PlatformConfigProvider? config,
  ) {
    final comm = config?.getCommissionPercentForCategory(category) ?? 5.0;
    final gw = TaxConfig.effectiveGatewayDeductionPercent * 100; // 2.36%
    const tds = TaxConfig.itTdsRate * 100; // 0.10%
    final tcs = TaxConfig.tcsRateForCategory(category) * 100; // 0.50% or 0.00%
    final total = comm + gw + tds + tcs;
    final net = (100.0 - total).clamp(0.0, 100.0);
    final isFood = TaxConfig.isEnythingDeemedSupplier(category);
    final isExempt = category == 'Fruits & Vegs' ||
        category == 'Butcher' ||
        category == 'Fish & Seafood';
    final gstRate = TaxConfig.gstRateForCategory(category) * 100;
    // Section 9(5) Food: Enything collects and remits GST directly. Seller payout has 0% GST passthrough.
    // Non-food: GST is collected from customer on behalf of seller and deposited into seller's bank payout.
    final gstPassthrough = isFood ? 0.0 : gstRate;
    final netWithGst = net + gstPassthrough;

    return SellerDeductibleBreakdown(
      category: category,
      commissionPercent: comm,
      gatewayPercent: gw,
      tdsPercent: tds,
      tcsPercent: tcs,
      totalDeductiblePercent: total,
      netPayoutPercent: net,
      categoryGstPercent: gstRate,
      gstPassthroughPercent: gstPassthrough,
      netPayoutWithGstPercent: netWithGst,
      isFoodDeemedSupplier: isFood,
      isExemptProduce: isExempt,
    );
  }
}

/// A responsive, premium card showing the Total Deductible Percentage
/// and itemized breakdown for sellers.
///
/// Supports:
/// - [isCompact] = true: Sleek card for seller sign-up (CompleteProfilePage)
/// - [isCompact] = false: Rich full section for ShopManagementPage
class SellerDeductibleCard extends StatelessWidget {
  final String category;
  final bool isCompact;
  final VoidCallback? onTap;

  const SellerDeductibleCard({
    super.key,
    required this.category,
    this.isCompact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final config = context.watch<PlatformConfigProvider>();
    final breakdown = SellerDeductibleBreakdown.fromCategory(category, config);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isCompact) {
      return _buildCompactCard(context, breakdown, isDark);
    }
    return _buildExpandedCard(context, breakdown, isDark);
  }

  /// Compact layout tailored for CompleteProfilePage (Sign-up).
  Widget _buildCompactCard(
    BuildContext context,
    SellerDeductibleBreakdown b,
    bool isDark,
  ) {
    final catMap = AppCategories.all.firstWhere(
      (c) => c['name'] == b.category,
      orElse: () => {'name': b.category, 'emoji': '🏷️'},
    );
    final emoji = catMap['emoji'] ?? '🏷️';

    return InkWell(
      onTap: onTap ?? () => showSellerDeductiblesModal(context, category: b.category),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131A3E) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF4C6EF5).withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4C6EF5).withValues(alpha: isDark ? 0.15 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category & Net Payout Badges (Wrapped for small screens)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C6EF5).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          b.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1A2E9E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B8A3E).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF2B8A3E).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF51CF66)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Net Payout: ${b.netPayoutPercent.toStringAsFixed(2)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF51CF66),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Headline Metric
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        'Total Deductible:',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : const Color(0xFF495057),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${b.totalDeductiblePercent.toStringAsFixed(2)}%',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFFFFD43B) : const Color(0xFFE8590C),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 4 Itemized Mini Badges
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _miniChip(
                      width: itemWidth,
                      title: 'Commission',
                      value: '${b.commissionPercent.toStringAsFixed(1)}%',
                      isDark: isDark,
                    ),
                    _miniChip(
                      width: itemWidth,
                      title: 'Gateway (Online)',
                      value: '${b.gatewayPercent.toStringAsFixed(2)}%',
                      isDark: isDark,
                    ),
                    _miniChip(
                      width: itemWidth,
                      title: 'TDS (§194-O)',
                      value: '${b.tdsPercent.toStringAsFixed(2)}%',
                      isDark: isDark,
                    ),
                    _miniChip(
                      width: itemWidth,
                      title: 'TCS (§52)',
                      value: b.tcsPercent == 0.0
                          ? '0.00% (Exempt)'
                          : '${b.tcsPercent.toStringAsFixed(2)}%',
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),

            // ── Payout Summary (Base & With GST) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Estimated Net Payout (Base):',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            color: isDark ? Colors.white70 : const Color(0xFF495057),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${b.netPayoutPercent.toStringAsFixed(2)}%',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2B8A3E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          b.isFoodDeemedSupplier
                              ? 'Estimated Net Payout (with GST):'
                              : 'Estimated Net Payout (with GST)*:',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: isDark ? Colors.white : const Color(0xFF0A0A14),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${b.netPayoutWithGstPercent.toStringAsFixed(2)}%',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2B8A3E),
                        ),
                      ),
                    ],
                  ),
                  if (!b.isFoodDeemedSupplier && b.gstPassthroughPercent > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '*Includes ${b.gstPassthroughPercent.toStringAsFixed(0)}% GST passthrough deposited in your bank for GSTR-3B',
                        style: GoogleFonts.outfit(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    'Tap for details & calculation >',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: const Color(0xFF748FFC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip({
    required double width,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 3,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full expanded section card for ShopManagementPage.
  Widget _buildExpandedCard(
    BuildContext context,
    SellerDeductibleBreakdown b,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C6EF5).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.percent_rounded,
                    color: Color(0xFF4C6EF5),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Fees & Deductibles',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF0A0A14),
                      ),
                    ),
                    Text(
                      'Category: ${b.category}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2B8A3E).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${b.netPayoutPercent.toStringAsFixed(2)}% Net Payout',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B8A3E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Prominent Total Rate Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1A2350), const Color(0xFF0F1535)]
                  : [const Color(0xFFEDF2FF), const Color(0xFFDBE4FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF4C6EF5).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Deductions',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF495057),
                    ),
                  ),
                  Text(
                    '${b.totalDeductiblePercent.toStringAsFixed(2)}%',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark ? const Color(0xFFFFD43B) : const Color(0xFFE8590C),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: onTap ?? () => showSellerDeductiblesModal(context, category: b.category),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4C6EF5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                label: Text('View Details', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Itemized list
        _detailRow(
          icon: Icons.store_rounded,
          title: 'Platform Commission',
          rate: '${b.commissionPercent.toStringAsFixed(1)}%',
          subtitle: 'Admin-configured commission for ${b.category}',
          isDark: isDark,
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.credit_card_rounded,
          title: 'Payment Gateway',
          rate: '${b.gatewayPercent.toStringAsFixed(2)}%',
          subtitle: 'Razorpay UPI/Cards processing (2% + 18% GST)',
          isDark: isDark,
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.account_balance_rounded,
          title: 'Income Tax TDS (§194-O)',
          rate: '${b.tdsPercent.toStringAsFixed(2)}%',
          subtitle: 'Withheld & deposited to your PAN / Form 26AS',
          isDark: isDark,
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.receipt_long_rounded,
          title: 'GST TCS (§52)',
          rate: b.tcsPercent == 0.0
              ? '0.00% (Exempt)'
              : '${b.tcsPercent.toStringAsFixed(2)}%',
          subtitle: b.isFoodDeemedSupplier
              ? 'Section 9(5) Deemed Supplier (Enything remits GST)'
              : (b.isExemptProduce
                  ? 'Exempt 0% GST fresh produce'
                  : 'Claimable credit in your monthly GSTR-2B'),
          isDark: isDark,
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Estimated Net Payout (Base Only)',
          rate: '${b.netPayoutPercent.toStringAsFixed(2)}%',
          subtitle: 'Net product earnings deposited before GST passthrough',
          isDark: isDark,
          color: const Color(0xFF2B8A3E),
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.receipt_rounded,
          title: 'GST Passthrough to Seller',
          rate: b.isFoodDeemedSupplier
              ? '0.00% (ECO §9(5))'
              : (b.isExemptProduce
                  ? '0.00% (Exempt)'
                  : '+${b.gstPassthroughPercent.toStringAsFixed(2)}%'),
          subtitle: b.isFoodDeemedSupplier
              ? 'Enything remits 5% GST directly to Govt under Section 9(5)'
              : (b.isExemptProduce
                  ? '0% GST fresh produce'
                  : 'Collected from customer & deposited to your bank for GSTR-3B'),
          isDark: isDark,
          color: b.isFoodDeemedSupplier ? null : const Color(0xFF2B8A3E),
        ),
        const Divider(height: 16, thickness: 0.5),
        _detailRow(
          icon: Icons.payments_rounded,
          title: 'Estimated Net Payout (with GST)',
          rate: '${b.netPayoutWithGstPercent.toStringAsFixed(2)}%',
          subtitle: b.isFoodDeemedSupplier
              ? 'Total net payout to seller (GST handled by Enything)'
              : 'Total net amount deposited to your bank account',
          isDark: isDark,
          isBold: true,
          color: const Color(0xFF2B8A3E),
        ),
      ],
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String title,
    required String rate,
    required String subtitle,
    required bool isDark,
    Color? color,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? const Color(0xFF4C6EF5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                  color: color ?? (isDark ? Colors.white : Colors.black87),
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          rate,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: color ?? (isDark ? Colors.white : const Color(0xFF0A0A14)),
          ),
        ),
      ],
    );
  }
}

/// Opens a modal bottom sheet displaying full statutory transparency
/// and an interactive payout simulation.
void showSellerDeductiblesModal(BuildContext context, {required String category}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SellerDeductiblesModalSheet(category: category),
  );
}

class _SellerDeductiblesModalSheet extends StatelessWidget {
  final String category;

  const _SellerDeductiblesModalSheet({required this.category});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<PlatformConfigProvider>();
    final b = SellerDeductibleBreakdown.fromCategory(category, config);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Simulation for ₹1,000 order
    const sampleAmount = 1000.0;
    final commAmount = sampleAmount * (b.commissionPercent / 100.0);
    final gwAmount = sampleAmount * (b.gatewayPercent / 100.0);
    final tdsAmount = sampleAmount * (b.tdsPercent / 100.0);
    final tcsAmount = sampleAmount * (b.tcsPercent / 100.0);
    final gstPassthroughAmount = sampleAmount * (b.gstPassthroughPercent / 100.0);
    final totalDeductionsAmount = commAmount + gwAmount + tdsAmount + tcsAmount;
    final netPayoutAmount = sampleAmount - totalDeductionsAmount;
    final netBankDepositAmount = netPayoutAmount + gstPassthroughAmount;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10142D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payout & Fee Structure',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0A0A14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ],
                ),
                Text(
                  'Category: ${b.category} • 100% digital prepaid payments',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // High-level cards
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8590C).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE8590C).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Deductions',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : const Color(0xFF495057),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${b.totalDeductiblePercent.toStringAsFixed(2)}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFFE8590C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B8A3E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF2B8A3E).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Net Payout (with GST)',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : const Color(0xFF495057),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${b.netPayoutWithGstPercent.toStringAsFixed(2)}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF2B8A3E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Order Simulation Box
                Text(
                  'Example Calculation (₹1,000 Order)',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0A0A14),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      _calcRow('Customer Order Base Value', '₹1,000.00', isBold: true, isDark: isDark),
                      const Divider(height: 16),
                      _calcRow(
                        'Platform Commission (${b.commissionPercent.toStringAsFixed(1)}%)',
                        '-₹${commAmount.toStringAsFixed(2)}',
                        isDark: isDark,
                        color: const Color(0xFFFA5252),
                      ),
                      _calcRow(
                        'Payment Gateway (2.36%)',
                        '-₹${gwAmount.toStringAsFixed(2)}',
                        isDark: isDark,
                        color: const Color(0xFFFA5252),
                      ),
                      _calcRow(
                        'Income Tax TDS §194-O (0.10%)',
                        '-₹${tdsAmount.toStringAsFixed(2)}',
                        isDark: isDark,
                        color: const Color(0xFFFA5252),
                      ),
                      _calcRow(
                        'GST TCS §52 (${b.tcsPercent.toStringAsFixed(2)}%)',
                        b.tcsPercent == 0.0 ? '₹0.00 (Exempt)' : '-₹${tcsAmount.toStringAsFixed(2)}',
                        isDark: isDark,
                        color: b.tcsPercent == 0.0 ? null : const Color(0xFFFA5252),
                      ),
                      const Divider(height: 16, thickness: 1.0),
                      _calcRow(
                        'Estimated Net Payout (Base)',
                        '₹${netPayoutAmount.toStringAsFixed(2)} (${b.netPayoutPercent.toStringAsFixed(2)}%)',
                        isBold: true,
                        isDark: isDark,
                        color: const Color(0xFF2B8A3E),
                        fontSize: 13.5,
                      ),
                      const SizedBox(height: 6),
                      _calcRow(
                        b.isFoodDeemedSupplier
                            ? 'GST Handling (§9(5) Food)'
                            : 'GST Passthrough to Seller (${b.categoryGstPercent.toStringAsFixed(0)}%)',
                        b.isFoodDeemedSupplier
                            ? 'Enything remits to Govt'
                            : '+₹${gstPassthroughAmount.toStringAsFixed(2)} (+${b.gstPassthroughPercent.toStringAsFixed(2)}%)',
                        isDark: isDark,
                        color: b.isFoodDeemedSupplier ? null : const Color(0xFF2B8A3E),
                      ),
                      const Divider(height: 16, thickness: 1.2),
                      _calcRow(
                        'Estimated Net Bank Deposit (with GST)',
                        '₹${netBankDepositAmount.toStringAsFixed(2)} (${b.netPayoutWithGstPercent.toStringAsFixed(2)}%)',
                        isBold: true,
                        isDark: isDark,
                        color: const Color(0xFF2B8A3E),
                        fontSize: 15.5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Transparency & Statutory Notes
                Text(
                  'Statutory Notes & Legal Transparency',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0A0A14),
                  ),
                ),
                const SizedBox(height: 12),
                _legalTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Income Tax TDS (§194-O)',
                  body:
                      'E-commerce operators are mandated by law to withhold 0.1% TDS under Section 194-O. This is deposited directly to the government against your PAN and is claimable as tax credit in Form 26AS / AIS.',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _legalTile(
                  icon: Icons.account_balance_outlined,
                  title: 'GST TCS (§52)',
                  body: b.isFoodDeemedSupplier
                      ? 'Section 9(5) Deemed Supplier: For restaurant and prepared food orders, Enything remits GST directly to the government. No TCS is deducted from your payout.'
                      : (b.isExemptProduce
                          ? 'Genuinely Exempt Supplies: Fresh produce, meat, and fish carry 0% GST and are exempt from GST TCS under Section 52.'
                          : '0.50% (0.25% CGST + 0.25% SGST) is collected and filed in GSTR-8. You can claim this as full cash credit in your GSTR-2B return.'),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _legalTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Admin Commission Configuration',
                  body:
                      'Platform commission is managed by Enything administrators. Any adjustments made in the Admin Panel reflect dynamically and immediately across your dashboard.',
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calcRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
    double fontSize = 13,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: isDark ? Colors.white70 : const Color(0xFF495057),
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? (isDark ? Colors.white : const Color(0xFF0A0A14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legalTile({
    required IconData icon,
    required String title,
    required String body,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF4C6EF5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0A0A14),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
