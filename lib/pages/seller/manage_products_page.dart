import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_layout.dart';
class ManageProductsPage extends StatefulWidget {
  const ManageProductsPage({super.key});

  @override
  State<ManageProductsPage> createState() => _ManageProductsPageState();
}

class _ManageProductsPageState extends State<ManageProductsPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final auth = context.read<AuthProvider>();
    try {
      final shopResp = await _supabase
          .from('shops')
          .select('id')
          .eq('seller_id', auth.currentUserId ?? '')
          .single();

      _shopId = shopResp['id'];

      final productsResp = await _supabase
          .from('products')
          .select()
          .eq('shop_id', _shopId!);

      setState(() {
        _products = (productsResp as List)
            .map((p) => ProductModel.fromMap(p))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAvailability(ProductModel product) async {
    try {
      await _supabase
          .from('products')
          .update({'is_available': !product.isAvailable}).eq('id', product.id).eq('shop_id', product.shopId);
      _loadProducts();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Product?',
            style: TextStyle(fontFamily: 'Poppins')),
        content: Text('Are you sure you want to delete "${product.name}"?',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _supabase.from('products').delete().eq('id', product.id).eq('shop_id', product.shopId);
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Products'),
      ),
      body: MaxWidthContainer(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('📦',
                          style: TextStyle(fontSize: 60)),
                      SizedBox(height: 16),
                      Text('No products yet',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins')),
                      SizedBox(height: 8),
                      Text('Add your first product!',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Poppins')),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isDark
                            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              image: product.images.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(product.images.first),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: product.images.isEmpty
                                ? const Icon(Icons.shopping_bag_outlined,
                                    color: AppColors.primary)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      fontFamily: 'Poppins',
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    )),
                                Row(
                                  children: [
                                    Text(
                                      '₹${product.price.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: product.isAvailable
                                            ? AppColors.success
                                                .withValues(alpha: 0.1)
                                            : AppColors.danger
                                                .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        product.isAvailable
                                            ? 'Available'
                                            : 'Hidden',
                                        style: TextStyle(
                                          color: product.isAvailable
                                              ? AppColors.success
                                              : AppColors.danger,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Actions — scaled & constrained to prevent row overflow
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: 0.82,
                                child: Switch(
                                  value: product.isAvailable,
                                  onChanged: (_) => _toggleAvailability(product),
                                  activeThumbColor: AppColors.primary,
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.edit_outlined,
                                      color: AppColors.primary, size: 20),
                                  onPressed: () async {
                                    final result = await Navigator.pushNamed(
                                      context,
                                      '/seller/add-product',
                                      arguments: {'product': product},
                                    );
                                    if (result == true) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Changes saved successfully! 🎉'),
                                          backgroundColor: AppColors.success,
                                        ),
                                      );
                                    }
                                    _loadProducts();
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.danger, size: 20),
                                  onPressed: () => _deleteProduct(product),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
    );
  }
}
