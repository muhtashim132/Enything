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
  final _supabase = Supabase.instance.client;
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
          .update({'is_available': !product.isAvailable}).eq('id', product.id);
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
      await _supabase.from('products').delete().eq('id', product.id);
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      fontFamily: 'Poppins',
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
                          Row(
                            children: [
                              Switch(
                                value: product.isAvailable,
                                onChanged: (_) =>
                                    _toggleAvailability(product),
                                activeThumbColor: AppColors.primary,
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: AppColors.primary),
                                onPressed: () async {
                                  await Navigator.pushNamed(
                                    context,
                                    '/seller/add-product',
                                    arguments: {'product': product},
                                  );
                                  _loadProducts();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.danger),
                                onPressed: () =>
                                    _deleteProduct(product),
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
