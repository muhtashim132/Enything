import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

/// A premium, animated role switcher card shown on the profile page.
///
/// Displays all roles the user has registered for, with:
/// - [customer]: always enabled
/// - [seller] / [delivery_partner]: enabled only if verificationStatus == 'verified'
/// - [admin]: enabled, routes to admin password gate
///
/// Unverified shop/rider roles are shown as "locked" (dimmed, non-tappable).
class RoleSwitcherCard extends StatefulWidget {
  const RoleSwitcherCard({super.key});

  @override
  State<RoleSwitcherCard> createState() => _RoleSwitcherCardState();
}

class _RoleSwitcherCardState extends State<RoleSwitcherCard>
    with SingleTickerProviderStateMixin {
  String? _switchingTo;

  // Role metadata — icon, label, emoji
  static const _roleMeta = {
    'customer': (
      icon: Icons.shopping_bag_rounded,
      label: 'Customer',
      emoji: '🛍️',
    ),
    'seller': (
      icon: Icons.storefront_rounded,
      label: 'Seller',
      emoji: '🏪',
    ),
    'delivery_partner': (
      icon: Icons.delivery_dining_rounded,
      label: 'Rider',
      emoji: '🏍️',
    ),
    'admin': (
      icon: Icons.shield_rounded,
      label: 'Admin',
      emoji: '🛡️',
    ),
  };

  bool _isRoleEnabled(UserModel user, String role) {
    if (!user.activeRoles.contains(role)) return false;
    if (role == 'customer' || role == 'admin') return true;
    
    // God Mode: Admins can bypass KYC verification to access any dashboard
    if (user.activeRoles.contains('admin')) return true;
    
    if (role == 'seller') return user.sellerVerificationStatus == 'verified';
    if (role == 'delivery_partner') return user.riderVerificationStatus == 'verified';
    return false;
  }

  /// Returns whether this role is 'pending verification' (in active roles but not verified)
  bool _isRolePendingVerification(UserModel user, String role) {
    if (role == 'customer' || role == 'admin') return false;
    if (!user.activeRoles.contains(role)) return false;
    
    // God Mode: Admins don't get the pending lock UI
    if (user.activeRoles.contains('admin')) return false;
    
    if (role == 'seller') return user.sellerVerificationStatus != 'verified';
    if (role == 'delivery_partner') return user.riderVerificationStatus != 'verified';
    return false;
  }

  Future<void> _switchTo(BuildContext ctx, String role) async {
    final auth = ctx.read<AuthProvider>();
    final user = auth.user;
    if (user == null || _switchingTo != null) return;
    if (role == user.activeSessionRole) return; // already on this role

    HapticFeedback.lightImpact();
    setState(() => _switchingTo = role);

    // Capture navigator BEFORE the async gap
    final navigator = Navigator.of(ctx);

    try {
      await auth.switchSessionRole(role);
    } catch (e) {
      if (mounted) setState(() => _switchingTo = null);
      return;
    }

    if (!mounted) return;
    setState(() => _switchingTo = null);

    // Navigate to the correct dashboard with a fresh stack
    String dest;
    switch (role) {
      case 'seller':
        dest = AppRoutes.sellerDashboard;
      case 'delivery_partner':
        dest = AppRoutes.deliveryDashboard;
      case 'admin':
        dest = AppRoutes.adminPassword;
      default:
        dest = AppRoutes.customerHome;
    }

    navigator.pushNamedAndRemoveUntil(dest, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    // Only show the switcher if the user has more than 1 role
    if (user.activeRoles.length <= 1) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Switch Role',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        _RoleSwitcherRow(
          user: user,
          switchingTo: _switchingTo,
          isDark: isDark,
          isRoleEnabled: _isRoleEnabled,
          isRolePendingVerification: _isRolePendingVerification,
          onSwitch: (role) => _switchTo(context, role),
          roleMeta: _roleMeta,
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ─── Row of Role Cards ────────────────────────────────────────────────────────

class _RoleSwitcherRow extends StatelessWidget {
  final UserModel user;
  final String? switchingTo;
  final bool isDark;
  final bool Function(UserModel, String) isRoleEnabled;
  final bool Function(UserModel, String) isRolePendingVerification;
  final void Function(String) onSwitch;
  final Map<String, ({IconData icon, String label, String emoji})> roleMeta;

  const _RoleSwitcherRow({
    required this.user,
    required this.switchingTo,
    required this.isDark,
    required this.isRoleEnabled,
    required this.isRolePendingVerification,
    required this.onSwitch,
    required this.roleMeta,
  });

  // Ordered role display list
  static const _orderedRoles = [
    'customer',
    'seller',
    'delivery_partner',
    'admin',
  ];

  @override
  Widget build(BuildContext context) {
    // Only show roles the user actually has
    final displayRoles =
        _orderedRoles.where((r) => user.activeRoles.contains(r)).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: displayRoles.map((role) {
          final meta = roleMeta[role]!;
          final isActive = user.activeSessionRole == role;
          final enabled = isRoleEnabled(user, role);
          final isPending = isRolePendingVerification(user, role);
          final isSwitching = switchingTo == role;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _RoleCard(
              role: role,
              label: meta.label,
              emoji: meta.emoji,
              icon: meta.icon,
              isActive: isActive,
              isEnabled: enabled,
              isPending: isPending,
              isSwitching: isSwitching,
              isDark: isDark,
              onTap: enabled && !isActive && switchingTo == null
                  ? () => onSwitch(role)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Individual Role Card ─────────────────────────────────────────────────────

class _RoleCard extends StatefulWidget {
  final String role;
  final String label;
  final String emoji;
  final IconData icon;
  final bool isActive;
  final bool isEnabled;
  final bool isPending;
  final bool isSwitching;
  final bool isDark;
  final VoidCallback? onTap;

  const _RoleCard({
    required this.role,
    required this.label,
    required this.emoji,
    required this.icon,
    required this.isActive,
    required this.isEnabled,
    required this.isPending,
    required this.isSwitching,
    required this.isDark,
    this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.roleGradient(widget.role);
    final roleColor = AppColors.roleColor(widget.role);

    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _pressCtrl.forward() : null,
      onTapUp: widget.onTap != null
          ? (_) {
              _pressCtrl.reverse();
              widget.onTap?.call();
            }
          : null,
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (_, child) => Transform.scale(
          scale: _pressScale.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: 96,
          height: 125,
          decoration: BoxDecoration(
            gradient: widget.isActive ? gradient : null,
            color: widget.isActive
                ? null
                : widget.isDark
                    ? const Color(0xFF1E2236)
                    : const Color(0xFFF0F2FF),
            borderRadius: BorderRadius.circular(22),
            border: widget.isActive
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  )
                : Border.all(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                  ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: roleColor.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                          alpha: widget.isDark ? 0.25 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: widget.isActive
                  ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                  : ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Stack(
                children: [
                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon / Loading / Lock
                        _buildIconArea(roleColor),
                        const SizedBox(height: 8),
                        // Label
                        Text(
                          widget.label,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: widget.isActive
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: widget.isActive
                                ? Colors.white
                                : widget.isEnabled
                                    ? (widget.isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary)
                                    : (widget.isDark
                                        ? Colors.white30
                                        : Colors.black38),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Status badge
                        if (widget.isActive) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'ACTIVE',
                              style: GoogleFonts.outfit(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ] else if (widget.isPending) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Pending',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Shimmer overlay for disabled cards
                  if (!widget.isEnabled && !widget.isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: widget.isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconArea(Color roleColor) {
    if (widget.isSwitching) {
      return SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: widget.isActive ? Colors.white : roleColor,
        ),
      );
    }

    if (!widget.isEnabled && widget.isPending) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 22,
              color: roleColor.withValues(alpha: 0.4),
            ),
          ),
          Positioned(
            right: -4,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.warning,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isDark
                      ? const Color(0xFF1E2236)
                      : const Color(0xFFF0F2FF),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 9,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: widget.isActive
            ? Colors.white.withValues(alpha: 0.22)
            : roleColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          widget.icon,
          size: 22,
          color: widget.isActive ? Colors.white : roleColor,
        ),
      ),
    );
  }
}
