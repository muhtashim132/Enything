import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/platform_config_provider.dart';

import '../../providers/recently_viewed_provider.dart';
import '../../providers/referral_provider.dart';
import '../../providers/cart_provider.dart';

import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../config/app_categories.dart';
import '../../utils/delivery_calculator.dart';
import '../../utils/responsive_layout.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../widgets/product_search_card.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../widgets/common/notification_bell.dart';
import '../../widgets/common/animated_search_ticker.dart';
import '../../widgets/3d/perspective_card.dart';
import '../../theme/sensory_haptics.dart';
import '../../widgets/address_picker_sheet.dart';
import 'all_listings_page.dart';

class CustomerHomeView extends StatefulWidget {
  const CustomerHomeView({super.key});

  @override
  State<CustomerHomeView> createState() => CustomerHomeViewState();
}

enum _SortMode { relevant, bestRating, priceLow, priceHigh, discount, nearest }

class CustomerHomeViewState extends State<CustomerHomeView>
    with SingleTickerProviderStateMixin {
  static final ValueNotifier<bool> globalIsFiltering = ValueNotifier(false);

  void resetToHome() {
    if (!mounted) return;
    setState(() {
      _selectedTabIndex = -1;
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
      _selectedFilterCategories.clear();
      _selectedSizes.clear();
      _searchQuery = '';
      _searchController.clear();
    });
    _loadAllData();
  }

  SupabaseClient get _supabase => Supabase.instance.client;
  int _selectedTabIndex = -1; // -1 = no tab selected (show ALL)
  String? _comingSoonMessage;
  String? _comingSoonSubMessage;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _searchError = false;
  String _searchErrorMessage = '';
  int _shopsDisplayLimit = 3;
  int _productsDisplayLimit = 6;
  int _searchShopsDisplayLimit = 12;
  int _searchProductsDisplayLimit = 10;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _searchProductResults = [];
  Map<String, ShopModel> _searchProductShops = {};
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
  String _searchQuery = '';
  String _selectedSearchDemographic = 'All';
  _SortMode _sortMode = _SortMode.relevant;
  final _searchController = TextEditingController();
  final Set<String> _selectedFilterCategories = {};
  final Set<String> _selectedSizes = {};
  final Set<String> _cachedAvailableSizes = {};

  static const Map<String, List<String>> _searchKeywords = {
    'Food': [
      'food',
      'eat',
      'hungry',
      'pizza',
      'burger',
      'meal',
      'restaurant',
      'fast food',
      'biryani',
      'chicken',
      'mutton',
      'kebab',
      'fries'
    ],
    'Grocery': [
      'grocery',
      'milk',
      'bread',
      'eggs',
      'supermarket',
      'ration',
      'vegetables',
      'fruits',
      'apple',
      'banana',
      'meat',
      'beef',
      'dal',
      'rice'
    ],
    'Pharmacy': [
      'pharmacy',
      'medicine',
      'pill',
      'tablet',
      'syrup',
      'medical',
      'health',
      'drug',
      'panadol',
      'paracetamol',
      'clinic',
      'doctor'
    ],
    'Clothing': [
      'clothing',
      'clothes',
      'shirt',
      'pant',
      'shoes',
      'fashion',
      'apparel',
      'wear',
      'dress',
      'tshirt',
      'jeans',
      'jacket',
      'sneakers'
    ],
    'Electronics': [
      'electronics',
      'mobile',
      'phone',
      'laptop',
      'charger',
      'gadget',
      'device',
      'computer',
      'earbuds',
      'headphones',
      'cable'
    ],
  };
  // Debounce timer for GPS listener to prevent race conditions
  Timer? _locationDebounceTimer;

  int _compareAvailability(
      ProductModel a, ProductModel b, Map<String, ShopModel> shops) {
    final sA = shops[a.id];
    final sB = shops[b.id];
    final availA = a.isAvailable && (sA?.isOpenRightNow ?? true);
    final availB = b.isAvailable && (sB?.isOpenRightNow ?? true);
    if (availA && !availB) return -1;
    if (!availA && availB) return 1;
    return 0;
  }

  /// Returns search product results sorted by the current _sortMode.
  List<ProductModel> get _sortedProductResults {
    var list = List<ProductModel>.from(_searchProductResults);
    list.sort((a, b) {
      final availCmp = _compareAvailability(a, b, _searchProductShops);
      if (availCmp != 0) return availCmp;

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.priceLow:
          return a.price.compareTo(b.price);
        case _SortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _SortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
        case _SortMode.nearest:
          final sA = _searchProductShops[a.id];
          final sB = _searchProductShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _SortMode.relevant:
          return 0; // Maintain original order
      }
    });
    return list;
  }

  /// Returns normal product results sorted by the current _sortMode.
  List<ProductModel> get _sortedNormalProducts {
    var list = List<ProductModel>.from(_products);
    list.sort((a, b) {
      final availCmp = _compareAvailability(a, b, _productShops);
      if (availCmp != 0) return availCmp;

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.priceLow:
          return a.price.compareTo(b.price);
        case _SortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _SortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
        case _SortMode.nearest:
          final sA = _productShops[a.id];
          final sB = _productShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _SortMode.relevant:
          return b.rating
              .compareTo(a.rating); // Default rating sort for relevant
      }
    });
    return list;
  }

  /// Returns search shop results sorted by the current _sortMode.
  List<ShopModel> get _sortedShopResults {
    final list = List<ShopModel>.from(_searchResults);
    switch (_sortMode) {
      case _SortMode.bestRating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      default:
        list.sort((a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity));
        break;
    }
    return list;
  }

  /// Returns normal shop results sorted by the current _sortMode.
  List<ShopModel> get _sortedNormalShops {
    final list = List<ShopModel>.from(_shops);
    switch (_sortMode) {
      case _SortMode.bestRating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case _SortMode.nearest:
      case _SortMode.priceLow:
      case _SortMode.priceHigh:
      case _SortMode.discount:
      case _SortMode.relevant:
        list.sort((a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity));
        break;
    }
    return list;
  }

  // Track if the very first load has completed (shimmer only on first load)
  bool _hasLoadedOnce = false;
  // Phase 25 Fix: Atomic State Tracking to prevent Tab Desync and Overload
  int _fetchId = 0;
  bool _isFetching = false;

  // ── Industrial-standard retry state (Issue 2 fix) ────────────────────────
  // Tracks consecutive transient failures so we can backoff exponentially.
  // Resets to 0 on any successful data load.
  int _loadRetryCount = 0;
  static const int _maxLoadRetries = 3;
  Timer? _retryTimer;

  // Banner carousel
  final PageController _bannerController = PageController();
  final ValueNotifier<int> _bannerIndex = ValueNotifier<int>(0);
  Timer? _bannerTimer;
  bool _isBannerHovered = false;
  Timer? _searchDebounce;

  // Location Required block
  final GlobalKey _locationRequiredKey = GlobalKey();
  late AnimationController _locationGlowCtrl;
  late Animation<double> _locationGlowAnim;

  // ── Trending Strip auto-scroll ──────────────────────────────────────────
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _trendingScrollController = ScrollController();
  Timer? _trendingScrollTimer;

  // Dynamic trending keywords fetched from DB (real order data).
  // Falls back to _staticFallbackKeywords if DB returns nothing or on error.
  List<Map<String, dynamic>> _dynamicTrendingKeywords = [];

  // Static fallback shown until/if DB data arrives or when DB is empty.
  static const List<Map<String, dynamic>> _staticFallbackKeywords = [
    {'label': 'Pizza', 'emoji': '🍕'},
    {'label': 'Milk', 'emoji': '🥛'},
    {'label': 'Burger', 'emoji': '🍔'},
    {'label': 'Chicken', 'emoji': '🍗'},
    {'label': 'Paracetamol', 'emoji': '💊'},
    {'label': 'Eggs', 'emoji': '🥚'},
    {'label': 'Bread', 'emoji': '🍞'},
    {'label': 'Biryani', 'emoji': '🍛'},
    {'label': 'Shoes', 'emoji': '👟'},
    {'label': 'Mobile', 'emoji': '📱'},
    {'label': 'Dal', 'emoji': '🫘'},
    {'label': 'Kebab', 'emoji': '🥙'},
  ];

  // Helper: pick a relevant emoji for a product name based on keywords.
  // Purely cosmetic — no logic impact.
  static String _emojiForKeyword(String label) {
    final l = label.toLowerCase();
    if (l.contains('pizza')) {
      return '🍕';
    }
    if (l.contains('burger')) {
      return '🍔';
    }
    if (l.contains('chicken')) {
      return '🍗';
    }
    if (l.contains('milk')) {
      return '🥛';
    }
    if (l.contains('egg')) {
      return '🥚';
    }
    if (l.contains('bread')) {
      return '🍞';
    }
    if (l.contains('biryani') || l.contains('rice')) {
      return '🍛';
    }
    if (l.contains('dal') || l.contains('daal')) {
      return '🫘';
    }
    if (l.contains('kebab') || l.contains('kabab')) {
      return '🥙';
    }
    if (l.contains('tea') || l.contains('chai')) {
      return '🍵';
    }
    if (l.contains('coffee')) {
      return '☕';
    }
    if (l.contains('juice')) {
      return '🍹';
    }
    if (l.contains('water')) {
      return '💧';
    }
    if (l.contains('fish')) {
      return '🐟';
    }
    if (l.contains('mutton') || l.contains('lamb')) {
      return '🥩';
    }
    if (l.contains('paneer')) {
      return '🧀';
    }
    if (l.contains('roti') || l.contains('naan') || l.contains('paratha')) {
      return '🫓';
    }
    if (l.contains('cake') || l.contains('sweet') || l.contains('mithai')) {
      return '🎂';
    }
    if (l.contains('medicine') ||
        l.contains('tablet') ||
        l.contains('capsule') ||
        l.contains('syrup') ||
        l.contains('paracetamol')) {
      return '💊';
    }
    if (l.contains('shoe') || l.contains('sandal')) {
      return '👟';
    }
    if (l.contains('mobile') || l.contains('phone')) {
      return '📱';
    }
    if (l.contains('shirt') || l.contains('cloth') || l.contains('dress')) {
      return '👕';
    }
    if (l.contains('soap') || l.contains('shampoo') || l.contains('cream')) {
      return '🧴';
    }
    if (l.contains('fruit') || l.contains('apple') || l.contains('mango')) {
      return '🍎';
    }
    if (l.contains('veg') || l.contains('sabzi')) {
      return '🥬';
    }
    if (l.contains('ice cream') || l.contains('icecream')) {
      return '🍨';
    }
    return '🛒'; // default: shopping bag
  }

  bool _pendingLocationUpdate = false;

  /// True when a food-type tab is currently selected.
  bool get _isFoodTab {
    if (_selectedTabIndex < 0) return false;
    final cats = _categories;
    if (_selectedTabIndex >= cats.length) return false;
    final name = cats[_selectedTabIndex]['name'] as String;
    return name == 'Food';
  }

  // ── Category tabs: filtered by admin-disabled categories (Additive) ──────
  // This is a getter so it reacts to PlatformConfigProvider changes.
  List<Map<String, dynamic>> get _categories {
    final config = context.read<PlatformConfigProvider>();
    const allTabs = [
      {
        'name': 'Food',
        'emoji': '🍔',
        'grad': [Color(0xFFFF6B6B), Color(0xFFEE5A24)]
      },
      {
        'name': 'Supermarket / Hypermarket',
        'emoji': '🏬',
        'grad': [Color(0xFF51CF66), Color(0xFF2F9E44)]
      },
      {
        'name': 'Pharmacy',
        'emoji': '💊',
        'grad': [Color(0xFF4C6EF5), Color(0xFF364FC7)]
      },
      {
        'name': 'Clothing',
        'emoji': '👕',
        'grad': [Color(0xFFFF8C42), Color(0xFFE8590C)]
      },
      {
        'name': 'Electronics',
        'emoji': '📱',
        'grad': [Color(0xFFCC5DE8), Color(0xFF9C36B5)]
      },
      {
        'name': 'More',
        'emoji': '🛍️',
        'grad': [Color(0xFF20C997), Color(0xFF0CA678)]
      },
    ];
    // Keep a tab only if at least one of its subcategories is active
    return allTabs.where((tab) {
      final name = tab['name'] as String;
      final subcategories = _tabCategories[name] ?? [name];
      return subcategories.any((c) => config.isActiveCategory(c));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _locationGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _locationGlowAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _locationGlowCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationAndLoad();
    });
    _startNotifications();
    _checkActiveOrders();
    // Subscribe to live GPS updates so distance filter stays accurate
    _startLiveLocationUpdates();
    // Auto-scroll banner every 4 seconds (pauses on hover/touch)
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients || _isBannerHovered) return;
      final next = (_bannerIndex.value + 1) % 3;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
    // Auto-scroll trending strip + fetch real trending keywords
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTrendingScroll();
      _loadTrendingKeywords(); // fetch real trending from DB (additive, no SQL change)
    });
    // Fetch favorites, saved address, and subscription state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId != null) {
        context.read<FavoritesProvider>().fetchFavorites(auth.currentUserId!);
        context.read<LocationProvider>().loadAddressFromDb(auth.currentUserId!);
        context.read<ReferralProvider>().init(auth.currentUserId!);
      }
    });
  }

  void _startTrendingScroll() {
    _trendingScrollTimer?.cancel();
    // Slowly auto-scroll the trending strip, wrap around when reaching end
    _trendingScrollTimer =
        Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted || !_trendingScrollController.hasClients) return;
      final max = _trendingScrollController.position.maxScrollExtent;
      if (max <= 0) return;
      final current = _trendingScrollController.offset;
      if (current >= max) {
        // Jump silently back to start for infinite loop effect
        _trendingScrollController.jumpTo(0);
      } else {
        _trendingScrollController.jumpTo(current + 0.6);
      }
    });
  }

  /// Fetches real trending product names from DB (last 30 days, delivered orders).
  /// Purely additive — new read-only RPC, zero changes to existing SQL logic.
  /// On error or empty result, falls back to the static curated list.
  Future<void> _loadTrendingKeywords() async {
    try {
      final locationProvider = context.read<LocationProvider>();
      final lat = locationProvider.currentLocation?.latitude;
      final lng = locationProvider.currentLocation?.longitude;

      dynamic response;
      if (locationProvider.hasLocation && lat != null && lng != null) {
        final disabledCats =
            context.read<PlatformConfigProvider>().disabledCategories.toList();
        response =
            await _supabase.rpc('get_trending_keywords_geospatial', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 15,
          'p_disabled_categories': disabledCats.isEmpty ? null : disabledCats,
        });
      } else {
        // When location is not yet locked, rely on clean curated static fallback
        response = [];
      }

      if (!mounted) return;

      final rows = response as List?;
      if (rows == null || rows.isEmpty) {
        if (mounted && _dynamicTrendingKeywords.isNotEmpty) {
          setState(() => _dynamicTrendingKeywords = []);
        }
        return;
      }

      final fetched = rows
          .map((row) {
            final keyword = (row['keyword'] as String? ?? '').trim();
            if (keyword.isEmpty) return null;
            return {
              'label': keyword,
              'emoji': _emojiForKeyword(keyword),
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      if (fetched.isEmpty) {
        if (mounted && _dynamicTrendingKeywords.isNotEmpty) {
          setState(() => _dynamicTrendingKeywords = []);
        }
        return;
      }

      // Re-start the scroll from position 0 so it doesn't jump mid-way
      if (mounted) {
        setState(() => _dynamicTrendingKeywords = fetched);
        // Reset scroll position so the new list starts from the beginning
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_trendingScrollController.hasClients) {
            _trendingScrollController.jumpTo(0);
          }
        });
      }
    } catch (e) {
      debugPrint('[Trending] Failed to load trending keywords: $e');
    }
  }

  bool _isActiveOrderNavigating = false;
  bool _isSettingsNavigating = false;
  Future<void> _checkActiveOrders() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId == null) return;
      try {
        final activeOrder = await _supabase
            .from('orders')
            .select('id, status, payment_deadline, created_at')
            .eq('customer_id', auth.currentUserId!)
            .inFilter('status', [
              'awaiting_acceptance',
              'awaiting_payment',
              'pending',
              'confirmed',
              'preparing',
              'ready_for_pickup',
              'picked_up',
              'out_for_delivery',
            ])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (activeOrder != null && mounted) {
          final status = activeOrder['status'];
          bool isExpired = false;

          if (status == 'awaiting_payment' &&
              activeOrder['payment_deadline'] != null) {
            final deadline =
                DateTime.parse(activeOrder['payment_deadline']).toLocal();
            if (DateTime.now().isAfter(deadline)) {
              isExpired = true;
            }
          } else if (status == 'pending' && activeOrder['created_at'] != null) {
            final createdAt =
                DateTime.parse(activeOrder['created_at']).toLocal();
            // If stuck in payment processing for more than 30 mins, treat as expired
            if (DateTime.now().difference(createdAt).inMinutes > 30) {
              isExpired = true;
            }
          }

          if (isExpired) {
            // Silently cancel it in the background so it stops polluting queries
            _supabase.rpc('cancel_order', params: {
              'p_order_id': activeOrder['id'],
              'p_reason': 'timeout'
            }).catchError((e) {
              debugPrint('Failed to auto-cancel expired active order: $e');
            });
            return; // DO NOT NAVIGATE
          }

          if (status == 'awaiting_payment') {
            // FIX (Issue 3): Do not auto-redirect if the customer is actively
            // searching for replacement items after a partial order rejection.
            final cartProvider = context.read<CartProvider>();
            if (cartProvider.pendingCartGroupId != null) {
              return;
            }

            if (_isActiveOrderNavigating) return;
            _isActiveOrderNavigating = true;
            Navigator.pushNamed(context, AppRoutes.trackOrder,
                    arguments: {'orderId': activeOrder['id']})
                .then((_) => _isActiveOrderNavigating = false);
          } else {
            final controller =
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('You have an active order in progress.'),
              action: SnackBarAction(
                label: 'Track',
                textColor: Colors.white,
                onPressed: () {
                  if (_isActiveOrderNavigating) return;
                  _isActiveOrderNavigating = true;
                  Navigator.pushNamed(context, AppRoutes.trackOrder,
                          arguments: {'orderId': activeOrder['id']})
                      .then((_) => _isActiveOrderNavigating = false);
                },
              ),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 10),
            ));

            // Additive fix: Force close after duration to bypass sticky SnackBar bug
            Future.delayed(const Duration(seconds: 10), () {
              try {
                controller.close();
              } catch (_) {}
            });
          }
        }
      } catch (e) {
        debugPrint('Failed to check active orders: $e');
      }
    });
  }

  LocationProvider? _locationProvider;

  bool _argsProcessed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locationProvider ??= context.read<LocationProvider>();

    if (!_argsProcessed) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['searchQuery'] != null) {
        final query = args['searchQuery'] as String;
        if (query.isNotEmpty) {
          _searchController.text = query;
          _searchShops(query);
        }
      }
      _argsProcessed = true;
    }
  }

  void _startLiveLocationUpdates() {
    // Re-fetch data whenever GPS location changes significantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationProvider?.addListener(_onLocationChanged);
    });
  }

  void _onLocationChanged() {
    if (!mounted || _searchQuery.isNotEmpty) return;

    if (_isFetching) {
      // Guard against actual network activity, not UI shimmer
      _pendingLocationUpdate = true;
      return;
    }

    _locationDebounceTimer?.cancel();
    _locationDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isFetching) {
        if (_isFetching) _pendingLocationUpdate = true;
        return;
      }
      _loadTrendingKeywords();
      if (_selectedTabIndex < 0) {
        _loadAllData();
      } else {
        _loadData(_categories[_selectedTabIndex]['name']! as String);
      }
    });
  }

  void _startNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsCustomer(userId);
        notifProvider.registerFcmToken(
            userId, 'customer'); // Register push token
      }
    });
  }

  @override
  void dispose() {
    _locationGlowCtrl.dispose();
    _bannerTimer?.cancel();
    _locationDebounceTimer?.cancel();
    _searchDebounce?.cancel();
    _trendingScrollTimer?.cancel();
    _retryTimer?.cancel(); // Issue 2: Cancel any pending retry on dispose
    _mainScrollController.dispose();
    _trendingScrollController.dispose();
    // Remove live location listener to avoid memory leaks
    _locationProvider?.removeListener(_onLocationChanged);
    _searchController.dispose();
    _bannerController.dispose();
    _bannerIndex.dispose();
    globalIsFiltering.value = false; // Reset state leakage
    super.dispose();
  }

  /// Scrolls the main view to the top if it's currently scrolled down.
  /// Returns true if a scroll action was triggered, false otherwise.
  bool scrollToTopIfNeeded() {
    if (_mainScrollController.hasClients && _mainScrollController.offset > 0) {
      _mainScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    return false;
  }

  /// Runs a Supabase text search for shops by name across all categories.
  Future<void> _searchShops(String query, {bool skipNLP = false}) async {
    final locationProvider = context.read<LocationProvider>();
    if (!locationProvider.hasLocation) {
      _promptEnableLocation();
      return;
    }
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _searchProductResults = [];
        _searchProductShops = {};
        _isSearching = false;
        _searchError = false;
        _searchErrorMessage = '';
        _comingSoonMessage = null;
        _comingSoonSubMessage = null;
        _sortMode = _SortMode.relevant; // reset sort on clear
        _selectedSearchDemographic = 'All'; // reset demographic on clear
        _selectedSizes.clear(); // reset sizes on clear
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = false;
      _searchErrorMessage = '';
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
      _searchQuery = query;
      _searchShopsDisplayLimit = 2;
      _searchProductsDisplayLimit = 10;
      if (!skipNLP) {
        _selectedSearchDemographic = 'All';
        _selectedSizes.clear();
      }
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();
      final String lowerQuery = query.toLowerCase().trim();
      List<String> matchedSubcategories = [];

      if (!skipNLP) {
        _searchKeywords.forEach((catName, keywords) {
          bool match = keywords.any((k) {
            return lowerQuery.contains(k) || k.contains(lowerQuery);
          });
          if (match) {
            final subs = _tabCategories[catName] ?? [catName];
            matchedSubcategories.addAll(subs.where((c) => config.isActiveCategory(c)));
          }
        });
      }

      String? specialTag;
      if (_selectedSearchDemographic != 'All') {
        specialTag = '#$_selectedSearchDemographic';
      }

      List<String>? effectiveCategories;
      if (_selectedFilterCategories.isNotEmpty) {
        effectiveCategories = [];
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
      }
      List<dynamic> shopsByName = [];
      List<dynamic> productsByName = [];
      List<dynamic> shopsByCat = [];
      List<dynamic> productsByCat = [];

      final lat = locationProvider.currentLocation?.latitude;
      final lng = locationProvider.currentLocation?.longitude;

      if (locationProvider.hasLocation && lat != null && lng != null) {
        // Phase 24: Mathematically pure ST_DWithin geospatial search via Additive RPC
        final maxRadius = DeliveryCalculator.maxRadiusKm;

        debugPrint(
            '[Search] Step 1/4: search_shops_geospatial (byName) q="$query" lat=$lat lng=$lng radius=$maxRadius');
        try {
          shopsByName = await _supabase.rpc('search_shops_geospatial', params: {
            'p_lat': lat,
            'p_lng': lng,
            'p_query': query,
            'p_categories': effectiveCategories,
            'p_radius_km': maxRadius,
            'p_limit': 50
          });
          debugPrint('[Search] Step 1/4 OK: ${shopsByName.length} shops found');
        } catch (e) {
          debugPrint(
              '[Search] Step 1/4 FAILED (search_shops_geospatial byName): $e');
          rethrow;
        }

        // Phase 26 Fix: Fetch products without .select('*, shops(*)')  which
        // causes PostgREST to reject embedded-resource requests on SETOF RPCs.
        // Instead, we batch-fetch shops separately and reconstruct the map.
        debugPrint(
            '[Search] Step 2/4: search_products_geospatial (byName) BYPASS q="$query"');
        List<dynamic> rawProductsByName = [];
        try {
          // Offload geospatial ST_DWithin and ST_Distance to the working shops RPC
          final nearbyShops =
              await _supabase.rpc('search_shops_geospatial', params: {
            'p_lat': lat,
            'p_lng': lng,
            'p_query': null, // All shops in radius to search their products
            'p_categories': effectiveCategories,
            'p_radius_km': maxRadius,
            'p_limit': 150
          });

          final shopIds =
              (nearbyShops as List).map((s) => s['id'] as String).toList();

          if (shopIds.isNotEmpty) {
            var q = _supabase
                .from('products')
                .select()
                .eq('is_deleted', false)
                .eq('is_available', true)
                .inFilter('shop_id', shopIds);

            final terms =
                query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
            for (final term in terms) {
              q = q.ilike('name', '%$term%');
            }

            if (specialTag != null) {
              q = q.contains('special_tags', [specialTag]);
            }

            final allProducts = await q;

            // Phase 31 Fix: Pre-truncation Local Size Filter (Solves JSONB + Pagination Edge Cases)
            final filteredProducts = _selectedSizes.isEmpty
                ? allProducts
                : allProducts.where((p) {
                    final variants = p['variants'] as List<dynamic>? ?? [];
                    return variants.any((v) {
                      final name = (v['name'] as String?)?.trim() ?? '';
                      return _selectedSizes.contains(name);
                    });
                  }).toList();

            // Group, sort by rating, limit 5 per shop
            final productsByShop = <String, List<dynamic>>{};
            for (final p in filteredProducts) {
              final sid = p['shop_id'] as String;
              productsByShop.putIfAbsent(sid, () => []).add(p);
            }

            // Iterate through sorted shops to maintain distance ordering
            for (final shop in nearbyShops) {
              final sid = shop['id'] as String;
              if (productsByShop.containsKey(sid)) {
                final shopProds = productsByShop[sid]!;
                shopProds.sort((a, b) {
                  final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
                  final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
                  return ratingB.compareTo(ratingA);
                });
                rawProductsByName.addAll(shopProds.take(5));
                if (rawProductsByName.length >= 50) break;
              }
            }
            if (rawProductsByName.length > 50) {
              rawProductsByName = rawProductsByName.sublist(0, 50);
            }
          }
          debugPrint(
              '[Search] Step 2/4 OK: ${rawProductsByName.length} products found');
        } catch (e) {
          debugPrint('[Search] Step 2/4 FAILED (byName bypass): $e');
          rethrow;
        }

        List<dynamic> rawProductsByCat = [];
        if (matchedSubcategories.isNotEmpty && !skipNLP) {
          debugPrint(
              '[Search] Step 3/4: search_shops_geospatial (byCat) cats=$matchedSubcategories');
          try {
            shopsByCat =
                await _supabase.rpc('search_shops_geospatial', params: {
              'p_lat': lat,
              'p_lng': lng,
              'p_categories': matchedSubcategories,
              'p_radius_km': maxRadius,
              'p_limit': 50
            });
            debugPrint(
                '[Search] Step 3/4 OK: ${shopsByCat.length} shops found');
          } catch (e) {
            debugPrint(
                '[Search] Step 3/4 FAILED (search_shops_geospatial byCat): $e');
            rethrow;
          }

          debugPrint(
              '[Search] Step 4/4: search_products_geospatial (byCat) BYPASS cats=$matchedSubcategories');
          try {
            // Leverage shopsByCat from Step 3 which is already distance sorted
            final shopIds = shopsByCat.map((s) => s['id'] as String).toList();

            if (shopIds.isNotEmpty) {
              final allProducts = await _supabase
                  .from('products')
                  .select()
                  .eq('is_deleted', false)
                  .eq('is_available', true)
                  .inFilter('shop_id', shopIds);

              // Phase 31 Fix: Pre-truncation Local Size Filter
              final filteredProducts = _selectedSizes.isEmpty
                  ? allProducts
                  : allProducts.where((p) {
                      final variants = p['variants'] as List<dynamic>? ?? [];
                      return variants.any((v) {
                        final name = (v['name'] as String?)?.trim() ?? '';
                        return _selectedSizes.contains(name);
                      });
                    }).toList();

              final productsByShop = <String, List<dynamic>>{};
              for (final p in filteredProducts) {
                final sid = p['shop_id'] as String;
                productsByShop.putIfAbsent(sid, () => []).add(p);
              }

              for (final shop in shopsByCat) {
                final sid = shop['id'] as String;
                if (productsByShop.containsKey(sid)) {
                  final shopProds = productsByShop[sid]!;
                  shopProds.sort((a, b) {
                    final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
                    final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
                    return ratingB.compareTo(ratingA);
                  });
                  rawProductsByCat.addAll(shopProds.take(5));
                  if (rawProductsByCat.length >= 100) break;
                }
              }
              if (rawProductsByCat.length > 100) {
                rawProductsByCat = rawProductsByCat.sublist(0, 100);
              }
            }
            debugPrint(
                '[Search] Step 4/4 OK: ${rawProductsByCat.length} products found');
          } catch (e) {
            debugPrint('[Search] Step 4/4 FAILED (byCat bypass): $e');
            rethrow;
          }
        } else {
          debugPrint(
              '[Search] Steps 3-4 skipped: no NLP-matched subcategories for "$query"');
        }

        // Collect all unique shop_ids from both product lists so we can
        // batch-fetch shop rows in a single query — no per-product round trips.
        final Set<String> productShopIds = {};
        for (final p in rawProductsByName) {
          final sid = (p as Map<String, dynamic>)['shop_id'] as String?;
          if (sid != null && sid.isNotEmpty) productShopIds.add(sid);
        }
        for (final p in rawProductsByCat) {
          final sid = (p as Map<String, dynamic>)['shop_id'] as String?;
          if (sid != null && sid.isNotEmpty) productShopIds.add(sid);
        }

        // Single batch query for all shops referenced by the product results.
        final Map<String, Map<String, dynamic>> shopById = {};
        if (productShopIds.isNotEmpty) {
          debugPrint(
              '[Search] Batch-fetching ${productShopIds.length} shop(s) for product results');
          final shopRows = await _supabase
              .from('shops')
              .select('*')
              .inFilter('id', productShopIds.toList());
          for (final s in shopRows as List) {
            final sm = s as Map<String, dynamic>;
            shopById[sm['id'] as String] = sm;
          }
        }

        // Reconstruct the product maps with the 'shops' key so that the
        // existing addProducts() closure (which reads p['shops']) works
        // without any modification — all downstream logic is preserved exactly.
        productsByName = rawProductsByName.map((p) {
          final m = Map<String, dynamic>.from(p as Map<String, dynamic>);
          m['shops'] = shopById[m['shop_id'] as String?];
          return m;
        }).toList();

        productsByCat = rawProductsByCat.map((p) {
          final m = Map<String, dynamic>.from(p as Map<String, dynamic>);
          m['shops'] = shopById[m['shop_id'] as String?];
          return m;
        }).toList();
      } else {
        // Fallback removed to prevent out-of-bounds checkouts
        shopsByName = [];
        productsByName = [];
        shopsByCat = [];
        productsByCat = [];
      }

      final allShopsSet = <String, ShopModel>{};

      void addShops(List<dynamic> response, bool requireNameMatch) {
        for (final s in response) {
          final shop = ShopModel.fromMap(s);
          if (!config.isActiveCategory(shop.category)) continue;
          if (!locationProvider.hasLocation &&
              requireNameMatch &&
              !shop.name.toLowerCase().contains(lowerQuery)) {
            continue;
          }
          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(shop.category)) {
            continue;
          }
          allShopsSet[shop.id] = shop;
        }
      }

      addShops(shopsByName, true);
      addShops(shopsByCat, false);

      final allShops = allShopsSet.values.toList();

      List<ShopModel> shopResults;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        // The RPC already enforces delivery range mathematically, so we just populate distanceKm.
        shopResults = allShops.toList();
      } else {
        shopResults = allShops;
      }

      final List<ProductModel> prodResults = [];
      final Map<String, ShopModel> prodShops = {};
      final addedProductIds = <String>{};

      void addProducts(List<dynamic> response) {
        for (final p in response) {
          final product = ProductModel.fromMap(p);
          if (!config.isActiveCategory(product.category)) continue;
          if (addedProductIds.contains(product.id)) continue;

          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;
          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(shop.category)) {
            continue;
          }

          if (locationProvider.hasLocation) {
            // Distance is enforced by RPC, just populate it
            if (shop.location.latitude != 0 && shop.location.longitude != 0) {
              shop.distanceKm = locationProvider.distanceTo(shop.location);
            }
          }

          prodResults.add(product);
          prodShops[product.id] = shop;
          addedProductIds.add(product.id);

          // Phase 25 Fix: Additive logic to ensure shops that sell the searched product
          // also appear in the "Shops & Restaurants" section. Zero SQL changes required.
          if (!allShopsSet.containsKey(shop.id)) {
            allShopsSet[shop.id] = shop;
            shopResults.add(shop);
          }
        }
      }

      addProducts(productsByName);
      addProducts(productsByCat);

      if (mounted) {
        if (_searchQuery != query) return;

        setState(() {
          _searchResults = shopResults;
          _searchProductResults = prodResults;
          _searchProductShops = prodShops;
          _isSearching = false;
        });
      }
    } catch (e, st) {
      debugPrint('_searchShops ERROR: $e\n$st');

      // Classify the error for user-facing messaging
      String userMessage;
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('HandshakeException') ||
          errStr.contains('Connection closed') ||
          errStr.contains('Network is unreachable')) {
        userMessage = 'Please check your internet connection.';
      } else if (errStr.contains('42883') ||
          errStr.contains('function') && errStr.contains('does not exist')) {
        userMessage =
            'Search service unavailable. DB function missing — contact support.';
        debugPrint(
            '[Search] ⚠ PostgREST 42883: search function not found. Migrations may not be applied.');
      } else if (errStr.contains('42725') || errStr.contains('is not unique')) {
        userMessage =
            'Search service error. DB function ambiguity — contact support.';
        debugPrint('[Search] ⚠ PostgREST 42725: ambiguous function overload.');
      } else if (errStr.contains('PGRST')) {
        userMessage = 'Search service error: $errStr';
      } else {
        userMessage =
            'Search failed: ${errStr.length > 120 ? '${errStr.substring(0, 120)}...' : errStr}';
      }

      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = true;
          _searchErrorMessage = userMessage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _checkLocationAndLoad() async {
    final locationProvider = context.read<LocationProvider>();

    setState(() {
      _isSearching = false;
      _searchError = false;
      _searchQuery = '';
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
    });

    if (!locationProvider.hasLocation) {
      await locationProvider.requestLocation();
    }

    // _selectedTabIndex == -1 means "All" — fetch every active shop
    _loadTrendingKeywords();
    final cats = _categories;
    if (_selectedTabIndex < 0 || _selectedTabIndex >= cats.length) {
      _loadAllData();
    } else {
      _loadData(cats[_selectedTabIndex]['name']! as String);
    }
  }

  /// Maps broad tab name → actual DB category values
  static const Map<String, List<String>> _tabCategories = {
    'Food': [
      'Restaurant',
      'Fast Food',
      'Bakery',
      'Sweets & Mithai',
      'Tea & Coffee',
      'Ice Cream',
      'Paan Shop',
      'Beverages'
    ],
    'Grocery': [
      'Grocery',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic'
    ],
    'Pharmacy': ['Pharmacy', 'Medical Store'],
    'GroceryAndMed': [
      'Grocery',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic',
      'Pharmacy',
      'Medical Store'
    ],
    'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
    'Electronics': ['Electronics', 'Mobile & Repair'],
    'More': [
      'Hardware Store',
      'Stationery',
      'Toys & Games',
      'Sports',
      'Pet Supplies',
      'Cosmetics & Beauty',
      'Salon & Beauty',
      'Flowers',
      'Home Decor',
      'Furniture',
      'Auto Parts',
      'Other'
    ],
  };

  /// Fetch ALL active shops & products, sorted by rating then total_orders.
  /// Used on initial load when no category tab is selected.
  Future<void> _loadAllData() async {
    final currentFetchId = ++_fetchId;
    _isFetching = true;

    // Only show the shimmer on the very first load. On subsequent loads
    // (e.g., GPS update or category deselect) keep old data visible.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();

      List<String> effectiveCategories = [];
      if (_selectedFilterCategories.isNotEmpty) {
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
      }

      // Phase 16 Fix: Additive Geospatial fetch to prevent Pixel Blindness
      final shopsResponse = (locationProvider.hasLocation && effectiveCategories.isNotEmpty)
          ? await _supabase.rpc('get_nearby_shops', params: {
              'p_lat': locationProvider.currentLocation!.latitude,
              'p_lng': locationProvider.currentLocation!.longitude,
              'p_radius_km': DeliveryCalculator.maxRadiusKm,
              'p_limit':
                  500, // Fetch up to 500 nearby shops to prevent category starving
              'p_categories': effectiveCategories,
            })
          : [];

      final allShops = (shopsResponse as List)
          .map((s) => ShopModel.fromMap(s))
          .where((s) => s.isActive && config.isActiveCategory(s.category))
          .toList();

      List<ShopModel> nearby;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        nearby = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) {
            // Primary sort: higher rating first
            final ratingCmp = (b.rating).compareTo(a.rating);
            if (ratingCmp != 0) return ratingCmp;
            // Secondary: closer distance first
            return (a.distanceKm ?? double.infinity)
                .compareTo(b.distanceKm ?? double.infinity);
          });
      } else {
        // No GPS yet — show all active shops sorted by rating
        nearby = allShops..sort((a, b) => b.rating.compareTo(a.rating));
      }

      // Phase 21 Fix: Prevent Pixel Overloading by using RPC to fetch a diverse per-shop limit
      final nearbyShopIds = nearby.map((s) => s.id).take(50).toList();

      final productsResponse = nearbyShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': nearbyShopIds,
              'p_limit_per_shop': 5,
              'p_categories': effectiveCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!effectiveCategories.contains(product.category) ||
              !config.isActiveCategory(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) {
              continue;
            }
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }
        prods.sort((a, b) => b.rating.compareTo(a.rating));

        if (_fetchId != currentFetchId) return; // Prevent async tab desync

        // Atomic update: swap data and clear loading in a single setState
        setState(() {
          _shopsDisplayLimit = 3;
          _productsDisplayLimit = 6;
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0; // Reset retry counter on success
        });
      }
    } catch (e, st) {
      // Log full error so we can debug exactly what Supabase query failed
      debugPrint('_loadAllData ERROR: $e\n$st');
      if (!mounted || _fetchId != currentFetchId) return;

      // ── Industrial-standard error classification ─────────────────────────
      // Transient: SocketException, TimeoutException, ClientException — safe to retry
      // Permanent: auth errors, query errors — fail fast, show actionable message
      final isTransient = e is SocketException ||
          e is TimeoutException ||
          (e.toString().contains('ClientException') &&
              !e.toString().contains('403') &&
              !e.toString().contains('401'));

      setState(() => _isLoading = false);

      if (isTransient && _loadRetryCount < _maxLoadRetries) {
        _loadRetryCount++;
        // Exponential backoff with jitter: 1s → 2s → 4s + up to 500ms random jitter
        final backoffSeconds = (1 << (_loadRetryCount - 1)); // 1, 2, 4
        final jitterMs =
            (500 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round();
        final delay = Duration(seconds: backoffSeconds, milliseconds: jitterMs);
        debugPrint(
            '_loadAllData: transient error, retry $_loadRetryCount/$_maxLoadRetries in ${delay.inSeconds}s');

        // Show silent inline status — no alarming red banner for network blips
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('Connection issue — retrying in ${backoffSeconds}s…'),
              ]),
              backgroundColor: const Color(0xFF2A2A2A),
              duration: delay + const Duration(milliseconds: 200),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (mounted) _loadAllData();
        });
      } else {
        // Permanent error or retries exhausted — show friendly actionable message
        _loadRetryCount = 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Couldn\'t load shops. Check your connection and pull down to refresh.'),
              backgroundColor: const Color(0xFF1A1A1A),
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.primary,
                onPressed: () {
                  _loadRetryCount = 0;
                  _loadAllData();
                },
              ),
            ),
          );
        }
      }
    } finally {
      if (_fetchId == currentFetchId) {
        _isFetching = false;
        if (_pendingLocationUpdate && mounted) {
          _pendingLocationUpdate = false;
          _onLocationChanged();
        }
      }
    }
  }

  Future<void> _loadData(String tabName) async {
    final currentFetchId = ++_fetchId;
    _isFetching = true;

    if (mounted) {
      setState(() {
        _comingSoonMessage = null;
        _comingSoonSubMessage = null;
      });
    }

    // Do NOT set _isLoading = true here on category switch — this causes the
    // existing content to disappear (the "flash"). Keep old data visible
    // and only swap data once the new fetch is complete.
    // Only show shimmer on the very first app load.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();
      final rawSubcategories = _tabCategories[tabName] ?? [tabName];
      final subcategories =
          rawSubcategories.where((c) => config.isActiveCategory(c)).toList();

      // Guard: If category or all its subcategories are disabled by admin
      if (subcategories.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Coming Soon!';
          _comingSoonSubMessage =
              'This category is currently paused in your area. We\'ll be back soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      List<String> effectiveCategories = [];
      if (_selectedFilterCategories.isNotEmpty) {
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
      }

      final finalCategories =
          subcategories.where((c) => effectiveCategories.contains(c)).toList();

      if (finalCategories.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Coming Soon!';
          _comingSoonSubMessage =
              'This category is currently paused in your area. We\'ll be back soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      // Phase 16 Fix: Additive Geospatial fetch to prevent Pixel Blindness
      final shopsResponse =
          (locationProvider.hasLocation && finalCategories.isNotEmpty)
              ? await _supabase.rpc('get_nearby_shops', params: {
                  'p_lat': locationProvider.currentLocation!.latitude,
                  'p_lng': locationProvider.currentLocation!.longitude,
                  'p_radius_km': DeliveryCalculator.maxRadiusKm,
                  'p_limit':
                      500, // Fetch ample pool, then filter down to subcategories locally
                  'p_categories': finalCategories,
                })
              : [];

      final allShops = (shopsResponse as List)
          .map((s) => ShopModel.fromMap(s))
          .where((s) => s.isActive && config.isActiveCategory(s.category))
          .toList();

      List<ShopModel> nearby;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        nearby = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) => (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity));
      } else {
        nearby = allShops..sort((a, b) => b.rating.compareTo(a.rating));
      }

      // If no shops in delivery radius, show Coming Soon state
      if (nearby.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Delivery Coming Soon!';
          _comingSoonSubMessage =
              'We\'re partnering with top local stores to bring $tabName to your location soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      // Phase 21 Fix: Prevent Pixel Overloading by using RPC to fetch a diverse per-shop limit
      final nearbyShopIds = nearby.map((s) => s.id).take(50).toList();

      final productsResponse = nearbyShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': nearbyShopIds,
              'p_limit_per_shop': 5,
              'p_categories': finalCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!effectiveCategories.contains(product.category) ||
              !config.isActiveCategory(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) {
              continue;
            }
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }
        prods.sort((a, b) => b.rating.compareTo(a.rating));

        if (_fetchId != currentFetchId) return; // Prevent async tab desync

        // Atomic update: swap data in a single setState
        setState(() {
          _shopsDisplayLimit = 3;
          _productsDisplayLimit = 6;
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _comingSoonMessage = prods.isEmpty && nearby.isEmpty
              ? '$tabName Delivery Coming Soon!'
              : null;
          _comingSoonSubMessage = prods.isEmpty && nearby.isEmpty
              ? 'We\'re partnering with top local stores to bring $tabName to your location soon!'
              : null;
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0; // Reset retry counter on success
        });
      }
    } catch (e, st) {
      debugPrint('_loadData ERROR: $e\n$st');
      if (!mounted || _fetchId != currentFetchId) return;

      // ── Same error classification as _loadAllData ──────────────────────
      final isTransient = e is SocketException ||
          e is TimeoutException ||
          (e.toString().contains('ClientException') &&
              !e.toString().contains('403') &&
              !e.toString().contains('401'));

      setState(() => _isLoading = false);

      if (isTransient && _loadRetryCount < _maxLoadRetries) {
        _loadRetryCount++;
        final backoffSeconds = (1 << (_loadRetryCount - 1));
        final jitterMs =
            (500 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round();
        final delay = Duration(seconds: backoffSeconds, milliseconds: jitterMs);
        debugPrint(
            '_loadData: transient error, retry $_loadRetryCount/$_maxLoadRetries in ${delay.inSeconds}s');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('Connection issue — retrying in ${backoffSeconds}s…'),
              ]),
              backgroundColor: const Color(0xFF2A2A2A),
              duration: delay + const Duration(milliseconds: 200),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (mounted) _loadData(tabName);
        });
      } else {
        _loadRetryCount = 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Couldn\'t load shops. Check your connection and pull down to refresh.'),
              backgroundColor: const Color(0xFF1A1A1A),
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.primary,
                onPressed: () {
                  _loadRetryCount = 0;
                  _loadData(tabName);
                },
              ),
            ),
          );
        }
      }
    } finally {
      if (_fetchId == currentFetchId) {
        _isFetching = false;
        if (_pendingLocationUpdate && mounted) {
          _pendingLocationUpdate = false;
          _onLocationChanged();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFiltering = _selectedTabIndex >= 0 ||
        _selectedFilterCategories.isNotEmpty ||
        _searchQuery.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (globalIsFiltering.value != currentFiltering) {
        globalIsFiltering.value = currentFiltering;
      }
    });

    final locationProvider = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          controller: _mainScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // ── Premium Modern AppBar ──────────────────────────────────────
            SliverAppBar(
              expandedHeight: _searchQuery.isNotEmpty ? 0 : 125,
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _searchQuery.isNotEmpty ? 0.0 : 1.0,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                          16, MediaQuery.of(context).padding.top + 10, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Location Pill + actions
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => showAddressPickerSheet(context),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E1E2E)
                                            : const Color(0xFFF0F0F8),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (locationProvider
                                              .activeLabelIcon.isNotEmpty) ...[
                                            Text(
                                                locationProvider
                                                    .activeLabelIcon,
                                                style: const TextStyle(
                                                    fontSize: 14)),
                                            const SizedBox(width: 4),
                                            Text(
                                              locationProvider.activeLabel,
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white30
                                                    : Colors.grey.shade400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ] else ...[
                                            const Icon(
                                                Icons.location_on_rounded,
                                                size: 14,
                                                color: AppColors.primary),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              locationProvider.hasLocation
                                                  ? locationProvider
                                                          .currentAddress
                                                          .isNotEmpty
                                                      ? locationProvider
                                                          .currentAddress
                                                      : 'Current Location'
                                                  : 'Set location...',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 16,
                                              color: isDark
                                                  ? Colors.white38
                                                  : AppColors.textSecondary),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              NotificationBell(
                                iconColor: isDark
                                    ? Colors.white70
                                    : AppColors.textPrimary,
                                containerColor: isDark
                                    ? const Color(0xFF1E1E2E)
                                    : const Color(0xFFF0F0F8),
                              ),
                              const SizedBox(width: 8),
                              _buildCircleAction(
                                icon:
                                    isDark ? Icons.light_mode : Icons.dark_mode,
                                isDark: isDark,
                                onTap: () => themeProvider.toggleTheme(),
                              ),
                              const SizedBox(width: 8),
                              _buildCircleAction(
                                icon: Icons.person_outline,
                                isDark: isDark,
                                onTap: () {
                                  if (_isSettingsNavigating) return;
                                  _isSettingsNavigating = true;
                                  Navigator.pushNamed(
                                          context, AppRoutes.settings)
                                      .then(
                                          (_) => _isSettingsNavigating = false);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Hero(
                    tag: 'search_bar',
                    child: Material(
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                TextField(
                                  controller: _searchController,
                                  onChanged: (v) {
                                    _searchDebounce?.cancel();
                                    if (v.trim().isNotEmpty) {
                                      setState(() {
                                        _searchQuery = v;
                                        _isSearching = true;
                                      });
                                    }
                                    _searchDebounce = Timer(
                                      const Duration(milliseconds: 350),
                                      () => _searchShops(v),
                                    );
                                  },
                                  decoration: InputDecoration(
                                    hintText: '',
                                    prefixIcon: const Icon(Icons.search,
                                        color: AppColors.primary),
                                    suffixIcon: _isSearching
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: CupertinoActivityIndicator(
                                                radius: 9),
                                          )
                                        : _searchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 18),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  _searchShops('');
                                                },
                                              )
                                            : null,
                                    filled: true,
                                    fillColor: Theme.of(context)
                                            .inputDecorationTheme
                                            .fillColor ??
                                        Colors.grey.shade100,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                          color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                          width: 1.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                  ),
                                ),
                                if (_searchController.text.isEmpty)
                                  Positioned(
                                    left: 44,
                                    right: 48,
                                    child: IgnorePointer(
                                      child: AnimatedSearchTicker(
                                        textStyle: GoogleFonts.outfit(
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade500,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showFilterSheet(context, isDark),
                            child: Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                color: _selectedFilterCategories.isNotEmpty
                                    ? AppColors.primary
                                    : (isDark
                                        ? const Color(0xFF1E1E2E)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: _selectedFilterCategories.isNotEmpty
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Trending Now Auto-Marquee Strip ──────────────────────────────────
            if (_searchQuery.isEmpty &&
                _selectedTabIndex < 0 &&
                _selectedFilterCategories.isEmpty)
              SliverToBoxAdapter(
                child: _buildTrendingStrip(isDark),
              ),

            // ── Search Filter Bar (visible during search only) ───────────
            if (_searchQuery.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildSearchFilterBar(isDark),
              ),

            // ── Main Content ──────────────────────────────────────────
            // ── Main Content ──────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: _isLoading
                  ? SliverToBoxAdapter(child: _buildShimmer())
                  : SliverMainAxisGroup(
                      slivers: [
                        // ──────────────────────────────────────────────────
                        // SEARCH MODE: clean results-only view
                        // ──────────────────────────────────────────────────
                        if (_searchQuery.isNotEmpty) ...[
                          const SliverToBoxAdapter(child: SizedBox(height: 4)),

                          // Header
                          SliverToBoxAdapter(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isSearching
                                            ? 'Searching...'
                                            : 'Search results',
                                        style: GoogleFonts.outfit(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      if (!_isSearching)
                                        Text(
                                          '${_searchResults.length + _searchProductResults.length} result${(_searchResults.length + _searchProductResults.length) == 1 ? "" : "s"} for "$_searchQuery"',
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),

                          // Skeleton while loading
                          if (_isSearching)
                            SliverToBoxAdapter(
                                child: Column(
                                    children: List.generate(3,
                                        (_) => _buildSearchSkeleton(isDark))))

                          // Error state
                          else if (_searchError)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: AppColors.danger
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.wifi_off_rounded,
                                              size: 36,
                                              color: AppColors.danger),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text('Search Failed',
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(height: 8),
                                      Text(
                                          _searchErrorMessage.isNotEmpty
                                              ? _searchErrorMessage
                                              : 'Please check your internet connection',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textSecondary)),
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _searchShops(_searchQuery),
                                        icon: const Icon(Icons.refresh_rounded,
                                            color: Colors.white, size: 20),
                                        label: Text('Retry Search',
                                            style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )

                          // Empty state
                          else if (_searchResults.isEmpty &&
                              _searchProductResults.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.15)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.search_off_rounded,
                                            size: 36,
                                            color: isDark
                                                ? AppColors.primaryLight
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text('No results for',
                                          style: GoogleFonts.outfit(
                                              fontSize: 15,
                                              color: AppColors.textSecondary)),
                                      const SizedBox(height: 4),
                                      Text('"$_searchQuery"',
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(height: 8),
                                      Text('Try a different keyword',
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textLight)),
                                    ],
                                  ),
                                ),
                              ),
                            )

                          // Results
                          else ...[
                            // Products first (most relevant for the user)
                            if (_searchProductResults.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 8),
                                      Text('Items & Products',
                                          style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            '${_searchProductResults.length}',
                                            style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: _sortedProductResults.length >
                                        _searchProductsDisplayLimit
                                    ? _searchProductsDisplayLimit
                                    : _sortedProductResults.length,
                                itemBuilder: (context, index) {
                                  final product = _sortedProductResults[index];
                                  final shop = _searchProductShops[product.id];
                                  if (shop == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return ProductSearchCard(
                                      product: product, shop: shop);
                                },
                              ),
                              if (_searchProductResults.length >
                                  _searchProductsDisplayLimit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => setState(() =>
                                            _searchProductsDisplayLimit += 20),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          backgroundColor: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.05),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                        ),
                                        child: Text(
                                          'Load more items',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 16)),
                            ],

                            // Shops below products
                            if (_searchResults.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12, top: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                              color: AppColors.secondary,
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 8),
                                      Text('Shops & Restaurants',
                                          style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: AppColors.secondary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text('${_searchResults.length}',
                                            style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.secondary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: _sortedShopResults.length >
                                        _searchShopsDisplayLimit
                                    ? _searchShopsDisplayLimit
                                    : _sortedShopResults.length,
                                itemBuilder: (context, index) {
                                  final shop = _sortedShopResults[index];
                                  final isFood =
                                      AppCategories.groupFor(shop.category) ==
                                          CategoryGroup.food;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SizedBox(
                                      height: 280,
                                      child: isFood
                                          ? RestaurantShopCard(
                                              shop: shop,
                                              onTap: () =>
                                                  showRestaurantDashboardSheet(
                                                      context, shop.id))
                                          : ShopCard(
                                              shop: shop,
                                              onTap: () => showShopDetailSheet(
                                                  context, shop.id)),
                                    ),
                                  );
                                },
                              ),
                              if (_searchResults.length >
                                  _searchShopsDisplayLimit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => setState(() =>
                                            _searchShopsDisplayLimit += 20),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          backgroundColor: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.05),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                        ),
                                        child: Text(
                                          'Load more shops',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],

                          // ──────────────────────────────────────────────────
                          // NORMAL MODE: banner + shops + products
                          // ──────────────────────────────────────────────────
                        ] else ...[
                          if (_selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty) ...[
                            // Featured Banner
                            SliverToBoxAdapter(child: _buildFeaturedBanner()),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 24)),
                          ],

                          // ── Explore Categories ─────────────────────────────────
                          // Shown FIRST so users can orient themselves immediately.
                          // Always visible when no search + no filter chip active.
                          if (_searchQuery.isEmpty &&
                              _selectedFilterCategories.isEmpty)
                            SliverToBoxAdapter(
                              child: _buildCategorySection(isDark),
                            ),

                          // ── Recently Viewed ─────────────────────────────
                          if (_selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty)
                            SliverToBoxAdapter(
                              child: Builder(builder: (ctx) {
                                final recentProv =
                                    ctx.watch<RecentlyViewedProvider>();
                                if (!recentProv.hasItems) {
                                  return const SizedBox.shrink();
                                }

                                // Filter out products whose shop is closed
                                final availableRecent =
                                    recentProv.products.where((p) {
                                  final shop = _productShops[p.id];
                                  return shop != null && shop.isActive;
                                }).toList();

                                if (availableRecent.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionTitle(
                                      'Recently Viewed',
                                      subtitle: 'Continue where you left off',
                                      isLoading: recentProv.isLoading,
                                      onSeeAllTap: (recentProv.products.length <
                                              recentProv.totalIdsCount)
                                          ? () => recentProv.loadAll()
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 260,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: availableRecent.length,
                                        itemBuilder: (_, index) {
                                          final p = availableRecent[index];
                                          final shop = _productShops[p.id];
                                          return SizedBox(
                                            width: 148,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 12),
                                              child: ProductCard(
                                                  product: p, shop: shop),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                );
                              }),
                            ),

                          if (_shops.isNotEmpty) ...[
                            // ── Normal category browse ───────────────────
                            SliverToBoxAdapter(
                              child: _buildSectionTitle(
                                _selectedTabIndex < 0
                                    ? 'Stores near you'
                                    : _isFoodTab
                                        ? 'Restaurants near you'
                                        : 'Shops near you',
                                subtitle:
                                    '${_shops.length} within ${DeliveryCalculator.maxRadiusKm.toInt()} km',
                                count: _shops.length,
                              ),
                            ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                            SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount =
                                    Responsive.getGridCrossAxisCount(context,
                                        mobile: 1, tablet: 2, desktop: 3);
                                List<ShopModel> displayShops;
                                if (_selectedTabIndex < 0) {
                                  displayShops =
                                      _getTop4DiverseShops(_sortedNormalShops);
                                } else {
                                  displayShops = _sortedNormalShops
                                      .take(_shopsDisplayLimit)
                                      .toList();
                                }
                                return SliverGrid.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent:
                                        280, // Fixed extent for the card
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: displayShops.length,
                                  itemBuilder: (context, index) {
                                    final shop = displayShops[index];
                                    final isFood =
                                        AppCategories.groupFor(shop.category) ==
                                            CategoryGroup.food;
                                    return isFood
                                        ? RestaurantShopCard(
                                            shop: shop,
                                            onTap: () =>
                                                showRestaurantDashboardSheet(
                                                    context, shop.id),
                                          )
                                        : ShopCard(
                                            shop: shop,
                                            onTap: () => showShopDetailSheet(
                                                context, shop.id),
                                          );
                                  },
                                );
                              },
                            ),
                            // ── Professional "See all" button ──
                            if (_sortedNormalShops.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                              SliverToBoxAdapter(
                                child: _buildModernSeeAllButton(
                                  context,
                                  label: _isFoodTab
                                      ? 'See all restaurants'
                                      : 'See all stores',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.allListings,
                                    arguments: {
                                      'type': _isFoodTab
                                          ? ListingType.restaurants
                                          : ListingType.shops,
                                      'shops': List<ShopModel>.from(
                                          _sortedNormalShops),
                                      'sectionTitle': _selectedTabIndex < 0
                                          ? 'Stores Near You'
                                          : _isFoodTab
                                              ? 'All Restaurants'
                                              : 'All Shops',
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                            ],
                          ] else if (!_isLoading &&
                              _selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty) ...[
                            SliverToBoxAdapter(
                              child: locationProvider.hasLocation
                                  ? _buildNoShopsNearby()
                                  : _buildLocationRequired(),
                            ),
                          ],

                          // Products Section
                          if (_products.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 8)),
                            SliverToBoxAdapter(
                              child: _buildSectionTitle('Popular in your area'),
                            ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                            SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount =
                                    Responsive.getGridCrossAxisCount(context,
                                        mobile: 2, tablet: 4, desktop: 5);
                                const crossAxisSpacing = 16.0;
                                final availableWidth =
                                    constraints.crossAxisExtent;
                                final itemWidth = (availableWidth -
                                        (crossAxisSpacing *
                                            (crossAxisCount - 1))) /
                                    crossAxisCount;
                                final itemHeight = itemWidth + 120;
                                final childAspectRatio = itemWidth / itemHeight;
                                final displayProducts = _sortedNormalProducts
                                    .take(_productsDisplayLimit)
                                    .toList();

                                return SliverGrid.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    childAspectRatio: childAspectRatio,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: crossAxisSpacing,
                                  ),
                                  itemCount: displayProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = displayProducts[index];
                                    final shop = _productShops[product.id];
                                    return ProductCard(
                                        product: product, shop: shop);
                                  },
                                );
                              },
                            ),
                            if (_sortedNormalProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                              SliverToBoxAdapter(
                                child: _buildModernSeeAllButton(
                                  context,
                                  label: 'See all popular items',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.allListings,
                                    arguments: {
                                      'type': ListingType.products,
                                      'products': List<ProductModel>.from(
                                          _sortedNormalProducts),
                                      'productShops':
                                          Map<String, ShopModel>.from(
                                              _productShops),
                                      'sectionTitle': 'Popular in Your Area',
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ] else if (_shops.isNotEmpty && !_isLoading) ...[
                            // ── "Popular in your area" empty state ──────────────
                            // Shows when shops exist but no products returned yet.
                            // This prevents the section from silently disappearing.
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 8)),
                            SliverToBoxAdapter(
                              child: _buildSectionTitle('Popular in your area'),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 28, horizontal: 20),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.12)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Icon(
                                          Icons.storefront_outlined,
                                          size: 30,
                                          color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No popular items right now',
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Check back soon — shops near you will list their popular items here.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white38
                                              : AppColors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_comingSoonMessage != null &&
                              !_isLoading) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.15)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.rocket_launch_rounded,
                                            size: 36,
                                            color: isDark
                                                ? AppColors.primaryLight
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(_comingSoonMessage!,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      if (_comingSoonSubMessage != null) ...[
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 32),
                                          child: Text(
                                            _comingSoonSubMessage!,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.white54
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_shops.isEmpty &&
                              (_selectedTabIndex >= 0 ||
                                  _selectedFilterCategories.isNotEmpty) &&
                              !_isLoading) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.15)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.rocket_launch_rounded,
                                            size: 36,
                                            color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                          _comingSoonMessage ??
                                              'Delivery Coming Soon!',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 32),
                                        child: Text(
                                            _comingSoonSubMessage ??
                                                'We\'re partnering with top local stores to bring this category to your location soon!',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                color: isDark
                                                    ? Colors.white54
                                                    : AppColors.textSecondary,
                                                height: 1.4)),
                                      ),
                                      const SizedBox(height: 20),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _selectedTabIndex = -1;
                                            _selectedFilterCategories.clear();
                                            _comingSoonMessage = null;
                                            _comingSoonSubMessage = null;
                                          });
                                          _loadAllData();
                                        },
                                        icon: const Icon(Icons.storefront_rounded, size: 18),
                                        label: Text('Explore All Stores',
                                            style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 120)),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchFilterBar(bool isDark) {
    final filters = [
      {
        'mode': _SortMode.relevant,
        'label': 'Relevant',
        'icon': Icons.bolt_rounded
      },
      {
        'mode': _SortMode.bestRating,
        'label': 'Best Rating',
        'icon': Icons.star_rounded
      },
      {
        'mode': _SortMode.priceLow,
        'label': 'Price: Low to High',
        'icon': Icons.trending_up_rounded
      },
      {
        'mode': _SortMode.priceHigh,
        'label': 'Price: High to Low',
        'icon': Icons.trending_down_rounded
      },
      {
        'mode': _SortMode.discount,
        'label': 'Biggest Discount',
        'icon': Icons.local_offer_rounded
      },
    ];

    final hasDemographicCategories = _searchProductResults.any((p) => [
              'Clothing',
              'Footwear',
              'Jewellery',
              'Cosmetics & Beauty',
              'Salon & Beauty'
            ].contains(p.category)) ||
        _selectedSearchDemographic != 'All';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: filters.map((filter) {
              final mode = filter['mode'] as _SortMode;
              final isSelected = _sortMode == mode;

              return GestureDetector(
                onTap: () => setState(() => _sortMode = mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        filter['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppColors.textPrimary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        filter['label'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? Colors.white70
                                  : AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (hasDemographicCategories)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['All', 'Men', 'Women', 'Boys', 'Girls', 'Kids']
                  .map((demo) => Padding(
                        padding:
                            const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                        child: ChoiceChip(
                          label: Text(demo),
                          selected: _selectedSearchDemographic == demo,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedSearchDemographic = demo;
                              });
                              _searchShops(_searchQuery, skipNLP: true);
                            }
                          },
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _selectedSearchDemographic == demo
                                ? Colors.white
                                : (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary),
                            fontFamily: 'Poppins',
                            fontSize: 13,
                          ),
                          backgroundColor:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          side: BorderSide(
                            color: _selectedSearchDemographic == demo
                                ? AppColors.primary
                                : (isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchSkeleton(bool isDark) {
    final shimmerBase =
        isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8);
    final shimmerHigh =
        isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8);
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHigh,
      child: Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: shimmerBase,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              decoration: BoxDecoration(
                color: shimmerHigh,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 14,
                      width: 140,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(7))),
                  const SizedBox(height: 8),
                  Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 10),
                  Container(
                      height: 12,
                      width: 60,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: 60,
                height: 34,
                decoration: BoxDecoration(
                    color: shimmerHigh,
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleAction(
      {required IconData icon,
      required bool isDark,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D30) : const Color(0xFFEEF0FF),
          shape: BoxShape.circle,
          border:
              Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        ),
        child: Icon(icon,
            color: isDark ? Colors.white70 : AppColors.textPrimary, size: 20),
      ),
    );
  }

  Widget _buildFeaturedBanner() {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final slides = [
      {
        'tag': '🔥 HOT & FRESH',
        'title': 'Get Food Instantly\nDelivered to you',
        'sub': 'Fast, fresh, and local restaurants',
        'icon': Icons.local_dining_rounded,
        'colors': <Color>[
          const Color(0xFFFF512F),
          const Color(0xFFF09819),
          const Color(0xFFFF6A00)
        ],
        'accent': const Color(0xFFFFE082),
        'emoji': '🍔',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Food');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _comingSoonMessage = 'Food Delivery Coming Soon!';
              _comingSoonSubMessage =
                  'We are partnering with the best local restaurants. Stay tuned!';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
          });
          _loadData('Food');
        },
      },
      {
        'tag': '🛒 DAILY ESSENTIALS',
        'title': 'Grocery & Medicines\nAt your doorstep',
        'sub': 'Supermarkets and local pharmacies',
        'icon': Icons.shopping_basket_rounded,
        'colors': <Color>[
          const Color(0xFF11998E),
          const Color(0xFF38EF7D),
          const Color(0xFF00B09B)
        ],
        'accent': const Color(0xFFB9F6CA),
        'emoji': '🥦💊',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final hasGrocery =
              _categories.any((c) => c['name'] == 'Supermarket / Hypermarket');
          final hasPharmacy = _categories.any((c) => c['name'] == 'Pharmacy');
          if (!hasGrocery && !hasPharmacy) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _comingSoonMessage = 'Groceries & Medicines Coming Soon!';
              _comingSoonSubMessage =
                  'Daily essentials delivered to your doorstep, launching soon.';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = -1;
            _selectedFilterCategories.clear();
          });
          _loadData('GroceryAndMed');
        },
      },
      {
        'tag': '👗 FASHION & MORE',
        'title': 'Clothing, Shoes\nAnd everything else!',
        'sub': 'Local fashion and apparel stores',
        'icon': Icons.checkroom_rounded,
        'colors': <Color>[
          const Color(0xFF0A1260),
          const Color(0xFF142999),
          const Color(0xFF1E3FD8)
        ],
        'accent': const Color(0xFF00E5FF),
        'emoji': '👠👗',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Clothing');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _comingSoonMessage = 'Fashion & Clothing Coming Soon!';
              _comingSoonSubMessage =
                  'Your favorite local apparel stores will be here shortly.';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
          });
          _loadData('Clothing');
        },
      },
    ];

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) => _isBannerHovered = true,
          onExit: (_) => _isBannerHovered = false,
          child: SizedBox(
            height: 130,
            child: PageView.builder(
              controller: _bannerController,
              onPageChanged: (i) => _bannerIndex.value = i,
              itemCount: slides.length,
              itemBuilder: (_, i) {
                final s = slides[i];
                final colors = s['colors'] as List<Color>;
                final accent = s['accent'] as Color;
                final emoji = s['emoji'] as String;
                return GestureDetector(
                  onTap: () {
                    SensoryHaptics.light();
                    (s['action'] as VoidCallback)();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: colors[1].withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Large background circle
                        Positioned(
                            right: -30,
                            top: -30,
                            child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Colors.white.withValues(alpha: 0.05)))),
                        // Smaller circle
                        Positioned(
                            left: -15,
                            bottom: -15,
                            child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Colors.white.withValues(alpha: 0.04)))),
                        // Background icon
                        Positioned(
                            right: -5,
                            bottom: -15,
                            child: Icon(s['icon'] as IconData,
                                size: 90,
                                color: Colors.white.withValues(alpha: 0.07))),
                        // Big emoji top-right
                        Positioned(
                            right: 16,
                            top: 16,
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 36))),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 70, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                          color: accent.withValues(alpha: 0.4),
                                          blurRadius: 6)
                                    ]),
                                child: Text(s['tag'] as String,
                                    style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black87,
                                        letterSpacing: 0.5)),
                              ),
                              const SizedBox(height: 8),
                              Text(s['title'] as String,
                                  style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      height: 1.15,
                                      letterSpacing: -0.3)),
                              const SizedBox(height: 4),
                              Text(s['sub'] as String,
                                  style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color: Colors.white.withValues(alpha: 0.72),
                                      height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Premium animated pill indicator
        ValueListenableBuilder<int>(
          valueListenable: _bannerIndex,
          builder: (context, bannerIndex, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (i) {
                final active = bannerIndex == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: active
                        ? const LinearGradient(
                            colors: [Color(0xFF1E3FD8), Color(0xFF3D6BFF)])
                        : null,
                    color: active
                        ? null
                        : (isDark ? Colors.white24 : AppColors.textLight),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8)
                          ]
                        : [],
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    String title, {
    String? subtitle,
    int? count,
    bool isHighlighted = false,
    bool isLoading = false,
    VoidCallback? onSeeAllTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colored left accent bar
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isHighlighted
                        ? [AppColors.secondary, const Color(0xFFFF3366)]
                        : [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isHighlighted
                                    ? [
                                        const Color(0xFFFF6B35)
                                            .withValues(alpha: 0.12),
                                        const Color(0xFFFF3366)
                                            .withValues(alpha: 0.08),
                                      ]
                                    : [
                                        const Color(0xFF0A2A9E)
                                            .withValues(alpha: 0.10),
                                        const Color(0xFF1E40AF)
                                            .withValues(alpha: 0.06),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isHighlighted
                                    ? const Color(0xFFFF3366)
                                        .withValues(alpha: 0.25)
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              '$count',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isHighlighted
                                    ? const Color(0xFFFF3366)
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color:
                              isDark ? Colors.white54 : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onSeeAllTap != null || isLoading)
          GestureDetector(
            onTap: isLoading ? null : onSeeAllTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.white70 : AppColors.primary,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: isDark ? Colors.white70 : AppColors.primary,
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  List<ShopModel> _getTop4DiverseShops(List<ShopModel> allShops) {
    if (allShops.isEmpty) return [];

    final sortedByRating = List<ShopModel>.from(allShops)
      ..sort((a, b) => b.rating.compareTo(a.rating));

    ShopModel? restaurant;
    ShopModel? grocery;
    ShopModel? clothing;
    ShopModel? pharmacy;

    final remaining = <ShopModel>[];

    for (final shop in sortedByRating) {
      final group = AppCategories.groupFor(shop.category);
      final catLower = shop.category.toLowerCase();

      if (restaurant == null && group == CategoryGroup.food) {
        restaurant = shop;
      } else if (grocery == null &&
          (group == CategoryGroup.perishable ||
              catLower.contains('grocery') ||
              catLower.contains('supermarket'))) {
        grocery = shop;
      } else if (clothing == null && catLower.contains('clothing')) {
        clothing = shop;
      } else if (pharmacy == null && group == CategoryGroup.pharmacy) {
        pharmacy = shop;
      } else {
        remaining.add(shop);
      }
    }

    final selected = <ShopModel>[];
    if (restaurant != null) selected.add(restaurant);
    if (grocery != null) selected.add(grocery);
    if (clothing != null) selected.add(clothing);
    if (pharmacy != null) selected.add(pharmacy);

    for (final shop in remaining) {
      if (selected.length >= 4) break;
      selected.add(shop);
    }

    return selected;
  }

  Widget _buildModernSeeAllButton(BuildContext context,
      {required String label,
      required VoidCallback onTap,
      required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: isDark ? Colors.white : AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoShopsNearby() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('🏪', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No shops nearby',
              style:
                  GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'No shops found within ${DeliveryCalculator.maxRadiusKm.toInt()} km of\nyour location in this category.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRequired() {
    return AnimatedBuilder(
      animation: _locationGlowAnim,
      builder: (context, child) {
        return Container(
          key: _locationRequiredKey,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (_locationGlowAnim.value > 0)
                BoxShadow(
                  color: AppColors.primary
                      .withValues(alpha: 0.3 * _locationGlowAnim.value),
                  blurRadius: 15 * _locationGlowAnim.value,
                  spreadRadius: 5 * _locationGlowAnim.value,
                )
            ],
            border: Border.all(
              color:
                  AppColors.primary.withValues(alpha: _locationGlowAnim.value),
              width: 2 * _locationGlowAnim.value,
            ),
          ),
          child: child,
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📍', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 20),
              Text(
                'Location Required',
                style: GoogleFonts.outfit(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'We need your location to show nearby shops and ensure delivery is available.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () =>
                    context.read<LocationProvider>().requestLocation(),
                icon: const Icon(Icons.my_location),
                label: const Text('Enable Location'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptEnableLocation() {
    if (_locationRequiredKey.currentContext != null) {
      Scrollable.ensureVisible(
        _locationRequiredKey.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
    _locationGlowCtrl.forward(from: 0).then((_) {
      _locationGlowCtrl.reverse();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please enable location to view nearby items.'),
        backgroundColor: AppColors.danger,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8EE);
    final highlight =
        isDark ? const Color(0xFF26263A) : const Color(0xFFF4F4FA);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Banner skeleton
          Container(
            height: 190,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          // Card skeletons (restaurant-style)
          ...List.generate(
            2,
            (_) => Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  // Banner skeleton
                  Container(
                    height: 185,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name bar
                        Container(
                            height: 18,
                            width: 200,
                            decoration: BoxDecoration(
                                color: base,
                                borderRadius: BorderRadius.circular(9))),
                        const SizedBox(height: 8),
                        // Cuisine chips
                        Row(
                          children: [
                            Container(
                                height: 22,
                                width: 70,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(8))),
                            const SizedBox(width: 8),
                            Container(
                                height: 22,
                                width: 80,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(8))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: base, height: 1),
                        const SizedBox(height: 12),
                        // Meta chips row
                        Row(
                          children: [
                            Container(
                                height: 28,
                                width: 80,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                            const SizedBox(width: 8),
                            Container(
                                height: 28,
                                width: 100,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                            const SizedBox(width: 8),
                            Container(
                                height: 28,
                                width: 60,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isFilterSheetOpen = false;
  void _showFilterSheet(BuildContext context, bool isDark) {
    if (_isFilterSheetOpen) return;
    _isFilterSheetOpen = true;

    // Cache available sizes if no size filter is currently active
    if (_selectedSizes.isEmpty) {
      _cachedAvailableSizes.clear();
      final productsToCheck =
          _searchQuery.isNotEmpty ? _searchProductResults : _products;
      for (final p in productsToCheck) {
        for (final v in p.variants) {
          if (v.name.trim().isNotEmpty && v.isAvailable) {
            _cachedAvailableSizes.add(v.name.trim());
          }
        }
      }
    }
    final sortedAvailableSizes = _cachedAvailableSizes.toList()..sort();

    // Create localized state copies to prevent desync on sheet dismissal
    final Set<String> tempSelectedSizes = Set.from(_selectedSizes);
    final Set<String> tempCategories = Set.from(_selectedFilterCategories);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          bool isApplying = false;
          final catNames = AppCategories.names;
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filters',
                        style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sort By',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildSortChip('Relevant', _SortMode.relevant,
                                setSheetState, isDark),
                            _buildSortChip('Nearest', _SortMode.nearest,
                                setSheetState, isDark),
                            _buildSortChip('Price: Low to High',
                                _SortMode.priceLow, setSheetState, isDark),
                            _buildSortChip('Price: High to Low',
                                _SortMode.priceHigh, setSheetState, isDark),
                            _buildSortChip('Best Rating', _SortMode.bestRating,
                                setSheetState, isDark),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Categories',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: catNames.map((cat) {
                            final isSelected = tempCategories.contains(cat);
                            return ChoiceChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (selected) {
                                setSheetState(() {
                                  if (selected) {
                                    tempCategories.add(cat);
                                  } else {
                                    tempCategories.remove(cat);
                                  }
                                });
                              },
                              selectedColor:
                                  AppColors.primary.withValues(alpha: 0.15),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A3E)
                                  : Colors.grey.shade100,
                              labelStyle: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.black)),
                              side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.transparent),
                            );
                          }).toList(),
                        ),
                        if (sortedAvailableSizes.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text('Sizes',
                              style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sortedAvailableSizes.map((size) {
                              final isSelected =
                                  tempSelectedSizes.contains(size);
                              return ChoiceChip(
                                label: Text(size),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      tempSelectedSizes.add(size);
                                    } else {
                                      tempSelectedSizes.remove(size);
                                    }
                                  });
                                },
                                selectedColor:
                                    AppColors.primary.withValues(alpha: 0.15),
                                backgroundColor: isDark
                                    ? const Color(0xFF2A2A3E)
                                    : Colors.grey.shade100,
                                labelStyle: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isDark
                                            ? Colors.white70
                                            : Colors.black)),
                                side: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.transparent),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (isApplying) return;
                      isApplying = true;

                      // Apply temp localized state to parent state
                      _selectedSizes.clear();
                      _selectedSizes.addAll(tempSelectedSizes);
                      _selectedFilterCategories.clear();
                      _selectedFilterCategories.addAll(tempCategories);

                      Navigator.pop(context);
                      setState(() {});
                      if (_searchQuery.isNotEmpty) {
                        _searchShops(_searchQuery, skipNLP: true);
                      } else {
                        if (_selectedTabIndex < 0) {
                          _loadAllData();
                        } else {
                          _loadData(_categories[_selectedTabIndex]['name']!
                              as String);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Apply Filters',
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) {
      _isFilterSheetOpen = false;
    });
  }

  Widget _buildSortChip(
      String label, _SortMode mode, StateSetter setSheetState, bool isDark) {
    final isSelected = _sortMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setSheetState(() => _sortMode = mode);
        }
      },
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100,
      labelStyle: TextStyle(
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black)),
      side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent),
    );
  }

  // ── Trending Now Auto-Marquee Strip ──────────────────────────────────────────
  // Purely additive UI — no SQL, no new state, reuses existing _searchShops().
  Widget _buildTrendingStrip(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF512F), Color(0xFFF09819)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        'Trending',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Tap to search instantly',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Builder(builder: (context) {
            // Active list: DB-fetched trending OR static fallback if DB empty/error
            final activeKeywords = _dynamicTrendingKeywords.isNotEmpty
                ? _dynamicTrendingKeywords
                : _staticFallbackKeywords;
            return SizedBox(
              height: 36,
              child: ListView.builder(
                controller: _trendingScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Duplicate list for infinite loop illusion
                itemCount: activeKeywords.length * 2,
                itemBuilder: (context, index) {
                  final kw = activeKeywords[index % activeKeywords.length];
                  final label = kw['label'] as String;
                  final emoji = kw['emoji'] as String;
                  return GestureDetector(
                    onTap: () {
                      // Pause auto-scroll temporarily so user can see result
                      _trendingScrollTimer?.cancel();
                      _searchController.text = label;
                      _searchShops(label);
                      // Resume after 5 seconds
                      Future.delayed(const Duration(seconds: 5), () {
                        if (mounted) _startTrendingScroll();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2035) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Shop by Category Section ────────────────────────────────────────────────
  // 5 main categories + a "See More" card, horizontally swipable.
  // Tap: filter home page in-place (same logic as old upper chips).
  // Long-press: navigate to dedicated CategoryProductsPage.
  Widget _buildCategorySection(bool isDark) {
    // First 5 entries from the already-existing _categories list
    final mainCats = _categories.take(5).toList();
    final remainingCount = _categories.length > 5 ? _categories.length - 5 : 29;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'Explore Categories',
          subtitle: _selectedTabIndex >= 0
              ? 'Filtering feed • Tap again to show all'
              : 'Tap to filter feed • Hold to view catalog',
          onSeeAllTap: () =>
              Navigator.pushNamed(context, AppRoutes.allCategories),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 116,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            // +1 for the "See More" card
            itemCount: mainCats.length + 1,
            itemBuilder: (context, index) {
              // ── "See More" card (last item) ────────────────────────────────
              if (index == mainCats.length) {
                return PerspectiveCard(
                  borderRadius: 22,
                  maxTiltAngle: 0.08,
                  pressScale: 0.95,
                  onTap: () {
                    SensoryHaptics.light();
                    Navigator.pushNamed(context, AppRoutes.allCategories);
                  },
                  child: Container(
                    width: 90,
                    margin: const EdgeInsets.only(right: 10, top: 2, bottom: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF16192B)
                          : const Color(0xFFF4F6FB),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.20),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.35)
                              : AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Subtle gradient accent aura in corner
                        Positioned(
                          top: -15,
                          right: -15,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryDark,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.grid_view_rounded,
                                  size: 19,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'See All',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: isDark ? 0.22 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '+$remainingCount More',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.primaryLight
                                        : AppColors.primary,
                                  ),
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

              // ── Main category card ─────────────────────────────────────────
              final cat = mainCats[index];
              final grad = cat['grad'] as List<Color>;
              final catName = cat['name'] as String;
              final displayLabel = catName == 'Supermarket / Hypermarket'
                  ? 'Supermarket\nHypermarket'
                  : catName;
              final imageUrl = AppCategories.getImageUrl(catName);
              final isSelected = _selectedTabIndex == index;

              return PerspectiveCard(
                borderRadius: 22,
                maxTiltAngle: 0.08,
                pressScale: 0.95,
                // Tap: filter home page in-place (same exact logic as old upper chips)
                onTap: () {
                  SensoryHaptics.light();
                  if (!context.read<LocationProvider>().hasLocation) {
                    _promptEnableLocation();
                    return;
                  }
                  if (_selectedTabIndex == index) {
                    // Toggle off: already selected → reset to all
                    setState(() => _selectedTabIndex = -1);
                    _loadAllData();
                  } else {
                    // Select: filter by this category
                    setState(() => _selectedTabIndex = index);
                    _loadData(catName);
                  }
                },
                // Long-press: navigate to dedicated full category page
                onLongPress: () {
                  SensoryHaptics.medium();
                  if (!context.read<LocationProvider>().hasLocation) {
                    _promptEnableLocation();
                    return;
                  }
                  Navigator.pushNamed(
                    context,
                    AppRoutes.categoryProducts,
                    arguments: {'categoryName': catName},
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 96 : 90,
                  margin: const EdgeInsets.only(right: 10, top: 2, bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    // Selected state: vibrant ambient halo glow
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? grad.first.withValues(alpha: 0.55)
                            : isDark
                                ? Colors.black.withValues(alpha: 0.30)
                                : Colors.black.withValues(alpha: 0.08),
                        blurRadius: isSelected ? 16 : 10,
                        offset: Offset(0, isSelected ? 6 : 3),
                      ),
                    ],
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : isDark
                              ? Colors.white.withValues(alpha: 0.09)
                              : Colors.black.withValues(alpha: 0.05),
                      width: isSelected ? 2.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(isSelected ? 19.5 : 21),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Hero Photo
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          maxWidthDiskCache: 600,
                          fadeInDuration: const Duration(milliseconds: 250),
                          placeholder: (context, url) => Container(
                            color: grad.first.withValues(alpha: 0.25),
                            child: Center(
                              child: Text(
                                cat['emoji'] as String? ?? '🏬',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: grad,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                cat['emoji'] as String? ?? '🏬',
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),

                        // High-contrast gradient scrim (Clear top, deep elegant glass bottom)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.35),
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),

                        // Selected checkmark badge & active indicator ring
                        if (isSelected)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 11,
                                color: grad.first,
                              ),
                            ),
                          ),

                        // Category Label + Emoji Micro-avatar
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    displayLabel,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w900
                                          : FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.12,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(height: 3),
                                  Container(
                                    width: 14,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ],
                              ],
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
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
