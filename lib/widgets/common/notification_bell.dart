import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

/// A bell icon that shows unread count badge and opens the notification panel.
class NotificationBell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final unread = notifProvider.unreadCount;

    return GestureDetector(
      onTap: () => _showNotificationPanel(context, notifProvider),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: containerColor ?? const Color(0xFFF0F0F8),
          shape: BoxShape.circle,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                unread > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_outlined,
                color: iconColor ?? AppColors.textPrimary,
                size: 20,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: badgeColor ?? AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
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
          ],
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
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
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // List
          Expanded(
            child: notifications.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, indent: 72, endIndent: 20),
                    itemBuilder: (ctx, i) =>
                        _NotificationTile(notification: notifications[i],
                         onTap: notifications[i].orderId != null
                            ? () {
                                Navigator.pop(ctx);
                                Navigator.pushNamed(
                                  ctx,
                                  AppRoutes.trackOrder,
                                  arguments: {'orderId': notifications[i].orderId},
                                );
                              }
                            : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔔', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: GoogleFonts.outfit(
                fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll be notified when your order status changes.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  const _NotificationTile({required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: notification.isRead ? Colors.transparent : AppColors.primary.withValues(alpha: 0.04),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
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
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: Colors.grey.shade400,
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
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
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
