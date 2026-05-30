import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/theme_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../config/app_categories.dart';
import '../../utils/delivery_calculator.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../widgets/common/notification_bell.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  int _selectedTabIndex = -1; // -1 = no tab selected (show ALL)
  int _navIndex = 0;
  bool _isLoading = true;
  bool _isSearching = false;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _products = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

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
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newIndex = _tabController.index;
        setState(() => _selectedTabIndex = newIndex);
        _loadData(_categories[newIndex]['name']! as String);
      }
    });
    // Load ALL shops/products on startup — no tab pre-selected
    _checkLocationAndLoad();
    _startNotifications();
    // Subscribe to live GPS updates so distance filter stays accurate
    _startLiveLocationUpdates();
  }

  void _startLiveLocationUpdates() {
    // Re-fetch data whenever GPS location changes significantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().addListener(_onLocationChanged);
    });
  }

  void _onLocationChanged() {
    // When location provider updates (new GPS fix), refresh the shop list
    // so distance calculations use the latest coordinates
    if (mounted && !_isLoading && _searchQuery.isEmpty) {
      if (_selectedTabIndex < 0) {
        _loadAllData();
      } else {
        _loadData(_categories[_selectedTabIndex]['name']! as String);
      }
    }
  }


  void _startNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsCustomer(userId);
        notifProvider.registerFcmToken(userId); // Register push token
      }
    });
  }

  @override
  void dispose() {
    // Remove live location listener to avoid memory leaks
    context.read<LocationProvider>().removeListener(_onLocationChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }


  /// Runs a Supabase text search for shops by name across all categories.
  Future<void> _searchShops(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
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
      final response =
          await _supabase.from('shops').select().ilike('name', '%$query%');

      final allShops =
          (response as List).map((s) => ShopModel.fromMap(s)).toList();

      List<ShopModel> results;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          shop.distanceKm = locationProvider.distanceTo(shop.location);
        }
        results = allShops
            .where((s) => DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      } else {
        results = allShops;
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
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
    'Food': ['Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Beverages'],
    'Grocery': ['Grocery', 'Fruits & Vegs', 'Dairy & Eggs', 'Butcher', 'Fish & Seafood', 'Organic'],
    'Pharmacy': ['Pharmacy', 'Medical Store'],
    'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
    'Electronics': ['Electronics', 'Mobile & Repair'],
    'More': ['Hardware Store', 'Stationery', 'Toys & Games', 'Sports', 'Pet Supplies', 'Salon & Beauty', 'Flowers', 'Home Decor', 'Furniture', 'Auto Parts', 'Other'],
  };

  /// Fetch ALL active shops & products, sorted by rating then total_orders.
  /// Used on initial load when no category tab is selected.
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final locationProvider = context.read<LocationProvider>();

      // Fetch all shops, then filter is_active locally to bypass any RLS column blocks
      final shopsResponse = await _supabase
          .from('shops')
          .select();

      final productsResponse = await _supabase
          .from('products')
          .select()
          .limit(100);

      if (mounted) {
        final allShops = (shopsResponse as List)
            .map((s) => ShopModel.fromMap(s))
            .where((s) => s.isActive)
            .toList();

        List<ShopModel> nearby;
        if (locationProvider.hasLocation) {
          for (final shop in allShops) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          }
          nearby = allShops
              .where((s) =>
                  // Show shops with no GPS stored (0,0) OR within 9 km
                  (s.location.latitude == 0 && s.location.longitude == 0) ||
                  DeliveryCalculator.isWithinRange(s.distanceKm!))
              .toList()
            ..sort((a, b) {
              // Primary sort: higher rating first
              final ratingCmp = (b.rating).compareTo(a.rating);
              if (ratingCmp != 0) return ratingCmp;
              // Secondary: closer distance first
              return (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0);
            });
        } else {
          // No GPS yet — show all active shops sorted by rating
          nearby = allShops
            ..sort((a, b) => b.rating.compareTo(a.rating));
        }

        final prods = (productsResponse as List)
            .map((p) => ProductModel.fromMap(p))
            .where((p) => p.isAvailable)
            .toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));

        setState(() {
          _shops = nearby;
          _products = prods;
          _isLoading = false;
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
    setState(() => _isLoading = true);
    try {
      final locationProvider = context.read<LocationProvider>();
      final subcategories = _tabCategories[tabName] ?? [tabName];

      // Build OR filter for all subcategories in this tab
      final catFilter = subcategories
          .map((c) => 'category.eq.$c')
          .join(',');

      // Fetch all, filter locally
      final shopsResponse = await _supabase
          .from('shops')
          .select()
          .or(catFilter);

      final productsResponse = await _supabase
          .from('products')
          .select()
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
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          }
          nearby = allShops
              .where((s) =>
                  (s.location.latitude == 0 && s.location.longitude == 0) ||
                  DeliveryCalculator.isWithinRange(s.distanceKm!))
              .toList()
            ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
        } else {
          nearby = allShops
            ..sort((a, b) => b.rating.compareTo(a.rating));
        }

        final prods = (productsResponse as List)
            .map((p) => ProductModel.fromMap(p))
            .where((p) => p.isAvailable)
            .toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));
        setState(() {
          _shops = nearby;
          _products = prods;
          _isLoading = false;
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Premium Modern AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showLocationSheet(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'DELIVERING TO',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down,
                                        size: 16, color: AppColors.primary),
                                  ],
                                ),
                                Text(
                                  locationProvider.hasLocation
                                      ? locationProvider
                                              .currentAddress.isNotEmpty
                                          ? locationProvider.currentAddress
                                          : 'Current Location'
                                      : 'Set location...',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
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
                  ],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
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
                        filled: true,
                        fillColor:
                            Theme.of(context).inputDecorationTheme.fillColor ??
                                Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
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

          // ── Categories Horizontal List ──────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 108,
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
                        // Tap selected tab again → go back to All
                        setState(() => _selectedTabIndex = -1);
                        _loadAllData();
                      } else {
                        _tabController.animateTo(index);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      width: 76,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      colors: grad,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight)
                                  : null,
                              color: isSelected
                                  ? null
                                  : (isDark
                                      ? const Color(0xFF1E1E2E)
                                      : const Color(0xFFF0F0F8)),
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                          color: grad.first.withValues(alpha: 0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4))
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: (isSelected && cat['name'] == 'Grocery')
                                  ? ColorFiltered(
                                      colorFilter: const ColorFilter.mode(
                                        Colors.black87,
                                        BlendMode.srcIn,
                                      ),
                                      child: Text(cat['emoji'], style: const TextStyle(fontSize: 26)),
                                    )
                                  : Text(cat['emoji'], style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cat['name'],
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? grad.first
                                  : (isDark
                                      ? Colors.white54
                                      : Colors.grey.shade600),
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
                                  : '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                            ),
                            const SizedBox(height: 16),
                            if (_isSearching)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_searchResults.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Text('🔍',
                                          style: TextStyle(fontSize: 48)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No shops found for "$_searchQuery"',
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
                            else
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
                            ..._shops.map((shop) {
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
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.72,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                              ),
                              itemCount: _products.length,
                              itemBuilder: (context, index) =>
                                  ProductCard(product: _products[index]),
                            ),
                          ],
                        ]),
                      ),
          ),
        ],
      ),

      // ── Floating Action Bar (Bottom Nav Replacement) ────────────────
      bottomNavigationBar: _buildFloatingBottomNav(cartProvider),
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
    return Container(
      width: double.infinity,
      height: 170,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1260), Color(0xFF162AC4), Color(0xFF2444E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF162AC4).withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
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
              right: 30,
              bottom: -40,
              child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF4C542).withValues(alpha: 0.12)))),
          Positioned(
              right: -10,
              bottom: -10,
              child: Icon(Icons.bolt_rounded,
                  size: 140, color: Colors.white.withValues(alpha: 0.06))),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4C542),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('⚡ FAST DELIVERY',
                      style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 14),
                Text('Delivered at the\nspeed of life!',
                    style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1)),
                const SizedBox(height: 8),
                Text('Supporting local sellers · 5% commission',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        Text(
          'See all',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
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
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1260), Color(0xFF162AC4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
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
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label,
      {int badge = 0}) {
    final isSelected = _navIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _navIndex = index);
        if (index == 1) Navigator.pushNamed(context, AppRoutes.cart);
        if (index == 2) Navigator.pushNamed(context, AppRoutes.orderHistory);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: isSelected
              ? Border.all(color: Colors.white.withValues(alpha: 0.2))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
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
            if (isSelected) ...[
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700))
            ],
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
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade200,
      highlightColor: isDark ? const Color(0xFF2A2A3A) : Colors.grey.shade100,
      child: Column(
        children: List.generate(
            3,
            (_) => Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                )),
      ),
    );
  }

  void _showLocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Delivery Location',
                style: GoogleFonts.outfit(
                    fontSize: 20, fontWeight: FontWeight.w700)),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
