import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/notification_provider.dart';

import '../../providers/recently_viewed_provider.dart';
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
import '../../widgets/address_picker_sheet.dart';

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
      _selectedFilterCategories.clear();
      _searchQuery = '';
      _searchController.clear();
    });
    _loadAllData();
  }

  final _supabase = Supabase.instance.client;
  int _selectedTabIndex = -1; // -1 = no tab selected (show ALL)
  bool _isLoading = true;
  bool _isSearching = false;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _searchProductResults = [];
  Map<String, ShopModel> _searchProductShops = {};
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.relevant;
  final _searchController = TextEditingController();
  final Set<String> _selectedFilterCategories = {};

  static const Map<String, List<String>> _searchKeywords = {
    'Food': ['food', 'eat', 'hungry', 'pizza', 'burger', 'meal', 'restaurant', 'fast food', 'biryani', 'chicken', 'mutton', 'kebab', 'fries'],
    'Grocery': ['grocery', 'milk', 'bread', 'eggs', 'supermarket', 'ration', 'vegetables', 'fruits', 'apple', 'banana', 'meat', 'beef', 'dal', 'rice'],
    'Pharmacy': ['pharmacy', 'medicine', 'pill', 'tablet', 'syrup', 'medical', 'health', 'drug', 'panadol', 'paracetamol', 'clinic', 'doctor'],
    'Clothing': ['clothing', 'clothes', 'shirt', 'pant', 'shoes', 'fashion', 'apparel', 'wear', 'dress', 'tshirt', 'jeans', 'jacket', 'sneakers'],
    'Electronics': ['electronics', 'mobile', 'phone', 'laptop', 'charger', 'gadget', 'device', 'computer', 'earbuds', 'headphones', 'cable'],
  };
  // Debounce timer for GPS listener to prevent race conditions
  Timer? _locationDebounceTimer;

  /// Returns search product results sorted by the current _sortMode.
  List<ProductModel> get _sortedProductResults {
    final list = List<ProductModel>.from(_searchProductResults);
    switch (_sortMode) {
      case _SortMode.bestRating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case _SortMode.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _SortMode.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _SortMode.discount:
        list.sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
      case _SortMode.nearest:
        list.sort((a, b) {
          final sA = _searchProductShops[a.id];
          final sB = _searchProductShops[b.id];
          return (sA?.distanceKm ?? double.infinity).compareTo(sB?.distanceKm ?? double.infinity);
        });
      case _SortMode.relevant:
        break;
    }
    return list;
  }

  /// Returns search shop results sorted by the current _sortMode.
  List<ShopModel> get _sortedShopResults {
    final list = List<ShopModel>.from(_searchResults);
    switch (_sortMode) {
      case _SortMode.bestRating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      default:
        list.sort((a, b) => (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity));
        break;
    }
    return list;
  }
  // Track if the very first load has completed (shimmer only on first load)
  bool _hasLoadedOnce = false;

  // Banner carousel
  final PageController _bannerController = PageController();
  int _bannerIndex = 0;
  Timer? _bannerTimer;
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
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
        _sortMode = _SortMode.relevant; // reset sort on clear
      });
      return;
    }
    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });
    try {
      final locationProvider = context.read<LocationProvider>();

      final lowerQuery = query.toLowerCase().trim();
      final List<String> matchedSubcategories = [];
      _searchKeywords.forEach((catName, keywords) {
        bool match = keywords.any((k) {
          if (lowerQuery.length < 3) return lowerQuery == k;
          return lowerQuery.contains(k) || k.contains(lowerQuery);
        });
        if (match) {
          matchedSubcategories.addAll(_tabCategories[catName] ?? [catName]);
        }
      });

      List<String>? effectiveCategories;
      if (_selectedFilterCategories.isNotEmpty) {
        effectiveCategories = [];
        for (final cat in _selectedFilterCategories) {
          effectiveCategories.addAll(_tabCategories[cat] ?? [cat]);
        }
      }

      final shopsByName = await _supabase.from('shops').select().ilike('name', '%$query%');
      final productsByName = await _supabase.from('products').select('*, shops(*)').ilike('name', '%$query%');
      
      List<dynamic> shopsByCat = [];
      List<dynamic> productsByCat = [];

      if (matchedSubcategories.isNotEmpty) {
        shopsByCat = await _supabase.from('shops').select().inFilter('category', matchedSubcategories);
        productsByCat = await _supabase.from('products').select('*, shops(*)').inFilter('category', matchedSubcategories).limit(100);
      }

      final allShopsSet = <String, ShopModel>{};
      
      void addShops(List<dynamic> response, bool requireNameMatch) {
        for (final s in response) {
          final shop = ShopModel.fromMap(s);
          if (requireNameMatch && !shop.name.toLowerCase().contains(lowerQuery)) continue;
          if (effectiveCategories != null && !effectiveCategories.contains(shop.category)) continue;
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
        shopResults = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList();
      } else {
        shopResults = allShops;
      }

      final List<ProductModel> prodResults = [];
      final Map<String, ShopModel> prodShops = {};
      final addedProductIds = <String>{};

      void addProducts(List<dynamic> response) {
        for (final p in response) {
          final product = ProductModel.fromMap(p);
          if (!product.isAvailable) continue;
          if (addedProductIds.contains(product.id)) continue;
          
          if (effectiveCategories != null && !effectiveCategories.contains(product.category)) continue;
          if (p['shops'] == null) continue;
          
          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive) continue;
          if (effectiveCategories != null && !effectiveCategories.contains(shop.category)) continue;
          
          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) continue;
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }
          
          prodResults.add(product);
          prodShops[product.id] = shop;
          addedProductIds.add(product.id);
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
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _checkLocationAndLoad() async {
    final locationProvider = context.read<LocationProvider>();
    final authProvider = context.read<AuthProvider>();

    final isMagic = authProvider.user?.phone.contains('9999999996') == true;

    if (isMagic) {
      locationProvider.setManualLocation(
        LatLng(34.4225, 74.6366),
        'Main Market, Bandipora',
      );
    } else if (!locationProvider.hasLocation) {
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
        List<String>? effectiveCategories;
        if (_selectedFilterCategories.isNotEmpty) {
          effectiveCategories = [];
          for (final cat in _selectedFilterCategories) {
            effectiveCategories.addAll(_tabCategories[cat] ?? [cat]);
          }
        }

        final allShops = (shopsResponse as List)
            .map((s) => ShopModel.fromMap(s))
            .where((s) => s.isActive && (effectiveCategories == null || effectiveCategories.contains(s.category)))
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
          if (effectiveCategories != null && !effectiveCategories.contains(product.category)) continue;
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
        List<String>? effectiveCategories;
        if (_selectedFilterCategories.isNotEmpty) {
          effectiveCategories = [];
          for (final cat in _selectedFilterCategories) {
            effectiveCategories.addAll(_tabCategories[cat] ?? [cat]);
          }
        }

        final allShops = (shopsResponse as List)
            .map((s) => ShopModel.fromMap(s))
            .where((s) => s.isActive && (effectiveCategories == null || effectiveCategories.contains(s.category)))
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
          if (effectiveCategories != null && !effectiveCategories.contains(product.category)) continue;
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
    final currentFiltering = _selectedTabIndex >= 0 || _selectedFilterCategories.isNotEmpty || _searchQuery.isNotEmpty;
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
          // ── Premium Modern AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: _searchQuery.isNotEmpty ? 0 : 135,
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
                    padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
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
                                    Icon(Icons.keyboard_arrow_down_rounded,
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
                          child: TextField(
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
                                              child: CupertinoActivityIndicator(radius: 9),
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
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showFilterSheet(context, isDark),
                          child: Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              color: _selectedFilterCategories.isNotEmpty 
                                  ? AppColors.primary 
                                  : (isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.transparent,
                              ),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: _selectedFilterCategories.isNotEmpty
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : AppColors.textPrimary),
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

          // ── Categories Horizontal List (premium card style) ──────────────────
          if (_searchQuery.isEmpty && _selectedTabIndex < 0 && _selectedFilterCategories.isEmpty)
            SliverToBoxAdapter(
            child: SizedBox(
              height: 72,
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
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: grad,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight)
                            : null,
                        color: isSelected
                            ? Colors.transparent
                            : (isDark
                                ? const Color(0xFF1A1D30)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                    color: grad.first.withValues(alpha: 0.45),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5))
                              ]
                            : [
                                BoxShadow(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.3)
                                        : Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4))
                              ],
                        border: isSelected
                            ? null
                            : Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.grey.shade100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            scale: isSelected ? 1.15 : 1.0,
                            duration: const Duration(milliseconds: 280),
                            child: Text(
                              cat['emoji'],
                              style: TextStyle(fontSize: isSelected ? 22 : 19),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat['name'],
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : const Color(0xFF2D3748)),
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  height: 2,
                                  width: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Search Filter Bar (visible during search only) ───────────
          if (_searchQuery.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildSearchFilterBar(isDark),
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
                      // ──────────────────────────────────────────────────
                      // SEARCH MODE: clean results-only view
                      // ──────────────────────────────────────────────────
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 4),

                        // Header
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isSearching ? 'Searching...' : 'Search results',
                                    style: GoogleFonts.outfit(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                  if (!_isSearching)
                                    Text(
                                      '${_searchResults.length + _searchProductResults.length} result${(_searchResults.length + _searchProductResults.length) == 1 ? '' : 's'} for "$_searchQuery"',
                                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Skeleton while loading
                        if (_isSearching)
                          Column(children: List.generate(3, (_) => _buildSearchSkeleton(isDark)))

                        // Empty state
                        else if (_searchResults.isEmpty && _searchProductResults.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 80, height: 80,
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.search_off_rounded,
                                        size: 36,
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('No results for', style: GoogleFonts.outfit(fontSize: 15, color: AppColors.textSecondary)),
                                  const SizedBox(height: 4),
                                  Text('"$_searchQuery"', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary)),
                                  const SizedBox(height: 8),
                                  Text('Try a different keyword', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textLight)),
                                ],
                              ),
                            ),
                          )

                        // Results
                        else ...[
                          // Products first (most relevant for the user)
                          if (_searchProductResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(width: 8),
                                  Text('Items & Products', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppColors.textPrimary)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Text('${_searchProductResults.length}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                  ),
                                ],
                              ),
                            ),
                            ..._sortedProductResults.map((product) {
                              final shop = _searchProductShops[product.id];
                              if (shop == null) return const SizedBox.shrink();
                              return ProductSearchCard(product: product, shop: shop);
                            }),
                            const SizedBox(height: 16),
                          ],

                          // Shops below products
                          if (_searchResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, top: 4),
                              child: Row(
                                children: [
                                  Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(width: 8),
                                  Text('Shops & Restaurants', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppColors.textPrimary)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Text('${_searchResults.length}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                                  ),
                                ],
                              ),
                            ),
                            ..._sortedShopResults.map((shop) {
                              final isFood = AppCategories.groupFor(shop.category) == CategoryGroup.food;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: isFood
                                    ? RestaurantShopCard(shop: shop, onTap: () => showRestaurantDashboardSheet(context, shop.id))
                                    : ShopCard(shop: shop, onTap: () => showShopDetailSheet(context, shop.id)),
                              );
                            }),
                          ],
                        ],

                      // ──────────────────────────────────────────────────
                      // NORMAL MODE: banner + shops + products
                      // ──────────────────────────────────────────────────
                      ] else ...[
                        if (_selectedTabIndex < 0 && _selectedFilterCategories.isEmpty) ...[
                          // Featured Banner
                          _buildFeaturedBanner(),
                          const SizedBox(height: 24),
                        ],

                        // ── Recently Viewed ─────────────────────────────
                        if (_selectedTabIndex < 0 && _selectedFilterCategories.isEmpty)
                          Builder(builder: (ctx) {
                            final recentProv = ctx.watch<RecentlyViewedProvider>();
                          if (!recentProv.hasItems) return const SizedBox.shrink();
                          
                          // Filter out products whose shop is closed
                          final availableRecent = recentProv.products.where((p) {
                            final shop = _productShops[p.id];
                            return shop != null && shop.isActive;
                          }).toList();
                          
                          if (availableRecent.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Recently Viewed', subtitle: 'Continue where you left off'),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 335,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: availableRecent.length,
                                  itemBuilder: (_, index) {
                                    final p = availableRecent[index];
                                    final shop = _productShops[p.id];
                                    return SizedBox(
                                      width: 155,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 12),
                                        child: ProductCard(product: p, shop: shop),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          );
                        }),

                        if (_selectedTabIndex < 0 && _selectedFilterCategories.isEmpty) ...[
                          if (_shops.isNotEmpty) ...[
                          // ── Normal category browse ───────────────────
                          _buildSectionTitle(
                            _selectedTabIndex < 0
                                ? 'All stores near you'
                                : _isFoodTab
                                    ? 'Restaurants near you'
                                    : 'Shops near you',
                            subtitle: '${_shops.length} within ${DeliveryCalculator.maxRadiusKm.toInt()} km',
                            count: _shops.length,
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
                                        ? RestaurantShopCard(shop: shop, onTap: () => showRestaurantDashboardSheet(context, shop.id))
                                        : ShopCard(shop: shop, onTap: () => showShopDetailSheet(context, shop.id)),
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
                        ],

                        // Products Section
                        if (_products.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildSectionTitle('Popular in your area'),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount = Responsive.getGridCrossAxisCount(context, mobile: 2, tablet: 4, desktop: 5);
                              const crossAxisSpacing = 16.0;
                              final availableWidth = constraints.maxWidth;
                              final itemWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;
                              final itemHeight = itemWidth + 178;
                              final childAspectRatio = itemWidth / itemHeight;

                              return GridView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: crossAxisSpacing,
                                ),
                                itemCount: _products.length,
                                itemBuilder: (context, index) {
                                  final product = _products[index];
                                  final shop = _productShops[product.id];
                                  return ProductCard(product: product, shop: shop);
                                },
                              );
                            },
                          ),
                        ] else if ((_selectedTabIndex >= 0 || _selectedFilterCategories.isNotEmpty) && !_isLoading) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 80, height: 80,
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.inventory_2_outlined,
                                        size: 36,
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('No items found', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary)),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 32),
                                    child: Text('We could not find any products in this category at the moment.', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 120),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSearchFilterBar(bool isDark) {
    final filters = [
      {'mode': _SortMode.relevant, 'label': 'Relevant', 'icon': Icons.bolt_rounded},
      {'mode': _SortMode.bestRating, 'label': 'Best Rating', 'icon': Icons.star_rounded},
      {'mode': _SortMode.priceLow, 'label': 'Price: Low to High', 'icon': Icons.trending_up_rounded},
      {'mode': _SortMode.priceHigh, 'label': 'Price: High to Low', 'icon': Icons.trending_down_rounded},
      {'mode': _SortMode.discount, 'label': 'Biggest Discount', 'icon': Icons.local_offer_rounded},
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final mode = filter['mode'] as _SortMode;
          final isSelected = _sortMode == mode;

          return GestureDetector(
            onTap: () => setState(() => _sortMode = mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchSkeleton(bool isDark) {
    final shimmerBase = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8);
    final shimmerHigh = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8);
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
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 140, decoration: BoxDecoration(color: shimmerHigh, borderRadius: BorderRadius.circular(7))),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 100, decoration: BoxDecoration(color: shimmerHigh, borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 10),
                  Container(height: 12, width: 60, decoration: BoxDecoration(color: shimmerHigh, borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: 60, height: 34,
                decoration: BoxDecoration(color: shimmerHigh, borderRadius: BorderRadius.circular(10)),
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
    final slides = [
      {
        'tag': '🔥 HOT & FRESH',
        'title': 'Get Food Instantly\nDelivered to you',
        'sub': 'Fast, fresh, and local restaurants',
        'icon': Icons.local_dining_rounded,
        'colors': [
          const Color(0xFFFF512F),
          const Color(0xFFF09819),
          const Color(0xFFFF6A00)
        ],
        'accent': const Color(0xFFFFE082),
        'emoji': '🍔',
        'action': () {
          setState(() => _selectedTabIndex = 0);
          _loadData('Food');
        },
      },
      {
        'tag': '🛒 DAILY ESSENTIALS',
        'title': 'Grocery & Medicines\nAt your doorstep',
        'sub': 'Supermarkets and local pharmacies',
        'icon': Icons.shopping_basket_rounded,
        'colors': [
          const Color(0xFF11998E),
          const Color(0xFF38EF7D),
          const Color(0xFF00B09B)
        ],
        'accent': const Color(0xFFB9F6CA),
        'emoji': '🥦💊',
        'action': () {
          setState(() => _selectedTabIndex = -1);
          _loadData('GroceryAndMed');
        },
      },
      {
        'tag': '👗 FASHION & MORE',
        'title': 'Clothing, Shoes\nAnd everything else!',
        'sub': 'Local fashion and apparel stores',
        'icon': Icons.checkroom_rounded,
        'colors': [
          const Color(0xFF0A1260),
          const Color(0xFF142999),
          const Color(0xFF1E3FD8)
        ],
        'accent': const Color(0xFF00E5FF),
        'emoji': '👠👗',
        'action': () {
          setState(() => _selectedTabIndex = 3);
          _loadData('Clothing');
        },
      },
    ];

    return Column(
      children: [
        SizedBox(
          height: 130, // Reduced from 190
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemCount: slides.length,
            itemBuilder: (_, i) {
              final s = slides[i];
              final colors = s['colors'] as List<Color>;
              final accent = s['accent'] as Color;
              final emoji = s['emoji'] as String;
              return GestureDetector(
                onTap: s['action'] as VoidCallback,
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
                                  color: Colors.white.withValues(alpha: 0.05)))),
                      // Smaller circle
                      Positioned(
                          left: -15,
                          bottom: -15,
                          child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.04)))),
                      // Background icon
                      Positioned(
                          right: -5,
                          bottom: -15,
                          child: Icon(s['icon'] as IconData,
                              size: 90, // Reduced from 130
                              color: Colors.white.withValues(alpha: 0.07))),
                      // Big emoji top-right
                      Positioned(
                          right: 16,
                          top: 16,
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 36))), // Reduced from 52
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
                                    fontSize: 18, // Reduced from 22
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1.15,
                                    letterSpacing: -0.3)),
                            const SizedBox(height: 4),
                            Text(s['sub'] as String,
                                style: GoogleFonts.outfit(
                                    fontSize: 10, // Reduced from 11
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
        const SizedBox(height: 12),
        // Premium animated pill indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slides.length, (i) {
            final active = _bannerIndex == i;
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
                color: active ? null : AppColors.textLight,
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
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    String title, {
    String? subtitle,
    int? count,
    bool isHighlighted = false,
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
                          color: isDark
                              ? Colors.white54
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {},
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
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
    final base = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8EE);
    final highlight = isDark ? const Color(0xFF26263A) : const Color(0xFFF4F4FA);
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
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24)),
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

  void _showFilterSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final catNames = AppCategories.names;
            return Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filters', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
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
                          Text('Sort By', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSortChip('Relevant', _SortMode.relevant, setSheetState, isDark),
                      _buildSortChip('Nearest', _SortMode.nearest, setSheetState, isDark),
                      _buildSortChip('Price: Low to High', _SortMode.priceLow, setSheetState, isDark),
                      _buildSortChip('Price: High to Low', _SortMode.priceHigh, setSheetState, isDark),
                      _buildSortChip('Best Rating', _SortMode.bestRating, setSheetState, isDark),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Categories', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: catNames.map((cat) {
                      final isSelected = _selectedFilterCategories.contains(cat);
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              _selectedFilterCategories.add(cat);
                            } else {
                              _selectedFilterCategories.remove(cat);
                            }
                          });
                        },
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100,
                        labelStyle: TextStyle(color: isSelected ? AppColors.primary : (isDark ? Colors.white70 : Colors.black)),
                        side: BorderSide(color: isSelected ? AppColors.primary : Colors.transparent),
                      );
                    }).toList(),
                  ),
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
                        Navigator.pop(context);
                        setState(() {});
                        if (_searchQuery.isNotEmpty) {
                          _searchShops(_searchQuery);
                        } else {
                          if (_selectedTabIndex < 0) {
                            _loadAllData();
                          } else {
                            _loadData(_categories[_selectedTabIndex]['name']! as String);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Apply Filters', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildSortChip(String label, _SortMode mode, StateSetter setSheetState, bool isDark) {
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
      labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black)),
      side: BorderSide(color: isSelected ? AppColors.primary : Colors.transparent),
    );
  }
}
