import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/product_model.dart';
import '../../../services/product_storage_service.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/haptic_utils.dart';
import '../../seller/add_product_page.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';

/// Lightweight representation of a shop for admin catalog management.
class AdminShopItem {
  final String id;
  final String name;
  final String category;
  final String? address;
  final bool isActive;
  final String? sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final String? bannerUrl;

  const AdminShopItem({
    required this.id,
    required this.name,
    required this.category,
    this.address,
    required this.isActive,
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    this.bannerUrl,
  });

  factory AdminShopItem.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? sName;
    String? sPhone;
    if (profile is Map) {
      sName = profile['full_name'] ?? profile['name'];
      sPhone = profile['phone'];
    }
    return AdminShopItem(
      id: map['id']?.toString() ?? '',
      name: (map['shop_name'] ?? map['name'] ?? 'Unnamed Shop').toString(),
      category: (map['category'] ?? 'Retail').toString(),
      address: map['address']?.toString(),
      isActive: (map['is_active'] == true),
      sellerId: map['seller_id']?.toString(),
      sellerName: sName,
      sellerPhone: sPhone,
      bannerUrl: (map['banner_url'] ?? map['banner_image'])?.toString(),
    );
  }
}

/// Comprehensive Admin Product Management Page.
///
/// Enables platform admins to:
/// 1. Browse and search all registered shops across all categories.
/// 2. Select any shop and view its complete product catalog.
/// 3. Add new products to the target shop via [AddProductPage].
/// 4. Edit existing products with full shop-specific category validations.
/// 5. Optimistically toggle product availability (Available vs Hidden).
/// 6. Safely delete products with active unfulfilled order guards and cloud storage cleanup.
class AdminProductManagementPage extends StatefulWidget {
  final String? initialShopId;

  const AdminProductManagementPage({super.key, this.initialShopId});

  @override
  State<AdminProductManagementPage> createState() =>
      _AdminProductManagementPageState();
}

