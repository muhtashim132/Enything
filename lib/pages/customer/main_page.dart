import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/responsive_layout.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

import 'home_page.dart';
import 'favorites_page.dart';
import 'order_history_page.dart';
import '../settings/profile_settings_page.dart';
import '../../providers/notification_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class CustomerMainPage extends StatefulWidget {
  const CustomerMainPage({super.key});

  @override
  State<CustomerMainPage> createState() => _CustomerMainPageState();
}

class _CustomerMainPageState extends State<CustomerMainPage> with WidgetsBindingObserver {
  int _navIndex = 0;
  DateTime? _lastBackPressTime;
  final GlobalKey<CustomerHomeViewState> _homeKey = GlobalKey();
  StreamSubscription<String>? _orderCancelledSub;
  Timer? _snackbarDebounceTimer;
  int _pendingAddedCount = 0;
  bool _isCheckingMissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkMissedCancellations();

    // Listen to order cancellation to auto-readd items to cart
    _orderCancelledSub = context.read<NotificationProvider>().onOrderCancelledStream.listen((orderId) async {
      if (mounted) {
        final result = await context.read<CartProvider>().restoreOrderToCart(orderId);
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
      final fortyEightHoursAgo = DateTime.now().subtract(const Duration(hours: 48)).toIso8601String();
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
            if (fatalErrors.length < 2) fatalErrors.add(result.error!);
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
            content: Text('$_pendingAddedCount item(s) restored. Warning: $warningMsg'),
            backgroundColor: const Color(0xFFF59E0B), // Orange
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order cancelled. $_pendingAddedCount item(s) have been restored to your cart.'),
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
    _orderCancelledSub?.cancel();
    _snackbarDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkMissedCancellations();
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
          final scrolled = _homeKey.currentState?.scrollToTopIfNeeded() ?? false;
          if (scrolled) return;

          final now = DateTime.now();
          if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
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
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true, // Let body extend behind bottom nav
        body: IndexedStack(
          index: _navIndex,
          children: [
            CustomerHomeView(key: _homeKey),
            const FavoritesPage(),
            const OrderHistoryPage(),
            const ProfileSettingsPage(),
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0A1260).withValues(alpha: 0.88),
                  const Color(0xFF1E3FD8).withValues(alpha: 0.88),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: CustomerHomeViewState.globalIsFiltering,
                  builder: (context, isFiltering, _) {
                    return _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home', overrideSelected: isFiltering ? false : null);
                  },
                ),
                _buildNavItem(1, Icons.favorite_rounded, Icons.favorite_border_rounded, 'Favs'),
                
                // Prominent Cart inside the pill
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.cart),
                  child: Container(
                    height: 64, // Increased size
                    width: 64, // Increased size
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 28), // Increased icon size
                        if (cart.totalItemCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                cart.totalItemCount > 99 ? '99+' : '${cart.totalItemCount}',
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

                _buildNavItem(2, Icons.receipt_long_rounded, Icons.receipt_long_outlined, 'Orders'),
                _buildNavItem(3, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label, {bool? overrideSelected}) {
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
                      color: isSelected ? Colors.white : Colors.white54,
                      size: 22),
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
