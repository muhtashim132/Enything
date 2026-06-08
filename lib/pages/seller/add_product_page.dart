import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../config/app_categories.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../models/product_model.dart';
import '../../utils/responsive_layout.dart';
class AddProductPage extends StatefulWidget {
  final ProductModel? existingProduct;
  const AddProductPage({super.key, this.existingProduct});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _menuCategoryController = TextEditingController();
  final _weightController = TextEditingController();
  final _inventoryController = TextEditingController();

  bool _isVeg = true;
  bool _isAvailable = true;
  bool _isSaving = false;
  String _productCategory = 'Food';
  String _unitType = 'pieces';
  bool _isFoodGroup = true;
  bool _requiresPrescription = false;
  String _medicineType = 'General';
  String? _shopId;
  // BUG-FIX: Only categories belonging to the shop's CategoryGroup are allowed.
  // Prevents a restaurant seller from mis-categorising a product as Pharmacy etc.
  late List<String> _allowedCategories = [_productCategory]; // secure fallback until shop loads
  List<XFile> _images = [];
  List<String> _existingImageUrls = [];

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
    _fetchShopId();
    if (widget.existingProduct != null) {
      final p = widget.existingProduct!;
      _nameController.text = p.name;
      _priceController.text = p.price.toString();
      _descriptionController.text = p.description ?? '';
      _productCategory = p.category;
      _menuCategoryController.text = p.menuCategory ?? '';
      _isVeg = p.isVeg ?? false;
      _isAvailable = p.isAvailable;
      if (p.weightPerUnit != null) _weightController.text = p.weightPerUnit.toString();
      _unitType = p.unitType;
      if (p.totalQuantity != null) _inventoryController.text = p.totalQuantity.toString();
      _requiresPrescription = p.requiresPrescription;
      _medicineType = p.medicineType;
      _existingImageUrls = List.from(p.images);
    }
  }

  Future<void> _fetchShopId() async {
    final auth = context.read<AuthProvider>();
    try {
      final resp = await _supabase
          .from('shops')
          .select('id, category, categories')
          .eq('seller_id', auth.currentUserId ?? '')
          .single();

      // Collect all category names associated with this shop
      final shopCatNames = <String>{
        if (resp['category'] != null) resp['category'] as String,
        ...List<String>.from(resp['categories'] ?? []),
      }.where((c) => c.isNotEmpty).toSet();

      // Derive the union of CategoryGroups for this shop
      final shopGroups = shopCatNames.map(AppCategories.groupFor).toSet();

      // Only app-level categories whose group is within the shop's groups are allowed
      // Exception: Supermarkets can sell anything.
      final allowed = shopCatNames.contains('Supermarket / Hypermarket')
          ? AppCategories.names
          : AppCategories.names
              .where((name) => shopGroups.contains(AppCategories.groupFor(name)))
              .toList();

      // Primary category to default to (shop's own declared category)
      final primaryCat = resp['category'] ??
          (resp['categories'] != null && (resp['categories'] as List).isNotEmpty
              ? resp['categories'][0]
              : allowed.isNotEmpty ? allowed.first : 'Other');

      setState(() {
        _shopId = resp['id'];
        _allowedCategories = allowed.isNotEmpty ? allowed : AppCategories.names;

        // If editing an existing product whose category is already valid, keep it.
        // Otherwise snap to the shop's primary category.
        if (!_allowedCategories.contains(_productCategory)) {
          _productCategory = _allowedCategories.contains(primaryCat)
              ? primaryCat
              : _allowedCategories.first;
        }

        _isFoodGroup =
            AppCategories.groupFor(_productCategory) == CategoryGroup.food ||
                AppCategories.groupFor(_productCategory) ==
                    CategoryGroup.perishable;
      });
    } catch (e) {
      debugPrint('Shop fetch error: $e');
    }
  }

  Future<void> _pickImage() async {
    if (_images.length >= 3) return;
    final picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage(imageQuality: 70);
    if (picked.isNotEmpty) {
      setState(() {
        _images.addAll(picked);
        if (_images.length > 3) _images = _images.sublist(0, 3);
      });
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No shop found. Create a shop first.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      List<String> uploadedUrls = [];
      for (int i = 0; i < _images.length; i++) {
        final file = _images[i];
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last;
        final path =
            '$_shopId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await _supabase.storage.from('products').uploadBinary(path, bytes);
        uploadedUrls.add(_supabase.storage.from('products').getPublicUrl(path));
      }

      uploadedUrls.addAll(_existingImageUrls);

      final data = {
        'shop_id': _shopId,
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text),
        'description': _descriptionController.text.trim(),
        'category': _productCategory,
        'menu_category': _menuCategoryController.text.trim().isEmpty
            ? null
            : _menuCategoryController.text.trim(),
        'is_veg': _isFoodGroup ? _isVeg : false,
        'is_available': _isAvailable,
        'weight_per_unit': _weightController.text.trim().isEmpty
            ? null
            : double.tryParse(_weightController.text.trim()),
        'unit_type': _unitType,
        'total_quantity': _inventoryController.text.trim().isEmpty
            ? null
            : int.tryParse(_inventoryController.text.trim()),
        'images': uploadedUrls,
        'requires_prescription':
            _productCategory == 'Pharmacy' ? _requiresPrescription : false,
        'medicine_type':
            _productCategory == 'Pharmacy' ? _medicineType : 'General',
      };

      if (widget.existingProduct == null) {
        await _supabase.from('products').insert(data);
      } else {
        await _supabase.from('products').update(data).eq('id', widget.existingProduct!.id).eq('shop_id', widget.existingProduct!.shopId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product saved successfully! 🎉'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.existingProduct != null ? 'Edit Product' : 'Add Product')),
      body: MaxWidthContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Picker
              if (_images.isEmpty && _existingImageUrls.isEmpty)
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 2,
                          style: BorderStyle.solid),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap to add up to 3 images\nRecommended size: 1:1 (Square)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
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
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length + _existingImageUrls.length < 3
                            ? _images.length + _existingImageUrls.length + 1
                            : _images.length + _existingImageUrls.length,
                        itemBuilder: (context, index) {
                          if (index == _images.length + _existingImageUrls.length) {
                            return GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                width: 120,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      width: 2),
                                ),
                                child: const Center(
                                  child: Icon(Icons.add_photo_alternate,
                                      color: AppColors.primary),
                                ),
                              ),
                            );
                          }
                          return Stack(
                            children: [
                              Container(
                                width: 120,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: index < _existingImageUrls.length
                                        ? NetworkImage(_existingImageUrls[index])
                                        : FileImage(File(_images[index - _existingImageUrls.length].path)) as ImageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 16,
                                child: GestureDetector(
                                  onTap: () {
                                    if (index < _existingImageUrls.length) {
                                      _removeExistingImage(index);
                                    } else {
                                      _removeImage(index - _existingImageUrls.length);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),

              _card(
                children: [
                  TextFormField(
                    controller: _nameController,
                    validator: (v) =>
                        AppValidators.required(v, field: 'Product name'),
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      hintText: 'e.g., Chicken Biryani',
                      prefixIcon: Icon(Icons.fastfood_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    validator: AppValidators.price,
                    decoration: const InputDecoration(
                      labelText: 'Price (₹)',
                      hintText: '199',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Describe your product...',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
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
                        '${AppCategories.all.firstWhere((c) => c['name'] == _productCategory, orElse: () => {'emoji': '🏪'})['emoji']}  $_productCategory',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _allowedCategories.contains(_productCategory)
                          ? _productCategory
                          : _allowedCategories.first,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Product Category',
                        prefixIcon: Icon(Icons.category_outlined),
                        helperText: 'Limited to your shop\'s category group',
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
                            _isFoodGroup =
                                AppCategories.groupFor(v) == CategoryGroup.food ||
                                    AppCategories.groupFor(v) ==
                                        CategoryGroup.perishable;
                            if (!_availableUnitTypes.contains(_unitType)) {
                              _unitType = _availableUnitTypes.first;
                            }
                          });
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _menuCategoryController,
                    decoration: const InputDecoration(
                      labelText: 'Menu/Section Category (Optional)',
                      hintText: 'e.g. Main Course, Beverages, Shirts',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                ],
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
                          initialValue: _unitType,
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
                  if (_isFoodGroup) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vegetarian',
                          style: TextStyle(fontFamily: 'Poppins')),
                      subtitle: Text(
                        _isVeg ? 'Marked as veg 🟢' : 'Marked as non-veg 🔴',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isVeg,
                      activeThumbColor: AppColors.vegGreen,
                      onChanged: (v) => setState(() => _isVeg = v),
                    ),
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
                    onChanged: (v) => setState(() => _isAvailable = v),
                  ),
                ],
              ),
              if (_productCategory == 'Pharmacy') ...[
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
                      : Text(widget.existingProduct != null ? 'Save Changes' : 'Add Product',
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
