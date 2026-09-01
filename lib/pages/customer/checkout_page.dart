import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/cart_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/enything_map.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/payment_config.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../utils/responsive_layout.dart';
import '../../services/image_compression_service.dart';
import '../../utils/delivery_calculator.dart';
import '../../providers/coupon_provider.dart';
import '../../models/shop_model.dart';
import 'dart:math' as math;

import '../../widgets/coupon_input_widget.dart';
import '../../widgets/common/slide_to_action.dart';
import '../../utils/haptic_utils.dart';

class CheckoutPage extends StatefulWidget {
  final String? existingCartGroupId;
  final String? orderIdToCancelOnSuccess;

  const CheckoutPage(
      {super.key, this.existingCartGroupId, this.orderIdToCancelOnSuccess});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  bool _isCreatingOrder =
      false; // O1 FIX: Idempotency lock — prevents duplicate order creation
  final _notesController = TextEditingController();
  
  // ── 100x Multi-Shop Targeted Prescription State ─────────────────────────────
  final Map<String, List<XFile>> _shopPrescriptions = {};
  bool _applyToAllPharmacies = true;

  List<XFile> _getPrescriptionsForShop(String shopId) {
    if (_applyToAllPharmacies) {
      return _shopPrescriptions['__ALL__'] ?? [];
    }
    return _shopPrescriptions[shopId] ?? [];
  }

