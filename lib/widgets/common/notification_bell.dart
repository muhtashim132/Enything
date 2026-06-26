import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
import '../../config/routes.dart';

/// A bell icon that shows unread count badge and opens the notification panel.
class NotificationBell extends StatefulWidget {
  final Color? iconColor;
  final Color? badgeColor;
  final Color? containerColor;

  const NotificationBell({
    super.key,
    this.iconColor,
    this.badgeColor,
    this.containerColor,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  int _lastUnread = 0;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.06, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake(int unread) {
    if (unread > _lastUnread && unread > 0) {
      _shakeController.forward(from: 0);
    }
    _lastUnread = unread;
  }

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final unread = notifProvider.unreadCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Trigger shake when new notification arrives
    WidgetsBinding.instance.addPostFrameCallback((_) => _triggerShake(unread));

    return GestureDetector(
      onTap: () => _showNotificationPanel(context, notifProvider),
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          return Transform.rotate(
            angle: _shakeAnim.value,
            child: child,
          );
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.containerColor ??
                (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFF0F0F8)),
            shape: BoxShape.circle,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: AnimatedSwitcher(
                  duration: PremiumAnimations.fast,
                  child: Icon(
                    key: ValueKey(unread > 0),
                    unread > 0
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_outlined,
                    color: widget.iconColor ??
                        (isDark ? Colors.white70 : AppColors.textPrimary),
                    size: 20,
                  ),
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: AnimatedScale(
                    scale: unread > 0 ? 1.0 : 0.0,
                    duration: PremiumAnimations.normal,
                    curve: Curves.elasticOut,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: widget.badgeColor ?? AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF12121A) : Colors.white,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.danger.withValues(alpha: 0.5),
                            blurRadius: 6,
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
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

  void _showNotificationPanel(
      BuildContext context, NotificationProvider provider) {
    provider.markAllRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NotificationPanel(provider: provider),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  final NotificationProvider provider;
  const _NotificationPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final notifications = provider.notifications;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: PremiumShadows.elevated(isDark: isDark),
      ),
      child: Column(
        children: [
          // Premium drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (notifications.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      provider.clearAll();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Clear all',
                      style: GoogleFonts.outfit(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),

          Divider(
              height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.divider),

          // List
          Expanded(
            child: notifications.isEmpty
                ? _buildEmpty(isDark)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 72,
                        endIndent: 20,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : AppColors.divider),
                    itemBuilder: (ctx, i) => _NotificationTile(
                        notification: notifications[i],
                        isDark: isDark,
                        onTap: notifications[i].orderId != null
                            ? () {
                                Navigator.pop(ctx);
                                Navigator.pushNamed(
                                  ctx,
                                  AppRoutes.trackOrder,
                                  arguments: {
                                    'orderId': notifications[i].orderId
                                  },
                                );
                              }
                            : null),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.primary.withValues(alpha: 0.06),
            ),
            child: const Center(
              child: Text('🔔', style: TextStyle(fontSize: 36)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No notifications yet',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "You'll be notified when your order status changes.",
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white38 : Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final bool isDark;
  const _NotificationTile(
      {required this.notification, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: PremiumAnimations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: notification.isRead
            ? Colors.transparent
            : AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.04),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                    AppColors.primaryLight.withValues(alpha: isDark ? 0.15 : 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _iconForTitle(notification.title),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 6,
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _iconForTitle(String title) {
    if (title.startsWith('🔔')) return '🔔';
    if (title.startsWith('✅')) return '✅';
    if (title.startsWith('❌')) return '❌';
    if (title.startsWith('🎉')) return '🎉';
    if (title.startsWith('🚚')) return '🚚';
    if (title.startsWith('🛍️')) return '🛍️';
    if (title.startsWith('🚀')) return '🚀';
    if (title.startsWith('🛵')) return '🛵';
    if (title.startsWith('📦')) return '📦';
    if (title.startsWith('👨')) return '👨‍🍳';
    if (title.startsWith('😔')) return '😔';
    return '📬';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
