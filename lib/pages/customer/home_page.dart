import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/platform_config_provider.dart';
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
import '../../widgets/common/notification_bell.dart';
import '../../widgets/address_picker_sheet.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  int _selectedTabIndex = -1; // -1 = no tab selected (show ALL)
  int _navIndex = 0;
  bool _isLoading = true;
  bool _isSearching = false;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _searchProductResults = [];
  Map<String, ShopModel> _searchProductShops = {};
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
  String _searchQuery = '';
  final _searchController = TextEditingController();
  // Debounce timer for GPS listener to prevent race conditions
  Timer? _locationDebounceTimer;
  // Track if the very first load has completed (shimmer only on first load)
  bool _hasLoadedOnce = false;

  // Banner carousel
  final PageController _bannerController = PageController();
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  /// True when a food-type tab is currently selected.
  bool get _isFoodTab {
    if (_selectedTabIndex < 0) return false;
    final name = _categories[_selectedTabIndex]['name'] as String;
    return name == 'Food';
  }

  final List<Map<String, dynamic>> _categories = [
    {
      'name': 'Food',
      'emoji': '🍔',
      'grad': [const Color(0xFFFF6B6B), const Color(0xFFEE5A24)]
    },
    {
      'name': 'Grocery',
      'emoji': '🛒',
      'grad': [const Color(0xFF51CF66), const Color(0xFF2F9E44)]
    },
    {
      'name': 'Pharmacy',
      'emoji': '💊',
      'grad': [const Color(0xFF4C6EF5), const Color(0xFF364FC7)]
    },
    {
      'name': 'Clothing',
      'emoji': '👕',
      'grad': [const Color(0xFFFF8C42), const Color(0xFFE8590C)]
    },
    {
      'name': 'Electronics',
      'emoji': '📱',
      'grad': [const Color(0xFFCC5DE8), const Color(0xFF9C36B5)]
    },
    {
      'name': 'More',
      'emoji': '🛍️',
      'grad': [const Color(0xFF20C997), const Color(0xFF0CA678)]
    },
  ];

  @override
  void initState() {
    super.initState();
    // Load ALL shops/products on startup — no tab pre-selected
    _checkLocationAndLoad();
    _startNotifications();
    // Subscribe to live GPS updates so distance filter stays accurate
    _startLiveLocationUpdates();
    // Auto-scroll banner every 4 seconds
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % 3;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
    // Fetch favorites and saved address
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId != null) {
        context.read<FavoritesProvider>().fetchFavorites(auth.currentUserId!);
        context.read<LocationProvider>().loadAddressFromDb(auth.currentUserId!);
      }
    });
  }

  void _startLiveLocationUpdates() {
    // Re-fetch data whenever GPS location changes significantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().addListener(_onLocationChanged);
    });
  }

  void _onLocationChanged() {
    // When location provider updates (new GPS fix), refresh the shop list.
    // IMPORTANT: Debounce to prevent race conditions where:
    //   1) User taps a category → _loadData() starts
    //   2) GPS fires → _onLocationChanged triggers another _loadData()
    //   3) Second load sets _isLoading=true, wiping the first load's results
    if (!mounted || _isLoading || _searchQuery.isNotEmpty) return;
    _locationDebounceTimer?.cancel();
    _locationDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isLoading) return;
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
    _bannerTimer?.cancel();
    _locationDebounceTimer?.cancel();
    // Remove live location listener to avoid memory leaks
    context.read<LocationProvider>().removeListener(_onLocationChanged);
    _searchController.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  /// Runs a Supabase text search for shops by name across all categories.
  Future<void> _searchShops(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _searchProductResults = [];
        _searchProductShops = {};
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });
    try {
      final locationProvider = context.read<LocationProvider>();

      final shopsResponse =
          await _supabase.from('shops').select().ilike('name', '%$query%');

      final productsResponse = await _supabase
          .from('products')
          .select('*, shops(*)')
          .ilike('name', '%$query%');

      final allShops =
          (shopsResponse as List).map((s) => ShopModel.fromMap(s)).toList();

      List<ShopModel> shopResults;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        shopResults = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) => (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity));
      } else {
        shopResults = allShops;
      }

      final List<ProductModel> prodResults = [];
      final Map<String, ShopModel> prodShops = {};

      for (final p in productsResponse as List) {
        final product = ProductModel.fromMap(p);
        if (!product.isAvailable) continue;
        if (p['shops'] == null) continue;
        
        final shop = ShopModel.fromMap(p['shops']);
        if (!shop.isActive) continue;
        
        if (locationProvider.hasLocation) {
          if (shop.location.latitude == 0 || shop.location.longitude == 0) continue;
          final d = locationProvider.distanceTo(shop.location);
          if (!DeliveryCalculator.isWithinRange(d)) continue;
        }
        
        prodResults.add(product);
        prodShops[product.id] = shop;
      }

      // Ensure that if a shop matches because of a product, we don't accidentally
      // have it in `shopResults` unless its name actually matches the query.
      // But the Supabase query `ilike('name', '%$query%')` on `shops` already guarantees
      // it only matches by name.

      if (mounted) {
        // Prevent race condition: if the user typed something else while this
        // async request was flying, discard these results.
        if (_searchQuery != query) return;

        // Enforce extra client-side check to guarantee we only show shops that match
        // the search query by name. (This fixes an issue where shops could appear
        // when searching for a product name that doesn't match the shop name).
        final finalShopResults = shopResults
            .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
            .toList();

        setState(() {
          _searchResults = finalShopResults;
          _searchProductResults = prodResults;
          _searchProductShops = prodShops;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _checkLocationAndLoad() async {
    final locationProvider = context.read<LocationProvider>();
    if (!locationProvider.hasLocation) {
      await locationProvider.requestLocation();
    }
    // _selectedTabIndex == -1 means "All" — fetch every active shop
    if (_selectedTabIndex < 0) {
      _loadAllData();
    } else {
      _loadData(_categories[_selectedTabIndex]['name']! as String);
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
    // Only show the shimmer on the very first load. On subsequent loads
    // (e.g., GPS update or category deselect) keep old data visible.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();

      // Fetch all shops, then filter is_active locally to bypass any RLS column blocks
      final shopsResponse = await _supabase.from('shops').select();

      final productsResponse =
          await _supabase.from('products').select('*, shops(*)').limit(100);

      if (mounted) {
        final allShops = (shopsResponse as List)
            .map((s) => ShopModel.fromMap(s))
            .where((s) => s.isActive)
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

        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse as List) {
          final product = ProductModel.fromMap(p);
          if (!product.isAvailable) continue;
          if (p['shops'] == null) continue;
          
          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive) continue;

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) continue;
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }
        prods.sort((a, b) => b.rating.compareTo(a.rating));

        // Atomic update: swap data and clear loading in a single setState
        setState(() {
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (e, st) {
      // Log full error so we can debug exactly what Supabase query failed
      debugPrint('_loadAllData ERROR: $e\n$st');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e', maxLines: 5),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _loadData(String tabName) async {
    // Do NOT set _isLoading = true here on category switch — this causes the
    // existing content to disappear (the "flash"). Keep old data visible
    // and only swap data once the new fetch is complete.
    // Only show shimmer on the very first app load.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final subcategories = _tabCategories[tabName] ?? [tabName];

      // Fetch all, filter locally
      final shopsResponse =
          await _supabase.from('shops').select().inFilter('category', subcategories);

      final productsResponse = await _supabase
          .from('products')
          .select('*, shops(*)')
          .inFilter('category', subcategories)
          .limit(100);

      if (mounted) {
        final allShops = (shopsResponse as List)
            .map((s) => ShopModel.fromMap(s))
            .where((s) => s.isActive)
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

        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse as List) {
          final product = ProductModel.fromMap(p);
          if (!product.isAvailable) continue;
          if (p['shops'] == null) continue;
          
          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive) continue;

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) continue;
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }
        prods.sort((a, b) => b.rating.compareTo(a.rating));
        
        // Atomic update: swap data in a single setState so there is no
        // intermediate blank-screen state
        setState(() {
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (e, st) {
      debugPrint('_loadData ERROR: $e\n$st');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e', maxLines: 5),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final cartProvider = context.watch<CartProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    // Greeting based on time of day
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning ☀️'
        : hour < 17
            ? 'Good afternoon 🌤'
            : 'Good evening 🌙';
    final firstName =
        context.read<AuthProvider>().user?.fullName.split(' ').first ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [

          // ── Premium Modern AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 165,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Greeting + actions
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                firstName.isNotEmpty
                                    ? '$greeting, $firstName!'
                                    : '$greeting!',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        NotificationBell(
                          iconColor:
                              isDark ? Colors.white70 : AppColors.textPrimary,
                          containerColor: isDark
                              ? const Color(0xFF1E1E2E)
                              : const Color(0xFFF0F0F8),
                        ),
                        const SizedBox(width: 8),
                        _buildCircleAction(
                          icon: isDark ? Icons.light_mode : Icons.dark_mode,
                          isDark: isDark,
                          onTap: () => themeProvider.toggleTheme(),
                        ),
                        const SizedBox(width: 8),
                        _buildCircleAction(
                          icon: Icons.person_outline,
                          isDark: isDark,
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.settings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 2: Location pill
                    GestureDetector(
                      onTap: () => showAddressPickerSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : const Color(0xFFF0F0F8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (locationProvider.activeLabelIcon.isNotEmpty) ...[
                              Text(locationProvider.activeLabelIcon, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                locationProvider.activeLabel,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white30 : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ] else ...[
                              const Icon(Icons.location_on_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                locationProvider.hasLocation
                                    ? locationProvider.currentAddress.isNotEmpty
                                        ? locationProvider.currentAddress
                                        : 'Current Location'
                                    : 'Set location...',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: locationProvider.activeLabelIcon.isNotEmpty 
                                      ? FontWeight.w500 
                                      : FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: isDark
                                    ? Colors.white38
                                    : AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => _searchShops(v),
                      decoration: InputDecoration(
                        hintText: 'Search "Milk", "Pizza" or "Medicines"',
                        hintStyle: GoogleFonts.outfit(
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                            fontSize: 14),
                        prefixIcon:
                            const Icon(Icons.search, color: AppColors.primary),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchShops('');
                                    },
                                  )
                                : null,
                        filled: true,
                        fillColor:
                            Theme.of(context).inputDecorationTheme.fillColor ??
                                Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: isDark ? AppColors.primaryLight : AppColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Categories Horizontal List (pill style) ──────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedTabIndex == index;
                  final grad = cat['grad'] as List<Color>;
                  return GestureDetector(
                    onTap: () {
                      if (_selectedTabIndex == index) {
                        setState(() => _selectedTabIndex = -1);
                        _loadAllData();
                      } else {
                        setState(() => _selectedTabIndex = index);
                        _loadData(cat['name']);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin:
                          const EdgeInsets.only(right: 10, top: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: grad,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight)
                            : null,
                        color: isSelected
                            ? Colors.transparent
                            : (isDark
                                ? const Color(0xFF1E1E2E)
                                : const Color(0xFFF0F0F8)),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                    color: grad.first.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]
                            : [],
                        border: isSelected
                            ? null
                            : Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(fontSize: isSelected ? 20 : 16),
                            child: Text(cat['emoji']),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat['name'],
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700),
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

          // ── Main Content ──────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            // BUG FIX: no longer gate on location — show shops even without GPS.
            // If no location, distance filter is skipped and all active shops show.
            sliver: _isLoading
                ? SliverToBoxAdapter(child: _buildShimmer())
                : SliverList(
                    delegate: SliverChildListDelegate([
                      // Featured Banner
                      _buildFeaturedBanner(),
                      const SizedBox(height: 24),

                      // Shops Section
                      // ── Search Results (Supabase live search) ──────
                      if (_searchQuery.isNotEmpty) ...[
                        _buildSectionTitle(
                          'Search results',
                          subtitle: _isSearching
                              ? 'Searching...'
                              : '${_searchResults.length + _searchProductResults.length} result${(_searchResults.length + _searchProductResults.length) == 1 ? '' : 's'}',
                        ),
                        const SizedBox(height: 16),
                        if (_isSearching)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_searchResults.isEmpty &&
                            _searchProductResults.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                children: [
                                  const Text('🔍',
                                      style: TextStyle(fontSize: 48)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No results found for "$_searchQuery"',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          if (_searchResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text('Shops & Restaurants',
                                  style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                            ),
                            ..._searchResults.map((shop) {
                              final isFood =
                                  AppCategories.groupFor(shop.category) ==
                                      CategoryGroup.food;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: isFood
                                    ? RestaurantShopCard(
                                        shop: shop,
                                        onTap: () => Navigator.pushNamed(
                                          context,
                                          AppRoutes.restaurantDashboard,
                                          arguments: {'shopId': shop.id},
                                        ),
                                      )
                                    : ShopCard(
                                        shop: shop,
                                        onTap: () => Navigator.pushNamed(
                                          context,
                                          AppRoutes.restaurant,
                                          arguments: {'shopId': shop.id},
                                        ),
                                      ),
                              );
                            }),
                          ],
                          if (_searchProductResults.isNotEmpty) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12, top: 8),
                              child: Text('Items & Products',
                                  style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                            ),
                            ..._searchProductResults.map((product) {
                              final shop = _searchProductShops[product.id];
                              if (shop == null) return const SizedBox.shrink();
                              return ProductSearchCard(
                                product: product,
                                shop: shop,
                              );
                            }),
                          ],
                        ],
                      ] else if (_shops.isNotEmpty) ...[
                        // ── Normal category browse ───────────────────
                        _buildSectionTitle(
                          _selectedTabIndex < 0
                              ? 'All stores near you'
                              : _isFoodTab
                                  ? 'Restaurants near you'
                                  : 'Shops near you',
                          subtitle:
                              '${_shops.length} within ${DeliveryCalculator.maxRadiusKm.toInt()} km',
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = Responsive.getGridCrossAxisCount(context, mobile: 1, tablet: 2, desktop: 3);
                            const spacing = 16.0;
                            final itemWidth = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

                            return Wrap(
                              spacing: spacing,
                              runSpacing: 0,
                              children: _shops.map((shop) {
                                final isFood = AppCategories.groupFor(shop.category) == CategoryGroup.food;
                                return SizedBox(
                                  width: itemWidth,
                                  child: isFood
                                      ? RestaurantShopCard(
                                          shop: shop,
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.restaurantDashboard,
                                            arguments: {'shopId': shop.id},
                                          ),
                                        )
                                      : ShopCard(
                                          shop: shop,
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.restaurant,
                                            arguments: {'shopId': shop.id},
                                          ),
                                        ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ] else if (!_isLoading) ...[
                        locationProvider.hasLocation
                            ? _buildNoShopsNearby()
                            : _buildLocationRequired(),
                      ],

                      // Products Section
                      if (_products.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildSectionTitle('Popular in your area'),
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.getGridCrossAxisCount(context, mobile: 2, tablet: 4, desktop: 5),
                            childAspectRatio: 0.65,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            final shop = _productShops[product.id];
                            return ProductCard(product: product, shop: shop);
                          },
                        ),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
      ),

      // ── Floating Action Bar (Bottom Nav Replacement) ────────────────
      bottomNavigationBar: MaxWidthContainer(
        maxWidth: 600,
        alignment: Alignment.bottomCenter,
        child: _buildFloatingBottomNav(cartProvider),
      ),
    ));
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
          color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8),
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
    final config = context.watch<PlatformConfigProvider>();
    final slides = [
      {
        'tag': '⚡ FAST DELIVERY',
        'title': 'Delivered at the\nspeed of life!',
        'sub':
            'Supporting local sellers · ${config.unifiedCommissionPercent.toStringAsFixed(2)}% commission',
        'icon': Icons.bolt_rounded,
        'colors': [
          const Color(0xFF0A1260),
          const Color(0xFF162AC4),
          const Color(0xFF2444E8)
        ],
        'accent': const Color(0xFFF4C542),
      },
      {
        'tag': '🏪 LOCAL SHOPS',
        'title': 'Support your\ncommunity!',
        'sub': 'Local shops near you · fresh & authentic',
        'icon': Icons.storefront_rounded,
        'colors': [
          const Color(0xFF0F4C1A),
          const Color(0xFF1A7A30),
          const Color(0xFF27AE60)
        ],
        'accent': const Color(0xFF7DEFA1),
      },
      {
        'tag': '📍 LIVE TRACKING',
        'title': 'Track your\norder live!',
        'sub': 'Real-time GPS route · always in the know',
        'icon': Icons.map_rounded,
        'colors': [
          const Color(0xFF4A0080),
          const Color(0xFF7B1FA2),
          const Color(0xFFAB47BC)
        ],
        'accent': const Color(0xFFE1BEE7),
      },
    ];

    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemCount: slides.length,
            itemBuilder: (_, i) {
              final s = slides[i];
              final colors = s['colors'] as List<Color>;
              final accent = s['accent'] as Color;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: colors[1].withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 12)),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                        right: -30,
                        top: -30,
                        child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05)))),
                    Positioned(
                        right: -10,
                        bottom: -10,
                        child: Icon(s['icon'] as IconData,
                            size: 140,
                            color: Colors.white.withValues(alpha: 0.06))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(s['tag'] as String,
                                style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(height: 14),
                          Text(s['title'] as String,
                              style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.1)),
                          const SizedBox(height: 8),
                          Text(s['sub'] as String,
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Dot indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slides.length, (i) {
            final active = _bannerIndex == i;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.textLight,
                borderRadius: BorderRadius.circular(3),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6)
                      ]
                    : [],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.blue.shade300 : AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: isDark ? Colors.blue.shade300 : AppColors.primary,
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildFloatingBottomNav(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0A1260).withValues(alpha: 0.85),
                  const Color(0xFF162AC4).withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF162AC4).withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
                _buildNavItem(1, Icons.shopping_cart_rounded,
                    Icons.shopping_cart_outlined, 'Cart',
                    badge: cart.totalItemCount),
                _buildNavItem(2, Icons.receipt_long_rounded,
                    Icons.receipt_long_outlined, 'Orders'),
                _buildNavItem(3, Icons.favorite_rounded,
                    Icons.favorite_border_rounded, 'Favs'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Need to use dart:ui for blur. Instead of importing dart:ui globally, we can use 
  // ImageFilter.blur by importing dart:ui inside the file, but we'll just use flutter's ImageFilter.
  // We need to import 'dart:ui' at the top of the file. I will use a simple way:
  // Actually, wait, ImageFilter is in dart:ui. Let's add the import or just use a helper.

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label,
      {int badge = 0}) {
    final isSelected = _navIndex == index;
    return GestureDetector(
      onTap: () async {
        if (index == 0) {
          setState(() => _navIndex = 0);
          return;
        }

        setState(() => _navIndex = index);

        if (!mounted) return;

        if (index == 1) {
          await Navigator.pushNamed(context, AppRoutes.cart);
        } else if (index == 2) {
          await Navigator.pushNamed(context, AppRoutes.orderHistory);
        } else if (index == 3) {
          await Navigator.pushNamed(context, AppRoutes.favorites);
        }

        if (mounted) {
          setState(() => _navIndex = 0);
        }
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(isSelected ? activeIcon : inactiveIcon,
                      color: isSelected ? Colors.white : Colors.white54,
                      size: 22),
                  if (badge > 0)
                    Positioned(
                      right: -7,
                      top: -7,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF6B6B), shape: BoxShape.circle),
                        child: Center(
                            child: Text('$badge',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold))),
                      ),
                    ),
                ],
              ),
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

  Widget _buildLocationRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📍', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 20),
            Text(
              'Location Required',
              style:
                  GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700),
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
    );
  }

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use stable hex constants instead of .shade getters to prevent
    // the dart:ui/painting.dart assertion crash
    final base = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE0E0E0);
    final highlight = isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF5F5F5);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        children: List.generate(
            2,
            (_) => Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      // Banner skeleton
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: base,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title bar
                            Container(height: 16, width: 180, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(8))),
                            const SizedBox(height: 8),
                            // Subtitle bar
                            Container(height: 12, width: 120, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                            const SizedBox(height: 10),
                            const Divider(),
                            const SizedBox(height: 10),
                            // Chips row
                            Row(
                              children: [
                                Container(height: 12, width: 40, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                                const SizedBox(width: 10),
                                Container(height: 12, width: 60, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                                const SizedBox(width: 10),
                                Container(height: 12, width: 40, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
      ),
    );
  }

  void _showLocationSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Delivery Location',
                style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                context.read<LocationProvider>().requestLocation();
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Use Current Location'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}
