import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/rbac_provider.dart';
import '../../pages/admin/rbac/forbidden_page.dart';

// ═══════════════════════════════════════════════════════════════
// PERMISSION GUARD WIDGET
// Wraps any child with a permission check.
// Shows ForbiddenPage (or custom fallback) if check fails.
// ═══════════════════════════════════════════════════════════════
class PermissionGuard extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;
  final bool showForbidden;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showForbidden = false,
  });

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    if (rbac.can(permission)) return child;
    if (showForbidden) return const ForbiddenPage();
    return fallback ?? const SizedBox.shrink();
  }
}

// ─── Convenience: hide widget if no permission ──────────────────
class ShowIfCan extends StatelessWidget {
  final String permission;
  final Widget child;
  const ShowIfCan({super.key, required this.permission, required this.child});

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    return rbac.can(permission) ? child : const SizedBox.shrink();
  }
}

// ═══════════════════════════════════════════════════════════════
// ROLE BADGE
// ═══════════════════════════════════════════════════════════════
class RoleBadge extends StatelessWidget {
  final String name;
  final Color color;
  final bool isSystem;
  final bool small;

  const RoleBadge({
    super.key,
    required this.name,
    required this.color,
    this.isSystem = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.15);
    final fontSize = small ? 9.0 : 11.0;
    final padding = small
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSystem) ...[
            Icon(Icons.verified_rounded, color: color, size: small ? 8 : 10),
            SizedBox(width: small ? 3 : 4),
          ],
          Text(
            name,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// USER STATUS BADGE
// ═══════════════════════════════════════════════════════════════
class UserStatusBadge extends StatelessWidget {
  final bool isActive;
  final bool isSuspended;
  final bool small;

  const UserStatusBadge({
    super.key,
    required this.isActive,
    required this.isSuspended,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = isSuspended
        ? ('Suspended', const Color(0xFFFF5722))
        : isActive
            ? ('Active', const Color(0xFF4CAF50))
            : ('Inactive', const Color(0xFF9E9E9E));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: small ? 5 : 6,
            height: small ? 5 : 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: small ? 4 : 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: small ? 9 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PERMISSION CHECKBOX TILE
// ═══════════════════════════════════════════════════════════════
class PermissionCheckboxTile extends StatelessWidget {
  final String code;
  final String name;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  const PermissionCheckboxTile({
    super.key,
    required this.code,
    required this.name,
    required this.description,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: const Color(0xFF8B2FC9),
                side: BorderSide(
                  color: enabled ? Colors.white30 : Colors.white12,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.outfit(
                      color: enabled ? const Color(0xDEFFFFFF) : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    code,
                    style: GoogleFonts.outfit(
                      color: enabled ? Colors.white38 : Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PERMISSION GROUP CARD
// ═══════════════════════════════════════════════════════════════
class PermissionGroupCard extends StatefulWidget {
  final String module;
  final List<Map<String, String>> permissions; // {code, name}
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  const PermissionGroupCard({
    super.key,
    required this.module,
    required this.permissions,
    required this.selected,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  State<PermissionGroupCard> createState() => _PermissionGroupCardState();
}

class _PermissionGroupCardState extends State<PermissionGroupCard> {
  bool _expanded = false;

  bool get _allSelected =>
      widget.permissions.every((p) => widget.selected.contains(p['code']));

  void _toggleAll() {
    final updated = Set<String>.from(widget.selected);
    if (_allSelected) {
      for (final p in widget.permissions) {
        updated.remove(p['code']);
      }
    } else {
      for (final p in widget.permissions) {
        updated.add(p['code']!);
      }
    }
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final moduleColor = _moduleColor(widget.module);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: moduleColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _moduleIcon(widget.module),
                      color: moduleColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.module,
                          style: GoogleFonts.outfit(
                            color: const Color(0xDEFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.permissions.where((p) => widget.selected.contains(p['code'])).length}/${widget.permissions.length} selected',
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.enabled)
                    GestureDetector(
                      onTap: _toggleAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _allSelected
                              ? moduleColor.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _allSelected
                                ? moduleColor.withValues(alpha: 0.5)
                                : Colors.white12,
                          ),
                        ),
                        child: Text(
                          _allSelected ? 'Deselect All' : 'Select All',
                          style: GoogleFonts.outfit(
                            color: _allSelected ? moduleColor : Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                children: widget.permissions.map((p) {
                  return PermissionCheckboxTile(
                    code: p['code']!,
                    name: p['name']!,
                    description: p['code']!,
                    value: widget.selected.contains(p['code']),
                    enabled: widget.enabled,
                    onChanged: (v) {
                      final updated = Set<String>.from(widget.selected);
                      if (v == true) {
                        updated.add(p['code']!);
                      } else {
                        updated.remove(p['code']);
                      }
                      widget.onChanged(updated);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Color _moduleColor(String module) {
    const colors = {
      'Dashboard': Color(0xFF8B2FC9),
      'Orders': Color(0xFF2196F3),
      'Customers': Color(0xFF4CAF50),
      'Sellers': Color(0xFFFF9800),
      'Riders': Color(0xFF00BCD4),
      'Payments': Color(0xFFE91E63),
      'Withdrawals': Color(0xFF9C27B0),
      'Marketing': Color(0xFFFF5722),
      'Support': Color(0xFF009688),
      'Finance': Color(0xFFF44336),
      'Analytics': Color(0xFF607D8B),
      'Settings': Color(0xFF795548),
      'Roles': Color(0xFFF4C542),
      'Audit': Color(0xFF3F51B5),
      'System': Color(0xFF9E9E9E),
    };
    return colors[module] ?? const Color(0xFF8B2FC9);
  }

  IconData _moduleIcon(String module) {
    const icons = {
      'Dashboard': Icons.dashboard_rounded,
      'Orders': Icons.receipt_long_rounded,
      'Customers': Icons.people_rounded,
      'Sellers': Icons.store_rounded,
      'Riders': Icons.delivery_dining_rounded,
      'Payments': Icons.payment_rounded,
      'Withdrawals': Icons.account_balance_wallet_rounded,
      'Marketing': Icons.campaign_rounded,
      'Support': Icons.support_agent_rounded,
      'Finance': Icons.account_balance_rounded,
      'Analytics': Icons.bar_chart_rounded,
      'Settings': Icons.settings_rounded,
      'Roles': Icons.admin_panel_settings_rounded,
      'Audit': Icons.history_rounded,
      'System': Icons.dns_rounded,
    };
    return icons[module] ?? Icons.lock_rounded;
  }
}

// ═══════════════════════════════════════════════════════════════
// ACCESS DENIED CARD (inline)
// ═══════════════════════════════════════════════════════════════
class AccessDeniedCard extends StatelessWidget {
  final String permission;
  final String? message;

  const AccessDeniedCard({
    super.key,
    required this.permission,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFFFF5722), size: 48),
            const SizedBox(height: 16),
            Text(
              'Access Denied',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ??
                  'You don\'t have permission to perform this action.\nRequired: $permission',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CONFIRM ACTION DIALOG
// ═══════════════════════════════════════════════════════════════
class ConfirmActionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm;

  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.confirmColor = const Color(0xFF8B2FC9),
    required this.onConfirm,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    Color confirmColor = const Color(0xFF8B2FC9),
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => ConfirmActionDialog(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            confirmColor: confirmColor,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1030),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel', style: GoogleFonts.outfit()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                      onConfirm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      confirmLabel,
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w700),
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
}

// ═══════════════════════════════════════════════════════════════
// LOADING SKELETON
// ═══════════════════════════════════════════════════════════════
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.10),
            _anim.value,
          ),
        ),
      ),
    );
  }
}
