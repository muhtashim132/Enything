import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../config/app_categories.dart';
import '../../config/tax_config.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../models/product_model.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/image_picker_utils.dart';
import '../../services/image_compression_service.dart';
import 'dart:ui' show lerpDouble;
import '../../services/gst_recommendation_engine.dart';
import '../../services/master_catalog_service.dart';
import '../../utils/haptic_utils.dart';

/// 100x Unified Image Item for Product Gallery
/// Preserves exact drag-and-drop repositioning sequence across remote CDN URLs and local files.
class ProductImageItem {
  final String id;
  final String? remoteUrl;
  final XFile? localFile;

  ProductImageItem.remote(this.remoteUrl, {String? customId})
      : id = customId ?? 'remote_${remoteUrl}_${DateTime.now().microsecondsSinceEpoch}',
        localFile = null;

  ProductImageItem.local(this.localFile, {String? customId})
      : id = customId ?? 'local_${localFile?.path}_${DateTime.now().microsecondsSinceEpoch}',
        remoteUrl = null;

  bool get isRemote => remoteUrl != null && remoteUrl!.isNotEmpty;
  bool get isLocal => localFile != null;
}

class AddProductPage extends StatefulWidget {
  final ProductModel? existingProduct;
  final String? initialShopId;
  const AddProductPage({super.key, this.existingProduct, this.initialShopId});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  SupabaseClient get _supabase => Supabase.instance.client;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _originalPriceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _menuCategoryController = TextEditingController();
  final _weightController = TextEditingController();
  final _inventoryController = TextEditingController();

  bool? _isVeg;
  bool _isAvailable = true;
  bool _hasDiscount = false;
  bool _isSaving = false;
  String _productCategory = 'Food';
  String _unitType = 'pieces';
  bool _requiresPrescription = false;
  String _medicineType = 'General';
  String? _shopId;
  String? _shopPrimaryCategory;

  // ── Bulk Catering & Event Ordering ─────────────────────────────────────────
  bool _bulkEligible = false;
  final _minBulkQuantityController = TextEditingController(text: '10');
  List<Map<String, dynamic>> _bulkPriceTiers = [];
  // BUG-FIX: Only categories belonging to the shop's CategoryGroup are allowed.
  // Prevents a restaurant seller from mis-categorising a product as Pharmacy etc.
  late List<String> _allowedCategories = [
    _productCategory
  ]; // secure fallback until shop loads
  List<XFile> _images = [];
  List<String> _existingImageUrls = [];
  List<ProductImageItem> _productImages = [];
  List<ProductVariant> _variants = [];
  final Map<String, File> _variantImageFiles = {};

  // ── Professional UX State ─────────────────────────────────────────────────
  bool _isDirty = false;
  final Set<String> _removedVariantImageUrls = {};

  // ── Shop-Scoped Menu Categories ──────────────────────────────────────────
  List<String> _existingMenuCategories = [];
  bool _loadingMenuCategories = false;

  // ── GST Recommendation Engine ────────────────────────────────────────────
  GstRecommendation? _gstRecommendation;
  double? _gstRateOverride;
  bool _gstLoading = false;
  bool _gstUserOverridden = false;
  Timer? _gstDebounce;
  String _selectedDemographic = 'Unisex';

  // ── Master Catalog Dropdown & 1-Tap Autofill ───────────────────────────────
  final _brandController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  List<ProductModel> _catalogSuggestions = [];
  bool _isSearchingCatalog = false;
  bool _showCatalogSuggestions = false;
  Timer? _catalogDebounce;
  int _catalogSearchSeq = 0;
  Map<String, dynamic>? _lastAutofillSnapshot;
  String? _autofilledFromProductName;

  List<String> get _availableUnitTypes {
    if (_productCategory == 'Clothing' ||
        _productCategory == 'Electronics' ||
        _productCategory == 'Hardware' ||
        _productCategory == 'Books') {
      return ['pieces'];
    }
    return ['pieces', 'kg', 'grams', 'liter', 'ml'];
  }

  @override
  void initState() {
    super.initState();
    _shopId = widget.existingProduct?.shopId ?? widget.initialShopId;
    if (_shopId != null && _shopId!.isNotEmpty) {
      _fetchExistingMenuCategories();
    }
    // Pre-load DB keyword rules so first recommendation is instant
    GstRecommendationEngine.instance.ensureLoaded();
    _fetchShopId();
    // Debounced listener: re-run GST recommendation when product name changes
    _nameController.addListener(_scheduleGstUpdate);
    _nameController.addListener(_markDirty);
    _nameController.addListener(_onNameChanged);
    _nameFocusNode.addListener(_onNameFocusChanged);
    _brandController.addListener(_markDirty);
    _priceController.addListener(_markDirty);
    _originalPriceController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _menuCategoryController.addListener(_markDirty);
    _weightController.addListener(_markDirty);
    _inventoryController.addListener(_markDirty);
    _minBulkQuantityController.addListener(_markDirty);
    if (widget.existingProduct != null) {
      final p = widget.existingProduct!;
      _nameController.text = p.name;
      if (p.brand != null) {
        _brandController.text = p.brand!;
      }
      _priceController.text = p.price.toString();
      if (p.originalPrice != null && p.originalPrice! > 0) {
        _hasDiscount = true;
        _originalPriceController.text = p.originalPrice.toString();
      }
      _descriptionController.text = p.description ?? '';
      _productCategory = p.category;
      _menuCategoryController.text = p.menuCategory ?? '';
      _isVeg = AppCategories.isFoodCategory(p.category) ? p.isVeg : null;
      _isAvailable = p.isAvailable;
      if (p.weightPerUnit != null) {
        _weightController.text = p.weightPerUnit.toString();
      }
      final normalizedUnit = (p.unitType.toLowerCase() == 'piece' || p.unitType.isEmpty)
          ? 'pieces'
          : p.unitType.toLowerCase();
      _unitType = _availableUnitTypes.contains(normalizedUnit)
          ? normalizedUnit
          : _availableUnitTypes.first;
      if (p.totalQuantity != null) {
        _inventoryController.text = p.totalQuantity.toString();
      }
      _requiresPrescription = p.requiresPrescription;
      _medicineType = p.medicineType;
      _existingImageUrls = List.from(p.images);
      _productImages =
          p.images.map((url) => ProductImageItem.remote(url)).toList();
      _variants = List.from(p.variants);

      // Bulk catering restoration
      _bulkEligible = p.bulkEligible;
      if (p.minBulkQuantity != null) {
        _minBulkQuantityController.text = p.minBulkQuantity.toString();
      }
      _bulkPriceTiers = p.bulkPriceTiers.map((t) => Map<String, dynamic>.from(t)).toList();

      // Restore saved product-level GST override
      if (p.gstRateOverride != null) {
        _gstRateOverride = p.gstRateOverride;
        _gstUserOverridden = true;
        _gstRecommendation = GstRecommendation(
          rate: p.gstRateOverride!,
          reason:
              '${(p.gstRateOverride! * 100).toStringAsFixed(0)}% — Previously saved',
          isAmbiguous: false,
        );
      }
      for (final tag in p.specialTags) {
        if (['#Men', '#Women', '#Boys', '#Girls', '#Kids', '#Unisex']
            .contains(tag)) {
          _selectedDemographic = tag.replaceAll('#', '');
        }
      }
    }
  }

  Future<void> _fetchShopId() async {
    final auth = context.read<AuthProvider>();
    try {
      final targetShopId = _shopId ?? widget.existingProduct?.shopId ?? widget.initialShopId;
      Map<String, dynamic>? resp;

      if (targetShopId != null && targetShopId.isNotEmpty) {
        final queryResp = await _supabase
            .from('shops')
            .select('id, category, categories')
            .eq('id', targetShopId)
            .maybeSingle();
        resp = queryResp;
      }

      if (resp == null) {
        final queryResp = await _supabase
            .from('shops')
            .select('id, category, categories')
            .eq('seller_id', auth.currentUserId ?? '')
            .limit(1)
            .maybeSingle();
        resp = queryResp;
      }

      if (resp == null) return;

      // Collect all category names associated with this shop
      final shopCatNames = <String>{
        if (resp['category'] != null) resp['category'] as String,
        ...List<String>.from(resp['categories'] ?? []),
      }.where((c) => c.isNotEmpty).toSet();

      // Derive the union of CategoryGroups for this shop
      final shopGroups = shopCatNames.map(AppCategories.groupFor).toSet();

      // 100x ADDITIVE FIX: Filter allowed categories by Admin active status
      final activeNames = AppCategories.names
          .where((name) =>
              PlatformConfigProvider.instance?.isActiveCategory(name) ?? true)
          .toList();

      // Only app-level categories whose group is within the shop's groups are allowed
      // Exception: Supermarkets, Hypermarkets, Supermarts, and Departmental stores can sell anything.
      final isOmnibus = shopCatNames.any(AppCategories.isOmnibusStoreCategory);
      final allowed = isOmnibus
          ? activeNames
          : activeNames
              .where(
                  (name) => shopGroups.contains(AppCategories.groupFor(name)))
              .toList();

      // Primary category to default to (shop's own declared category)
      final primaryCat = resp['category'] ??
          (resp['categories'] != null && (resp['categories'] as List).isNotEmpty
              ? resp['categories'][0]
              : allowed.isNotEmpty
                  ? allowed.first
                  : 'Other');

      setState(() {
        _shopId = resp!['id'];
        _shopPrimaryCategory = primaryCat;
        _allowedCategories = allowed.isNotEmpty ? allowed : activeNames;

        // If editing an existing product whose category is already valid, keep it.
        // Otherwise snap to the shop's primary category.
        if (!_allowedCategories.contains(_productCategory)) {
          _productCategory = _allowedCategories.contains(primaryCat)
              ? primaryCat
              : _allowedCategories.first;
        }
        if (widget.existingProduct == null) {
          _isVeg = AppCategories.isFoodCategory(_productCategory) ? true : null;
        }
      });
      _fetchExistingMenuCategories();
    } catch (e) {
      debugPrint('Shop fetch error: $e');
    }
  }

