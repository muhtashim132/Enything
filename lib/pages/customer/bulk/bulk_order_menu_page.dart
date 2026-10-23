// ============================================================================
// bulk_order_menu_page.dart — Bulk-Eligible Catering Menu with Tiered Pricing
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../models/product_model.dart';
import '../../../models/shop_model.dart';
import '../../../providers/bulk_order_provider.dart';
import '../../../widgets/product_detail_sheet.dart';

class BulkOrderMenuPage extends StatefulWidget {
  final ShopModel? shop;

  const BulkOrderMenuPage({super.key, this.shop});

  @override
  State<BulkOrderMenuPage> createState() => _BulkOrderMenuPageState();
}

class _BulkOrderMenuPageState extends State<BulkOrderMenuPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late ShopModel _shop;
  bool _isLoading = true;
  List<ProductModel> _allProducts = [];
  List<ProductModel> _filteredProducts = [];
  String _selectedCategory = 'All';
  List<String> _categories = ['All'];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<BulkOrderProvider>(context, listen: false);
    _shop = widget.shop ?? provider.selectedShop!;
    _loadBulkProducts();
  }

  Future<void> _loadBulkProducts() async {
    setState(() => _isLoading = true);
    try {
      // Soft-delete rule: ALWAYS include is_deleted = false
      final response = await _supabase
          .from('products')
          .select()
          .eq('shop_id', _shop.id)
          .eq('bulk_eligible', true)
          .eq('is_deleted', false)
          .order('name');

      final list = (response as List)
          .map((m) => ProductModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();

      final categorySet = <String>{'All'};
      for (final p in list) {
        if (p.menuCategory != null && p.menuCategory!.trim().isNotEmpty) {
          categorySet.add(p.menuCategory!.trim());
        } else if (p.category.trim().isNotEmpty) {
          categorySet.add(p.category.trim());
        }
      }

      if (mounted) {
        setState(() {
          _allProducts = list;
          _categories = categorySet.toList();
          _filterByCategory();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading bulk menu products: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterByCategory() {
    if (_selectedCategory == 'All') {
      _filteredProducts = List.from(_allProducts);
    } else {
      _filteredProducts = _allProducts.where((p) {
        return p.menuCategory == _selectedCategory || p.category == _selectedCategory;
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;
    final bulkProvider = Provider.of<BulkOrderProvider>(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _shop.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Bulk & Catering Menu',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_seat_rounded, size: 14, color: primary),
                const SizedBox(width: 4),
                Text(
                  'Max ${_shop.maxBulkItemsPerSlot} items',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Notice banner
          _buildNoticeHeader(isDark, primary),

          // Categories horizontal bar
          if (_categories.length > 2)
            _buildCategoryTabs(isDark, primary),

          // Product List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? _buildEmptyMenuState(isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _buildProductCard(product, bulkProvider, isDark, primary);
                        },
                      ),
          ),

          // Bottom Cart Bar
          if (bulkProvider.items.isNotEmpty)
            _buildBottomCartBar(bulkProvider, isDark, primary),
        ],
      ),
    );
  }

  Widget _buildNoticeHeader(bool isDark, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Prices dynamically drop as quantity increases! Minimum order quantities apply per item.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(bool isDark, Color primary) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          return Center(
            child: FilterChip(
              selected: isSelected,
              label: Text(cat),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
              selectedColor: primary,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected
                      ? primary
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                ),
              ),
              onSelected: (val) {
                setState(() {
                  _selectedCategory = cat;
                  _filterByCategory();
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(
    ProductModel product,
    BulkOrderProvider bulkProvider,
    bool isDark,
    Color primary,
  ) {
    final cartItem = bulkProvider.items[product.id];
    final inCart = cartItem != null;
    final minQty = product.minBulkQuantity ?? 20;
    final currentQty = cartItem?.quantity ?? minQty;
    final currentUnitPrice = product.getPriceForQuantity(currentQty);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: inCart ? primary.withValues(alpha: 0.5) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          width: inCart ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              showProductDetailSheet(context, product.id);
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 80,
                  height: 80,
                  color: isDark ? Colors.black26 : Colors.grey[100],
                  child: product.firstImage.isNotEmpty
                      ? Image.network(
                          product.firstImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholderIcon(),
                        )
                      : _buildPlaceholderIcon(),
                ),
              ),
              const SizedBox(width: 12),

              // Title, veg icon, base price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (product.showsDietEmblem)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: product.isVeg! ? Colors.green : Colors.red,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: product.isVeg! ? Colors.green : Colors.red,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Min: $minQty ${product.unitType}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '₹${currentUnitPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: primary,
                          ),
                        ),
                        Text(
                          ' / unit',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                        ),
                        if (inCart) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Total: ₹${cartItem.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

          // Tiered Pricing Pill List
          if (product.bulkPriceTiers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sell_outlined, size: 12, color: Colors.amber),
                  const SizedBox(width: 6),
                  const Text(
                    'Tiers: ',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: product.bulkPriceTiers.map((tier) {
                          final min = tier['min_qty'];
                          final p = tier['price'];
                          final isApplied = inCart && currentQty >= (min as int);
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isApplied
                                  ? primary.withValues(alpha: 0.2)
                                  : (isDark ? Colors.black26 : Colors.white),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isApplied ? primary : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              '≥$min: ₹$p',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isApplied ? FontWeight.bold : FontWeight.normal,
                                color: isApplied ? primary : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Stepper or Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (inCart)
                TextButton.icon(
                  onPressed: () => _showInstructionsDialog(product, cartItem, bulkProvider),
                  icon: const Icon(Icons.note_alt_outlined, size: 14),
                  label: Text(
                    cartItem.specialInstructions?.isNotEmpty == true
                        ? 'Edit Note'
                        : 'Add Note',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                const SizedBox.shrink(),

              if (!inCart)
                ElevatedButton.icon(
                  onPressed: () {
                    bulkProvider.addToCart(product, quantity: minQty);
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('ADD $minQty UNITS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          currentQty <= minQty ? Icons.delete_outline_rounded : Icons.remove_rounded,
                          size: 18,
                          color: primary,
                        ),
                        onPressed: () {
                          if (currentQty <= minQty) {
                            bulkProvider.removeFromCart(product.id);
                          } else {
                            bulkProvider.updateQuantity(product.id, currentQty - 5);
                          }
                        },
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      InkWell(
                        onTap: () => _showQuantityDialog(product, currentQty, minQty, bulkProvider),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '$currentQty',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        color: primary,
                        onPressed: () {
                          bulkProvider.updateQuantity(product.id, currentQty + 5);
                        },
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(
    ProductModel product,
    int currentQty,
    int minQty,
    BulkOrderProvider bulkProvider,
  ) {
    final controller = TextEditingController(text: currentQty.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enter Quantity for ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Minimum order quantity: $minQty units', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Quantity',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text) ?? currentQty;
              if (parsed < minQty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Quantity cannot be less than $minQty')),
                );
              } else {
                bulkProvider.updateQuantity(product.id, parsed);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showInstructionsDialog(
    ProductModel product,
    BulkCartItem item,
    BulkOrderProvider bulkProvider,
  ) {
    final controller = TextEditingController(text: item.specialInstructions ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kitchen Notes: ${product.name}'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. Less spicy, pack in boxes of 20, separate sauce...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              item.specialInstructions = controller.text.trim();
              bulkProvider.saveDraft();
              Navigator.pop(ctx);
            },
            child: const Text('Save Note'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderIcon() {
    return const Center(
      child: Icon(Icons.fastfood_rounded, size: 30, color: Colors.grey),
    );
  }

  Widget _buildEmptyMenuState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🍽️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            'No bulk items listed yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This kitchen is currently updating their bulk catering items.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCartBar(
    BulkOrderProvider bulkProvider,
    bool isDark,
    Color primary,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${bulkProvider.totalItems} items (${bulkProvider.items.length} dishes)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                Text(
                  '₹${bulkProvider.subtotal.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.bulkOrderEvent);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Configure Event & Slot',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
