import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_layout.dart';
import '../../config/routes.dart';

class ManageProductsPage extends StatefulWidget {
  final String? initialShopId;
  const ManageProductsPage({super.key, this.initialShopId});

  @override
  State<ManageProductsPage> createState() => _ManageProductsPageState();
}

class _ManageProductsPageState extends State<ManageProductsPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  List<ProductModel> _allProducts = [];
  bool _isLoading = true;
  String? _selectedShopId;
  List<Map<String, dynamic>> _shops = [];

  // Filtering & Search
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _availabilityFilter = 'All'; // 'All', 'Available', 'Hidden'

  @override
  void initState() {
    super.initState();
    _selectedShopId = widget.initialShopId;
    _loadShopsAndProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShopsAndProducts() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUserId ?? '';
    if (userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final shopsResp = await _supabase
          .from('shops')
          .select('id, name, category, is_active')
          .eq('seller_id', userId);

      final shopsList = List<Map<String, dynamic>>.from(shopsResp as List);

      if (shopsList.isEmpty) {
        if (mounted) {
          setState(() {
            _shops = [];
            _allProducts = [];
            _isLoading = false;
          });
        }
        return;
      }

      String activeShopId = _selectedShopId ?? shopsList.first['id'] as String;
      // If previously selected shop no longer exists, snap to first
      if (!shopsList.any((s) => s['id'] == activeShopId)) {
        activeShopId = shopsList.first['id'] as String;
      }

      final productsResp = await _supabase
          .from('products')
          .select()
          .eq('shop_id', activeShopId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(500);

      if (mounted) {
        setState(() {
          _shops = shopsList;
          _selectedShopId = activeShopId;
          _allProducts = (productsResp as List)
              .map((p) => ProductModel.fromMap(p))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageProductsPage error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Failed to load products: $e', isError: true);
      }
    }
  }

  List<String> get _availableCategories {
    final set = <String>{'All'};
    for (final p in _allProducts) {
      if (p.category.isNotEmpty) set.add(p.category);
    }
    return set.toList();
  }

  List<ProductModel> get _filteredProducts {
    return _allProducts.where((p) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = p.name.toLowerCase().contains(q);
        final descMatch = (p.description ?? '').toLowerCase().contains(q);
        final catMatch = p.category.toLowerCase().contains(q);
        if (!nameMatch && !descMatch && !catMatch) return false;
      }

      // Category filter
      if (_selectedCategory != 'All' && p.category != _selectedCategory) {
        return false;
      }

      // Availability filter
      if (_availabilityFilter == 'Available' && !p.isAvailable) {
        return false;
      }
      if (_availabilityFilter == 'Hidden' && p.isAvailable) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _toggleAvailability(ProductModel product) async {
    final originalState = product.isAvailable;
    final newState = !originalState;

    // Optimistic UI update
    setState(() {
      final idx = _allProducts.indexWhere((p) => p.id == product.id);
      if (idx != -1) {
        _allProducts[idx] = product.copyWith(isAvailable: newState);
      }
    });

    try {
      await _supabase
          .from('products')
          .update({'is_available': newState})
          .eq('id', product.id)
          .eq('shop_id', product.shopId);

      _showSnack(
        newState ? '✅ "${product.name}" is now Available' : '👁️ "${product.name}" is now Hidden',
        isError: false,
      );
    } catch (e) {
      debugPrint('Toggle availability error: $e');
      // Rollback
      if (mounted) {
        setState(() {
          final idx = _allProducts.indexWhere((p) => p.id == product.id);
          if (idx != -1) {
            _allProducts[idx] = product.copyWith(isAvailable: originalState);
          }
        });
        _showSnack('Failed to update availability: $e', isError: true);
      }
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Product?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to delete "${product.name}"?\nThis item will be removed from your store catalog.',
          style: GoogleFonts.outfit(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Enforce soft delete: update is_deleted = true
        await _supabase
            .from('products')
            .update({'is_deleted': true})
            .eq('id', product.id)
            .eq('shop_id', product.shopId);

        _showSnack('Product deleted.', isError: false);
        _loadShopsAndProducts();
      } catch (e) {
        debugPrint('Delete error: $e');
        _showSnack('Failed to delete product: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredProducts;
    final totalCount = _allProducts.length;
    final availableCount = _allProducts.where((p) => p.isAvailable).length;
    final hiddenCount = totalCount - availableCount;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Manage Products',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
            if (_shops.isNotEmpty)
              Text(
                _shops.firstWhere((s) => s['id'] == _selectedShopId, orElse: () => _shops.first)['name'] ?? 'Store',
                style: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          if (_shops.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.store_rounded),
                tooltip: 'Switch Shop',
                initialValue: _selectedShopId,
                onSelected: (shopId) {
                  setState(() {
                    _selectedShopId = shopId;
                    _isLoading = true;
                  });
                  _loadShopsAndProducts();
                },
                itemBuilder: (context) => _shops.map((s) {
                  final id = s['id'] as String;
                  final name = s['name'] as String? ?? 'Shop';
                  return PopupMenuItem<String>(
                    value: id,
                    child: Row(
                      children: [
                        Icon(
                          id == _selectedShopId ? Icons.check_circle : Icons.store_outlined,
                          color: id == _selectedShopId ? AppColors.primary : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              style: GoogleFonts.outfit(
                                fontWeight: id == _selectedShopId ? FontWeight.w700 : FontWeight.w500,
                              )),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Add Product', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
        onPressed: () async {
          final result = await Navigator.pushNamed(
            context,
            AppRoutes.addProduct,
            arguments: {'shopId': _selectedShopId},
          );
          if (result == true) {
            _loadShopsAndProducts();
          }
        },
      ),
      body: MaxWidthContainer(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadShopsAndProducts,
                color: AppColors.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Search & Filters Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Search Bar
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurface : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                                style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Search by product name or category...',
                                  hintStyle: GoogleFonts.outfit(color: Colors.grey, fontSize: 13),
                                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Availability Segment Filter Chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip(
                                    label: 'All ($totalCount)',
                                    isSelected: _availabilityFilter == 'All',
                                    onTap: () => setState(() => _availabilityFilter = 'All'),
                                    isDark: isDark,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterChip(
                                    label: 'Available ($availableCount)',
                                    isSelected: _availabilityFilter == 'Available',
                                    onTap: () => setState(() => _availabilityFilter = 'Available'),
                                    isDark: isDark,
                                    activeColor: AppColors.success,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterChip(
                                    label: 'Hidden ($hiddenCount)',
                                    isSelected: _availabilityFilter == 'Hidden',
                                    onTap: () => setState(() => _availabilityFilter = 'Hidden'),
                                    isDark: isDark,
                                    activeColor: AppColors.danger,
                                  ),
                                ],
                              ),
                            ),

                            if (_availableCategories.length > 2) ...[
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _availableCategories.map((cat) {
                                    final isSelected = _selectedCategory == cat;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(cat),
                                        labelStyle: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                        selected: isSelected,
                                        selectedColor: AppColors.primary,
                                        backgroundColor: isDark ? const Color(0xFF2A2A3A) : Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        side: BorderSide(
                                          color: isSelected
                                              ? AppColors.primary
                                              : (isDark ? Colors.white12 : Colors.grey.shade300),
                                        ),
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() => _selectedCategory = cat);
                                          }
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Products List
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Text('📦', style: TextStyle(fontSize: 40)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _allProducts.isEmpty
                                      ? 'No products in catalog yet'
                                      : 'No products match your filter',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _allProducts.isEmpty
                                      ? 'Tap "Add Product" below to list your first item!'
                                      : 'Try adjusting your search or category filters.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildProductCard(filtered[index], isDark),
                            childCount: filtered.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    Color activeColor = AppColors.primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? Colors.white12 : Colors.grey.shade300),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product, bool isDark) {
    final hasVariants = product.variants.isNotEmpty;
    final hasDiscount = product.originalPrice != null && product.originalPrice! > product.price;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image / Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 64,
              height: 64,
              color: AppColors.primary.withValues(alpha: 0.08),
              child: product.images.isNotEmpty
                  ? Image.network(
                      product.images.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    )
                  : const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primary,
                      size: 28,
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),

                // Price & Badges
                Row(
                  children: [
                    Text(
                      '₹${product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        '₹${product.originalPrice!.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    if (hasVariants) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${product.variants.length} options',
                          style: GoogleFonts.outfit(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),

                // Status row (Available + Stock count)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (product.isAvailable ? AppColors.success : AppColors.danger)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        product.isAvailable ? '● Available' : '● Hidden',
                        style: GoogleFonts.outfit(
                          color: product.isAvailable ? AppColors.success : AppColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (product.totalQuantity != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Stock: ${product.totalQuantity}',
                          style: GoogleFonts.outfit(
                            color: Colors.blue.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (product.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          product.category,
                          style: GoogleFonts.outfit(
                            color: isDark ? Colors.white60 : Colors.grey.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Column(
            children: [
              Transform.scale(
                scale: 0.82,
                child: Switch(
                  value: product.isAvailable,
                  onChanged: (_) => _toggleAvailability(product),
                  activeThumbColor: AppColors.primary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 20,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                    tooltip: 'Edit Product',
                    onPressed: () async {
                      final result = await Navigator.pushNamed(
                        context,
                        AppRoutes.addProduct,
                        arguments: {'product': product, 'shopId': product.shopId},
                      );
                      if (result == true) {
                        _loadShopsAndProducts();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 20,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    tooltip: 'Delete Product',
                    onPressed: () => _deleteProduct(product),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