  /// 100x Shop-Scoped Menu Category Fetcher
  /// Fetches all distinct, non-deleted menu_category values for this particular shop.
  /// Even if only a single product has a distinct menu_category, it is captured and made available.
  Future<void> _fetchExistingMenuCategories() async {
    final targetShopId =
        _shopId ?? widget.existingProduct?.shopId ?? widget.initialShopId;
    if (targetShopId == null || targetShopId.isEmpty) return;

    if (mounted) setState(() => _loadingMenuCategories = true);

    try {
      // RULE: Products table queries MUST ALWAYS include .eq('is_deleted', false)
      final resp = await _supabase
          .from('products')
          .select('menu_category')
          .eq('shop_id', targetShopId)
          .eq('is_deleted', false)
          .not('menu_category', 'is', null);

      final Set<String> seen = {};
      final List<String> categories = [];

      for (final item in resp as List) {
        final raw = item['menu_category']?.toString() ?? '';
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          categories.add(trimmed);
        }
      }

      // Also ensure existing product's current category is included if editing
      if (widget.existingProduct?.menuCategory != null) {
        final current = widget.existingProduct!.menuCategory!.trim();
        if (current.isNotEmpty && seen.add(current.toLowerCase())) {
          categories.add(current);
        }
      }

      // Case-insensitive alphabetical sort
      categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (mounted) {
        setState(() {
          _existingMenuCategories = categories;
          _loadingMenuCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching existing menu categories: $e');
      if (mounted) {
        setState(() => _loadingMenuCategories = false);
      }
    }
  }

  void _showMenuCategoryPickerSheet() {
    if (_existingMenuCategories.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filterQuery = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _existingMenuCategories.where((c) {
              return c.toLowerCase().contains(filterQuery.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Menu Categories',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_existingMenuCategories.length} total',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search categories...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: filterQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setSheetState(() => filterQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setSheetState(() => filterQuery = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.category_outlined,
                                    size: 40, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text(
                                  'No category matching "$filterQuery"',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                            ),
                            itemBuilder: (ctx, idx) {
                              final cat = filtered[idx];
                              final isSelected = _menuCategoryController.text
                                      .trim()
                                      .toLowerCase() ==
                                  cat.toLowerCase();
                              return ListTile(
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: (isSelected
                                            ? AppColors.primary
                                            : Colors.grey[200])!
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.restaurant_menu_rounded,
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.grey[700],
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.primary,
                                        size: 22,
                                      )
                                    : null,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  HapticUtils.selection();
                                  setState(() {
                                    _menuCategoryController.text = cat;
                                    _markDirty();
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMenuCategorySelector() {
    final currentText = _menuCategoryController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _menuCategoryController,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Menu Category is required';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'Menu Category *',
                  hintText: 'e.g. Starters, Main Course, Beverages, Desserts',
                  prefixIcon: const Icon(Icons.restaurant_menu_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingMenuCategories)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else ...[
                        if (currentText.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Clear category',
                            onPressed: () {
                              _menuCategoryController.clear();
                              _markDirty();
                              setState(() {});
                            },
                          ),
                        if (_existingMenuCategories.isNotEmpty)
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.arrow_drop_down_circle_outlined,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            tooltip: 'Select Existing Category',
                            onSelected: (val) {
                              HapticUtils.selection();
                              _menuCategoryController.text = val;
                              _markDirty();
                              setState(() {});
                            },
                            itemBuilder: (ctx) {
                              return _existingMenuCategories.map((cat) {
                                final isSel = currentText.toLowerCase() ==
                                    cat.toLowerCase();
                                return PopupMenuItem<String>(
                                  value: cat,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.restaurant_menu_rounded,
                                        size: 16,
                                        color: isSel
                                            ? AppColors.primary
                                            : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          cat,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSel
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSel
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSel)
                                        const Icon(
                                          Icons.check_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                );
                              }).toList();
                            },
                          ),
                      ],
                    ],
                  ),
                ),
                onChanged: (_) {
                  _markDirty();
                  setState(() {});
                },
              ),
            ),
          ],
        ),

        // Quick-Pick Chips or Empty Hint
        if (_existingMenuCategories.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Existing in this shop:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_existingMenuCategories.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_existingMenuCategories.length > 5)
                GestureDetector(
                  onTap: _showMenuCategoryPickerSheet,
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _existingMenuCategories.map((cat) {
                final isSelected =
                    currentText.toLowerCase() == cat.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.label_outline_rounded,
                      size: 14,
                      color: isSelected ? Colors.white : AppColors.primary,
                    ),
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        color:
                            isSelected ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    backgroundColor: isSelected
                        ? AppColors.primary
                        : const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onPressed: () {
                      HapticUtils.selection();
                      setState(() {
                        if (isSelected) {
                          _menuCategoryController.clear();
                        } else {
                          _menuCategoryController.text = cat;
                        }
                        _markDirty();
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ] else if (!_loadingMenuCategories) ...[
          const SizedBox(height: 6),
          const Text(
            '💡 Type a category name to create your shop\'s first menu category (e.g., Starters, Main Course, Drinks).',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  void _markDirty() {
    if (!_isDirty && mounted) setState(() => _isDirty = true);
  }

  /// Returns true if all current variant names are purely dimensional
  /// (sizes, weights, portions) where separate images are unnecessary.
  bool _areVariantsDimensional() {
    if (_variants.isEmpty) return false;
    final dimensionalPattern = RegExp(
      r'^(XS|S|M|L|XL|XXL|XXXL|'
      r'UK\s*\d+|US\s*\d+|EU\s*\d+|'
      r'\d+\s*(g|kg|ml|L|oz|lb|tabs?|strips?|pieces?|pcs?)|'
      r'Half|Full|Regular|Medium|Large|Small|'
      r'Single|Double|Triple|'
      r'Pack of \d+|'
      r'\d+GB|\d+TB|\d+\s*inch|'
      r'1 Strip.*|1 Tube|1 Dozen|Half Dozen|'
      r'\d+\s*Pound[s]?)$',
      caseSensitive: false,
    );
    return _variants.every((v) => dimensionalPattern.hasMatch(v.name.trim()));
  }

  void _syncLegacyLists() {
    _existingImageUrls = _productImages
        .where((item) => item.isRemote)
        .map((item) => item.remoteUrl!)
        .toList();
    _images = _productImages
        .where((item) => item.isLocal)
        .map((item) => item.localFile!)
        .toList();
  }

  void _removeProductImage(int index) {
    if (index < 0 || index >= _productImages.length) return;
    setState(() {
      _productImages.removeAt(index);
      _syncLegacyLists();
      _isDirty = true;
    });
    HapticUtils.selection();
  }

  void _moveProductImage(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= _productImages.length) return;
    if (toIndex < 0 || toIndex >= _productImages.length) return;
    if (fromIndex == toIndex) return;

    setState(() {
      final item = _productImages.removeAt(fromIndex);
      _productImages.insert(toIndex, item);
      _syncLegacyLists();
      _isDirty = true;
    });
    HapticUtils.selection();
  }

  Future<void> _pickImage() async {
    if (_productImages.length >= 3) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final bool isFashion = AppCategories.isFashionCategory(_productCategory);
    const double maxW = 1080;
    final double maxH = isFashion ? 1440 : 1080;
    final defaultCropRatio = isFashion
        ? const CropAspectRatio(ratioX: 3, ratioY: 4)
        : const CropAspectRatio(ratioX: 1, ratioY: 1);

    if (source == ImageSource.camera) {
      while (_productImages.length < 3) {
        final XFile? picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: maxW,
          maxHeight: maxH,
        );
        if (picked == null) break;
        if (!mounted) return;
        final cropped = await cropImage(context, picked.path,
            title: 'Crop Product Image',
            aspectRatio: defaultCropRatio);
        if (cropped != null) {
          setState(() {
            _productImages.add(ProductImageItem.local(XFile(cropped.path)));
            if (_productImages.length > 3) {
              _productImages = _productImages.sublist(0, 3);
            }
            _syncLegacyLists();
            _isDirty = true;
          });
        }

        if (_productImages.length >= 3) break;

        if (!mounted) break;
        final bool? takeAnother = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Add another?'),
            content: const Text('Would you like to take another photo?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yes')),
            ],
          ),
        );
        if (takeAnother != true) break;
      }
    } else {
      final List<XFile> picked = await picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: maxW,
        maxHeight: maxH,
      );
      if (picked.isNotEmpty) {
        for (var p in picked) {
          if (!mounted) return;
          final cropped = await cropImage(context, p.path,
              title: 'Crop Product Image',
              aspectRatio: defaultCropRatio);
          if (cropped != null) {
            _productImages.add(ProductImageItem.local(XFile(cropped.path)));
          }
          if (_productImages.length >= 3) break;
        }
        setState(() {
          _syncLegacyLists();
          _isDirty = true;
        });
      }
    }
  }

  void _showImagePreview(ImageProvider imageProvider) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: Image(image: imageProvider, fit: BoxFit.contain),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Variant Image Picker (with Camera + Gallery parity) ──────────────────
  Future<File?> _pickVariantImage(BuildContext dialogContext) async {
    final source = await showImageSourceSheet(dialogContext);
    if (source == null) return null;
    final bool isFashion =
        AppCategories.isFashionCategory(_productCategory);
    const double maxW = 1080;
    final double maxH = isFashion ? 1440 : 1080;
    final defaultCropRatio = isFashion
        ? const CropAspectRatio(ratioX: 3, ratioY: 4)
        : const CropAspectRatio(ratioX: 1, ratioY: 1);

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: maxW,
      maxHeight: maxH,
    );
    if (xfile != null) {
      if (!dialogContext.mounted) return null;
      final cropped = await cropImage(dialogContext, xfile.path,
          title: 'Crop Variant Image',
          aspectRatio: defaultCropRatio);
      if (cropped != null) {
        return File(cropped.path);
      }
    }
    return null;
  }

  /// Builds the variant image section widget for add/edit dialogs.
  /// [existingImageUrl] is the network URL of an already-uploaded variant image.
  Widget _buildVariantImageSection(
    BuildContext dialogContext,
    void Function(void Function()) setDialogState, {
    String? existingImageUrl,
    bool isDimensional = false,
  }) {
    final hasLocalFile = _variantImageFiles['temp_dialog'] != null;
    final hasExistingUrl = existingImageUrl != null &&
        existingImageUrl.isNotEmpty &&
        !_removedVariantImageUrls.contains(existingImageUrl);
    final hasImage = hasLocalFile || hasExistingUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Smart guidance based on variant type
        if (isDimensional) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 14, color: Colors.blue),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tip: Size/quantity variants look the same — '
                    'your product gallery photos will be shown.',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (!hasImage)
          ElevatedButton.icon(
            icon: Icon(
              Icons.add_photo_alternate_rounded,
              size: 18,
              color: isDimensional ? const Color(0xFF475569) : AppColors.primary,
            ),
            label: Text(
              isDimensional
                  ? 'Add Variant Image (Usually Not Needed)'
                  : 'Add Variant Image (Optional)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: isDimensional ? const Color(0xFF475569) : AppColors.primary,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDimensional
                  ? const Color(0xFFF1F5F9)
                  : const Color(0xFFEFF6FF),
              foregroundColor: isDimensional
                  ? const Color(0xFF475569)
                  : AppColors.primary,
              side: BorderSide(
                color: isDimensional
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF93C5FD),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () async {
              final file = await _pickVariantImage(dialogContext);
              if (file != null && dialogContext.mounted) {
                setDialogState(() {
                  _variantImageFiles['temp_dialog'] = file;
                });
              }
            },
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasLocalFile
                    ? Image.file(
                        _variantImageFiles['temp_dialog']!,
                        height: 72,
                        width: 72,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        existingImageUrl!,
                        height: 72,
                        width: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 72,
                          width: 72,
                          color: const Color(0xFFEFF6FF),
                          child: const Icon(Icons.broken_image_outlined,
                              color: AppColors.primary),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: Color(0xFF93C5FD), width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Change',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      final file = await _pickVariantImage(dialogContext);
                      if (file != null && dialogContext.mounted) {
                        setDialogState(() {
                          _variantImageFiles['temp_dialog'] = file;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: AppColors.danger),
                    label: const Text('Remove',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger)),
                    onPressed: () {
                      setDialogState(() {
                        _variantImageFiles.remove('temp_dialog');
                        if (existingImageUrl != null &&
                            existingImageUrl.isNotEmpty) {
                          _removedVariantImageUrls.add(existingImageUrl);
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _showAddVariantDialog({String? prefilledName}) async {
    // P2: Max variant limit
    if (_variants.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 20 variants allowed per product.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: prefilledName ?? '');
    final priceCtrl = TextEditingController();
    final originalPriceCtrl = TextEditingController();

    _variantImageFiles.remove('temp_dialog');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Variation',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Name (e.g., Large, Full)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (AppCategories.getSuggestedVariants(_productCategory)
                    .isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Quick Suggestions:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppCategories.getSuggestedVariants(_productCategory)
                        .map((s) {
                      final isSelected =
                          nameCtrl.text.trim().toLowerCase() == s.toLowerCase();
                      return GestureDetector(
                        onTap: () {
                          HapticUtils.selection();
                          setDialogState(() {
                            nameCtrl.text = s;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : const Color(0xFF93C5FD),
                              width: isSelected ? 1.6 : 1.2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 14,
                                color: isSelected ? Colors.white : AppColors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E3A8A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Selling Price (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: originalPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Original Price (MRP) (₹)',
                    hintText: 'Optional',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildVariantImageSection(
                  ctx,
                  setDialogState,
                  isDimensional: _areVariantsDimensional(),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                _variantImageFiles.remove('temp_dialog');
                Navigator.pop(ctx);
              },
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () {
                final n = nameCtrl.text.trim();
                final p = double.tryParse(priceCtrl.text.trim());
                final op = double.tryParse(originalPriceCtrl.text.trim());
                if (n.isNotEmpty && p != null) {
                  if (op != null && op <= p) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('MRP must be greater than Selling Price'),
                      ),
                    );
                    return;
                  }

                  final isDuplicate = _variants
                      .any((v) => v.name.trim().toLowerCase() == n.toLowerCase());
                  if (isDuplicate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('A variant with this name already exists!'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                    return;
                  }

                  final vId = DateTime.now().millisecondsSinceEpoch.toString();
                  setState(() {
                    _variants.add(ProductVariant(
                      id: vId,
                      name: n,
                      price: p,
                      originalPrice: op,
                    ));
                    if (_variantImageFiles['temp_dialog'] != null) {
                      _variantImageFiles[vId] =
                          _variantImageFiles['temp_dialog']!;
                    }
                    _isDirty = true;
                  });
                  _variantImageFiles.remove('temp_dialog');
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add Variation',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── C3: Variant Edit Dialog ─────────────────────────────────────────────
  Future<void> _showEditVariantDialog(int index) async {
    final variant = _variants[index];
    final nameCtrl = TextEditingController(text: variant.name);
    final priceCtrl = TextEditingController(text: variant.price.toString());
    final originalPriceCtrl = TextEditingController(
        text: variant.originalPrice?.toString() ?? '');

    // Set up temp image: if a local file was already picked, use it;
    // otherwise the dialog will show the existing network URL.
    if (_variantImageFiles.containsKey(variant.id)) {
      _variantImageFiles['temp_dialog'] = _variantImageFiles[variant.id]!;
    } else {
      _variantImageFiles.remove('temp_dialog');
    }

    // Determine existing image URL (if not removed)
    final existingUrl = (variant.imageUrl != null &&
            variant.imageUrl!.isNotEmpty &&
            !_removedVariantImageUrls.contains(variant.imageUrl))
        ? variant.imageUrl
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Variation',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Name (e.g., Large, Full)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (AppCategories.getSuggestedVariants(_productCategory)
                    .isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Quick Suggestions:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppCategories.getSuggestedVariants(_productCategory)
                        .map((s) {
                      final isSelected =
                          nameCtrl.text.trim().toLowerCase() == s.toLowerCase();
                      return GestureDetector(
                        onTap: () {
                          HapticUtils.selection();
                          setDialogState(() {
                            nameCtrl.text = s;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : const Color(0xFF93C5FD),
                              width: isSelected ? 1.6 : 1.2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 14,
                                color: isSelected ? Colors.white : AppColors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E3A8A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Selling Price (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: originalPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Original Price (MRP) (₹)',
                    hintText: 'Optional',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildVariantImageSection(
                  ctx,
                  setDialogState,
                  existingImageUrl: existingUrl,
                  isDimensional: _areVariantsDimensional(),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                _variantImageFiles.remove('temp_dialog');
                Navigator.pop(ctx);
              },
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () {
                final n = nameCtrl.text.trim();
                final p = double.tryParse(priceCtrl.text.trim());
                final op = double.tryParse(originalPriceCtrl.text.trim());
                if (n.isNotEmpty && p != null) {
                  if (op != null && op <= p) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('MRP must be greater than Selling Price'),
                      ),
                    );
                    return;
                  }

                  // Check for duplicate names (excluding current variant)
                  final isDuplicate = _variants.asMap().entries.any((e) =>
                      e.key != index &&
                      e.value.name.trim().toLowerCase() == n.toLowerCase());
                  if (isDuplicate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('A variant with this name already exists!'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                    return;
                  }

                  setState(() {
                    // Determine new image URL
                    String? newImageUrl = variant.imageUrl;
                    if (_variantImageFiles['temp_dialog'] != null) {
                      _variantImageFiles[variant.id] =
                          _variantImageFiles['temp_dialog']!;
                    } else if (_removedVariantImageUrls
                        .contains(variant.imageUrl)) {
                      newImageUrl = null;
                      _variantImageFiles.remove(variant.id);
                    }

                    _variants[index] = variant.copyWith(
                      name: n,
                      price: p,
                      originalPrice: op,
                      imageUrl: _removedVariantImageUrls
                              .contains(variant.imageUrl)
                          ? null
                          : newImageUrl,
                    );
                    _isDirty = true;
                  });
                  _variantImageFiles.remove('temp_dialog');
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (_menuCategoryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menu Category is required. Please enter or select a category.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // C1: Require at least 1 product image
    if (_productImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one product image.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (AppCategories.requiresVariant(_productCategory) && _variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please add at least one variant/size for this category.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    double finalPrice = 0.0;
    double? finalOriginalPrice;

    if (_variants.isNotEmpty) {
      final minVariant = _variants
          .reduce((curr, next) => curr.price < next.price ? curr : next);
      finalPrice = minVariant.price;
      finalOriginalPrice = minVariant.originalPrice;
    } else {
      finalPrice = double.tryParse(_priceController.text) ?? 0.0;
      if (_hasDiscount) {
        final originalPrice =
            double.tryParse(_originalPriceController.text) ?? 0.0;
        if (originalPrice <= finalPrice) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Original Price (MRP) must be greater than Selling Price')),
          );
          return;
        }
        finalOriginalPrice = _originalPriceController.text.trim().isNotEmpty
            ? originalPrice
            : null;
      }
    }

    if (_shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No shop found. Create a shop first.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      List<String> uploadedUrls = [];
      const uploadBucket = 'products';

      // 100x Unified Image Upload: Preserves exact drag-and-drop repositioning sequence
      for (int i = 0; i < _productImages.length; i++) {
        final item = _productImages[i];
        if (item.isRemote) {
          uploadedUrls.add(item.remoteUrl!);
        } else if (item.isLocal) {
          final file = item.localFile!;
          final Uint8List bytes =
              await ImageCompressionService.compressFile(File(file.path)) ??
                  await file.readAsBytes();
          const ext = 'jpg'; // Format is jpeg
          final path =
              '$_shopId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
          await _supabase.storage.from(uploadBucket).uploadBinary(path, bytes);
          uploadedUrls
              .add(_supabase.storage.from(uploadBucket).getPublicUrl(path));
        }
      }

      // Upload variant images & handle removed variant images (I6)
      for (var i = 0; i < _variants.length; i++) {
        final variantId = _variants[i].id;
        // Handle explicitly removed variant images
        if (_removedVariantImageUrls.contains(_variants[i].imageUrl)) {
          _variants[i] = _variants[i].copyWith(imageUrl: null);
        }
        if (_variantImageFiles.containsKey(variantId)) {
          final file = _variantImageFiles[variantId]!;
          if (!file.existsSync()) continue;
          try {
            final Uint8List bytes =
                await ImageCompressionService.compressFile(file) ??
                    await file.readAsBytes();
            const ext = 'jpg';
            final filename =
                'variant_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
            final path = '$_shopId/$filename';
            await _supabase.storage
                .from(uploadBucket)
                .uploadBinary(path, bytes);
            final url = _supabase.storage.from(uploadBucket).getPublicUrl(path);
            _variants[i] = _variants[i].copyWith(imageUrl: url);
          } catch (e) {
            // Log or ignore gracefully to prevent product save crash
            debugPrint('Failed to upload variant image: $e');
          }
        }
      }

      final data = {
        'shop_id': _shopId,
        'name': _nameController.text.trim(),
        'price': finalPrice,
        'original_price': finalOriginalPrice,
        'brand': _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        // P3: Save null instead of empty string for description
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'category': _productCategory,
        'menu_category': _menuCategoryController.text.trim(),
        'is_veg': AppCategories.isFoodCategory(_productCategory) ? _isVeg : null,
        'is_available': _isAvailable,
        'weight_per_unit': _weightController.text.trim().isEmpty
            ? null
            : double.tryParse(_weightController.text.trim()),
        'unit_type': _unitType,
        'total_quantity': _inventoryController.text.trim().isEmpty
            ? null
            : int.tryParse(_inventoryController.text.trim()),
        'images': uploadedUrls,
        'requires_prescription': AppCategories.isPharmacyCategory(_productCategory)
            ? _requiresPrescription
            : false,
        'medicine_type': AppCategories.isPharmacyCategory(_productCategory)
            ? _medicineType
            : 'General',
        'variants': _variants.map((v) => v.toMap()).toList(),
        // Product-level GST override (null = use category default)
        'gst_rate_override': _gstRateOverride,
        // Bulk Catering configuration
        'bulk_eligible': _bulkEligible,
        'min_bulk_quantity': _bulkEligible
            ? (int.tryParse(_minBulkQuantityController.text.trim()) ?? 10)
            : 10,
        'bulk_price_tiers': _bulkEligible ? _bulkPriceTiers : [],
        'special_tags': () {
          var tags = widget.existingProduct?.specialTags.toList() ?? [];
          tags.removeWhere((t) => [
                '#Men',
                '#Women',
                '#Boys',
                '#Girls',
                '#Kids',
                '#Unisex'
              ].contains(t));
          if ([
            'Clothing',
            'Footwear',
            'Jewellery',
            'Cosmetics & Beauty',
            'Salon & Beauty'
          ].contains(_productCategory)) {
            tags.add('#$_selectedDemographic');
          }
          return tags;
        }(),
      };

      if (widget.existingProduct == null) {
        await _supabase.from('products').insert(data);
      } else {
        await _supabase
            .from('products')
            .update(data)
            .eq('id', widget.existingProduct!.id)
            .eq('shop_id', widget.existingProduct!.shopId);
      }

      if (!mounted) return;
      // I4: Success feedback before popping
      messenger.showSnackBar(
        SnackBar(
          content: Text(widget.existingProduct != null
              ? 'Product updated successfully!'
              : 'Product added successfully!'),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 2),
        ),
      );
      _isDirty = false; // Prevent PopScope guard on successful save
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── GST Recommendation Helpers ───────────────────────────────────────────

  /// Schedules a debounced GST recommendation refresh (400ms).
  void _scheduleGstUpdate() {
    _gstDebounce?.cancel();
    _gstDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _triggerGstRecommendation();
    });
  }

  /// Runs the engine and updates state with the recommendation.
  Future<void> _triggerGstRecommendation() async {
    if (!mounted) return;
    setState(() => _gstLoading = true);
    await GstRecommendationEngine.instance.ensureLoaded();
    final name = _nameController.text.trim();
    final rec =
        GstRecommendationEngine.instance.recommend(name, _productCategory);
    if (!mounted) return;
    setState(() {
      _gstLoading = false;
      _gstRecommendation = rec;
      // Auto-apply only when the user hasn't manually overridden
      if (!_gstUserOverridden) {
        _gstRateOverride = rec.rate;
      }
    });
  }

  @override
  void dispose() {
    _gstDebounce?.cancel();
    _catalogDebounce?.cancel();
    _nameFocusNode.removeListener(_onNameFocusChanged);
    _nameFocusNode.dispose();
    _nameController.removeListener(_onNameChanged);
    _nameController.removeListener(_scheduleGstUpdate);
    _nameController.removeListener(_markDirty);
    _brandController.removeListener(_markDirty);
    _brandController.dispose();
    _priceController.removeListener(_markDirty);
    _originalPriceController.removeListener(_markDirty);
    _descriptionController.removeListener(_markDirty);
    _menuCategoryController.removeListener(_markDirty);
    _weightController.removeListener(_markDirty);
    _inventoryController.removeListener(_markDirty);
    _minBulkQuantityController.removeListener(_markDirty);
    _nameController.dispose();
    _priceController.dispose();
    _originalPriceController.dispose();
    _descriptionController.dispose();
    _menuCategoryController.dispose();
    _weightController.dispose();
    _inventoryController.dispose();
    _minBulkQuantityController.dispose();
    super.dispose();
  }

  // ── 100x Master Catalog Autocomplete & 1-Tap Autofill ──────────────────────

  void _onNameChanged() {
    _markDirty();
    // Do not trigger catalog dropdown while in edit mode unless user cleared and re-typed
    if (widget.existingProduct != null &&
        _nameController.text.trim() == widget.existingProduct!.name.trim()) {
      return;
    }

    final query = _nameController.text.trim();
    if (query.length < 2) {
      _catalogDebounce?.cancel();
      if (_catalogSuggestions.isNotEmpty || _showCatalogSuggestions) {
        setState(() {
          _catalogSuggestions = [];
          _showCatalogSuggestions = false;
          _isSearchingCatalog = false;
        });
      }
      return;
    }

    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 350), () {
      _triggerCatalogSearch(query: query);
    });
  }

  void _onNameFocusChanged() {
    if (!_nameFocusNode.hasFocus) {
      // Small delay allows tap on suggestion button to register before hiding
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && !_nameFocusNode.hasFocus) {
          setState(() => _showCatalogSuggestions = false);
        }
      });
    }
  }

  Future<void> _triggerCatalogSearch({String? query, bool force = false}) async {
    final cleanQuery = (query ?? _nameController.text).trim();
    if (cleanQuery.length < 2 && !force) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type at least 2 letters of product name to search catalog.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final seq = ++_catalogSearchSeq;
    if (mounted) {
      setState(() {
        _isSearchingCatalog = true;
        _showCatalogSuggestions = true;
      });
    }

    try {
      final results = await MasterCatalogService.instance.searchCatalog(
        query: cleanQuery,
        shopCategory: _productCategory,
        limit: 10,
      );

      if (!mounted || seq != _catalogSearchSeq) return;

      setState(() {
        _catalogSuggestions = results;
        _isSearchingCatalog = false;
        _showCatalogSuggestions = results.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Catalog search error: $e');
      if (mounted && seq == _catalogSearchSeq) {
        setState(() => _isSearchingCatalog = false);
      }
    }
  }

  void _autofillFromCatalog(ProductModel template) {
    HapticUtils.selection();

    // 1. Capture snapshot for Undo capability
    _lastAutofillSnapshot = {
      'name': _nameController.text,
      'brand': _brandController.text,
      'description': _descriptionController.text,
      'price': _priceController.text,
      'originalPrice': _originalPriceController.text,
      'hasDiscount': _hasDiscount,
      'category': _productCategory,
      'menuCategory': _menuCategoryController.text,
      'weight': _weightController.text,
      'unitType': _unitType,
      'inventory': _inventoryController.text,
      'isVeg': _isVeg,
      'requiresPrescription': _requiresPrescription,
      'medicineType': _medicineType,
      'productImages': List<ProductImageItem>.from(_productImages),
      'images': List<String>.from(_existingImageUrls),
      'localImages': List<XFile>.from(_images),
      'variants': _variants.map((v) => v.copyWith()).toList(),
      'gstRateOverride': _gstRateOverride,
    };

    setState(() {
      // 2. Name & Brand
      _nameController.text = template.name;
      if (template.brand != null && template.brand!.trim().isNotEmpty) {
        _brandController.text = template.brand!.trim();
      }

      // 3. Description (Chemical salts/composition for medicines)
      if (template.description != null && template.description!.trim().isNotEmpty) {
        _descriptionController.text = template.description!.trim();
      }

      // 4. Price & MRP
      if (template.price > 0) {
        _priceController.text = template.price.truncateToDouble() == template.price
            ? template.price.toInt().toString()
            : template.price.toStringAsFixed(2);
      }
      if (template.originalPrice != null && template.originalPrice! > template.price) {
        _hasDiscount = true;
        _originalPriceController.text =
            template.originalPrice!.truncateToDouble() == template.originalPrice!
                ? template.originalPrice!.toInt().toString()
                : template.originalPrice!.toStringAsFixed(2);
      } else {
        _hasDiscount = false;
        _originalPriceController.clear();
      }

      // 5. Category Alignment
      if (_allowedCategories.contains(template.category)) {
        _productCategory = template.category;
      } else if (_allowedCategories.isNotEmpty) {
        final matching = _allowedCategories.firstWhere(
          (c) => c.toLowerCase() == template.category.toLowerCase(),
          orElse: () => _allowedCategories.first,
        );
        _productCategory = matching;
      }

      // 6. Menu Category
      if (template.menuCategory != null && template.menuCategory!.trim().isNotEmpty) {
        final menuCat = template.menuCategory!.trim();
        _menuCategoryController.text = menuCat;
        if (!_existingMenuCategories.any((c) => c.toLowerCase() == menuCat.toLowerCase())) {
          _existingMenuCategories.insert(0, menuCat);
        }
      }

      // 7. Unit Type & Weight
      final normalizedUnit = (template.unitType.toLowerCase() == 'piece' || template.unitType.isEmpty)
          ? 'pieces'
          : template.unitType.toLowerCase();
      _unitType = _availableUnitTypes.contains(normalizedUnit)
          ? normalizedUnit
          : _availableUnitTypes.first;

      if (template.weightPerUnit != null && template.weightPerUnit! > 0) {
        _weightController.text = template.weightPerUnit! % 1 == 0
            ? template.weightPerUnit!.toInt().toString()
            : template.weightPerUnit!.toString();
      }

      // 8. Inventory Stock
      if (template.totalQuantity != null && template.totalQuantity! > 0) {
        _inventoryController.text = template.totalQuantity.toString();
      } else if (_inventoryController.text.trim().isEmpty) {
        _inventoryController.text = '50';
      }

      // 9. Dietary & Regulations
      if (template.isVeg != null) {
        _isVeg = template.isVeg;
      }
      _requiresPrescription = template.requiresPrescription;
      if (template.medicineType.isNotEmpty) {
        _medicineType = template.medicineType;
      }

      // 10. Images (Inherit CDN URLs directly, clear local picker queue)
      final validCdnUrls = template.images
          .where((url) => url.startsWith('http://') || url.startsWith('https://'))
          .toList();
      if (validCdnUrls.isNotEmpty) {
        _productImages = validCdnUrls
            .map((url) => ProductImageItem.remote(url))
            .toList();
        _syncLegacyLists();
      }

      // 11. Variants (Deep clone with clean IDs)
      if (template.variants.isNotEmpty) {
        _variants = template.variants.map((v) {
          final uniqueId =
              'variant_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
          return v.copyWith(id: uniqueId);
        }).toList();
      }

      // 12. GST Recommendation & Rate Override
      if (template.gstRateOverride != null) {
        _gstRateOverride = template.gstRateOverride;
        _gstUserOverridden = true;
      }

      // 13. UI Flags
      _showCatalogSuggestions = false;
      _autofilledFromProductName = template.name;
      _isDirty = true;
    });

    _scheduleGstUpdate();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Autofilled from catalog: ${template.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Colors.amberAccent,
          onPressed: _undoAutofill,
        ),
      ),
    );
  }

  void _undoAutofill() {
    if (_lastAutofillSnapshot == null) return;
    final snap = _lastAutofillSnapshot!;
    setState(() {
      _nameController.text = snap['name'] as String? ?? '';
      _brandController.text = snap['brand'] as String? ?? '';
      _descriptionController.text = snap['description'] as String? ?? '';
      _priceController.text = snap['price'] as String? ?? '';
      _originalPriceController.text = snap['originalPrice'] as String? ?? '';
      _hasDiscount = snap['hasDiscount'] as bool? ?? false;
      _productCategory = snap['category'] as String? ?? _productCategory;
      _menuCategoryController.text = snap['menuCategory'] as String? ?? '';
      _weightController.text = snap['weight'] as String? ?? '';
      _unitType = snap['unitType'] as String? ?? 'pieces';
      _inventoryController.text = snap['inventory'] as String? ?? '';
      _isVeg = snap['isVeg'] as bool?;
      _requiresPrescription = snap['requiresPrescription'] as bool? ?? false;
      _medicineType = snap['medicineType'] as String? ?? 'General';
      _existingImageUrls = List<String>.from(snap['images'] as List? ?? []);
      _images = List<XFile>.from(snap['localImages'] as List? ?? []);
      if (snap['productImages'] is List) {
        _productImages =
            List<ProductImageItem>.from(snap['productImages'] as List);
      } else {
        _productImages = [
          ..._existingImageUrls.map((url) => ProductImageItem.remote(url)),
          ..._images.map((f) => ProductImageItem.local(f)),
        ];
      }
      _syncLegacyLists();
      _variants = List<ProductVariant>.from(snap['variants'] as List? ?? []);
      _gstRateOverride = snap['gstRateOverride'] as double?;
      _autofilledFromProductName = null;
    });
    _lastAutofillSnapshot = null;
    HapticUtils.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Autofill reverted.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildCatalogSuggestionsDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Master Catalog Match ⚡',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Select an item to autofill details, salts & photos in 1-tap',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showCatalogSuggestions = false),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
          ),

          // Suggestion list
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _catalogSuggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.8,
                color: Colors.grey.withValues(alpha: 0.15),
              ),
              itemBuilder: (context, index) {
                final item = _catalogSuggestions[index];
                final isMedicine = item.category == 'Pharmacy' ||
                    item.category == 'Medical Store' ||
                    AppCategories.isPharmacyCategory(item.category);
                final hasSalt = isMedicine &&
                    item.description != null &&
                    item.description!.trim().isNotEmpty;
                final hasDiscount = item.originalPrice != null &&
                    item.originalPrice! > item.price;

                return InkWell(
                  onTap: () => _autofillFromCatalog(item),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey.shade100,
                            child: item.images.isNotEmpty
                                ? Image.network(
                                    item.images.first,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  )
                                : Icon(
                                    isMedicine
                                        ? Icons.medication_outlined
                                        : Icons.shopping_bag_outlined,
                                    size: 24,
                                    color: AppColors.primary,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (hasSalt) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '🧪 ${item.description!.trim()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF059669),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ] else if (item.brand != null &&
                                  item.brand!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '🏷️ ${item.brand!.trim()} • ${item.category}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.category,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    '₹${item.price.toStringAsFixed(item.price.truncateToDouble() == item.price ? 0 : 2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  if (hasDiscount) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      'MRP ₹${item.originalPrice!.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.grey.shade500,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                  if (item.images.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.photo_library_outlined,
                                              size: 10, color: Colors.blue),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${item.images.length}',
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Action button
                        FilledButton.icon(
                          onPressed: () => _autofillFromCatalog(item),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.bolt_rounded, size: 13),
                          label: const Text(
                            'Autofill',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutofillSuccessBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF059669).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF059669), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Autofilled from Master Catalog! ✨',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
                Text(
                  _autofilledFromProductName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _undoAutofill,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.undo_rounded, size: 14, color: AppColors.danger),
            label: const Text(
              'Undo',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GST Card Widget ───────────────────────────────────────────────────────

  Widget _buildGstCard() {
    final rec = _gstRecommendation;
    final currentRate = _gstRateOverride;
    final isSlabCat =
        _productCategory == 'Clothing' || _productCategory == 'Footwear';

    // Color coding by rate
    Color rateColor(double r) {
      if (r == 0.00) return const Color(0xFF00C853); // green — exempt
      if (r == 0.0025) return const Color(0xFF00BCD4); // cyan — rough diamonds
      if (r == 0.015) return const Color(0xFF009688); // teal — cut gems
      if (r == 0.03) return const Color(0xFF9C27B0); // purple — gold/jewellery
      if (r == 0.05) return const Color(0xFF2196F3); // blue — concessional / food
      if (r == 0.12) return const Color(0xFF3F51B5); // indigo — legacy / processed
      if (r == 0.18) return const Color(0xFFFF9800); // orange — standard
      if (r == 0.28) return const Color(0xFFFF5722); // deep orange — luxury / peak
      if (r >= 0.40) return const Color(0xFFF44336); // red — sin / tobacco
      return const Color(0xFF607D8B);
    }

    // Human-readable slab label (supports 0.25%, 1.5%, etc.)
    String rateLabel(double r) {
      if (r == 0.0025) return '0.25%';
      if (r == 0.015) return '1.5%';
      return '${(r * 100).toStringAsFixed(0)}%';
    }

    final alternatives = rec?.alternatives ?? [0.00, 0.05, 0.18, 0.40];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: currentRate != null
              ? rateColor(currentRate).withValues(alpha: 0.4)
              : AppColors.border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: currentRate != null
                ? rateColor(currentRate).withValues(alpha: 0.06)
                : Colors.transparent,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Color(0xFF7C4DFF), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GST Rate',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      Text(
                        'Goods & Services Tax — applied on top of your price',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                if (_gstLoading)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),

            const SizedBox(height: 14),

            // ── Recommendation Chip ───────────────────────────────────────
            if (rec != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 14, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rec.reason,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7C4DFF),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Slab selector ─────────────────────────────────────────────
            if (isSlabCat) ...[
              // Clothing/Footwear: show price-based slab note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        TaxConfig.slabDescription(_productCategory) ??
                            '5% for ≤₹2,500 | 18% for >₹2,500',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.amber,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Rate buttons ──────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: alternatives.map((rate) {
                final isSelected = currentRate == rate;
                final color = rateColor(rate);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _gstRateOverride = rate;
                      _gstUserOverridden = true;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : AppColors.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : AppColors.border,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(Icons.check_circle_rounded,
                              size: 14, color: color),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          rateLabel(rate),
                          style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 15,
                              color:
                                  isSelected ? color : AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            if (currentRate != null) ...[
              const SizedBox(height: 12),
              // Summary line: "Customer pays ₹XXX + 5% GST"
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: rateColor(currentRate).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_rounded,
                        size: 13, color: rateColor(currentRate)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Customer pays: Base Price + ${rateLabel(currentRate)} GST',
                        style: TextStyle(
                            fontSize: 11,
                            color: rateColor(currentRate),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Reset to category default ─────────────────────────────────
            if (_gstUserOverridden) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _gstUserOverridden = false;
                    final rec2 = _gstRecommendation;
                    if (rec2 != null) _gstRateOverride = rec2.rate;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt_rounded,
                        size: 13,
                        color: AppColors.textSecondary.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Reset to recommended',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                          decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Live Seller Earnings & Payout Breakdown Card ───────────────────────────
  Widget _buildEarningsPreviewCard() {
    final config = context.watch<PlatformConfigProvider>();
    final enteredPrice = double.tryParse(_priceController.text) ??
        (_variants.isNotEmpty
            ? _variants.map((v) => v.price).reduce(min)
            : 0.0);

    final isOmnibus = AppCategories.isOmnibusStoreCategory(_shopPrimaryCategory);
    final commPercent = config.getCommissionPercentForCategory(_productCategory, fallbackCategory: _shopPrimaryCategory);
    final gstRate = _gstRateOverride ?? TaxConfig.gstRateForCategory(_productCategory, itemPrice: enteredPrice);
    final isFood = TaxConfig.isEnythingDeemedSupplier(_productCategory);
    final isExempt = _productCategory == 'Fruits & Vegs' ||
        _productCategory == 'Butcher' ||
        _productCategory == 'Fish & Seafood' ||
        gstRate == 0.0;

    final customerGstAmount = enteredPrice * gstRate;
    final totalCustomerPrice = enteredPrice + customerGstAmount;
    final commAmount = enteredPrice * (commPercent / 100.0);
    final gwAmount = enteredPrice * TaxConfig.effectiveGatewayDeductionPercent;
    final tdsAmount = enteredPrice * TaxConfig.itTdsRate;
    final tcsAmount = isFood || isExempt
        ? 0.0
        : enteredPrice * TaxConfig.tcsRateForCategory(_productCategory);
    final totalDeductions = commAmount + gwAmount + tdsAmount + tcsAmount;
    final netBasePayout = enteredPrice - totalDeductions;
    // Section 9(5) Food: Enything remits directly. Non-food: GST passed through to seller bank.
    final gstPassthroughAmount = isFood ? 0.0 : customerGstAmount;
    final netBankDeposit = netBasePayout + gstPassthroughAmount;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2B8A3E).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B8A3E).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B8A3E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Color(0xFF2B8A3E), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seller Earnings & Payout Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Live payout calculation for $_productCategory',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8590C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${commPercent.toStringAsFixed(1)}% Comm',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8590C),
                    ),
                  ),
                ),
              ],
            ),
            if (isOmnibus &&
                _shopPrimaryCategory != null &&
                _shopPrimaryCategory != _productCategory) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF4C6EF5).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4C6EF5).withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('🏬', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Department Rate: As a $_shopPrimaryCategory, this item applies the ${commPercent.toStringAsFixed(1)}% $_productCategory commission upon sale.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1A2E9E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _earningsRow('Base Selling Price', '₹${enteredPrice.toStringAsFixed(2)}', isBold: true),
            _earningsRow(
              'Customer Add-on GST (${(gstRate * 100).toStringAsFixed(0)}%)',
              '+₹${customerGstAmount.toStringAsFixed(2)}',
              color: const Color(0xFF4C6EF5),
            ),
            _earningsRow(
              'Total Paid by Customer',
              '₹${totalCustomerPrice.toStringAsFixed(2)}',
              isSubdued: true,
            ),
            const Divider(height: 14, thickness: 0.6),
            _earningsRow(
              'Platform Commission (${commPercent.toStringAsFixed(1)}%)',
              '-₹${commAmount.toStringAsFixed(2)}',
              color: const Color(0xFFFA5252),
            ),
            _earningsRow(
              'Online Gateway Share (2.36%)',
              '-₹${gwAmount.toStringAsFixed(2)}',
              color: const Color(0xFFFA5252),
            ),
            _earningsRow(
              'Income Tax TDS §194-O (0.10%)',
              '-₹${tdsAmount.toStringAsFixed(2)}',
              color: const Color(0xFFFA5252),
            ),
            _earningsRow(
              'GST TCS §52 (${isFood || isExempt ? '0%' : '0.50%'})',
              isFood || isExempt ? '₹0.00 (Exempt)' : '-₹${tcsAmount.toStringAsFixed(2)}',
              color: isFood || isExempt ? null : const Color(0xFFFA5252),
            ),
            if (!isFood && gstPassthroughAmount > 0) ...[
              _earningsRow(
                'GST Passthrough to Your Bank',
                '+₹${gstPassthroughAmount.toStringAsFixed(2)}',
                color: const Color(0xFF2B8A3E),
              ),
            ],
            const Divider(height: 16, thickness: 1.2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2B8A3E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF2B8A3E).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated Net Bank Payout:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B8A3E),
                        ),
                      ),
                      Text(
                        '₹${netBankDeposit.toStringAsFixed(2)} / unit',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2B8A3E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFood
                        ? '• Food order: Enything remits 5% GST directly to Govt under Section 9(5).'
                        : (isExempt
                            ? '• Fresh produce: 0% GST and exempt from TCS.'
                            : '• Non-food item: GST collected from customer is deposited into your bank for monthly GSTR-3B filing.'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      height: 1.3,
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

  Widget _earningsRow(String label, String value,
      {bool isBold = false, bool isSubdued = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: isSubdued
                    ? AppColors.textSecondary.withValues(alpha: 0.8)
                    : AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: color ??
                  (isSubdued ? AppColors.textSecondary : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bulk Catering & Event Pricing Card (Custom quotes used instead) ─────────
  Widget _buildBulkCateringCard() => const SizedBox.shrink();

  Widget _buildReorderableImageCard(int index) {
    final item = _productImages[index];
    final isCover = index == 0;

    ImageProvider provider;
    if (item.isRemote) {
      provider = NetworkImage(item.remoteUrl!);
    } else {
      provider = FileImage(File(item.localFile!.path));
    }

    return Container(
      key: ValueKey(item.id),
      width: 120,
      height: 120,
      margin: const EdgeInsets.only(right: 12, top: 4, bottom: 16),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Stack(
          children: [
            // Thumbnail container
            GestureDetector(
              onTap: () => _showImagePreview(provider),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCover
                        ? const Color(0xFF059669)
                        : Colors.black.withValues(alpha: 0.12),
                    width: isCover ? 2.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isCover
                          ? const Color(0xFF059669).withValues(alpha: 0.20)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: isCover ? 8 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  image: DecorationImage(
                    image: provider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

            // Top Left: Cover badge or 1-tap "Make Cover"
            Positioned(
              top: 6,
              left: 6,
              child: isCover
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded,
                              size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'Cover',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _moveProductImage(index, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_border_rounded,
                                size: 12, color: Colors.amber),
                            SizedBox(width: 3),
                            Text(
                              'Make Cover',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Top Right: Remove button
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _removeProductImage(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
            ),

            // Bottom Bar: Reorder quick controls & Drag Handle
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Swap Arrows
                  if (_productImages.length > 1)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index > 0)
                          GestureDetector(
                            onTap: () =>
                                _moveProductImage(index, index - 1),
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 10,
                                  color: Colors.white),
                            ),
                          ),
                        if (index < _productImages.length - 1)
                          GestureDetector(
                            onTap: () =>
                                _moveProductImage(index, index + 1),
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 10,
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),

                  // Immediate Drag Handle with Position Pill (#1, #2, #3)
                  ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_indicator_rounded,
                              size: 12, color: Colors.white70),
                          const SizedBox(width: 1.5),
                          Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    final int totalImageCount = _productImages.length;

    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard Changes?'),
            content: const Text(
                'You have unsaved changes. Are you sure you want to go back?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep Editing')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard',
                      style: TextStyle(color: AppColors.danger))),
            ],
          ),
        );
        if (shouldLeave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: Text(
                widget.existingProduct != null ? 'Edit Product' : 'Add Product')),
        body: MaxWidthContainer(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Image Section Header ─────────────────────────────────────
                  if (totalImageCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.photo_library_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            _variants.isNotEmpty
                                ? 'Product Gallery'
                                : 'Product Photos',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary),
                          ),
                          const Spacer(),
                          // I1: Image count indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: totalImageCount >= 3
                                  ? const Color(0xFF00C853)
                                      .withValues(alpha: 0.1)
                                  : AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$totalImageCount of 3',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: totalImageCount >= 3
                                    ? const Color(0xFF00C853)
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Context-aware helper when variants exist
                  if (totalImageCount > 0 && _variants.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Default photos shown for all variants. Add variant-specific '
                        'images only for visually different variants (e.g., colors).',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  // Image Picker
                  if (_productImages.isEmpty)
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: double.infinity,
                        height: 180,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: const Color(0xFF93C5FD),
                              width: 1.8,
                              style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFFBFDBFE), width: 1.5),
                              ),
                              child: const Icon(
                                Icons.add_a_photo_rounded,
                                size: 36,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _variants.isNotEmpty
                                  ? 'Tap to add your product gallery\n'
                                    'These photos are shown for all variants'
                                  : 'Tap to add up to 3 product photos\n'
                                    'Recommended: 1:1 (Square)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF1E3A8A),
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Poppins',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_productImages.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.swap_horiz_rounded,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Hold & drag to reorder photos · 1st photo is the primary cover',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 140,
                        child: ReorderableListView(
                          scrollDirection: Axis.horizontal,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) {
                                final double animValue = Curves.easeInOut
                                    .transform(animation.value);
                                final double elevation =
                                    lerpDouble(0, 10, animValue)!;
                                final double scale =
                                    lerpDouble(1.0, 1.05, animValue)!;
                                return Transform.scale(
                                  scale: scale,
                                  child: Material(
                                    elevation: elevation,
                                    color: Colors.transparent,
                                    shadowColor: AppColors.primary
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(14),
                                    child: child,
                                  ),
                                );
                              },
                              child: child,
                            );
                          },
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              final item = _productImages.removeAt(oldIndex);
                              _productImages.insert(newIndex, item);
                              _syncLegacyLists();
                              _isDirty = true;
                            });
                            HapticUtils.selection();
                          },
                          footer: _productImages.length < 3
                              ? Container(
                                  key: const ValueKey('add_photo_footer'),
                                  child: GestureDetector(
                                    onTap: _pickImage,
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      margin: const EdgeInsets.only(
                                          right: 12, top: 4, bottom: 16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFF93C5FD),
                                          width: 1.8,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                              Icons
                                                  .add_photo_alternate_rounded,
                                              size: 32,
                                              color: AppColors.primary),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Add Photo\n(${_productImages.length}/3)',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                          children: [
                            for (int i = 0; i < _productImages.length; i++)
                              _buildReorderableImageCard(i),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),

                _card(
                  children: [
                    Builder(
                      builder: (context) {
                        final isPharmacy = _productCategory == 'Pharmacy' ||
                            AppCategories.isPharmacyCategory(_productCategory);
                        final isGrocery = _productCategory == 'Grocery' ||
                            _productCategory == 'Supermarket' ||
                            _productCategory == 'Hypermarket' ||
                            _productCategory == 'Supermarket / Hypermarket';
                        final isCosmetics = _productCategory == 'Cosmetics & Beauty' ||
                            _productCategory == 'Salon & Beauty';
                        final isFashion = _productCategory == 'Clothing' ||
                            _productCategory == 'Footwear' ||
                            _productCategory == 'Jewellery';
                        final isElectronics = _productCategory == 'Electronics' ||
                            _productCategory == 'Mobile & Repair';

                        final String hintText;
                        final IconData prefixIcon;
                        if (isPharmacy) {
                          hintText = 'e.g., Dolo 650, Rosuvas 20, Augmentin';
                          prefixIcon = Icons.medication_liquid_outlined;
                        } else if (isGrocery) {
                          hintText = 'e.g., Fortune Sunflower Oil 1L, Tata Salt';
                          prefixIcon = Icons.local_grocery_store_outlined;
                        } else if (isCosmetics) {
                          hintText = 'e.g., Nivea Soft Moisturizer, Lakme Lipstick';
                          prefixIcon = Icons.face_retouching_natural_outlined;
                        } else if (isFashion) {
                          hintText = 'e.g., Cotton Slim Fit Shirt, Running Shoes';
                          prefixIcon = Icons.checkroom_outlined;
                        } else if (isElectronics) {
                          hintText = 'e.g., Fast USB-C Charger, Wireless Earbuds';
                          prefixIcon = Icons.devices_other_outlined;
                        } else if (AppCategories.isFoodCategory(_productCategory)) {
                          hintText = 'e.g., Chicken Biryani, Chocolate Cake';
                          prefixIcon = Icons.fastfood_outlined;
                        } else {
                          hintText = 'e.g., Product Name / Model';
                          prefixIcon = Icons.shopping_bag_outlined;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              maxLength: 150,
                              validator: (v) =>
                                  AppValidators.required(v, field: 'Product name'),
                              decoration: InputDecoration(
                                labelText: 'Product Name',
                                hintText: hintText,
                                prefixIcon: Icon(prefixIcon),
                                suffixIcon: _isSearchingCatalog
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                                AppColors.primary),
                                          ),
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.auto_awesome_rounded,
                                              color: _nameController.text.trim().length >= 2
                                                  ? AppColors.primary
                                                  : Colors.grey.shade400,
                                              size: 20,
                                            ),
                                            tooltip: 'Search platform catalog & autofill',
                                            onPressed: () {
                                              _triggerCatalogSearch(
                                                  query: _nameController.text,
                                                  force: true);
                                            },
                                          ),
                                          if (_nameController.text.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.clear_rounded,
                                                  size: 18),
                                              tooltip: 'Clear',
                                              onPressed: () {
                                                _nameController.clear();
                                                setState(() {
                                                  _catalogSuggestions = [];
                                                  _showCatalogSuggestions = false;
                                                });
                                              },
                                            ),
                                        ],
                                      ),
                              ),
                            ),
                            if (_autofilledFromProductName != null)
                              _buildAutofillSuccessBanner(),
                            if (_showCatalogSuggestions && _catalogSuggestions.isNotEmpty)
                              _buildCatalogSuggestionsDropdown(),
                          ],
                        );
                      },
                    ),
                    if (_variants.isEmpty &&
                        !AppCategories.requiresVariant(_productCategory)) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        validator: AppValidators.price,
                        decoration: const InputDecoration(
                          labelText: 'Price (₹) *',
                          hintText: '199',
                          prefixIcon: Icon(Icons.currency_rupee),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Add Discount',
                            style: TextStyle(fontFamily: 'Poppins')),
                        subtitle: const Text(
                            'Show Original Price (MRP) slashed out',
                            style: TextStyle(fontSize: 12)),
                        value: _hasDiscount,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) => setState(() {
                          _hasDiscount = v;
                          _isDirty = true;
                        }),
                      ),
                      if (_hasDiscount) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _originalPriceController,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (!_hasDiscount) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter original price';
                            }
                            final op = double.tryParse(v);
                            final p = double.tryParse(_priceController.text);
                            if (op == null) return 'Invalid price';
                            if (p != null && op <= p) {
                              return 'MRP must be > Selling Price';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Original Price (MRP) (₹)',
                            hintText: '299',
                            prefixIcon: Icon(Icons.local_offer_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ] else if (_variants.isNotEmpty) ...[
                      // I2: Price-from-variants indicator
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 14, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Price auto-set from lowest variant: '
                                '₹${_variants.map((v) => v.price).reduce(min).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _brandController,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Brand / Manufacturer (Optional)',
                        hintText: 'e.g., Sun Pharma, Cipla, Amul, Nestlé',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final isPharmacy = _productCategory == 'Pharmacy' ||
                            AppCategories.isPharmacyCategory(_productCategory);
                        return TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          maxLength: 1000,
                          decoration: InputDecoration(
                            labelText: isPharmacy
                                ? 'Composition / Salts (Description)'
                                : 'Description (Optional)',
                            hintText: isPharmacy
                                ? 'Enter active salts & composition (e.g. Paracetamol 650mg, Rosuvastatin 20mg)...'
                                : 'Describe your product...',
                            helperText: isPharmacy
                                ? 'Customers can search medicines directly by salt/composition'
                                : null,
                            prefixIcon: Icon(isPharmacy
                                ? Icons.medication_outlined
                                : Icons.description_outlined),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _card(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  AppCategories.requiresVariant(
                                          _productCategory)
                                      ? 'Variations (Required)'
                                      : 'Variations (Optional)',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16)),
                              const Text('e.g., Small, Medium, Large',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAddVariantDialog(),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Variation'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (AppCategories.getSuggestedVariants(_productCategory)
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text(
                              'Quick Add:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ...AppCategories.getSuggestedVariants(
                                    _productCategory)
                                .map((s) {
                              final isAlreadyAdded = _variants.any((v) =>
                                  v.name.trim().toLowerCase() ==
                                  s.toLowerCase());
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: Icon(
                                    isAlreadyAdded
                                        ? Icons.check_circle_rounded
                                        : Icons.add_circle_outline_rounded,
                                    size: 14,
                                    color: isAlreadyAdded
                                        ? Colors.white
                                        : AppColors.primary,
                                  ),
                                  label: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isAlreadyAdded
                                          ? Colors.white
                                          : const Color(0xFF1E3A8A),
                                    ),
                                  ),
                                  backgroundColor: isAlreadyAdded
                                      ? AppColors.primary
                                      : const Color(0xFFEFF6FF),
                                  side: BorderSide(
                                    color: isAlreadyAdded
                                        ? AppColors.primary
                                        : const Color(0xFF93C5FD),
                                    width: 1.2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  onPressed: () {
                                    HapticUtils.selection();
                                    _showAddVariantDialog(prefilledName: s);
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    if (_variants.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ..._variants.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final v = entry.value;
                        final bool hasLocalImg =
                            _variantImageFiles.containsKey(v.id);
                        final bool hasNetworkImg = v.imageUrl != null &&
                            v.imageUrl!.isNotEmpty &&
                            !_removedVariantImageUrls.contains(v.imageUrl);
                        final bool hasAnyImg = hasLocalImg || hasNetworkImg;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFFE2E8F0), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              hasAnyImg
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: hasLocalImg
                                          ? Image.file(
                                              _variantImageFiles[v.id]!,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.network(
                                              v.imageUrl!,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                width: 44,
                                                height: 44,
                                                color: const Color(0xFFEFF6FF),
                                                child: const Icon(
                                                    Icons
                                                        .broken_image_outlined,
                                                    size: 18,
                                                    color: AppColors.primary),
                                              ),
                                            ),
                                    )
                                  : Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFFBFDBFE)),
                                      ),
                                      child: const Icon(
                                          Icons.label_important_outline_rounded,
                                          size: 20,
                                          color: AppColors.primary),
                                    ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _showEditVariantDialog(idx),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        v.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            '₹${v.price}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (v.originalPrice != null &&
                                              v.originalPrice! > v.price) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '₹${v.originalPrice}',
                                              style: const TextStyle(
                                                decoration: TextDecoration
                                                    .lineThrough,
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20, color: AppColors.primary),
                                onPressed: () => _showEditVariantDialog(idx),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20, color: AppColors.danger),
                                onPressed: () => setState(() {
                                  final variantId = _variants[idx].id;
                                  _variants.removeAt(idx);
                                  _variantImageFiles.remove(variantId);
                                  _isDirty = true;
                                }),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  children: [
                    // BUG-FIX: Category is locked to the shop's group.
                    // If the shop only belongs to one group (e.g. Restaurant → food),
                    // the field is read-only. If multi-group (rare), a constrained
                    // dropdown is shown — but never all 31 global categories.
                    if (_allowedCategories.length == 1)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Product Category',
                          prefixIcon: Icon(Icons.lock_outline),
                          helperText: 'Determined by your shop type',
                        ),
                        child: Text(
                          '${AppCategories.all.firstWhere((c) => c['name'] == _productCategory, orElse: () => {
                                'emoji': '🏪'
                              })['emoji']}  $_productCategory',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            _allowedCategories.contains(_productCategory)
                                ? _productCategory
                                : _allowedCategories.first,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Product Category',
                          prefixIcon: const Icon(Icons.category_outlined),
                          helperText: AppCategories.isOmnibusStoreCategory(_shopPrimaryCategory)
                              ? 'Omnibus store: Select any product department (Cosmetics, Grocery, etc.)'
                              : 'Limited to your shop\'s category group',
                        ),
                        items: _allowedCategories.map((cat) {
                          final emoji = AppCategories.all.firstWhere(
                              (c) => c['name'] == cat,
                              orElse: () => {'emoji': '🏪'})['emoji'];
                          return DropdownMenuItem(
                            value: cat,
                            child: Text('$emoji  $cat'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _productCategory = v;
                              if (!AppCategories.isFoodCategory(v)) {
                                _isVeg = null;
                              } else {
                                _isVeg ??= true;
                              }
                              if (!_availableUnitTypes.contains(_unitType)) {
                                _unitType = _availableUnitTypes.first;
                              }
                              // Reset user override when category changes
                              // so the engine can auto-apply the new category rate
                              if (!_gstUserOverridden) {
                                _gstRateOverride = null;
                              }
                              _isDirty = true;
                            });
                            // Re-run GST recommendation for the new category
                            _triggerGstRecommendation();
                          }
                        },
                      ),

