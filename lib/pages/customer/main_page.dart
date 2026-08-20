import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/responsive_layout.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../config/route_observer.dart';

import 'home_page.dart';
import 'favorites_page.dart';
import 'order_history_page.dart';
import '../settings/profile_settings_page.dart';
import '../../providers/notification_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class CustomerMainPage extends StatefulWidget {
  const CustomerMainPage({super.key});

  @override
  State<CustomerMainPage> createState() => _CustomerMainPageState();
}

class _CustomerMainPageState extends State<CustomerMainPage>
    with WidgetsBindingObserver {
  int _navIndex = 0;
  DateTime? _lastBackPressTime;
  final GlobalKey<CustomerHomeViewState> _homeKey = GlobalKey();
  StreamSubscription<String>? _orderCancelledSub;
  Timer? _snackbarDebounceTimer;
  int _pendingAddedCount = 0;
  bool _isCheckingMissed = false;

  final ValueNotifier<int?> _globalPendingTimer = ValueNotifier<int?>(null);
  Timer? _globalCountdown;
  String? _pendingOrderId;
  bool _isGlobalPartialRejection = false;

  void _onRouteChanged() {
    if (currentRouteNotifier.value == AppRoutes.customerHome) {
      _checkPendingOrdersTimer();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentRouteNotifier.addListener(_onRouteChanged);
    _checkMissedCancellations();
    _checkPendingOrdersTimer();

    // Listen to order cancellation to auto-readd items to cart
    _orderCancelledSub = context
        .read<NotificationProvider>()
        .onOrderCancelledStream
        .listen((orderId) async {
      if (mounted) {
        final result =
            await context.read<CartProvider>().restoreOrderToCart(orderId);
        if (!mounted) return; // Prevent Unmounted Context crash!
        if (result.added > 0) {
          _showReaddSnackbar(result.added, warningMsg: result.error);
        } else if (result.error != null) {
          _showErrorSnackbar(result.error!);
        }
      }
    });
  }

  Future<void> _checkMissedCancellations() async {
    if (_isCheckingMissed) return;
    _isCheckingMissed = true;
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch orders from the last 48 hours that were cancelled or rejected
      final fortyEightHoursAgo =
          DateTime.now().subtract(const Duration(hours: 48)).toIso8601String();
      final missedOrders = await supabase
          .from('orders')
          .select('id')
          .eq('customer_id', userId)
          .gte('created_at', fortyEightHoursAgo)
          .inFilter('status', ['cancelled', 'seller_rejected'])
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted) return;
      int totalAdded = 0;
      List<String> fatalErrors = [];
      String? lastWarning;
      final cart = context.read<CartProvider>();

      for (final order in missedOrders) {
        if (!mounted) break;
        final result = await cart.restoreOrderToCart(order['id'] as String);
        if (!mounted) break;
        totalAdded += result.added;
        if (result.error != null) {
          if (result.added == 0) {
            if (!fatalErrors.contains(result.error!) &&
                fatalErrors.length < 2) {
              fatalErrors.add(result.error!);
            }
          } else {
            lastWarning = result.error;
          }
        }
      }

      if (!mounted) return;

      if (totalAdded > 0) {
        if (fatalErrors.isNotEmpty) {
          lastWarning = (lastWarning != null)
              ? '$lastWarning Also: ${fatalErrors.first}'
              : fatalErrors.first;
        }
        _showReaddSnackbar(totalAdded, warningMsg: lastWarning);
      } else if (fatalErrors.isNotEmpty) {
        _showErrorSnackbar(fatalErrors.join(' '));
      }
    } catch (e) {
      debugPrint('CustomerMainPage: _checkMissedCancellations failed: $e');
    } finally {
      _isCheckingMissed = false;
    }
  }

  Future<void> _checkPendingOrdersTimer() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final resp = await supabase
          .from('orders')
          .select(
              'id, payment_deadline, created_at, status, cart_group_id, updated_at')
          .eq('customer_id', userId)
          .inFilter('status', ['awaiting_payment', 'awaiting_acceptance'])
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;
      if (resp.isNotEmpty) {
        final status = resp[0]['status'];
        final deadlineStr = resp[0]['payment_deadline'];
        final createdAtStr = resp[0]['created_at'];
        final cartGroupId = resp[0]['cart_group_id'];

        DateTime? deadline;
        bool isPartialRejection = false;

        // POINT 6: Check sibling orders to determine true partial rejection state and 5-min timer
        if (cartGroupId != null) {
          final siblings = await supabase
              .from('orders')
              .select('status, updated_at')
              .eq('cart_group_id', cartGroupId);

          DateTime? rejectionTime;
          for (var s in siblings) {
            if ({'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled'}.contains(s['status'])) {
              isPartialRejection = true;
              final u = s['updated_at'] != null
                  ? DateTime.tryParse(s['updated_at'])
                  : null;
              if (u != null &&
                  (rejectionTime == null || u.isBefore(rejectionTime))) {
                rejectionTime = u;
              }
            }
          }
          // Issue 2 FIX: If customer already placed a replacement order (Fix 3 wrote
          // this flag), treat as normal awaiting_acceptance — show 3-min countdown,
          // NOT the stale 5-min partial rejection banner.
          if (isPartialRejection) {
            try {
              final prefs = await SharedPreferences.getInstance();
              if (prefs.getBool('partial_rejection_resolved_$cartGroupId') ??
                  false) {
                isPartialRejection =
                    false; // overridden — decision already made
              }
            } catch (_) {}
          }

          // BUG FIX (Bug 4): Read the timer start from SharedPreferences using
          // the SAME key as track_order_page.dart so both timers are always
          // in perfect sync. Fall back to DB updated_at only if key not found.
          if (isPartialRejection) {
            final timerKey = 'partial_rejection_timer_start_$cartGroupId';
            try {
              final prefs = await SharedPreferences.getInstance();
              final storedStartStr = prefs.getString(timerKey);
              if (storedStartStr != null) {
                final storedStart = DateTime.tryParse(storedStartStr);
                if (storedStart != null) {
                  deadline = storedStart.add(const Duration(minutes: 5));
                }
              }
            } catch (_) {}
            // If SharedPrefs key not found, fall back to DB rejection time
            deadline ??= (rejectionTime ??
                    DateTime.tryParse(createdAtStr ?? '') ??
                    DateTime.now().toUtc())
                .add(const Duration(minutes: 5));
          }
        }

        if (!isPartialRejection) {
          if (status == 'awaiting_payment' && deadlineStr != null) {
            deadline = DateTime.parse(deadlineStr).toLocal();
          }
          // Do not set a deadline for 'awaiting_acceptance'.
          // The red urgent banner is for customer actions (payment or partial rejection).
          // For awaiting_acceptance, the customer is waiting on the shop, so the banner vanishes.
        }

        if (deadline != null) {
          _pendingOrderId = resp[0]['id'];

          if (mounted) {
            setState(() {
              _isGlobalPartialRejection = isPartialRejection;
            });
          }

          // BUG FIX: Immediately show the correct remaining time before first tick.
          // We DO NOT use an offset from updated_at, because updated_at is static
          // and causes the time difference to inflate as the clock ticks forward.
          // DateTime.now().toUtc() is exactly what the track order page uses.
          final serverNowInit = DateTime.now().toUtc();
          final initialRemaining = deadline.difference(serverNowInit).inSeconds;
          if (initialRemaining > 0) {
            _globalPendingTimer.value = initialRemaining;
          } else {
            _globalPendingTimer.value = null;
          }

          _globalCountdown?.cancel();
          _globalCountdown = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            final serverNow = DateTime.now().toUtc();
            final remaining = deadline!.difference(serverNow).inSeconds;
            if (remaining > 0) {
              _globalPendingTimer.value = remaining;
            } else {
              _globalPendingTimer.value = null;
              t.cancel();
              // 100x FIX: Re-check server state when timer hits 0 to avoid silent expiration
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _checkPendingOrdersTimer();
              });
            }
          });
        } else {
          _globalPendingTimer.value = null;
          _globalCountdown?.cancel();
        }
      } else {
        _globalPendingTimer.value = null;
        _globalCountdown?.cancel();
      }
    } catch (e) {
      debugPrint('Error checking pending timer: $e');
    }
  }

  void _showErrorSnackbar(String errorMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to restore cancelled order: $errorMsg'),
        backgroundColor: const Color(0xFFEF4444), // Red
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showReaddSnackbar(int added, {String? warningMsg}) {
    _pendingAddedCount += added;
    _snackbarDebounceTimer?.cancel();
    _snackbarDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _pendingAddedCount == 0) return;

      ScaffoldMessenger.of(context).clearSnackBars();

      if (warningMsg != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$_pendingAddedCount item(s) restored. Warning: $warningMsg'),
            backgroundColor: const Color(0xFFF59E0B), // Orange
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Order cancelled. $_pendingAddedCount item(s) have been restored to your cart.'),
            backgroundColor: const Color(0xFF10B981), // Green
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _pendingAddedCount = 0;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    currentRouteNotifier.removeListener(_onRouteChanged);
    _orderCancelledSub?.cancel();
    _snackbarDebounceTimer?.cancel();
    _globalCountdown?.cancel();
    _globalPendingTimer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkMissedCancellations();
      _checkPendingOrdersTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_navIndex != 0) {
          setState(() {
            _navIndex = 0;
          });
        } else {
          if (CustomerHomeViewState.globalIsFiltering.value) {
            _homeKey.currentState?.resetToHome();
            return;
          }
          final scrolled =
              _homeKey.currentState?.scrollToTopIfNeeded() ?? false;
          if (scrolled) return;

          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) >
                  const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // ignore: use_build_context_synchronously
            SystemNavigator.pop(animated: true);
          }
        }
      },
      child: Scaffold(
        extendBody: true, // Let body extend behind bottom nav
        backgroundColor: Theme.of(context)
            .scaffoldBackgroundColor, // Prevent black flash on back nav
        body: Stack(
          children: [
            IndexedStack(
              index: _navIndex,
              children: [
                CustomerHomeView(key: _homeKey),
                const FavoritesPage(),
                const OrderHistoryPage(),
                const ProfileSettingsPage(),
              ],
            ),
            ValueListenableBuilder<int?>(
              valueListenable: _globalPendingTimer,
              builder: (context, secondsLeft, child) {
                if (secondsLeft == null) return const SizedBox.shrink();
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      if (_pendingOrderId != null) {
                        Navigator.pushNamed(context, AppRoutes.trackOrder,
                            arguments: {'orderId': _pendingOrderId});
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isGlobalPartialRejection
                                  ? 'Finish replacing items for your pending order!'
                                  : 'Complete your pending order before time runs out!',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: MaxWidthContainer(
          maxWidth: 600,
          alignment: Alignment.bottomCenter,
          child: _buildFloatingBottomNav(context, cartProvider),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav(BuildContext context, CartProvider cart) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, bottomPadding > 0 ? bottomPadding + 8.0 : 20.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0A1260),
                  Color(0xFF1E3FD8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1E3FD8).withValues(alpha: 0.5),
                    blurRadius: 28,
                    offset: const Offset(0, 8)),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInBack,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: cart.recentNotification != null
                  ? _buildNotificationView(context, cart.recentNotification!)
                  : Row(
                      key: const ValueKey('nav_row'),
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              CustomerHomeViewState.globalIsFiltering,
                          builder: (context, isFiltering, _) {
                            return _buildNavItem(0, Icons.home_rounded,
                                Icons.home_outlined, 'Home',
                                overrideSelected: isFiltering ? false : null);
                          },
                        ),
                        _buildNavItem(1, Icons.favorite_rounded,
                            Icons.favorite_border_rounded, 'Favs'),

                        // Prominent Cart inside the pill
                        GestureDetector(
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.cart),
                          child: Container(
                            height: 64, // Increased size
                            width: 64, // Increased size
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.secondary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondary
                                      .withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.shopping_cart_outlined,
                                    color: Colors.white,
                                    size: 28), // Increased icon size
                                if (cart.totalItemCount > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.danger,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        cart.totalItemCount > 99
                                            ? '99+'
                                            : '${cart.totalItemCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        _buildNavItem(2, Icons.receipt_long_rounded,
                            Icons.receipt_long_outlined, 'Orders'),
                        _buildNavItem(3, Icons.person_rounded,
                            Icons.person_outline_rounded, 'Profile'),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationView(
      BuildContext context, CartNotification notification) {
    return Container(
      key: const ValueKey('notification_view'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  notification.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.cart);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E3FD8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              'View Cart',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: const Color(0xFF1E3FD8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label,
      {bool? overrideSelected}) {
    final isSelected = overrideSelected ?? _navIndex == index;
    return GestureDetector(
      onTap: () {
        if (_navIndex == 0 && index == 0) {
          _homeKey.currentState?.resetToHome();
        }
        setState(() => _navIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: isSelected
              ? Border.all(color: Colors.white.withValues(alpha: 0.2))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 200),
              child: Icon(isSelected ? activeIcon : inactiveIcon,
                  color: isSelected ? Colors.white : Colors.white54, size: 22),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.outfit(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