  // --- 100x Replacment Order Aggregate State ---
  // ignore: unused_field
  bool _isLoadingActiveGroup = false;
  double _activeSubtotal = 0.0;
  double _activeSmallCartFee = 0.0;
  // ignore: unused_field
  double _activeHeavyOrderFee = 0.0;
  Set<String> _activeShopIds = {};
  double _activeWeight = 0.0;
  // ignore: unused_field
  double _activeSurchargePaid = 0.0;
  // ignore: unused_field
  List<ShopModel> _activeShops = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateStockPreCheckout();
      _fetchActiveGroupState();
    });
  }

  Future<void> _fetchActiveGroupState() async {
    final cartProvider = context.read<CartProvider>();
    final pendingGroupId = cartProvider.pendingCartGroupId;
    final cartGroupId = widget.existingCartGroupId ?? pendingGroupId;
    if (cartGroupId == null) return;

    setState(() => _isLoadingActiveGroup = true);
    try {
      final supabase = Supabase.instance.client;
      // Bug 3.3: Exclude 'delivered' — delivered orders have separate payments
      final response = await supabase
          .from('orders')
          .select(
              'id, total_amount, small_cart_fee, heavy_order_fee, shop_id, multi_shop_surcharge')
          .eq('cart_group_id', cartGroupId)
          .inFilter('status', [
        'awaiting_acceptance',
        'awaiting_payment',
        'pending_pickup',
        'accepted',
        'preparing',
        'ready_for_pickup',
        'picked_up',
        'out_for_delivery',
      ]);

      double subtotal = 0.0;
      double smallCartFee = 0.0;
      double heavyFee = 0.0;
      double surchargePaid = 0.0;
      Set<String> shopIds = {};
      List<String> activeOrderIds = [];

      for (var row in (response as List)) {
        subtotal += (row['total_amount'] as num?)?.toDouble() ?? 0.0;
        smallCartFee += (row['small_cart_fee'] as num?)?.toDouble() ?? 0.0;
        heavyFee += (row['heavy_order_fee'] as num?)?.toDouble() ?? 0.0;
        surchargePaid +=
            (row['multi_shop_surcharge'] as num?)?.toDouble() ?? 0.0;
        if (row['shop_id'] != null) {
          shopIds.add(row['shop_id'].toString());
        }
        if (row['id'] != null) {
          activeOrderIds.add(row['id'].toString());
        }
      }

      // Bug 3.1: Fetch actual weight from order_items joined with products
      double weight = 0.0;
      if (activeOrderIds.isNotEmpty) {
        try {
          final weightResponse = await supabase
              .from('order_items')
              .select('quantity, product:products!inner(weight_per_unit, is_deleted)')
              .inFilter('order_id', activeOrderIds)
              .eq('product.is_deleted', false);
          for (var row in (weightResponse as List)) {
            final qty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
            final product = row['product'];
            final weightPerUnit = product != null
                ? (product['weight_per_unit'] as num?)?.toDouble() ?? 0.5
                : 0.5;
            weight += qty * weightPerUnit;
          }
        } catch (e) {
          debugPrint('Error fetching active order weight: $e');
        }
      }

      List<ShopModel> fetchedShops = [];
      if (shopIds.isNotEmpty) {
        final shopsResponse = await supabase
            .from('shops')
            .select()
            .inFilter('id', shopIds.toList());
        for (var shopData in shopsResponse) {
          fetchedShops.add(ShopModel.fromMap(shopData));
        }
      }

      if (mounted) {
        setState(() {
          _activeSubtotal = subtotal;
          _activeSmallCartFee = smallCartFee;
          _activeHeavyOrderFee = heavyFee;
          _activeWeight = weight;
          _activeSurchargePaid = surchargePaid;
          _activeShopIds = shopIds;
          _activeShops = fetchedShops;
        });
      }
    } catch (e) {
      debugPrint('Error fetching active group state: $e');
    } finally {
      if (mounted) setState(() => _isLoadingActiveGroup = false);
    }
  }

  Future<void> _validateStockPreCheckout() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    try {
      final productIds = cart.items.map((i) => i.product.id).toList();
      // Phase 25 Fix: Deep join with shops to verify shop is still active, and fetch variants/price to check spoofing.
      final latestProducts = await Supabase.instance.client
          .from('products')
          .select(
              'id, name, price, variants, is_available, total_quantity, shops(id, name, is_active)')
          .eq('is_deleted', false)
          .inFilter('id', productIds);

      final issues = <String>[];

      // Aggregated Inventory Guard to prevent Quantity Accumulation Bypass
      final Map<String, int> productQtyMap = {};
      for (var item in cart.items) {
        productQtyMap[item.product.id] =
            (productQtyMap[item.product.id] ?? 0) + item.quantity;
      }

      for (var cartItem in cart.items) {
        final dbProduct = latestProducts
            .where((p) => p['id'] == cartItem.product.id)
            .firstOrNull;

        if (dbProduct == null) {
          issues.add("${cartItem.product.name} is no longer available.");
          continue;
        }

        // 1. Ghost Kitchens II (Banned Shop Checkout) Guard
        if (dbProduct['shops'] != null &&
            dbProduct['shops']['is_active'] == false) {
          issues.add(
              "${dbProduct['shops']['name']} is currently not accepting orders.");
          continue;
        }

        // 2. Availability Guard
        if (dbProduct['is_available'] == false) {
          issues.add("${cartItem.product.name} is currently out of stock.");
          continue;
        }

        // 3. Stock Quantity Guard
        final totalRequestedQty =
            productQtyMap[cartItem.product.id] ?? cartItem.quantity;
        if (dbProduct['total_quantity'] != null &&
            dbProduct['total_quantity'] < totalRequestedQty) {
          issues.add(
              "Only ${dbProduct['total_quantity']} total units of ${cartItem.product.name} are available, but you have $totalRequestedQty in your cart.");
          continue;
        }

        // 4. Cart Price Spoofing Guard
        double freshPrice = (dbProduct['price'] ?? 0.0).toDouble();

        if (cartItem.selectedVariant != null) {
          bool variantFound = false;
          if (dbProduct['variants'] != null) {
            final variantsList = dbProduct['variants'] as List;
            for (var v in variantsList) {
              if (v['name'] == cartItem.selectedVariant!.name) {
                freshPrice = (v['price'] ?? 0.0).toDouble();
                if (v['is_available'] == false) {
                  issues.add(
                      "Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is out of stock.");
                }
                variantFound = true;
                break;
              }
            }
          }
          if (!variantFound) {
            issues.add(
                "Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is no longer available.");
            continue;
          }
        }

        double cartPrice =
            cartItem.selectedVariant?.price ?? cartItem.product.price;
        if ((freshPrice - cartPrice).abs() > 0.01) {
          issues.add(
              "Price changed for ${cartItem.product.name} (from ₹${cartPrice.toStringAsFixed(0)} to ₹${freshPrice.toStringAsFixed(0)}).");
        }
      }

      if (issues.isNotEmpty && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Cart Update Required',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Text(
                  'Some items in your cart require attention before you can check out:\n\n${issues.join('\n\n')}\n\nPlease update your cart to proceed.',
                  style: GoogleFonts.outfit()),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Back to Cart',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Pre-checkout stock validation error: $e');
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _isProcessing.dispose();
    super.dispose();
  }

  // No Razorpay callbacks here — payment is triggered from TrackOrderPage
  // after both seller & rider accept the order.

  bool _isPickerOpen = false;
  Future<void> _pickPrescription({String? shopId}) async {
    if (_isPickerOpen) return;
    _isPickerOpen = true;
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Upload Prescription',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: Text('Take a Photo', style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text('Choose from Gallery', style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) {
      _isPickerOpen = false;
      return;
    }

    final targetKey = (_applyToAllPharmacies || shopId == null) ? '__ALL__' : shopId;

    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(source: source, imageQuality: 70);
      _isPickerOpen = false;
      if (picked != null) {
        setState(() {
          _shopPrescriptions.putIfAbsent(targetKey, () => []).add(picked);
        });
      }
    } else {
      final picked = await picker.pickMultiImage(imageQuality: 70);
      _isPickerOpen = false;
      if (picked.isNotEmpty) {
        setState(() {
          _shopPrescriptions.putIfAbsent(targetKey, () => []).addAll(picked);
        });
      }
    }
  }

  void _removePrescription(String shopId, int index) {
    final targetKey = _applyToAllPharmacies ? '__ALL__' : shopId;
    setState(() {
      _shopPrescriptions[targetKey]?.removeAt(index);
    });
  }

  // ── Step 1: Save order as awaiting_acceptance (NO payment yet) ────────────
  // Payment is triggered ONLY after BOTH seller AND rider accept (within 1 min).
  Future<void> _placeOrder() async {
    if (_isCreatingOrder || _isProcessing.value) return;
    _isProcessing.value = true;
    _isCreatingOrder = true;
    final cart = context.read<CartProvider>();
    final location = context.read<LocationProvider>();

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Your cart is empty!'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _isCreatingOrder = false;
      _isProcessing.value = false;
      return;
    }

    // ── 100x Multi-Shop Prescription Guard ─────────────────────────────────
    final rxShops = cart.shops.where((s) {
      return cart.getItemsForShop(s.id).any((i) => i.product.requiresPrescription);
    }).toList();

    if (rxShops.isNotEmpty) {
      for (final s in rxShops) {
        final list = _getPrescriptionsForShop(s.id);
        if (list.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Please upload a prescription for ${s.name} to proceed.',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
          _isCreatingOrder = false;
          _isProcessing.value = false;
          return;
        }
      }
    }

    if (!location.hasLocation ||
        location.currentLocation?.latitude == null ||
        location.currentLocation?.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please set a valid delivery location first.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _isCreatingOrder = false;
      _isProcessing.value = false;
      return;
    }

    try {
      await _createOrderInDb();
    } catch (e) {
      debugPrint('Order placement error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_classifyCheckoutError(e.toString())),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
            margin: const EdgeInsets.all(16),
          ),
        );
        _isCreatingOrder = false;
        _isProcessing.value = false;
      }
    }
  }

  String _classifyCheckoutError(String errorStr) {
    final e = errorStr.toLowerCase();
    if (e.contains('socketexception') ||
        e.contains('timeoutexception') ||
        e.contains('clientexception')) {
      return 'Network issue detected. Please check your internet connection and try again.';
    } else if (e.contains('delivery charge spoofing') ||
        e.contains('commission mismatch')) {
      return 'Price synchronization failed. Please refresh your cart and try again.';
    } else if (e.contains('invalid replacement') ||
        e.contains('cannot change status')) {
      return 'This order cannot be modified at this time. Please pull down to refresh the page.';
    } else if (e.contains('unauthorized') || e.contains('ghost order')) {
      return 'Session expired or unauthorized request. Please restart the app.';
    } else if (e.contains('coupon')) {
      return 'The applied coupon is no longer valid or applicable to this order.';
    } else if (e.contains('postgrestexception')) {
      return 'Our servers are currently busy. Please wait a moment and try again.';
    }
    return 'An unexpected error occurred while placing your order. Please try again.';
  }

  // Verification & payment completion is now handled in TrackOrderPage.

  // ── Save order as 'awaiting_acceptance' — NO payment charged yet ──────────
  // Financial snapshot is stored immediately for transparency.
  // Razorpay is only opened from TrackOrderPage when both seller & rider accept.
  Future<void> _createOrderInDb() async {
    _isCreatingOrder = true;
    final cart = context.read<CartProvider>();
    final auth = context.read<AuthProvider>();
    final location = context.read<LocationProvider>();
    // Capture coupon ID & discount before any await to avoid BuildContext-across-async-gaps warning
    final couponProv = context.read<CouponProvider>();

    // O1 FIX: Coupon State Desync Guard
    // If the cart was modified after the coupon was applied (e.g., items removed),
    // the static discount amount in CouponProvider becomes stale. We must dynamically
    // re-validate it here before creating the order to prevent backend SQL rejection
    // (Coupon discount spoofing) or unexpected UI softlocks.
    if (couponProv.hasCoupon && couponProv.appliedCoupon != null) {
      final code = couponProv.appliedCoupon!.code;
      final stillValid = await couponProv.validateAndApply(
        code: code,
        cartTotal: cart.subtotal,
      );
      if (!stillValid) {
        throw Exception(
            "Your cart total has changed and the coupon '$code' is no longer valid or its discount amount has been adjusted. Please review your cart and try again.");
      }
    }

    // Capture coupon ID & discount after re-validation
    final appliedCouponId = couponProv.appliedCoupon?.id;
    final appliedCouponDiscount = couponProv.discountAmount;

    final supabase = Supabase.instance.client;

    List<String> uploadedPaths = [];

    try {
      // 0. Self-Dealing Guard (Anti-Sybil / Fraud Prevention)
      for (final shop in cart.shops) {
        if (shop.sellerId == auth.currentUserId) {
          throw Exception(
              "Self-Dealing Blocked: You cannot place orders on your own shop (${shop.name}).");
        }
      }

      // Add Shop Open validation
      final closedShops = cart.shops.where((s) => !s.isOpenRightNow).toList();
      if (closedShops.isNotEmpty) {
        throw Exception(
            "${closedShops.first.name} is currently closed and not accepting orders.");
      }

      // Stock Validation
      final productIds = cart.items.map((i) => i.product.id).toList();
      // Phase 25 Fix: Deep join with shops to verify shop is still active, and fetch variants/price to check spoofing.
      final latestProducts = await supabase
          .from('products')
          .select(
              'id, name, price, variants, is_available, total_quantity, shops(id, name, is_active)')
          .eq('is_deleted', false)
          .inFilter('id', productIds);

      // Aggregated Inventory Guard to prevent Quantity Accumulation Bypass
      final Map<String, int> productQtyMap = {};
      for (var item in cart.items) {
        productQtyMap[item.product.id] =
            (productQtyMap[item.product.id] ?? 0) + item.quantity;
      }

      for (var cartItem in cart.items) {
        final dbProduct = latestProducts
            .where((p) => p['id'] == cartItem.product.id)
            .firstOrNull;

        if (dbProduct == null) {
          throw Exception("${cartItem.product.name} is no longer available.");
        }

        // 1. Ghost Kitchens II (Banned Shop Checkout) Guard
        if (dbProduct['shops'] != null &&
            dbProduct['shops']['is_active'] == false) {
          throw Exception(
              "${dbProduct['shops']['name']} is currently not accepting orders.");
        }

        // 2. Availability Guard
        if (dbProduct['is_available'] == false) {
          throw Exception(
              "${cartItem.product.name} is currently out of stock.");
        }

        // 3. Stock Quantity Guard
        final totalRequestedQty =
            productQtyMap[cartItem.product.id] ?? cartItem.quantity;
        if (dbProduct['total_quantity'] != null &&
            dbProduct['total_quantity'] < totalRequestedQty) {
          throw Exception(
              "Only ${dbProduct['total_quantity']} total units of ${cartItem.product.name} are available, but you have $totalRequestedQty in your cart.");
        }

        // 4. Cart Price Spoofing Guard
        double freshPrice = (dbProduct['price'] ?? 0.0).toDouble();

        if (cartItem.selectedVariant != null) {
          bool variantFound = false;
          if (dbProduct['variants'] != null) {
            final variantsList = dbProduct['variants'] as List;
            for (var v in variantsList) {
              if (v['name'] == cartItem.selectedVariant!.name) {
                freshPrice = (v['price'] ?? 0.0).toDouble();
                if (v['is_available'] == false) {
                  throw Exception(
                      "Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is out of stock.");
                }
                variantFound = true;
                break;
              }
            }
          }
          if (!variantFound) {
            throw Exception(
                "Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is no longer available.");
          }
        }

        double cartPrice =
            cartItem.selectedVariant?.price ?? cartItem.product.price;
        if ((freshPrice - cartPrice).abs() > 0.01) {
          throw Exception(
              "The price of ${cartItem.product.name} has changed from ₹${cartPrice.toStringAsFixed(0)} to ₹${freshPrice.toStringAsFixed(0)}. Please review your cart.");
        }
      }

      double maxDistanceKm = 0.0;
      if (location.currentLocation != null && cart.shops.isNotEmpty) {
        for (var s in cart.shops) {
          final d = location.distanceTo(s.location);
          if (d > maxDistanceKm) maxDistanceKm = d;
        }
      }
      final baseDelivery = cart.calculateDeliveryCharges(maxDistanceKm);
      if (baseDelivery < 0) {
        throw Exception('Your delivery address is outside our delivery zone.');
      }

      final isReplacementOrder = widget.existingCartGroupId != null ||
          cart.pendingCartGroupId != null;

      double surcharge = 0.0;
      double heavyFee = 0.0;
      double smallCartFee = 0.0;
      double effectiveBase = 0.0;

      if (isReplacementOrder) {
        // Replacement order fees:
        // • effectiveBase = 0.0 — delivery charge stays the SAME because it's
        //   still one rider delivering to one address. We don't double-charge.
        // • Multi-shop surcharge uses the flat admin rate, NOT distance-based calc,
        //   because the SQL validation checks: flatRate × (shopCount − 1).
        //   Rule (confirmed): 2 total active shops at end = ₹20, 3 = ₹40.
        //   If new items are from an already-accepted shop → ₹0 extra surcharge.
        effectiveBase = 0.0;

        // Count total unique active shops at the end of this replacement:
        //   existing active shops + new shops from this checkout (if different)
        final newUniqueShopIds = cart.shops
            .map((s) => s.id)
            .where((id) => !_activeShopIds.contains(id))
            .toSet();
        final totalShopsAtEnd = _activeShopIds.length + newUniqueShopIds.length;
        final flatSurchargeRate =
            PlatformConfigProvider.instance?.multiShopSurcharge ?? 20.0;
        final totalSurchargeAtEnd = totalShopsAtEnd > 1
            ? flatSurchargeRate * (totalShopsAtEnd - 1)
            : 0.0;

        // 100x FIX: Anticipate the database's reallocation.
        // The DB will reduce the old payment pool's surcharge to match its active count.
        final oldActiveCount = _activeShopIds.length;
        final expectedOldSurchargePaid = math.min(
            _activeSurchargePaid,
            oldActiveCount > 1
                ? flatSurchargeRate * (oldActiveCount - 1)
                : 0.0);

        surcharge =
            math.max(0.0, totalSurchargeAtEnd - expectedOldSurchargePaid);

        // Small cart fee (aggregate check)
        final smallCartThreshold =
            PlatformConfigProvider.instance?.smallCartThreshold ??
                PaymentConfig.smallCartThreshold;
        if ((_activeSubtotal + cart.subtotal) < smallCartThreshold &&
            (_activeSubtotal + cart.subtotal) > 0) {
          final standardSmallCartFee =
              PlatformConfigProvider.instance?.smallCartFee ??
                  PaymentConfig.smallCartFee;
          smallCartFee =
              math.max(0, standardSmallCartFee - _activeSmallCartFee);
        }

        // Heavy order fee (aggregate check)
        final heavyThreshold =
            PlatformConfigProvider.instance?.heavyOrderThresholdKg ??
                PaymentConfig.heavyOrderThreshold;
        final aggregateWeight = _activeWeight + cart.totalWeight;
        if (aggregateWeight > heavyThreshold) {
          final feePerKg = PlatformConfigProvider.instance?.heavyOrderFee ??
              PaymentConfig.heavyOrderFee;
          final aggregateHeavyFee =
              feePerKg * (aggregateWeight - heavyThreshold).ceil();
          heavyFee = math.max(0.0, aggregateHeavyFee - _activeHeavyOrderFee);
        }
      } else {
        effectiveBase = baseDelivery >= 0
            ? baseDelivery
            : (PlatformConfigProvider.instance?.deliveryBaseFee ??
                PaymentConfig.deliveryFee);
        surcharge = cart.multiShopSurcharge;
        heavyFee = cart.heavyOrderFee;
        smallCartFee = cart.smallCartFee;
      }

      final riderBase = effectiveBase + surcharge + heavyFee;
      // ADDITIVE FIX: Use DB-driven rider payout ratio instead of hardcoded 0.80.
      // Admin can change rider_commission_percent in Admin → Commission & Fees.
      // To revert: replace with `riderBase * TaxConfig.riderPayoutRatio`
      final riderPayoutRatio =
          (PlatformConfigProvider.instance?.riderCommissionPercent ?? 80.0) /
              100.0;
      final riderEarnings = riderBase * riderPayoutRatio;

      double totalWithoutGst =
          effectiveBase + surcharge + heavyFee + smallCartFee;
      if (totalWithoutGst < 0) totalWithoutGst = 0.0;
      double totalDelivery = totalWithoutGst * (1 + TaxConfig.deliveryGstRate);

      // Payment method is always 'upi' now (COD removed)
      const paymentMethod = 'upi';

      // BUG FIX (Issue 3): Read pendingCartGroupId set by track_order_page when
      // customer taps "Search for Different Items" or "Find Missing Items".
      // This links the replacement order to the original rejected cart group.
      if (!mounted) return;
      final cartProvider = context.read<CartProvider>();
      final pendingGroupId = cartProvider.pendingCartGroupId;
      final pendingCancelId = cartProvider.pendingOrderIdToCancel;
      final cartGroupId =
          widget.existingCartGroupId ?? pendingGroupId ?? const Uuid().v4();

      // Clear the pending group ID now that we've consumed it
      if (pendingGroupId != null) cartProvider.setPendingCartGroupId(null);
      if (pendingCancelId != null) cartProvider.setPendingOrderIdToCancel(null);
      final numShops = cart.shops.length;

      // Acceptance deadline: 3 minutes from now (enforces 3-minute cancellation rule)
      final acceptanceDeadline =
          DateTime.now().toUtc().add(const Duration(minutes: 3));

      // Fetch customer phone
      String? customerPhone;
      try {
        final profile = await supabase
            .from('profiles')
            .select('phone')
            .eq('id', auth.currentUserId ?? '')
            .maybeSingle();
        if (profile != null) customerPhone = profile['phone'];
      } catch (_) {}

      // Fetch shop phones
      final shopPhones = <String, String?>{};
      for (final shop in cart.shops) {
        try {
          final profile = await supabase
              .from('profiles')
              .select('phone')
              .eq('id', shop.sellerId)
              .maybeSingle();
          if (profile != null) shopPhones[shop.id] = profile['phone'];
        } catch (_) {}
      }

      // ── 100x Multi-Shop Targeted Storage Upload ───────────────────────────
      final Map<String, List<String>> uploadedShopPrescriptionUrls = {};
      final rxShops = cart.shops.where((s) => cart.shopRequiresPrescription(s.id)).toList();

      if (rxShops.isNotEmpty) {
        for (final shop in rxShops) {
          final files = _getPrescriptionsForShop(shop.id);
          final urls = <String>[];

          for (int i = 0; i < files.length; i++) {
            final file = files[i];
            final rawBytes = await file.readAsBytes();
            if (rawBytes.length > 10 * 1024 * 1024) {
              throw Exception(
                  'Prescription file for ${shop.name} exceeds the 10MB limit. Please choose a smaller image.');
            }
            final bytes =
                await ImageCompressionService.compressFile(File(file.path)) ??
                    rawBytes;
            const ext = 'jpg'; // Compressed format is jpeg
            final path = '${auth.currentUserId}/${cartGroupId}_${shop.id}_$i.$ext';

            bool uploadSuccess = false;
            int retries = 0;
            while (!uploadSuccess && retries < 3) {
              try {
                await supabase.storage
                    .from('prescription_docs')
                    .uploadBinary(path, bytes);
                uploadSuccess = true;
              } catch (e) {
                retries++;
                if (retries >= 3) {
                  throw Exception(
                      'Failed to upload prescription for ${shop.name} after 3 attempts. Please check connection and try again.');
                }
                await Future.delayed(Duration(seconds: retries * 2));
              }
            }
            uploadedPaths.add(path);
            urls.add(supabase.storage.from('prescription_docs').getPublicUrl(path));
          }

          uploadedShopPrescriptionUrls[shop.id] = urls;
        }
      }

      final List<Map<String, dynamic>> allOrders = [];
      final List<Map<String, dynamic>> allItems = [];
      final List<String> orderIds = [];
      final List<Map<String, dynamic>> notificationData = [];

      final nowUtc = DateTime.now().toUtc().toIso8601String();

      // 100x ARCHITECTURE FIX: Economic Splitting Flaw
      // Calculate total geographic distance to all shops. We MUST split the delivery fee
      // and rider earnings by distance, NOT by the food's subtotal. Otherwise, a rider can
      // drop a distant shop with cheap items, and the replacement rider gets paid pennies
      // for a long drive, while the first rider pockets the entire fee for a short drive.
      double totalCartDistanceKm = 0.0;
      for (final shop in cart.shops) {
        totalCartDistanceKm += location.currentLocation != null
            ? location.distanceTo(shop.location)
            : 3.0;
      }
      if (totalCartDistanceKm == 0.0) totalCartDistanceKm = 1.0;

      for (final shop in cart.shops) {
        final shopItems =
            cart.items.where((i) => i.shop.id == shop.id).toList();
        final shopBaseSubtotal =
            shopItems.fold(0.0, (sum, i) => sum + i.totalPrice);

        double shopDistanceKm = 3.0;
        if (location.currentLocation != null) {
          shopDistanceKm = location.distanceTo(shop.location);
        }

        final proportion = cart.subtotal > 0
            ? (shopBaseSubtotal / cart.subtotal)
            : (1.0 / numShops);

        // 100x FIX: Distribute flat cart delivery and rider earnings equally across shops
        final shopDelivery = totalDelivery / (numShops > 0 ? numShops : 1);
        final shopRiderEarnings = riderEarnings / (numShops > 0 ? numShops : 1);

        // 100x FIX: Handling Fee (Platform Fee) is a fixed flat fee per cart (NOT per shop)
        final totalPlatformFee = isReplacementOrder
            ? 0.0
            : (PlatformConfigProvider.instance?.platformFee ??
                PaymentConfig.platformFee);
        final shopPlatformFee =
            totalPlatformFee / (numShops > 0 ? numShops : 1);

        final shopTaxBreakdownItems = shopItems.map((i) {
          return {
            'category': i.product.category,
            'price': i.selectedVariant?.price ?? i.product.price,
            'quantity': i.quantity,
            'gst_rate_override': i.product.gstRateOverride,
          };
        }).toList();

        final shopBreakdown = OrderTaxBreakdown.calculate(
          items: shopTaxBreakdownItems,
          deliveryCharge: shopDelivery,
          riderEarnings: shopRiderEarnings,
          platformFee: shopPlatformFee,
          paymentMethod: paymentMethod,
        );

        final Map<String, dynamic> rateSnapshot = {};
        for (final item in shopItems) {
          final cat = item.product.category;
          final itemPrice = item.selectedVariant?.price ?? item.product.price;
          // Use product-level override if set; otherwise use category rate
          final effectiveRate = item.product.gstRateOverride ??
              (PlatformConfigProvider.instance
                      ?.getGstRate(cat, itemPrice: itemPrice) ??
                  TaxConfig.gstRateForCategory(cat, itemPrice: itemPrice));
          if (!rateSnapshot.containsKey(cat)) {
            rateSnapshot[cat] = effectiveRate;
          }
        }

        final shopS9_5Gst = shopBreakdown.s9_5GstToRemit;
        final shopNonFoodGst = shopBreakdown.nonFoodGstPassThrough;

        // TCS and TDS are now computed inside OrderTaxBreakdown.calculate()
        final shopTcs = shopBreakdown.tcsAmount;
        final shopTds = shopBreakdown.tdsAmount;
        final shopGrandTotal = shopBreakdown.grandTotal;

        final orderId = const Uuid().v4();
        orderIds.add(orderId);

        allOrders.add({
          'id': orderId,
          'created_at': nowUtc,
          'updated_at': nowUtc,
          'cart_group_id': cartGroupId,
          'shop_id': shop.id,
          'customer_id': auth.currentUserId,
          'status': 'awaiting_acceptance',
          'seller_accepted': false,
          'partner_accepted': false,
          'acceptance_deadline': acceptanceDeadline.toIso8601String(),
          'total_amount': shopBaseSubtotal,
          'delivery_charges': shopDelivery,
          'rider_earnings': shopRiderEarnings,
          'multi_shop_surcharge': surcharge * proportion,
          'small_cart_fee': smallCartFee * proportion,
          'heavy_order_fee': heavyFee * proportion,
          'platform_fee': shopPlatformFee,
          'address': location.currentAddress,
          'address_label': location.activeLabel.isNotEmpty
              ? '${location.activeLabelIcon} ${location.activeLabel}'
              : null,
          'delivery_lat': location.currentLocation?.latitude,
          'delivery_lng': location.currentLocation?.longitude,
          'delivery_notes':
              _notesController.text.isEmpty ? null : _notesController.text,
          'payment_method': paymentMethod,
          'payment_status': 'pending',
          'razorpay_payment_id': null,
          'razorpay_order_id': null,
          'customer_phone': customerPhone,
          'shop_phone': shopPhones[shop.id],
          'gst_item_total': shopBreakdown.itemGstTotal,
          'gst_delivery': shopBreakdown.deliveryGst,
          'gst_platform': shopBreakdown.platformFeeGst,
          'enything_commission': shopBreakdown.enythingGrossCommission,
          'seller_payout': shopBreakdown.sellerPayoutNet,
          'gateway_deduction': shopBreakdown.gatewayDeduction,
          's9_5_gst_amount': shopS9_5Gst,
          'non_food_gst_amount': shopNonFoodGst,
          'tcs_amount': shopTcs,
          'tds_amount': shopTds,
          'grand_total_collected': math.max(
              0.0,
              shopGrandTotal - (appliedCouponDiscount * proportion)),
          'gst_rate_snapshot': rateSnapshot,
          'prescription_urls':
              shopItems.any((item) => item.product.requiresPrescription)
                  ? (uploadedShopPrescriptionUrls[shop.id] ?? [])
                  : [],
          'estimated_distance_km': shopDistanceKm,
          'shop_prep_time_snapshot': shop.prepTimeMinutes,
          'coupon_id': appliedCouponId,
          'coupon_discount':
              math.min(shopGrandTotal, appliedCouponDiscount * proportion),
        });

        final itemsToInsert = shopItems.map((item) {
          return {
            'id': const Uuid().v4(),
            'created_at': nowUtc,
            'order_id': orderId,
            'product_id': item.product.id,
            'product_name': item.product.name,
            'variant_name': item.selectedVariant?.name,
            'quantity': item.quantity,
            'price': item.selectedVariant?.price ?? item.product.price,
            'weight_kg': item.weightKg,
            'requires_prescription': item.product.requiresPrescription,
            'special_instructions': item.specialInstructions,
          };
        }).toList();
        allItems.addAll(itemsToInsert);

        notificationData.add({
          'shop': shop,
          'grandTotal': shopGrandTotal,
          'orderId': orderId,
        });
      }

      // Execute atomic transaction RPC
      await supabase.rpc('place_orders_transaction', params: {
        'p_orders': allOrders,
        'p_items': allItems,
        'p_cart_group_id': cartGroupId,
        'p_coupon_id': appliedCouponId,
        // BUG FIX (Issue 2b): When replacing a cancelled/rejected order in an
        // existing cart group, we MUST use a fresh UUID for the idempotency key.
        // The old key (= cartGroupId) is already taken by the cancelled order's
        // row in UNIQUE(idempotency_key, shop_id), causing a 23505 constraint
        // violation. A fresh UUID lets the new replacement order be inserted
        // cleanly while still using the SAME cartGroupId to link the group.
        'p_idempotency_key':
            isReplacementOrder ? const Uuid().v4() : cartGroupId,
        if (widget.orderIdToCancelOnSuccess != null || pendingCancelId != null)
          'p_order_id_to_cancel':
              widget.orderIdToCancelOnSuccess ?? pendingCancelId,
      });

      // Notify sellers AFTER successful atomic insertion
      if (mounted) {
        for (final data in notificationData) {
          context.read<NotificationProvider>().sendBackgroundPush(
            targetUserId: data['shop'].sellerId,
            title: '🔔 New Order!',
            body:
                'Order ₹${((data['grandTotal'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)} — Tap to accept. Customer pays AFTER you & rider accept. ⏱ 3 min window.',
            data: {
              'order_id': data['orderId'],
              'role': 'seller',
              'action': 'new_order',
            },
          );
        }
      }

      // ── Bug #3 FIX: Notify riders about the new order ────────────────────────
      // Dispatches push notification to online riders so their device buzzes
      // with enything_bell even when their app is killed.
      if (mounted) {
        final notifProv = context.read<NotificationProvider>();

        Future(() async {
          // FIX 1: Exclusive Rider Affinity check for replacement orders
          String? exclusiveRiderId;
          if (isReplacementOrder) {
            try {
              final activeOrder = await supabase
                  .from('orders')
                  .select('delivery_partner_id')
                  .eq('cart_group_id', cartGroupId)
                  .not('delivery_partner_id', 'is', null)
                  .limit(1)
                  .maybeSingle();
              if (activeOrder != null &&
                  activeOrder['delivery_partner_id'] != null) {
                exclusiveRiderId = activeOrder['delivery_partner_id'] as String;
              }
            } catch (e) {
              debugPrint('Error finding exclusive rider: $e');
            }
          }

          if (exclusiveRiderId != null) {
            final firstOrderId = notificationData.isNotEmpty
                ? (notificationData.first['orderId'] as String?)
                : null;
            notifProv.sendBackgroundPush(
              targetUserId: exclusiveRiderId,
              title: '🆕 Shop Replacement Added!',
              body:
                  'The customer replaced a shop in your active delivery! Open the app to accept it.',
              data: {
                'role': 'delivery',
                'action': 'new_order',
                if (firstOrderId != null) 'order_id': firstOrderId,
              },
            );
          } else {
            // Broadcast to all active delivery partners
            try {
              final firstOrderId = notificationData.isNotEmpty
                  ? (notificationData.first['orderId'] as String?)
                  : null;
              notifProv.sendBroadcastToAudience(
                audience: 'Riders',
                title: '🛵 New Order Available!',
                body:
                    'A new delivery order is waiting for acceptance. Tap to accept now!',
                data: {
                  'role': 'delivery',
                  'action': 'new_order',
                  if (firstOrderId != null) 'order_id': firstOrderId,
                },
              );
              debugPrint('Broadcasted new order notification to all Riders audience.');
            } catch (e) {
              debugPrint('Rider fallback broadcast error: $e');
            }
          }
        });
      }
      // ─────────────────────────────────────────────────────────────────────────

      // Fix 3: Mark partial rejection as resolved so TrackOrderPage hides the panel.      }
      // ─────────────────────────────────────────────────────────────────────────

      // Fix 3: Mark partial rejection as resolved so TrackOrderPage hides the panel.
      // Persisted in SharedPrefs so it survives banner-tap page recreations.
      if (isReplacementOrder && cartGroupId.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('partial_rejection_resolved_$cartGroupId', true);
          // Also stop the 5-min decision timer key so it doesn't restart on next load.
          await prefs.remove('partial_rejection_timer_start_$cartGroupId');
        } catch (e) {
          debugPrint('Non-critical: could not write resolved flag: $e');
        }
      }

      // Cleanup (Additive: avoid unmounted leaks and race conditions)
      await cart.clearAsync();
      couponProv.clearCoupon();

      if (!mounted) return;

      HapticUtils.success();

      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.trackOrder,
        (route) =>
            route.isFirst || route.settings.name == AppRoutes.customerHome,
        arguments: {'orderId': orderIds.first},
      );
    } catch (e) {
      debugPrint('Order placement error: $e');
      if (uploadedPaths.isNotEmpty) {
        try {
          await supabase.storage
              .from('prescription_docs')
              .remove(uploadedPaths);
        } catch (cleanupError) {
          debugPrint(
              'Failed to clean up uploaded prescriptions: $cleanupError');
        }
      }
      rethrow;
    } finally {
      _isCreatingOrder = false;
      if (mounted) _isProcessing.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cart = context.watch<CartProvider>();
    final location = context.watch<LocationProvider>();
    final couponProv = context.watch<CouponProvider>();

    double distanceKm = 3.0;
    if (location.currentLocation != null && cart.shops.isNotEmpty) {
      distanceKm = 0.0;
      for (var s in cart.shops) {
        final d = location.distanceTo(s.location);
        if (d > distanceKm) distanceKm = d;
      }
    }

    final baseCharge = cart.calculateDeliveryCharges(distanceKm);

    final isReplacementOrder = widget.existingCartGroupId != null ||
        context.read<CartProvider>().pendingCartGroupId != null;

    double surcharge = 0.0;
    double heavyFee = 0.0;
    double smallCartFee = 0.0;
    double effectiveBase = PlatformConfigProvider.instance?.deliveryBaseFee ??
        PaymentConfig.deliveryFee;

    if (isReplacementOrder) {
      effectiveBase = 0.0;
      final newUniqueShopIds = cart.shops
          .map((s) => s.id)
          .where((id) => !_activeShopIds.contains(id))
          .toSet();
      final totalShopsAtEnd = _activeShopIds.length + newUniqueShopIds.length;
      final flatSurchargeRate =
          PlatformConfigProvider.instance?.multiShopSurcharge ?? 20.0;
      final totalSurchargeAtEnd = totalShopsAtEnd > 1
          ? flatSurchargeRate * (totalShopsAtEnd - 1)
          : 0.0;

      final oldActiveCount = _activeShopIds.length;
      final expectedOldSurchargePaid = math.min(
          _activeSurchargePaid,
          oldActiveCount > 1
              ? flatSurchargeRate * (oldActiveCount - 1)
              : 0.0);

      surcharge =
          math.max(0.0, totalSurchargeAtEnd - expectedOldSurchargePaid);

      final smallCartThreshold =
          PlatformConfigProvider.instance?.smallCartThreshold ??
              PaymentConfig.smallCartThreshold;
      if ((_activeSubtotal + cart.subtotal) < smallCartThreshold &&
          (_activeSubtotal + cart.subtotal) > 0) {
        final standardSmallCartFee =
            PlatformConfigProvider.instance?.smallCartFee ??
                PaymentConfig.smallCartFee;
        smallCartFee = math.max(0, standardSmallCartFee - _activeSmallCartFee);
      }

      final heavyThreshold =
          PlatformConfigProvider.instance?.heavyOrderThresholdKg ??
              PaymentConfig.heavyOrderThreshold;
      final aggregateWeight = _activeWeight + cart.totalWeight;
      if (aggregateWeight > heavyThreshold) {
        final feePerKg = PlatformConfigProvider.instance?.heavyOrderFee ??
            PaymentConfig.heavyOrderFee;
        final aggregateHeavyFee =
            feePerKg * (aggregateWeight - heavyThreshold).ceil();
        heavyFee = math.max(0.0, aggregateHeavyFee - _activeHeavyOrderFee);
      }
    } else {
      effectiveBase = baseCharge >= 0
          ? baseCharge
          : (PlatformConfigProvider.instance?.deliveryBaseFee ??
              PaymentConfig.deliveryFee);
      surcharge = cart.multiShopSurcharge;
      heavyFee = cart.heavyOrderFee;
      smallCartFee = cart.smallCartFee;
    }

    final riderBase = effectiveBase + surcharge + heavyFee;
    // ADDITIVE FIX: Use DB-driven rider payout ratio instead of hardcoded 0.80.
    // To revert: replace with `riderBase * TaxConfig.riderPayoutRatio`
    final riderPayoutRatio =
        (PlatformConfigProvider.instance?.riderCommissionPercent ?? 80.0) /
            100.0;
    final riderEarnings = riderBase * riderPayoutRatio;

    // BUG-H3 FIX: Compute the breakdown ONCE so UI display and DB insertion
    // use the exact same figures.
    double totalWithoutGst =
        effectiveBase + surcharge + heavyFee + smallCartFee;
    if (totalWithoutGst < 0) totalWithoutGst = 0.0;
    double totalDelivery = totalWithoutGst * (1 + TaxConfig.deliveryGstRate);

    // ── ADD-ON GST model: GST is a real charge on top of base prices ─────────
    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      riderEarnings: riderEarnings,
      platformFee: isReplacementOrder ? 0.0 : cart.platformFee,
      paymentMethod: 'upi',
    );
    // Grand total = base items + item GST + delivery + platform - coupon discount
    final couponDiscount = couponProv.discountAmount;
    final total =
        (gstBreakdown.grandTotal - couponDiscount).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text('Checkout',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700))),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: MaxWidthContainer(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Delivery Address
                _sectionCard(
                  title: 'Delivery Address',
                  icon: Icons.location_on_outlined,
                  iconColor: AppColors.danger,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (location.activeLabel.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Text(location.activeLabelIcon,
                                      style: GoogleFonts.outfit(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(
                                    location.activeLabel,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              location.currentAddress.isEmpty
                                  ? 'Location not set'
                                  : location.currentAddress,
                              style: GoogleFonts.outfit(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (location.hasLocation)
                        Container(
                          height: 120,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: EnythingMap(
                              center: location.currentLocation!,
                              zoom: 15,
                              interactive: false,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => showAddressPickerSheet(context),
                            icon: const Icon(Icons.edit_location_alt_outlined,
                                size: 16),
                            label: const Text('Change Address'),
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                textStyle: GoogleFonts.outfit(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── ETA Banner ────────────────────────────────────────────────
                Builder(builder: (context) {
                  // Compute max distance and max prep time across all shops
                  double maxDist = 3.0;
                  int maxPrep = 30;
                  if (location.currentLocation != null &&
                      cart.shops.isNotEmpty) {
                    for (final s in cart.shops) {
                      final d = location.distanceTo(s.location);
                      if (d > maxDist) maxDist = d;
                      if (s.prepTimeMinutes > maxPrep) {
                        maxPrep = s.prepTimeMinutes;
                      }
                    }
                  }
                  final etaStr = DeliveryCalculator.etaLabel(maxDist, maxPrep);
                  final arrivalStr =
                      DeliveryCalculator.etaArrivalTime(maxDist, maxPrep);
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.primary.withValues(alpha: 0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.access_time_rounded,
                              color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estimated Delivery',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      AppColors.primary.withValues(alpha: 0.7),
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                etaStr,
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Arrives by',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              arrivalStr,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),

                // Order Items
                _sectionCard(
                  title: 'Order Summary',
                  icon: Icons.receipt_long_outlined,
                  iconColor: AppColors.primary,
                  child: Column(
                    children: [
                      ...cart.items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: item.product.isVeg == true
                                        ? AppColors.vegGreen
                                        : AppColors.nonVegRed,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${item.quantity}x ${item.product.name}',
                                    style: GoogleFonts.outfit(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '₹${item.totalPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                // ── 100x Multi-Shop Targeted Prescription Section ───────────────
                _buildPrescriptionSection(cart),
                const SizedBox(height: 16),

                // ── Coupon / Promo Code ──────────────────────────────────────────
                CouponInputWidget(cartTotal: cart.subtotal),
                const SizedBox(height: 16),

                // Delivery Instructions
                _sectionCard(
                  title: 'Delivery Instructions',
                  icon: Icons.delivery_dining_outlined,
                  iconColor: AppColors.info,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildInstructionChip('🔕 Do not ring bell'),
                            const SizedBox(width: 8),
                            _buildInstructionChip('🚪 Leave at door'),
                            const SizedBox(width: 8),
                            _buildInstructionChip('📞 Call before arriving'),
                            const SizedBox(width: 8),
                            _buildInstructionChip('🐕 Beware of pets'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1E1E2E)
                              : const Color(0xFFF8F9FE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white10
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Add landmark or gate instructions...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Payment Info (no selector — always online, charged after acceptance)
                _sectionCard(
                  title: 'Payment',
                  icon: Icons.lock_outline_rounded,
                  iconColor: AppColors.success,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_outlined,
                            color: AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pay after confirmation',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              'No money is charged now. Payment via UPI/Card is only requested after the shop & rider both accept your order.',
                              style: GoogleFonts.outfit(
                                  fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _sectionCard(
                  title: 'Bill Details',
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: AppColors.success,
                  child: Column(
                    children: [
                      _billRow(
                        'Item Subtotal',
                        '₹${cart.subtotal.toStringAsFixed(2)}',
                        hint: 'Base price (excl. GST)',
                      ),
                      const SizedBox(height: 8),
                      // Delivery row
                      _billRow(
                        'Delivery Fee',
                        '₹${effectiveBase.toStringAsFixed(0)}',
                      ),

                      if (smallCartFee > 0) ...[
                        const SizedBox(height: 8),
                        _billRow(
                          'Small Cart Fee',
                          '+₹${smallCartFee.toStringAsFixed(0)}',
                          hint:
                              'For orders under ₹${PlatformConfigProvider.instance?.smallCartThreshold.toInt() ?? PaymentConfig.smallCartThreshold.toInt()}',
                          valueColor: Colors.orange.shade700,
                        ),
                      ],
                      if (heavyFee > 0) ...[
                        const SizedBox(height: 8),
                        _billRow(
                          'Heavy Order Fee',
                          '+₹${heavyFee.toStringAsFixed(0)}',
                          hint:
                              'For orders over ${PlatformConfigProvider.instance?.heavyOrderThresholdKg.toInt() ?? PaymentConfig.heavyOrderThreshold.toInt()} kg',
                          valueColor: Colors.orange.shade700,
                        ),
                      ],
                      if (surcharge > 0) ...[
                        const SizedBox(height: 8),
                        _billRow(
                          'Multi-shop fee (${cart.shops.length} shops)',
                          '+₹${surcharge.toStringAsFixed(0)}',
                          valueColor: Colors.orange.shade700,
                          hint:
                              '₹${(PlatformConfigProvider.instance?.multiShopSurcharge ?? 20).toInt()} per additional shop',
                        ),
                      ],
                      const SizedBox(height: 8),
                      _billRow(
                        'Handling Fee',
                        '+₹${(cart.platformFee - gstBreakdown.platformFeeGst).toStringAsFixed(2)}',
                        hint: 'Covers payment gateway & app operations',
                      ),
                      if (gstBreakdown.totalGst > 0) ...[
                        const SizedBox(height: 8),
                        _billRow(
                          'TOTAL GST',
                          '+₹${gstBreakdown.totalGst.toStringAsFixed(2)}',
                          hint: 'Govt. taxes on items & services',
                          valueColor: const Color(0xFF1565C0),
                        ),
                      ],
                      if (couponDiscount > 0) ...[
                        const SizedBox(height: 8),
                        _billRow(
                          'Promo (${couponProv.appliedCoupon!.code})',
                          '-₹${couponDiscount.toStringAsFixed(2)}',
                          valueColor: AppColors.success,
                        ),
                      ],
                      const Divider(height: 20),
                      _billRow(
                        'Grand Total',
                        '₹${total.toStringAsFixed(2)}',
                        isBold: true,
                        valueColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: MaxWidthContainer(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Amount',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 13)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${total.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        if (gstBreakdown.totalGst > 0)
                          Text(
                            'Incl. ₹${gstBreakdown.totalGst.toStringAsFixed(2)} Total GST',
                            style: GoogleFonts.outfit(
                                fontSize: 10, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<bool>(
                  valueListenable: _isProcessing,
                  builder: (context, isProcessing, _) {
                    return SlideToAction(
                      label: 'Slide to Place Order • ₹${total.toStringAsFixed(0)}',
                      onConfirmed: _placeOrder,
                      isLoading: isProcessing,
                      enabled: !isProcessing,
                      isDark: isDark,
                      activeTrackColor: AppColors.secondary,
                      height: 56,
                      borderRadius: 16,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 100x Multi-Shop Targeted Prescription UI ─────────────────────────────
  Widget _buildPrescriptionSection(CartProvider cart) {
    final rxShops = cart.shops.where((s) {
      return cart.getItemsForShop(s.id).any((i) => i.product.requiresPrescription);
    }).toList();

    if (rxShops.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMultiShop = rxShops.length > 1;

    return _sectionCard(
      title: isMultiShop
          ? 'Upload Prescriptions (${rxShops.length} Pharmacies)'
          : 'Upload Prescription',
      icon: Icons.medical_information_outlined,
      iconColor: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Under Govt of India Drugs & Cosmetics rules, a valid doctor\'s prescription is required before pharmacies can legally dispense these medications.',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (isMultiShop) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_alt_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use 1 prescription for all pharmacies',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _applyToAllPharmacies,
                    activeTrackColor: AppColors.primary,
                    onChanged: (val) {
                      HapticUtils.selection();
                      setState(() => _applyToAllPharmacies = val);
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (isMultiShop && !_applyToAllPharmacies)
            Column(
              children: [
                for (int i = 0; i < rxShops.length; i++)
                  _buildSingleShopRxCard(rxShops[i], cart, isDark),
              ],
            )
          else
            _buildRxUploadGallery(
              shopId: '__ALL__',
              files: _shopPrescriptions['__ALL__'] ?? [],
              isDark: isDark,
              hintLabel: isMultiShop
                  ? 'Tap to upload prescription covering all stores'
                  : 'Tap to upload prescription\n(Clear & readable image)',
            ),
        ],
      ),
    );
  }

  Widget _buildSingleShopRxCard(ShopModel shop, CartProvider cart, bool isDark) {
    final rxItems = cart.getItemsForShop(shop.id).where((i) => i.product.requiresPrescription).toList();
    final files = _shopPrescriptions[shop.id] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: files.isNotEmpty
              ? AppColors.success.withValues(alpha: 0.6)
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          width: files.isNotEmpty ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_pharmacy_outlined,
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shop.name,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              if (files.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${files.length} Attached',
                    style: GoogleFonts.outfit(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Requires Rx for: ${rxItems.map((i) => i.product.name).join(", ")}',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          _buildRxUploadGallery(
            shopId: shop.id,
            files: files,
            isDark: isDark,
            hintLabel: 'Upload prescription for ${shop.name}',
          ),
        ],
      ),
    );
  }

  Widget _buildRxUploadGallery({
    required String shopId,
    required List<XFile> files,
    required bool isDark,
    required String hintLabel,
  }) {
    if (files.isEmpty) {
      return GestureDetector(
        onTap: () => _pickPrescription(shopId: shopId),
        child: Container(
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_photo_alternate_outlined,
                  color: AppColors.primary, size: 28),
              const SizedBox(height: 6),
              Text(
                hintLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: files.length + 1,
        itemBuilder: (context, index) {
          if (index == files.length) {
            return GestureDetector(
              onTap: () => _pickPrescription(shopId: shopId),
              child: Container(
                width: 90,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.add, color: AppColors.primary),
                ),
              ),
            );
          }
          return Stack(
            children: [
              Container(
                width: 90,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: FileImage(File(files[index].path)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 12,
                child: GestureDetector(
                  onTap: () => _removePrescription(shopId, index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInstructionChip(String text) {
    final isSelected = _notesController.text.contains(text);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        setState(() {
          if (isSelected) {
            _notesController.text = _notesController.text
                .replaceAll(text, '')
                .replaceAll(', ,', ',')
                .trim();
            if (_notesController.text.startsWith(',')) {
              _notesController.text = _notesController.text.substring(1).trim();
            }
            if (_notesController.text.endsWith(',')) {
              _notesController.text =
                  _notesController.text.substring(0, _notesController.text.length - 1).trim();
            }
          } else {
            if (_notesController.text.trim().isEmpty) {
              _notesController.text = text;
            } else {
              _notesController.text = '${_notesController.text.trim()}, $text';
            }
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? AppColors.primary
                : (isDark ? Colors.white : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _billRow(String label, String value,
      {bool isBold = false, Color? valueColor, String? hint}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: isBold
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: isBold ? 15 : 13,
                    fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                  )),
              if (hint != null)
                Text(hint,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    )),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: isBold ? 17 : 13,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              )),
        ),
      ],
    );
  }
}
