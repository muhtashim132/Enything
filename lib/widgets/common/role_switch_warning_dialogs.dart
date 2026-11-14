import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

enum RiderSwitchAction { cancel, proceed }

enum SellerSwitchAction { cancel, pauseAndSwitch, keepOpenAndSwitch }

/// Industrial-standard, 100x forensic warning dialogs shown when a Seller or Rider
/// switches to the Customer Dashboard.
class RoleSwitchWarningDialogs {
  /// Shows warning when a delivery partner switches to customer mode.
  static Future<RiderSwitchAction?> showRiderWarning(
    BuildContext context, {
    required bool hasActiveDeliveries,
    required int activeDeliveriesCount,
    required bool isOnline,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<RiderSwitchAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: isDark ? const Color(0xFF1E2138) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: hasActiveDeliveries
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : (isDark ? Colors.white12 : Colors.black12),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon Header with glowing halo
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasActiveDeliveries
                        ? AppColors.danger.withValues(alpha: 0.15)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: (hasActiveDeliveries
                                ? AppColors.danger
                                : const Color(0xFFF59E0B))
                            .withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      hasActiveDeliveries
                          ? Icons.warning_amber_rounded
                          : Icons.power_settings_new_rounded,
                      size: 34,
                      color: hasActiveDeliveries
                          ? AppColors.danger
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Text(
                  hasActiveDeliveries
                      ? 'Active Deliveries in Progress'
                      : 'Rider Duty Will Be Set to Offline',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),

                // Active orders badge if present
                if (hasActiveDeliveries) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delivery_dining_rounded,
                            size: 16, color: AppColors.danger),
                        const SizedBox(width: 6),
                        Text(
                          '$activeDeliveriesCount active delivery assigned',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Body description
                Text(
                  hasActiveDeliveries
                      ? 'You have customer deliveries currently assigned to you. Switching to Customer Dashboard will turn OFF your duty toggle and stop background GPS broadcasting, but you remain strictly responsible for completing these orders.'
                      : 'Switching to Customer Dashboard will turn off your duty toggle and set your status to Offline. You will not receive any new delivery orders until you switch back and turn your toggle ON.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),

                // Status transformation indicator card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildStatusRow(
                        'Duty Status',
                        '🟢 Online',
                        '🔴 Offline',
                        isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildStatusRow(
                        'Live GPS',
                        '📍 Broadcasting',
                        '⏸️ Stopped',
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, RiderSwitchAction.proceed),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasActiveDeliveries
                          ? AppColors.danger
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      hasActiveDeliveries
                          ? 'I Understand, Switch to Customer'
                          : 'Go Offline & Switch to Customer',
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, RiderSwitchAction.cancel),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        isDark ? Colors.white60 : AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    hasActiveDeliveries
                        ? 'Stay on Delivery Dashboard'
                        : 'Stay Online as Rider',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows warning when a seller switches to customer mode.
  static Future<SellerSwitchAction?> showSellerWarning(
    BuildContext context, {
    required String shopName,
    required bool isAcceptingOrders,
    required int activeOrdersCount,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<SellerSwitchAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: isDark ? const Color(0xFF1E2138) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Store Icon Header
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Text(
                  'Store is Currently Open',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),

                // Shop name pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    shopName.isNotEmpty ? shopName : 'Your Store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // In-Flight Kitchen Orders Alert if any
                if (activeOrdersCount > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.soup_kitchen_rounded,
                            size: 16, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Text(
                          '$activeOrdersCount kitchen order(s) in preparation',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Body text
                Text(
                  'Your store is currently live and accepting customer orders. While you browse as a Customer, how would you like to handle incoming orders?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),

                // Option 1: Pause Store & Switch (Recommended)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        Navigator.pop(ctx, SellerSwitchAction.pauseAndSwitch),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Icon(Icons.pause_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Pause Store & Switch',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Recommended',
                                        style: GoogleFonts.outfit(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Temporarily pauses new orders while you shop',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 2: Keep Store Open & Switch
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(
                        ctx, SellerSwitchAction.keepOpenAndSwitch),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Icon(Icons.bolt_rounded,
                                  color: Color(0xFF10B981), size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Keep Store Open & Switch',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Store remains live; listen for incoming chimes',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cancel Button
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, SellerSwitchAction.cancel),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        isDark ? Colors.white60 : AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Cancel (Stay on Seller Dashboard)',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildStatusRow(
      String label, String from, String to, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : AppColors.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              from,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded,
                size: 12, color: isDark ? Colors.white38 : AppColors.textLight),
            const SizedBox(width: 6),
            Text(
              to,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