                    if ([
                      'Clothing',
                      'Footwear',
                      'Jewellery',
                      'Cosmetics & Beauty',
                      'Salon & Beauty'
                    ].contains(_productCategory)) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Target Demographic',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            ['Unisex', 'Men', 'Women', 'Boys', 'Girls', 'Kids']
                                .map((demo) => ChoiceChip(
                                      label: Text(demo),
                                      selected: _selectedDemographic == demo,
                                      onSelected: (selected) {
                                        if (selected) {
                                          HapticUtils.selection();
                                          setState(() {
                                            _selectedDemographic = demo;
                                          });
                                        }
                                      },
                                      selectedColor: AppColors.primary,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      side: BorderSide(
                                        color: _selectedDemographic == demo
                                            ? AppColors.primary
                                            : const Color(0xFFCBD5E1),
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _selectedDemographic == demo
                                            ? Colors.white
                                            : const Color(0xFF1E293B),
                                      ),
                                    ))
                                .toList(),
                      ),
                    ],

                    const SizedBox(height: 16),
                    _buildMenuCategorySelector(),
                  ],
                ),
                const SizedBox(height: 16),

                // ── GST Recommendation Card ──────────────────────────────────
                _buildGstCard(),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _priceController,
                  builder: (context, _) => _buildEarningsPreviewCard(),
                ),
                const SizedBox(height: 16),

                _card(
                  children: [
                    TextFormField(
                      controller: _inventoryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total Quantity (Stock)',
                        hintText: 'Leave empty for unlimited (e.g. food)',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Weight/Volume per unit',
                              hintText: 'e.g. 0.5, 1.5, 2',
                              prefixIcon: Icon(Icons.scale_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _availableUnitTypes.contains(_unitType)
                                ? _unitType
                                : _availableUnitTypes.first,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                            ),
                            items: _availableUnitTypes
                                .map((u) =>
                                    DropdownMenuItem(value: u, child: Text(u)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _unitType = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  children: [
                    if (AppCategories.isFoodCategory(_productCategory)) ...[
                      DropdownButtonFormField<bool?>(
                        key: ValueKey('diet_pref_$_productCategory'),
                        initialValue: _isVeg,
                        decoration: const InputDecoration(
                          labelText: 'Dietary Preference',
                          prefixIcon: Icon(Icons.eco_outlined),
                        ),
                        items: const [
                          DropdownMenuItem<bool?>(
                              value: true, child: Text('Vegetarian 🟢')),
                          DropdownMenuItem<bool?>(
                              value: false, child: Text('Non-Vegetarian 🔴')),
                          DropdownMenuItem<bool?>(
                              value: null, child: Text('None (N/A)')),
                        ],
                        onChanged: (v) => setState(() {
                          _isVeg = v;
                          _isDirty = true;
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Available',
                          style: TextStyle(fontFamily: 'Poppins')),
                      subtitle: Text(
                        _isAvailable
                            ? 'Visible to customers'
                            : 'Hidden from customers',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isAvailable,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) => setState(() {
                        _isAvailable = v;
                        _isDirty = true;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildBulkCateringCard(),
                if (AppCategories.isPharmacyCategory(_productCategory)) ...[
                  const SizedBox(height: 16),
                  _card(
                    children: [
                      const Text('Pharmacy & Medical Regulations',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _medicineType,
                        decoration: const InputDecoration(
                          labelText: 'Medicine Type',
                          prefixIcon: Icon(Icons.medical_services_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'General',
                              child: Text('General / Wellness')),
                          DropdownMenuItem(
                              value: 'OTC',
                              child: Text('Over The Counter (OTC)')),
                          DropdownMenuItem(
                              value: 'Schedule H',
                              child: Text('Schedule H (Prescription)')),
                          DropdownMenuItem(
                              value: 'Schedule H1',
                              child: Text('Schedule H1 (Prescription)')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _medicineType = v;
                              if (v == 'Schedule H' || v == 'Schedule H1') {
                                _requiresPrescription = true;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Note: Schedule X, NDPS (Narcotics), and Psychotropic substances are strictly PROHIBITED for online sale under Govt of India norms. Do not list them.',
                        style: TextStyle(fontSize: 11, color: AppColors.danger),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Requires Prescription',
                            style: TextStyle(fontFamily: 'Poppins')),
                        subtitle: const Text(
                          'Customer must upload Rx',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _requiresPrescription,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) =>
                            setState(() => _requiresPrescription = v),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProduct,
                    child: _isSaving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            widget.existingProduct != null
                                ? 'Save Changes'
                                : 'Add Product',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(children: children),
    );
  }
}