class _AdminProductManagementPageState
    extends State<AdminProductManagementPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Shop Directory State ──────────────────────────────────────────────────
  List<AdminShopItem> _shops = [];
  Map<String, int> _shopProductCounts = {};
  bool _loadingShops = true;
  String? _shopsError;
  final TextEditingController _shopSearchCtrl = TextEditingController();
  String _selectedShopCategoryFilter = 'All';
  String _selectedShopStatusFilter = 'All'; // All, Active, Inactive

  // ── Selected Shop & Products State ────────────────────────────────────────
  AdminShopItem? _selectedShop;
  List<ProductModel> _products = [];
  bool _loadingProducts = false;
  String? _productsError;
  final TextEditingController _productSearchCtrl = TextEditingController();
  String _productCategoryFilter = 'All';
  String _productAvailabilityFilter = 'All'; // All, Available, Hidden

  @override
  void initState() {
    super.initState();
    _shopSearchCtrl.addListener(() => setState(() {}));
    _productSearchCtrl.addListener(() => setState(() {}));
    _fetchShopsAndCounts();
  }

  @override
  void dispose() {
    _shopSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    super.dispose();
  }

  // ── Data Fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchShopsAndCounts() async {
    setState(() {
      _loadingShops = true;
      _shopsError = null;
    });

    try {
      // 1. Fetch shops — Try admin_get_all_shops RPC first, fallback to direct query
      List<Map<String, dynamic>> rawShops = [];
      try {
        final rpcRes = await _supabase.rpc('admin_get_all_shops');
        if (rpcRes != null && rpcRes is List) {
          rawShops = List<Map<String, dynamic>>.from(rpcRes);
        }
      } catch (e) {
        debugPrint('admin_get_all_shops RPC fallback: $e');
      }

      if (rawShops.isEmpty) {
        final tableRes = await _supabase
            .from('shops')
            .select('*, profiles:seller_id(id, full_name, phone, avatar_url)')
            .order('name', ascending: true);
        rawShops = List<Map<String, dynamic>>.from(tableRes);
      }

      final parsedShops =
          rawShops.map((m) => AdminShopItem.fromMap(m)).toList();

      // 2. Fetch product counts per shop (COMPLYING WITH SOFT DELETE RULE)
      final countsRes = await _supabase
          .from('products')
          .select('shop_id')
          .eq('is_deleted', false);

      final Map<String, int> counts = {};
      for (final row in countsRes as List) {
        final sId = row['shop_id']?.toString();
        if (sId != null && sId.isNotEmpty) {
          counts[sId] = (counts[sId] ?? 0) + 1;
        }
      }

      if (!mounted) return;

      setState(() {
        _shops = parsedShops;
        _shopProductCounts = counts;
        _loadingShops = false;
      });

      // Auto-select initial shop if requested
      if (widget.initialShopId != null && _selectedShop == null) {
        final match = _shops.where((s) => s.id == widget.initialShopId).firstOrNull;
        if (match != null) {
          _selectShop(match);
        } else {
          // If shop wasn't in standard list, fetch directly
          _loadSingleShop(widget.initialShopId!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      if (mounted) {
        setState(() {
          _loadingShops = false;
          _shopsError = e.toString();
        });
      }
    }
  }

  Future<void> _loadSingleShop(String shopId) async {
    try {
      final res = await _supabase
          .from('shops')
          .select('*, profiles:seller_id(id, full_name, phone, avatar_url)')
          .eq('id', shopId)
          .maybeSingle();

      if (res != null && mounted) {
        final shop = AdminShopItem.fromMap(Map<String, dynamic>.from(res));
        _selectShop(shop);
      }
    } catch (e) {
      debugPrint('Error loading single shop: $e');
    }
  }

  Future<void> _selectShop(AdminShopItem shop) async {
    HapticUtils.selection();
    setState(() {
      _selectedShop = shop;
      _productSearchCtrl.clear();
      _productCategoryFilter = 'All';
      _productAvailabilityFilter = 'All';
    });
    await _loadProductsForShop(shop.id);
  }

  Future<void> _loadProductsForShop(String shopId) async {
    setState(() {
      _loadingProducts = true;
      _productsError = null;
    });

    try {
      // RULE: Products table queries MUST ALWAYS include .eq('is_deleted', false)
      final res = await _supabase
          .from('products')
          .select()
          .eq('shop_id', shopId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((m) => ProductModel.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      if (mounted) {
        setState(() {
          _products = list;
          _loadingProducts = false;
          _shopProductCounts[shopId] = list.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading products for shop $shopId: $e');
      if (mounted) {
        setState(() {
          _loadingProducts = false;
          _productsError = e.toString();
        });
        _showSnack('Failed to load products: $e', isError: true);
      }
    }
  }

  Future<void> _refreshShopProductCounts() async {
    try {
      final countsRes = await _supabase
          .from('products')
          .select('shop_id')
          .eq('is_deleted', false);

      final Map<String, int> counts = {};
      for (final row in countsRes as List) {
        final sId = row['shop_id']?.toString();
        if (sId != null && sId.isNotEmpty) {
          counts[sId] = (counts[sId] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() => _shopProductCounts = counts);
      }
    } catch (_) {}
  }

  // ── Product Actions (Toggle, Add, Edit, Delete) ───────────────────────────

  Future<void> _toggleAvailability(ProductModel product) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('products.manage')) {
      _showSnack('Permission denied: You cannot modify products.', isError: true);
      return;
    }
    HapticUtils.selection();
    final originalState = product.isAvailable;
    final newState = !originalState;

    // Optimistic local UI update
    setState(() {
      final idx = _products.indexWhere((p) => p.id == product.id);
      if (idx != -1) {
        _products[idx] = product.copyWith(isAvailable: newState);
      }
    });

    try {
      await _supabase
          .from('products')
          .update({'is_available': newState})
          .eq('id', product.id)
          .eq('shop_id', product.shopId);

      _showSnack(
        newState
            ? '✅ "${product.name}" is now Available'
            : '👁️ "${product.name}" is now Hidden / Out of Stock',
        isError: false,
      );
    } catch (e) {
      debugPrint('Admin toggle availability error: $e');
      // Rollback to original state on failure
      if (mounted) {
        setState(() {
          final idx = _products.indexWhere((p) => p.id == product.id);
          if (idx != -1) {
            _products[idx] = product.copyWith(isAvailable: originalState);
          }
        });
        _showSnack('Failed to update availability: $e', isError: true);
      }
    }
  }

  Future<void> _navigateToAddProduct() async {
    if (_selectedShop == null) return;
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('products.manage') && !rbac.can('products.create')) {
      _showSnack('Permission denied: You cannot add products.', isError: true);
      return;
    }
    HapticUtils.light();

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(
          initialShopId: _selectedShop!.id,
        ),
      ),
    );

    if (result == true && mounted) {
      _loadProductsForShop(_selectedShop!.id);
      _refreshShopProductCounts();
    }
  }

  Future<void> _navigateToEditProduct(ProductModel product) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('products.manage')) {
      _showSnack('Permission denied: You cannot edit products.', isError: true);
      return;
    }
    HapticUtils.light();

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(
          existingProduct: product,
          initialShopId: product.shopId,
        ),
      ),
    );

    if (result == true && mounted) {
      _loadProductsForShop(product.shopId);
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('products.manage') && !rbac.can('products.delete')) {
      _showSnack('Permission denied: You cannot delete products.', isError: true);
      return;
    }
    HapticUtils.medium();

    // 1. Guard against deleting products in active unfulfilled orders
    try {
      final activeResp = await _supabase
          .from('orders')
          .select('id, status, order_items!inner(product_id)')
          .eq('order_items.product_id', product.id)
          .inFilter('status', [
            'awaiting_acceptance',
            'pending',
            'awaiting_payment',
            'confirmed',
            'preparing',
            'ready_for_pickup',
            'out_for_delivery',
          ])
          .limit(1);

      if (!mounted) return;

      if ((activeResp as List).isNotEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AdminColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AdminColors.warning, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Active Order in Progress',
                      style: AdminStyles.title(size: 16)),
                ),
              ],
            ),
            content: Text(
              '"${product.name}" cannot be deleted right now because it is currently included in an active customer order in progress.\n\nTo prevent new orders while active deliveries are ongoing, mark this item as Out of Stock (Hidden).',
              style:
                  AdminStyles.body(size: 13, color: AdminColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK',
                    style: AdminStyles.body(color: AdminColors.textMuted)),
              ),
              if (product.isAvailable)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _toggleAvailability(product);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Mark Out of Stock',
                      style: AdminStyles.body(size: 13, color: Colors.white)),
                ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Active order check note: $e');
    }

    if (!mounted) return;

    // 2. Check for past order history (order_items)
    bool hasOrderHistory = false;
    try {
      final pastOrders = await _supabase
          .from('order_items')
          .select('id')
          .eq('product_id', product.id)
          .limit(1);
      hasOrderHistory = (pastOrders as List).isNotEmpty;
    } catch (e) {
      debugPrint('Order history check note: $e');
    }

    if (!mounted) return;

    // 3. Informative, context-aware confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          hasOrderHistory ? 'Delete Product?' : 'Permanently Delete Product?',
          style: AdminStyles.title(size: 16),
        ),
        content: Text(
          hasOrderHistory
              ? 'Are you sure you want to delete "${product.name}"?\n\nThis product has past customer orders. It will be removed from the catalog and store, while historical receipts and customer order history remain safely preserved.'
              : 'Are you sure you want to delete "${product.name}"?\n\nThis item has never been ordered. It will be removed from the catalog, and its pictures will be permanently cleaned up from cloud storage.',
          style: AdminStyles.body(size: 13, color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AdminStyles.body(color: AdminColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete',
                style: AdminStyles.body(
                    size: 13,
                    color: Colors.white)
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Show loading indicator dialog during deletion
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration:
                AdminDecorations.glassCard(bgColor: AdminColors.surface),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AdminColors.primary),
                const SizedBox(height: 16),
                Text('Deleting product...',
                    style: AdminStyles.title(size: 14)),
              ],
            ),
          ),
        ),
      );

      try {
        int deletedImagesCount = 0;
        if (!hasOrderHistory) {
          deletedImagesCount = await ProductStorageService.deleteProductImages(
            product,
            client: _supabase,
          );
        }

        // Soft delete the product in DB (complying with project soft-delete architecture)
        final updatePayload = <String, dynamic>{
          'is_deleted': true,
          'is_available': false,
          if (!hasOrderHistory) 'images': <String>[],
        };

        await _supabase
            .from('products')
            .update(updatePayload)
            .eq('id', product.id)
            .eq('shop_id', product.shopId);

        if (mounted) {
          // Dismiss loading dialog
          Navigator.of(context, rootNavigator: true).pop();

          final msg = !hasOrderHistory && deletedImagesCount > 0
              ? 'Product and $deletedImagesCount image(s) deleted.'
              : 'Product deleted successfully.';
          _showSnack(msg, isError: false);
          _loadProductsForShop(product.shopId);
          _refreshShopProductCounts();
        }
      } catch (e) {
        debugPrint('Delete error: $e');
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
          _showSnack('Failed to delete product: $e', isError: true);
        }
      }
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AdminStyles.body(size: 13, color: Colors.white)),
        backgroundColor: isError ? AdminColors.danger : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Filter Computations ───────────────────────────────────────────────────

  List<AdminShopItem> get _filteredShops {
    final query = _shopSearchCtrl.text.toLowerCase().trim();
    return _shops.where((s) {
      if (_selectedShopStatusFilter == 'Active' && !s.isActive) return false;
      if (_selectedShopStatusFilter == 'Inactive' && s.isActive) return false;
      if (_selectedShopCategoryFilter != 'All' &&
          s.category.toLowerCase() !=
              _selectedShopCategoryFilter.toLowerCase()) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesName = s.name.toLowerCase().contains(query);
        final matchesCategory = s.category.toLowerCase().contains(query);
        final matchesSeller =
            (s.sellerName ?? '').toLowerCase().contains(query);
        final matchesPhone =
            (s.sellerPhone ?? '').toLowerCase().contains(query);
        final matchesAddress =
            (s.address ?? '').toLowerCase().contains(query);
        return matchesName ||
            matchesCategory ||
            matchesSeller ||
            matchesPhone ||
            matchesAddress;
      }
      return true;
    }).toList();
  }

  List<ProductModel> get _filteredProducts {
    final query = _productSearchCtrl.text.toLowerCase().trim();
    return _products.where((p) {
      if (_productAvailabilityFilter == 'Available' && !p.isAvailable) {
        return false;
      }
      if (_productAvailabilityFilter == 'Hidden' && p.isAvailable) {
        return false;
      }
      if (_productCategoryFilter != 'All' &&
          p.category.toLowerCase() != _productCategoryFilter.toLowerCase()) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesName = p.name.toLowerCase().contains(query);
        final matchesCat = p.category.toLowerCase().contains(query);
        final matchesBrand = (p.brand ?? '').toLowerCase().contains(query);
        final matchesDesc =
            (p.description ?? '').toLowerCase().contains(query);
        return matchesName || matchesCat || matchesBrand || matchesDesc;
      }
      return true;
    }).toList();
  }

  List<String> get _availableProductCategories {
    final cats = <String>{'All'};
    for (final p in _products) {
      if (p.category.isNotEmpty) cats.add(p.category);
    }
    return cats.toList();
  }

  List<String> get _availableShopCategories {
    final cats = <String>{'All'};
    for (final s in _shops) {
      if (s.category.isNotEmpty) cats.add(s.category);
    }
    return cats.toList();
  }

  // ── Build Method ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    final isSuperAdmin = rbac.isSuperAdmin;
    final canView = isSuperAdmin || rbac.can('products.view') || rbac.can('products.manage');
    if (!canView) {
      return const ForbiddenPage(
        requiredPermission: 'products.view',
      );
    }
    final canManage = isSuperAdmin || rbac.can('products.manage');
    final canCreate = canManage || rbac.can('products.create');

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: _buildAppBar(),
      floatingActionButton:
          _selectedShop != null && canCreate ? _buildAddProductFAB() : null,
      body: _selectedShop == null
          ? _buildShopDirectoryView()
          : _buildProductCatalogView(),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    final isShopSelected = _selectedShop != null;
    return AppBar(
      backgroundColor: AdminColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () {
          if (isShopSelected && widget.initialShopId == null) {
            setState(() {
              _selectedShop = null;
              _products = [];
            });
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isShopSelected ? _selectedShop!.name : 'Product Management',
            style: AdminStyles.title(size: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            isShopSelected
                ? '${_products.length} Products • ${_selectedShop!.category}'
                : '${_shops.length} Shops Registered',
            style: AdminStyles.caption(size: 11, color: AdminColors.textMuted),
          ),
        ],
      ),
      actions: [
        if (isShopSelected) ...[
          IconButton(
            tooltip: 'Refresh Products',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => _loadProductsForShop(_selectedShop!.id),
          ),
          IconButton(
            tooltip: 'Switch Shop',
            icon: const Icon(Icons.swap_horiz_rounded,
                color: AdminColors.primary),
            onPressed: () {
              setState(() {
                _selectedShop = null;
                _products = [];
              });
            },
          ),
        ] else ...[
          IconButton(
            tooltip: 'Refresh Shops',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _fetchShopsAndCounts,
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Shop Directory View (Step 1) ──────────────────────────────────────────

  Widget _buildShopDirectoryView() {
    if (_loadingShops) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
    }

    if (_shopsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AdminColors.danger, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load shops', style: AdminStyles.title(size: 16)),
              const SizedBox(height: 6),
              Text(_shopsError!,
                  style: AdminStyles.caption(color: AdminColors.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.primary),
                onPressed: _fetchShopsAndCounts,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final shops = _filteredShops;
    final shopCategories = _availableShopCategories;

    return RefreshIndicator(
      onRefresh: _fetchShopsAndCounts,
      color: AdminColors.primary,
      backgroundColor: AdminColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Banner explanation
          AdminCard(
            padding: const EdgeInsets.all(16),
            borderColor: AdminColors.primary.withValues(alpha: 0.3),
            bgColor: AdminColors.primary.withValues(alpha: 0.08),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: AdminColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Admin Catalog Controller',
                          style: AdminStyles.title(size: 14)),
                      const SizedBox(height: 2),
                      Text(
                        'Select any shop below to add products, adjust pricing, toggle availability, or manage catalog inventory.',
                        style: AdminStyles.caption(
                            size: 12, color: AdminColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 14),

          // Search Field
          TextField(
            controller: _shopSearchCtrl,
            style: AdminStyles.body(size: 14),
            decoration: InputDecoration(
              hintText: 'Search shops by name, category, seller, phone...',
              hintStyle:
                  AdminStyles.caption(color: AdminColors.textMuted, size: 13),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AdminColors.textMuted),
              suffixIcon: _shopSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: Colors.white54, size: 18),
                      onPressed: () => _shopSearchCtrl.clear(),
                    )
                  : null,
              filled: true,
              fillColor: AdminColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AdminColors.primary, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Status & Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusPill('All'),
                const SizedBox(width: 6),
                _buildStatusPill('Active'),
                const SizedBox(width: 6),
                _buildStatusPill('Inactive'),
                const SizedBox(width: 12),
                Container(
                    width: 1,
                    height: 24,
                    color: AdminColors.cardBorder),
                const SizedBox(width: 12),
                ...shopCategories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildCategoryPill(cat),
                    )),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Shop Count Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${shops.length} of ${_shops.length} Shops',
                style: AdminStyles.caption(
                    size: 12, color: AdminColors.textMuted),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Empty state
          if (shops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded,
                        color: AdminColors.textMuted, size: 48),
                    const SizedBox(height: 12),
                    Text('No shops match your search',
                        style: AdminStyles.title(size: 15)),
                    const SizedBox(height: 4),
                    Text('Try adjusting filters or searching a different term',
                        style: AdminStyles.caption(
                            color: AdminColors.textMuted)),
                  ],
                ),
              ),
            )
          else
            ...shops.map((shop) => _buildShopCard(shop)),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    final selected = _selectedShopStatusFilter == status;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        setState(() => _selectedShopStatusFilter = status);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.primary
              : AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AdminColors.primary : AdminColors.cardBorder,
          ),
        ),
        child: Text(
          status,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPill(String cat) {
    final selected = _selectedShopCategoryFilter == cat;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        setState(() => _selectedShopCategoryFilter = cat);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2563EB)
              : AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : AdminColors.cardBorder,
          ),
        ),
        child: Text(
          cat,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(AdminShopItem shop) {
    final productCount = _shopProductCounts[shop.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectShop(shop),
          child: AdminCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar / Thumbnail
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminColors.cardBorder),
                  ),
                  child: shop.bannerUrl != null && shop.bannerUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            shop.bannerUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.storefront_rounded,
                              color: AdminColors.primary,
                              size: 26,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.storefront_rounded,
                          color: AdminColors.primary,
                          size: 26,
                        ),
                ),

                const SizedBox(width: 14),

                // Shop Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shop.name,
                              style: AdminStyles.title(size: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (shop.isActive
                                      ? AdminColors.success
                                      : AdminColors.warning)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              shop.isActive ? 'Active' : 'Inactive',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: shop.isActive
                                    ? AdminColors.success
                                    : AdminColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AdminColors.cardBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AdminColors.cardBorder, width: 0.8),
                            ),
                            child: Text(
                              shop.category,
                              style: AdminStyles.caption(
                                  size: 10, color: AdminColors.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (shop.sellerName != null &&
                              shop.sellerName!.isNotEmpty)
                            Expanded(
                              child: Text(
                                'Owner: ${shop.sellerName}',
                                style: AdminStyles.caption(
                                    size: 11, color: AdminColors.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      if (shop.address != null && shop.address!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          shop.address!,
                          style: AdminStyles.caption(
                              size: 10, color: AdminColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Products Count Pill & Arrow
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$productCount item${productCount == 1 ? '' : 's'}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white38, size: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Product Catalog View (Step 2 — Shop Selected) ─────────────────────────

  Widget _buildProductCatalogView() {
    final shop = _selectedShop!;
    final filtered = _filteredProducts;
    final total = _products.length;
    final availableCount = _products.where((p) => p.isAvailable).length;
    final hiddenCount = _products.where((p) => !p.isAvailable).length;
    final productCategories = _availableProductCategories;

    return RefreshIndicator(
      onRefresh: () => _loadProductsForShop(shop.id),
      color: AdminColors.primary,
      backgroundColor: AdminColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // Shop Header Card with Switch Button
          AdminCard(
            padding: const EdgeInsets.all(14),
            bgColor: AdminColors.surface,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: AdminColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name, style: AdminStyles.title(size: 14)),
                      const SizedBox(height: 2),
                      Text(
                        'Category: ${shop.category}${shop.sellerName != null ? " • Owner: ${shop.sellerName}" : ""}',
                        style: AdminStyles.caption(
                            size: 11, color: AdminColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: Text('Change',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () {
                    HapticUtils.selection();
                    setState(() {
                      _selectedShop = null;
                      _products = [];
                    });
                  },
                ),
              ],
            ),
          ).animate().fadeIn(duration: 200.ms),

          const SizedBox(height: 12),

          // Metrics Bar
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Total Products',
                  value: '$total',
                  color: AdminColors.primary,
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Available',
                  value: '$availableCount',
                  color: AdminColors.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Hidden',
                  value: '$hiddenCount',
                  color: AdminColors.warning,
                  icon: Icons.visibility_off_outlined,
                ),
              ),
            ],
          ).animate().fadeIn(delay: 50.ms),

          const SizedBox(height: 14),

          // Product Search Bar
          TextField(
            controller: _productSearchCtrl,
            style: AdminStyles.body(size: 14),
            decoration: InputDecoration(
              hintText: 'Search products in ${shop.name}...',
              hintStyle:
                  AdminStyles.caption(color: AdminColors.textMuted, size: 13),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AdminColors.textMuted),
              suffixIcon: _productSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: Colors.white54, size: 18),
                      onPressed: () => _productSearchCtrl.clear(),
                    )
                  : null,
              filled: true,
              fillColor: AdminColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AdminColors.primary, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Availability Filter & Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildProductAvailabilityPill('All', total),
                const SizedBox(width: 6),
                _buildProductAvailabilityPill('Available', availableCount),
                const SizedBox(width: 6),
                _buildProductAvailabilityPill('Hidden', hiddenCount),
                const SizedBox(width: 12),
                Container(
                    width: 1,
                    height: 24,
                    color: AdminColors.cardBorder),
                const SizedBox(width: 12),
                ...productCategories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildProductCategoryPill(cat),
                    )),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Products (${filtered.length})',
                style: AdminStyles.title(size: 14),
              ),
              if (_loadingProducts)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AdminColors.primary),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Catalog Content
          if (_loadingProducts && _products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: AdminColors.primary),
              ),
            )
          else if (_productsError != null && _products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AdminColors.danger, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load products',
                        style: AdminStyles.title(size: 16)),
                    const SizedBox(height: 6),
                    Text(_productsError!,
                        style: AdminStyles.caption(color: AdminColors.textMuted),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AdminColors.primary),
                      onPressed: () => _loadProductsForShop(shop.id),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_products.isEmpty)
            // Empty shop state
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_shopping_cart_rounded,
                          color: AdminColors.primary, size: 48),
                    ),
                    const SizedBox(height: 16),
                    Text('No products yet for ${shop.name}',
                        style: AdminStyles.title(size: 16)),
                    const SizedBox(height: 6),
                    Text(
                      'Be the first to upload products to this shop\'s catalog.',
                      style: AdminStyles.caption(
                          color: AdminColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    if (context.watch<RbacProvider>().isSuperAdmin ||
                        context.watch<RbacProvider>().can('products.manage') ||
                        context.watch<RbacProvider>().can('products.create'))
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text('Upload Product Now',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                        onPressed: _navigateToAddProduct,
                      ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.filter_alt_off_rounded,
                        color: AdminColors.textMuted, size: 40),
                    const SizedBox(height: 10),
                    Text('No products match current filters',
                        style: AdminStyles.title(size: 14)),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _productSearchCtrl.clear();
                          _productCategoryFilter = 'All';
                          _productAvailabilityFilter = 'All';
                        });
                      },
                      child: Text('Reset Filters',
                          style: GoogleFonts.poppins(
                              color: AdminColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((prod) => _buildProductCard(prod)),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AdminStyles.caption(
                      size: 10, color: AdminColors.textMuted)),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductAvailabilityPill(String filter, int count) {
    final selected = _productAvailabilityFilter == filter;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        setState(() => _productAvailabilityFilter = filter);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.primary
              : AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AdminColors.primary : AdminColors.cardBorder,
          ),
        ),
        child: Text(
          '$filter ($count)',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildProductCategoryPill(String cat) {
    final selected = _productCategoryFilter == cat;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        setState(() => _productCategoryFilter = cat);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2563EB)
              : AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : AdminColors.cardBorder,
          ),
        ),
        child: Text(
          cat,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
    final hasVariants = product.variants.isNotEmpty;
    final hasDiscount = product.originalPrice != null &&
        product.originalPrice! > product.price;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image Thumbnail with Veg/Non-Veg Tag
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: AdminColors.primary.withValues(alpha: 0.12),
                    child: product.images.isNotEmpty
                        ? Image.network(
                            product.images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_not_supported_outlined,
                              color: AdminColors.textMuted,
                              size: 28,
                            ),
                          )
                        : const Icon(
                            Icons.shopping_bag_outlined,
                            color: AdminColors.primary,
                            size: 28,
                          ),
                  ),
                ),
                if (product.isVeg != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: product.isVeg!
                            ? const Color(0xFF00C853)
                            : const Color(0xFFD50000),
                      ),
                    ),
                  ),
                if (hasDiscount && product.discountPercent != null)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AdminColors.danger,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${product.discountPercent!.toStringAsFixed(0)}% OFF',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: AdminStyles.title(size: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Category & Subcategory tags
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AdminColors.cardBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AdminColors.cardBorder, width: 0.8),
                        ),
                        child: Text(
                          product.category,
                          style: AdminStyles.caption(
                              size: 10, color: AdminColors.textSecondary),
                        ),
                      ),
                      if (product.menuCategory != null &&
                          product.menuCategory!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.menuCategory!,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFA78BFA),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Price Row & Badges
                  Row(
                    children: [
                      Text(
                        '₹${product.price.toStringAsFixed(product.price.truncateToDouble() == product.price ? 0 : 2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.primary,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${product.originalPrice!.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AdminColors.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      if (hasVariants) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${product.variants.length} opts',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Availability Toggle & Action Icons
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quick Toggle Switch
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (product.isAvailable
                                ? AdminColors.success
                                : AdminColors.warning)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        product.isAvailable ? 'Available' : 'Hidden',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: product.isAvailable
                              ? AdminColors.success
                              : AdminColors.warning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Transform.scale(
                      scale: 0.72,
                      child: Switch(
                        value: product.isAvailable,
                        activeThumbColor: AdminColors.success,
                        inactiveThumbColor: Colors.white60,
                        inactiveTrackColor: Colors.white24,
                        onChanged: (context.watch<RbacProvider>().isSuperAdmin ||
                                context.watch<RbacProvider>().can('products.manage'))
                            ? (_) => _toggleAvailability(product)
                            : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Edit & Delete Buttons
                Builder(builder: (ctx) {
                  final rbac = ctx.watch<RbacProvider>();
                  final canManage = rbac.isSuperAdmin || rbac.can('products.manage');
                  final canDelete = canManage || rbac.can('products.delete');
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canManage)
                        IconButton(
                          iconSize: 18,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.edit_outlined,
                              color: AdminColors.primary),
                          tooltip: 'Edit Product',
                          onPressed: () => _navigateToEditProduct(product),
                        ),
                      if (canManage && canDelete) const SizedBox(width: 8),
                      if (canDelete)
                        IconButton(
                          iconSize: 18,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AdminColors.danger),
                          tooltip: 'Delete Product',
                          onPressed: () => _deleteProduct(product),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Floating Action Button (Add Product) ──────────────────────────────────

  Widget _buildAddProductFAB() {
    return FloatingActionButton.extended(
      backgroundColor: AdminColors.primary,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: Text(
        'Add Product',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      onPressed: _navigateToAddProduct,
    );
  }
}
