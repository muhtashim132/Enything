import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart' show CropAspectRatio;
import 'package:cached_network_image/cached_network_image.dart';

import '../../../models/product_model.dart';
import '../../../services/product_storage_service.dart';
import '../../../services/image_compression_service.dart';
import '../../../utils/image_picker_utils.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/haptic_utils.dart';
import '../../seller/add_product_page.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../repositories/audit_repository.dart';

/// Lightweight representation of a shop for admin catalog management.
class AdminShopItem {
  final String id;
  final String name;
  final String category;
  final String? address;
  final bool isActive;
  final bool isAcceptingOrders;
  final String? openTime;
  final String? closeTime;
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
    this.isAcceptingOrders = true,
    this.openTime,
    this.closeTime,
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    this.bannerUrl,
  });

  AdminShopItem copyWith({
    String? id,
    String? name,
    String? category,
    String? address,
    bool? isActive,
    bool? isAcceptingOrders,
    String? openTime,
    String? closeTime,
    String? sellerId,
    String? sellerName,
    String? sellerPhone,
    String? bannerUrl,
    bool clearBanner = false,
  }) {
    return AdminShopItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      isAcceptingOrders: isAcceptingOrders ?? this.isAcceptingOrders,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      bannerUrl: clearBanner ? null : (bannerUrl ?? this.bannerUrl),
    );
  }

  factory AdminShopItem.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? sName;
    String? sPhone;
    if (profile is Map) {
      sName = profile['full_name'] ?? profile['name'];
      sPhone = profile['phone'];
    }
    final rawOpen = (map['open_time'] ?? map['opening_time'])?.toString();
    final rawClose = (map['close_time'] ?? map['closing_time'])?.toString();
    final openStr = (rawOpen != null && rawOpen.length >= 5)
        ? rawOpen.substring(0, 5)
        : (rawOpen ?? '09:00');
    final closeStr = (rawClose != null && rawClose.length >= 5)
        ? rawClose.substring(0, 5)
        : (rawClose ?? '21:00');

    final accepting = map['is_accepting_orders'];
    final isOpen = map['is_open'];
    final isActive = map['is_active'];
    final bool isAccepting = accepting != null
        ? (accepting == true)
        : (isOpen != null ? (isOpen == true) : (isActive == true));

    return AdminShopItem(
      id: map['id']?.toString() ?? '',
      name: (map['shop_name'] ?? map['name'] ?? 'Unnamed Shop').toString(),
      category: (map['category'] ?? 'Retail').toString(),
      address: map['address']?.toString(),
      isActive: (map['is_active'] ?? true),
      isAcceptingOrders: isAccepting,
      openTime: openStr,
      closeTime: closeStr,
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
  RealtimeChannel? _shopsRealtimeChannel;

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
    _initShopsRealtimeSubscription();
  }

  void _initShopsRealtimeSubscription() {
    _shopsRealtimeChannel = _supabase
        .channel('admin-shops-realtime-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shops',
          callback: (payload) {
            _handleRealtimeShopPayload(payload);
          },
        )
        .subscribe();
  }

  void _handleRealtimeShopPayload(PostgresChangePayload payload) {
    if (!mounted) return;
    final newRec = payload.newRecord;
    if (newRec.isEmpty) return;
    final sId = newRec['id']?.toString();
    if (sId == null || sId.isEmpty) return;

    setState(() {
      final sIdx = _shops.indexWhere((s) => s.id == sId);
      if (sIdx != -1) {
        final current = _shops[sIdx];
        final rawOpen = newRec['open_time']?.toString() ?? current.openTime;
        final rawClose = newRec['close_time']?.toString() ?? current.closeTime;
        final openStr = (rawOpen != null && rawOpen.length >= 5)
            ? rawOpen.substring(0, 5)
            : rawOpen;
        final closeStr = (rawClose != null && rawClose.length >= 5)
            ? rawClose.substring(0, 5)
            : rawClose;

        final hasBannerField = newRec.containsKey('banner_url') || newRec.containsKey('banner_image');
        final rawBanner = (newRec['banner_url'] ?? newRec['banner_image'])?.toString();
        final updatedBannerUrl = hasBannerField ? rawBanner : current.bannerUrl;

        final updated = current.copyWith(
          name: (newRec['name'] ?? newRec['shop_name'] ?? current.name).toString(),
          category: (newRec['category'] ?? current.category).toString(),
          address: newRec['address']?.toString() ?? current.address,
          isActive: newRec['is_active'] ?? current.isActive,
          isAcceptingOrders: newRec['is_accepting_orders'] ?? current.isAcceptingOrders,
          openTime: openStr,
          closeTime: closeStr,
          bannerUrl: updatedBannerUrl,
          clearBanner: hasBannerField && (rawBanner == null || rawBanner.isEmpty),
        );
        _shops[sIdx] = updated;
        if (_selectedShop?.id == sId) {
          _selectedShop = updated;
        }
      }
    });
  }

  @override
  void dispose() {
    _shopsRealtimeChannel?.unsubscribe();
    if (_shopsRealtimeChannel != null) {
      _supabase.removeChannel(_shopsRealtimeChannel!);
      _shopsRealtimeChannel = null;
    }
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
      } else {
        // Defensive enrichment: If any shop lacks is_accepting_orders, open_time, or banner info, enrich directly from shops table
        final bool needsEnrichment = rawShops.any((s) =>
            s['is_accepting_orders'] == null ||
            (s['open_time'] == null && s['opening_time'] == null) ||
            (!s.containsKey('banner_url') && !s.containsKey('banner_image')));
        if (needsEnrichment) {
          try {
            final enrichResp = await _supabase.from('shops').select(
                'id, is_active, is_accepting_orders, is_open, is_manually_closed, open_time, close_time, opening_time, closing_time, banner_url, banner_image');
            final enrichMap = {for (var r in enrichResp) r['id'].toString(): r};
            rawShops = rawShops.map((s) {
              final extra = enrichMap[s['id'].toString()];
              if (extra != null) {
                return {...s, ...extra};
              }
              return s;
            }).toList();
          } catch (enrichErr) {
            debugPrint('[AdminProductManagement] Error enriching shop timing data: $enrichErr');
          }
        }
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
          .eq('shop_id', product.shopId)
          .eq('is_deleted', false);

      // Fire-and-forget audit log
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        AuditRepository().log(
          actorId: currentUserId,
          actorRole: rbac.isSuperAdmin ? 'super_admin' : 'admin',
          action: newState ? 'product.enabled' : 'product.hidden',
          entityType: 'product',
          entityId: product.id,
          metadata: {
            'product_name': product.name,
            'shop_id': product.shopId,
            'is_available': newState,
          },
        );
      }

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

  Future<void> _toggleShopActive(AdminShopItem shop) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin &&
        !rbac.can('sellers.suspend') &&
        !rbac.can('shops.manage') &&
        !rbac.can('products.manage')) {
      _showSnack('Permission denied: You cannot modify shop status.',
          isError: true);
      return;
    }

    final originalOpen = shop.isAcceptingOrders;
    final newOpen = !originalOpen;

    // Edge Case: When closing an open shop, inspect if in-flight active orders exist
    if (originalOpen == true) {
      int activeOrdersCount = 0;
      try {
        final activeResp = await _supabase
            .from('orders')
            .select('id')
            .eq('shop_id', shop.id)
            .inFilter('status', [
              'confirmed',
              'preparing',
              'ready_for_pickup',
              'out_for_delivery',
            ]);
        activeOrdersCount = (activeResp as List).length;
      } catch (e) {
        debugPrint('Active orders check note: $e');
      }

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.pause_circle_outline_rounded,
                  color: AdminColors.warning, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Close Shop for Orders?',
                    style: AdminStyles.title(size: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to close "${shop.name}" for new orders?',
                style: AdminStyles.body(size: 14, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AdminColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (activeOrdersCount > 0) ...[
                      Text(
                        '⚡ $activeOrdersCount active order(s) currently in progress.',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.warning),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      '• Marked Closed on Seller Dashboard & Customer App.\n'
                      '• New checkouts will be blocked for this store.\n'
                      '• Existing orders in progress can complete delivery safely without interruption.',
                      style: AdminStyles.caption(
                          size: 11, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
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
              child: Text('Close Shop',
                  style: AdminStyles.body(size: 13, color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    } else {
      HapticUtils.selection();
    }

    if (!mounted) return;
    HapticUtils.selection();

    // 1. Optimistic Local State Update
    setState(() {
      final sIdx = _shops.indexWhere((s) => s.id == shop.id);
      if (sIdx != -1) {
        _shops[sIdx] = shop.copyWith(
          isAcceptingOrders: newOpen,
          isActive: newOpen ? true : shop.isActive,
        );
      }
      if (_selectedShop?.id == shop.id) {
        _selectedShop = _selectedShop!.copyWith(
          isAcceptingOrders: newOpen,
          isActive: newOpen ? true : shop.isActive,
        );
      }
    });

    try {
      // 2. Invoke RPC admin_toggle_shop_accepting_orders with fallback to direct table update
      bool rpcSuccess = false;
      try {
        await _supabase.rpc('admin_toggle_shop_accepting_orders', params: {
          'p_shop_id': shop.id,
          'p_is_open': newOpen,
        });
        rpcSuccess = true;
      } catch (rpcErr) {
        debugPrint('admin_toggle_shop_accepting_orders RPC fallback: $rpcErr');
      }

      if (!rpcSuccess) {
        try {
          await _supabase.rpc('admin_toggle_active', params: {
            'p_target_id': shop.id,
            'p_type': 'shop',
            'p_is_active': newOpen,
          });
          rpcSuccess = true;
        } catch (e2) {
          debugPrint('admin_toggle_active fallback to direct update: $e2');
        }
      }

      if (!rpcSuccess) {
        await _supabase
            .from('shops')
            .update({
              'is_accepting_orders': newOpen,
              'is_open': newOpen,
              'is_manually_closed': !newOpen,
              if (newOpen) 'is_active': true,
            })
            .eq('id', shop.id);
      }

      // 3. Fire-and-forget Audit Log
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        AuditRepository().log(
          actorId: currentUserId,
          actorRole: rbac.isSuperAdmin ? 'super_admin' : 'admin',
          action: newOpen ? 'shop.opened' : 'shop.closed',
          entityType: 'shop',
          entityId: shop.id,
          metadata: {
            'shop_name': shop.name,
            'previous_status': originalOpen,
            'new_status': newOpen,
          },
        );
      }

      _showSnack(
        newOpen
            ? '🟢 "${shop.name}" is now Open & Accepting Orders'
            : '⏸️ "${shop.name}" is now Closed (Not Taking Orders)',
        isError: false,
      );
    } catch (e) {
      debugPrint('Error toggling shop status: $e');
      // Rollback local state on error
      if (mounted) {
        setState(() {
          final sIdx = _shops.indexWhere((s) => s.id == shop.id);
          if (sIdx != -1) {
            _shops[sIdx] = shop.copyWith(
              isAcceptingOrders: originalOpen,
              isActive: shop.isActive,
            );
          }
          if (_selectedShop?.id == shop.id) {
            _selectedShop = _selectedShop!.copyWith(
              isAcceptingOrders: originalOpen,
              isActive: shop.isActive,
            );
          }
        });
        _showSnack('Failed to update shop status: $e', isError: true);
      }
    }
  }

  Future<void> _editShopOperatingHours(AdminShopItem shop) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin &&
        !rbac.can('shops.manage') &&
        !rbac.can('products.manage')) {
      _showSnack('Permission denied: You cannot edit store operating hours.',
          isError: true);
      return;
    }

    String openTimeVal = shop.openTime ?? '09:00';
    String closeTimeVal = shop.closeTime ?? '21:00';

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        String localOpen = openTimeVal;
        String localClose = closeTimeVal;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AdminColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.access_time_filled_rounded,
                      color: AdminColors.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Edit Operating Hours',
                        style: AdminStyles.title(size: 16)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set opening and closing hours for "${shop.name}". This will sync live to the seller dashboard and update customer ordering hours.',
                    style: AdminStyles.caption(
                        size: 12, color: AdminColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Opens at',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final parts = localOpen.split(':');
                                final initial = TimeOfDay(
                                  hour: int.tryParse(parts.firstOrNull ?? '') ?? 9,
                                  minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
                                );
                                final picked = await showTimePicker(
                                  context: dialogCtx,
                                  initialTime: initial,
                                );
                                if (picked != null) {
                                  final h = picked.hour.toString().padLeft(2, '0');
                                  final m = picked.minute.toString().padLeft(2, '0');
                                  setDialogState(() => localOpen = '$h:$m');
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AdminColors.cardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AdminColors.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded,
                                        size: 16, color: AdminColors.primary),
                                    const SizedBox(width: 8),
                                    Text(localOpen,
                                        style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Closes at',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final parts = localClose.split(':');
                                final initial = TimeOfDay(
                                  hour: int.tryParse(parts.firstOrNull ?? '') ?? 21,
                                  minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
                                );
                                final picked = await showTimePicker(
                                  context: dialogCtx,
                                  initialTime: initial,
                                );
                                if (picked != null) {
                                  final h = picked.hour.toString().padLeft(2, '0');
                                  final m = picked.minute.toString().padLeft(2, '0');
                                  setDialogState(() => localClose = '$h:$m');
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AdminColors.cardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AdminColors.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_filled_rounded,
                                        size: 16, color: AdminColors.warning),
                                    const SizedBox(width: 8),
                                    Text(localClose,
                                        style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: AdminStyles.body(color: AdminColors.textMuted)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                      ctx, {'open_time': localOpen, 'close_time': localClose}),
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Save Hours',
                      style: AdminStyles.body(size: 13, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    final newOpen = result['open_time']!;
    final newClose = result['close_time']!;

    final oldOpen = shop.openTime;
    final oldClose = shop.closeTime;

    // Optimistically update local state
    setState(() {
      final sIdx = _shops.indexWhere((s) => s.id == shop.id);
      if (sIdx != -1) {
        _shops[sIdx] = shop.copyWith(openTime: newOpen, closeTime: newClose);
      }
      if (_selectedShop?.id == shop.id) {
        _selectedShop = _selectedShop!.copyWith(openTime: newOpen, closeTime: newClose);
      }
    });

    try {
      bool rpcOk = false;
      try {
        await _supabase.rpc('admin_update_shop_operating_hours', params: {
          'p_shop_id': shop.id,
          'p_open_time': newOpen,
          'p_close_time': newClose,
        });
        rpcOk = true;
      } catch (rpcErr) {
        debugPrint('admin_update_shop_operating_hours fallback to direct update: $rpcErr');
      }

      if (!rpcOk) {
        await _supabase.from('shops').update({
          'open_time': newOpen,
          'close_time': newClose,
          'opening_time': newOpen,
          'closing_time': newClose,
          'is_manually_closed': false,
        }).eq('id', shop.id);
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        AuditRepository().log(
          actorId: currentUserId,
          actorRole: rbac.isSuperAdmin ? 'super_admin' : 'admin',
          action: 'shop.hours_updated',
          entityType: 'shop',
          entityId: shop.id,
          metadata: {
            'shop_name': shop.name,
            'open_time': newOpen,
            'close_time': newClose,
          },
        );
      }

      _showSnack(
        '🕒 Operating hours updated to $newOpen - $newClose',
        isError: false,
      );
    } catch (e) {
      debugPrint('Error updating shop operating hours: $e');
      if (mounted) {
        setState(() {
          final sIdx = _shops.indexWhere((s) => s.id == shop.id);
          if (sIdx != -1) {
            _shops[sIdx] = shop.copyWith(openTime: oldOpen, closeTime: oldClose);
          }
          if (_selectedShop?.id == shop.id) {
            _selectedShop = _selectedShop!.copyWith(openTime: oldOpen, closeTime: oldClose);
          }
        });
        _showSnack('Failed to update operating hours: $e', isError: true);
      }
    }
  }

  // ── Shop Banner Management (100x Forensic Parity) ─────────────────────────

  Future<void> _updateShopBanner(AdminShopItem shop, String? newBannerUrl) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin &&
        !rbac.can('shops.manage') &&
        !rbac.can('products.manage') &&
        !rbac.can('sellers.manage')) {
      _showSnack('Permission denied: You cannot modify store banners.',
          isError: true);
      return;
    }

    final sanitizedUrl = (newBannerUrl != null && newBannerUrl.trim().isNotEmpty)
        ? newBannerUrl.trim()
        : null;

    if (sanitizedUrl != null && sanitizedUrl.length > 1000) {
      _showSnack('Banner URL must be 1000 characters or fewer.', isError: true);
      return;
    }

    final oldBanner = shop.bannerUrl;

    // 1. Optimistic Local State Update
    setState(() {
      final sIdx = _shops.indexWhere((s) => s.id == shop.id);
      if (sIdx != -1) {
        _shops[sIdx] = shop.copyWith(
          bannerUrl: sanitizedUrl,
          clearBanner: sanitizedUrl == null,
        );
      }
      if (_selectedShop?.id == shop.id) {
        _selectedShop = _selectedShop!.copyWith(
          bannerUrl: sanitizedUrl,
          clearBanner: sanitizedUrl == null,
        );
      }
    });

    try {
      // 2. Atomic RPC invocation with fallback
      bool rpcOk = false;
      try {
        await _supabase.rpc('admin_update_shop_banner', params: {
          'p_shop_id': shop.id,
          'p_banner_url': sanitizedUrl,
        });
        rpcOk = true;
      } catch (rpcErr) {
        debugPrint('admin_update_shop_banner RPC fallback to direct update: $rpcErr');
      }

      if (!rpcOk) {
        // Dual column sync to guarantee 100% parity across legacy and new queries
        await _supabase.from('shops').update({
          'banner_url': sanitizedUrl,
          'banner_image': sanitizedUrl,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', shop.id);
      }

      // 3. Fire-and-forget Audit Log
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        AuditRepository().log(
          actorId: currentUserId,
          actorRole: rbac.isSuperAdmin ? 'super_admin' : 'admin',
          action: sanitizedUrl != null ? 'shop.banner_updated' : 'shop.banner_removed',
          entityType: 'shop',
          entityId: shop.id,
          metadata: {
            'shop_name': shop.name,
            'previous_banner': oldBanner,
            'new_banner': sanitizedUrl,
          },
        );
      }

      _showSnack(
        sanitizedUrl != null
            ? '🖼️ Store banner updated successfully!'
            : '🗑️ Store banner removed',
        isError: false,
      );
    } catch (e) {
      debugPrint('Error updating shop banner: $e');
      if (mounted) {
        setState(() {
          final sIdx = _shops.indexWhere((s) => s.id == shop.id);
          if (sIdx != -1) {
            _shops[sIdx] = shop.copyWith(
              bannerUrl: oldBanner,
              clearBanner: oldBanner == null,
            );
          }
          if (_selectedShop?.id == shop.id) {
            _selectedShop = _selectedShop!.copyWith(
              bannerUrl: oldBanner,
              clearBanner: oldBanner == null,
            );
          }
        });
        _showSnack('Failed to update banner: $e', isError: true);
      }
    }
  }

  Future<void> _confirmRemoveBanner(AdminShopItem shop) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin &&
        !rbac.can('shops.manage') &&
        !rbac.can('products.manage') &&
        !rbac.can('sellers.manage')) {
      _showSnack('Permission denied: You cannot modify store banners.',
          isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: AdminColors.danger, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Remove Store Banner?',
                  style: AdminStyles.title(size: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove the banner for "${shop.name}"?',
              style: AdminStyles.body(size: 14, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AdminColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Store will revert to default category branding in feeds.\n'
                    '• Customer app restaurant header will use standard styling.\n'
                    '• You can upload or set a new banner at any time.',
                    style: AdminStyles.caption(
                        size: 11, color: AdminColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
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
            child: Text('Remove Banner',
                style: AdminStyles.body(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateShopBanner(shop, null);
    }
  }

  void _showFullBannerViewer(AdminShopItem shop) {
    if (shop.bannerUrl == null || shop.bannerUrl!.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AdminColors.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: AdminColors.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_size_select_actual_rounded,
                      color: AdminColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${shop.name} • Banner',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 460),
                color: Colors.black,
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: shop.bannerUrl!,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      height: 220,
                      color: AdminColors.cardBg,
                      child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AdminColors.primary),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 220,
                      color: AdminColors.cardBg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image_rounded,
                                size: 40, color: AdminColors.warning),
                            const SizedBox(height: 6),
                            Text('Failed to load full image',
                                style: AdminStyles.caption(
                                    size: 12, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ),
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

  Future<void> _manageShopBanner(AdminShopItem shop) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin &&
        !rbac.can('shops.manage') &&
        !rbac.can('products.manage') &&
        !rbac.can('sellers.manage')) {
      _showSnack('Permission denied: You cannot modify store banners.',
          isError: true);
      return;
    }

    final urlCtrl = TextEditingController(text: shop.bannerUrl ?? '');
    int activeTab = 0; // 0: Upload from Device, 1: Enter Image URL
    bool isUploading = false;
    String? uploadStatusMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isUploading,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final currentBanner = shop.bannerUrl;
            final hasCurrent =
                currentBanner != null && currentBanner.trim().isNotEmpty;

            return AlertDialog(
              backgroundColor: AdminColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_rounded,
                        color: AdminColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Store Banner Studio',
                            style: AdminStyles.title(size: 16)),
                        Text(
                          shop.name,
                          style: AdminStyles.caption(
                              size: 11, color: AdminColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Promotional 16:9 banner displayed on customer discovery, search listings, and store menu header.',
                      style: AdminStyles.caption(
                          size: 11, color: AdminColors.textSecondary),
                    ),
                    const SizedBox(height: 14),

                    // Active / Current Banner Mini Preview
                    if (hasCurrent) ...[
                      Container(
                        height: 90,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.cardBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: currentBanner,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: AdminColors.cardBg,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AdminColors.primary),
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: AdminColors.cardBg,
                                  child: const Icon(Icons.broken_image_rounded,
                                      color: AdminColors.textMuted),
                                ),
                              ),
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Active Banner',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.success,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Mode Selection Tabs (Device vs URL)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AdminColors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: isUploading
                                  ? null
                                  : () => setDialogState(() => activeTab = 0),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 0
                                      ? AdminColors.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.upload_file_rounded,
                                        size: 14,
                                        color: activeTab == 0
                                            ? Colors.white
                                            : AdminColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Device Upload',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: activeTab == 0
                                              ? Colors.white
                                              : AdminColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: isUploading
                                  ? null
                                  : () => setDialogState(() => activeTab = 1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 1
                                      ? AdminColors.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.link_rounded,
                                        size: 14,
                                        color: activeTab == 1
                                            ? Colors.white
                                            : AdminColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Image URL',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: activeTab == 1
                                              ? Colors.white
                                              : AdminColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // TAB 0: Device Upload
                    if (activeTab == 0) ...[
                      if (isUploading) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          decoration: BoxDecoration(
                            color: AdminColors.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AdminColors.cardBorder),
                          ),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(
                                  color: AdminColors.primary),
                              const SizedBox(height: 14),
                              Text(
                                uploadStatusMessage ??
                                    'Uploading banner to storage...',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Compressing & generating public asset URL',
                                style: AdminStyles.caption(
                                    size: 10,
                                    color: AdminColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        InkWell(
                          onTap: () async {
                            final source =
                                await showImageSourceSheet(dialogCtx);
                            if (source == null || !mounted || !dialogCtx.mounted) return;

                            final picked = await pickSafeImage(
                              source: source,
                              maxWidth: 1920,
                              maxHeight: 1080,
                              imageQuality: 80,
                            );
                            if (picked == null || !mounted || !dialogCtx.mounted) return;

                            final cropped = await cropImage(
                              dialogCtx,
                              picked.path,
                              aspectRatio:
                                  const CropAspectRatio(ratioX: 16, ratioY: 9),
                              title: 'Crop Store Banner (16:9)',
                            );
                            if (cropped == null || !mounted) return;

                            setDialogState(() {
                              isUploading = true;
                              uploadStatusMessage =
                                  'Compressing banner image...';
                            });

                            try {
                              Uint8List bytes;
                              if (!kIsWeb) {
                                final file = File(cropped.path);
                                bytes = await ImageCompressionService
                                        .compressFile(file) ??
                                    await file.readAsBytes();
                              } else {
                                bytes = await cropped.readAsBytes();
                              }

                              setDialogState(() {
                                uploadStatusMessage =
                                    'Uploading to secure storage...';
                              });

                              final fileName =
                                  '${DateTime.now().millisecondsSinceEpoch}.jpg';
                              final filePath = 'banners/${shop.id}/$fileName';

                              await _supabase.storage.from('shops').uploadBinary(
                                    filePath,
                                    bytes,
                                    fileOptions: const FileOptions(
                                      contentType: 'image/jpeg',
                                      upsert: true,
                                    ),
                                  );

                              final uploadedUrl = _supabase.storage
                                  .from('shops')
                                  .getPublicUrl(filePath);

                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                              }

                              await _updateShopBanner(shop, uploadedUrl);
                            } catch (uploadErr) {
                              debugPrint('Error uploading banner: $uploadErr');
                              if (dialogCtx.mounted) {
                                setDialogState(() {
                                  isUploading = false;
                                  uploadStatusMessage = null;
                                });
                              }
                              _showSnack('Upload failed: $uploadErr',
                                  isError: true);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 22, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AdminColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AdminColors.primary.withValues(alpha: 0.35),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AdminColors.primary
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.cloud_upload_rounded,
                                    color: AdminColors.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Choose Photo / Camera',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to select image • Standard 16:9 crop will open automatically',
                                  style: AdminStyles.caption(
                                      size: 11,
                                      color: AdminColors.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],

                    // TAB 1: Enter Direct Image URL
                    if (activeTab == 1) ...[
                      TextField(
                        controller: urlCtrl,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'https://example.com/banner.jpg',
                          hintStyle: AdminStyles.caption(
                              size: 11, color: AdminColors.textMuted),
                          filled: true,
                          fillColor: AdminColors.cardBg,
                          prefixIcon: const Icon(Icons.link_rounded,
                              size: 16, color: AdminColors.primary),
                          suffixIcon: urlCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 14, color: Colors.white54),
                                  onPressed: () {
                                    urlCtrl.clear();
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AdminColors.cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AdminColors.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AdminColors.primary),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 10),

                      // Live Dynamic Preview Box
                      if (urlCtrl.text.trim().isNotEmpty) ...[
                        Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AdminColors.cardBorder),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: urlCtrl.text.trim(),
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AdminColors.cardBg,
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AdminColors.primary),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: AdminColors.cardBg,
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          size: 16, color: AdminColors.warning),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Invalid URL or image not accessible',
                                        style: AdminStyles.caption(
                                            size: 11,
                                            color: AdminColors.warning),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isUploading
                              ? null
                              : () async {
                                  final rawUrl = urlCtrl.text.trim();
                                  if (rawUrl.isEmpty) {
                                    _showSnack('Please enter an image URL.',
                                        isError: true);
                                    return;
                                  }
                                  final uri = Uri.tryParse(rawUrl);
                                  if (uri == null ||
                                      (!uri.isScheme('http') &&
                                          !uri.isScheme('https')) ||
                                      uri.host.isEmpty) {
                                    _showSnack(
                                        'Please enter a valid HTTP/HTTPS image URL.',
                                        isError: true);
                                    return;
                                  }
                                  if (rawUrl.length > 1000) {
                                    _showSnack(
                                        'URL exceeds maximum limit of 1000 characters.',
                                        isError: true);
                                    return;
                                  }

                                  Navigator.pop(dialogCtx);
                                  await _updateShopBanner(shop, rawUrl);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AdminColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              size: 16),
                          label: Text('Save Banner URL',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (hasCurrent && !isUploading)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _confirmRemoveBanner(shop);
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 14, color: AdminColors.danger),
                    label: Text(
                      'Remove Banner',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.danger,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed:
                      isUploading ? null : () => Navigator.pop(dialogCtx),
                  child: Text('Close',
                      style: AdminStyles.body(color: AdminColors.textMuted)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShopBannerSection(AdminShopItem shop) {
    final hasBanner =
        shop.bannerUrl != null && shop.bannerUrl!.trim().isNotEmpty;

    if (hasBanner) {
      return Container(
        height: 145,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AdminColors.cardBorder.withValues(alpha: 0.8), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Banner Background Image with High-Speed CachedNetworkImage
              CachedNetworkImage(
                imageUrl: shop.bannerUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AdminColors.cardBg,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AdminColors.primary),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AdminColors.cardBg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_rounded,
                            size: 28, color: AdminColors.warning),
                        const SizedBox(height: 4),
                        Text('Image Failed to Load',
                            style: AdminStyles.caption(
                                size: 11, color: AdminColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),

              // Gradient Scrim for Contrast & Legibility
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),

              // Top Row: Status Chip & Fullscreen Button
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_size_select_actual_rounded,
                              size: 12, color: AdminColors.info),
                          const SizedBox(width: 5),
                          Text(
                            'Store Banner • 16:9',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showFullBannerViewer(shop),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.fullscreen_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Actions: Remove & Change Banner
              Positioned(
                bottom: 10,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: AdminColors.danger.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _confirmRemoveBanner(shop),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Remove',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AdminColors.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _manageShopBanner(shop),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'Change Banner',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ],
                          ),
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

    // Unconfigured Banner State
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AdminColors.cardBorder.withValues(alpha: 0.9), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AdminColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_photo_alternate_outlined,
                color: AdminColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Store Banner Configured',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Upload a 16:9 banner for restaurant header & customer discovery feeds',
                  style: AdminStyles.caption(
                      size: 10, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.cloud_upload_rounded, size: 14),
            label: Text(
              'Add Banner',
              style:
                  GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            onPressed: () => _manageShopBanner(shop),
          ),
        ],
      ),
    );
  }

  Future<void> _batchToggleProducts(bool isAvailable) async {
    if (_selectedShop == null) return;
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('products.manage')) {
      _showSnack('Permission denied: You cannot batch modify products.',
          isError: true);
      return;
    }

    final shop = _selectedShop!;
    final actionLabel =
        isAvailable ? 'Enable All Products' : 'Hide All Products';
    final actionDesc = isAvailable
        ? 'Make all ${_products.length} products in "${shop.name}" Available for purchase?'
        : 'Hide all ${_products.length} products in "${shop.name}" (mark as Out of Stock)?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(actionLabel, style: AdminStyles.title(size: 16)),
        content: Text(
          actionDesc,
          style: AdminStyles.body(size: 13, color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: AdminStyles.body(color: AdminColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  isAvailable ? AdminColors.success : AdminColors.warning,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(actionLabel,
                style: AdminStyles.body(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    HapticUtils.medium();

    // Cache previous products state for rollback
    final previousProducts = List<ProductModel>.from(_products);

    // Optimistic local state update
    setState(() {
      _products =
          _products.map((p) => p.copyWith(isAvailable: isAvailable)).toList();
    });

    try {
      int updatedCount = 0;
      try {
        final res = await _supabase.rpc('admin_batch_toggle_products', params: {
          'p_shop_id': shop.id,
          'p_is_available': isAvailable,
        });
        if (res is int) {
          updatedCount = res;
        } else if (res is num) {
          updatedCount = res.toInt();
        }
      } catch (rpcErr) {
        debugPrint('admin_batch_toggle_products RPC fallback: $rpcErr');
        // Fallback direct table update complying strictly with soft-delete rule
        await _supabase
            .from('products')
            .update({
              'is_available': isAvailable,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('shop_id', shop.id)
            .eq('is_deleted', false);
        updatedCount = _products.length;
      }

      // Fire-and-forget Audit Log
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        AuditRepository().log(
          actorId: currentUserId,
          actorRole: rbac.isSuperAdmin ? 'super_admin' : 'admin',
          action: isAvailable ? 'products.batch_enable' : 'products.batch_hide',
          entityType: 'shop',
          entityId: shop.id,
          metadata: {
            'shop_name': shop.name,
            'is_available': isAvailable,
            'count': updatedCount,
          },
        );
      }

      _showSnack(
        isAvailable
            ? '✅ Enabled $updatedCount product(s) as Available'
            : '👁️ Hidden $updatedCount product(s) (Out of Stock)',
        isError: false,
      );
    } catch (e) {
      debugPrint('Batch toggle error: $e');
      if (mounted) {
        setState(() {
          _products = previousProducts;
        });
        _showSnack('Failed to batch update products: $e', isError: true);
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
      final isOpen = s.isAcceptingOrders && s.isActive;
      if ((_selectedShopStatusFilter == 'Active' || _selectedShopStatusFilter == 'Open') && !isOpen) {
        return false;
      }
      if ((_selectedShopStatusFilter == 'Inactive' || _selectedShopStatusFilter == 'Closed') && isOpen) {
        return false;
      }
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
                // Avatar / Banner Thumbnail with 1-Tap Studio Action
                Tooltip(
                  message: 'Manage Store Banner',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _manageShopBanner(shop),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.cardBorder),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          shop.bannerUrl != null && shop.bannerUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: shop.bannerUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => const Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AdminColors.primary,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => const Icon(
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
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30, width: 0.8),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Shop Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: AdminStyles.title(size: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    size: 10, color: AdminColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '${shop.openTime ?? '09:00'} - ${shop.closeTime ?? '21:00'}',
                                  style: AdminStyles.caption(
                                      size: 10, color: AdminColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Active Status Switch & Products Count Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Interactive Switch for Shop Status (is_accepting_orders)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ((shop.isAcceptingOrders && shop.isActive)
                                    ? AdminColors.success
                                    : AdminColors.warning)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            (shop.isAcceptingOrders && shop.isActive) ? 'Open' : 'Closed',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: (shop.isAcceptingOrders && shop.isActive)
                                  ? AdminColors.success
                                  : AdminColors.warning,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Transform.scale(
                          scale: 0.72,
                          child: Switch(
                            value: shop.isAcceptingOrders && shop.isActive,
                            activeThumbColor: AdminColors.success,
                            inactiveThumbColor: Colors.white60,
                            inactiveTrackColor: Colors.white24,
                            onChanged: (_) => _toggleShopActive(shop),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$productCount item${productCount == 1 ? '' : 's'}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white38, size: 10),
                      ],
                    ),
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
          // Shop Header Card with Master Toggle and Batch Actions
          AdminCard(
            padding: const EdgeInsets.all(14),
            bgColor: AdminColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Restaurant / Shop Banner Showcase & Management ────────
                _buildShopBannerSection(shop),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AdminColors.cardBorder),
                      ),
                      child: shop.bannerUrl != null && shop.bannerUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: shop.bannerUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AdminColors.primary,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => const Icon(
                                  Icons.storefront_rounded,
                                  color: AdminColors.primary,
                                  size: 24,
                                ),
                              ),
                            )
                          : const Icon(Icons.storefront_rounded,
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

                const SizedBox(height: 12),
                const Divider(color: AdminColors.cardBorder, height: 1),
                const SizedBox(height: 12),

                // Master Restaurant/Shop Active & Accepting Orders Status Switch
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: ((shop.isAcceptingOrders && shop.isActive)
                            ? AdminColors.success
                            : AdminColors.warning)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ((shop.isAcceptingOrders && shop.isActive)
                              ? AdminColors.success
                              : AdminColors.warning)
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (shop.isAcceptingOrders && shop.isActive)
                            ? Icons.check_circle_rounded
                            : Icons.pause_circle_filled_rounded,
                        size: 18,
                        color: (shop.isAcceptingOrders && shop.isActive)
                            ? AdminColors.success
                            : AdminColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (shop.isAcceptingOrders && shop.isActive)
                                  ? 'Shop Open & Accepting Orders'
                                  : 'Shop Closed (Not Taking Orders)',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (shop.isAcceptingOrders && shop.isActive)
                                    ? AdminColors.success
                                    : AdminColors.warning,
                              ),
                            ),
                            Text(
                              (shop.isAcceptingOrders && shop.isActive)
                                  ? 'Synchronized live with Seller Dashboard & Customer App'
                                  : 'Hidden from feeds; in-flight orders finish safely',
                              style: AdminStyles.caption(
                                  size: 10, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: 0.82,
                        child: Switch(
                          value: shop.isAcceptingOrders && shop.isActive,
                          activeThumbColor: AdminColors.success,
                          inactiveThumbColor: Colors.white60,
                          inactiveTrackColor: Colors.white24,
                          onChanged: (_) => _toggleShopActive(shop),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Store Operating Hours Section with 1-Tap Edit
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminColors.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_filled_rounded,
                          size: 18, color: AdminColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Operating Hours: ${shop.openTime ?? '09:00'} - ${shop.closeTime ?? '21:00'}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Syncs with customer ordering window & seller dashboard',
                              style: AdminStyles.caption(
                                  size: 10, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.primary,
                          side: BorderSide(
                              color: AdminColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_rounded, size: 13),
                        label: Text(
                          'Edit Hours',
                          style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => _editShopOperatingHours(shop),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Quick Batch Actions for Products
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.warning,
                          side: BorderSide(
                              color: AdminColors.warning.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon:
                            const Icon(Icons.visibility_off_outlined, size: 14),
                        label: Text(
                          'Hide All Items',
                          style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => _batchToggleProducts(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.success,
                          side: BorderSide(
                              color: AdminColors.success.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 14),
                        label: Text(
                          'Enable All Items',
                          style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => _batchToggleProducts(true),
                      ),
                    ),
                  ],
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
                if (product.showsDietEmblem)
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
