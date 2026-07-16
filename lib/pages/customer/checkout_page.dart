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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../config/payment_config.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../utils/responsive_layout.dart';
import '../../services/image_compression_service.dart';
import '../../utils/delivery_calculator.dart';
import '../../providers/coupon_provider.dart';
import 'dart:math' as math;

import '../../widgets/coupon_input_widget.dart';

class CheckoutPage extends StatefulWidget {
  final String? existingCartGroupId;
  final String? orderIdToCancelOnSuccess;
  final int activeOrdersCount;

  const CheckoutPage({super.key, this.existingCartGroupId, this.orderIdToCancelOnSuccess, this.activeOrdersCount = 0});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  bool _isCreatingOrder =
      false; // O1 FIX: Idempotency lock — prevents duplicate order creation
  final _notesController = TextEditingController();
  final List<XFile> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateStockPreCheckout();
    });
  }

  Future<void> _validateStockPreCheckout() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    try {
      final productIds = cart.items.map((i) => i.product.id).toList();
      // Phase 25 Fix: Deep join with shops to verify shop is still active, and fetch variants/price to check spoofing.
      final latestProducts = await Supabase.instance.client
          .from('products')
          .select('id, name, price, variants, is_available, total_quantity, shops(id, name, is_active)')
          .inFilter('id', productIds);

      final issues = <String>[];

      // Aggregated Inventory Guard to prevent Quantity Accumulation Bypass
      final Map<String, int> productQtyMap = {};
      for (var item in cart.items) {
         productQtyMap[item.product.id] = (productQtyMap[item.product.id] ?? 0) + item.quantity;
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
        if (dbProduct['shops'] != null && dbProduct['shops']['is_active'] == false) {
          issues.add("${dbProduct['shops']['name']} is currently not accepting orders.");
          continue;
        }

        // 2. Availability Guard
        if (dbProduct['is_available'] == false) {
          issues.add("${cartItem.product.name} is currently out of stock.");
          continue;
        }
        
        // 3. Stock Quantity Guard
        final totalRequestedQty = productQtyMap[cartItem.product.id] ?? cartItem.quantity;
        if (dbProduct['total_quantity'] != null &&
            dbProduct['total_quantity'] < totalRequestedQty) {
          issues.add("Only ${dbProduct['total_quantity']} total units of ${cartItem.product.name} are available, but you have $totalRequestedQty in your cart.");
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
                  issues.add("Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is out of stock.");
                }
                variantFound = true;
                break;
              }
            }
          }
          if (!variantFound) {
             issues.add("Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is no longer available.");
             continue;
          }
        }
        
        double cartPrice = cartItem.selectedVariant?.price ?? cartItem.product.price;
        if ((freshPrice - cartPrice).abs() > 0.01) {
           issues.add("Price changed for ${cartItem.product.name} (from ₹${cartPrice.toStringAsFixed(0)} to ₹${freshPrice.toStringAsFixed(0)}).");
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
  Future<void> _pickPrescription() async {
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

    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(source: source, imageQuality: 70);
      _isPickerOpen = false;
      if (picked != null) {
        setState(() {
          _prescriptions.add(picked);
        });
      }
    } else {
      final picked = await picker.pickMultiImage(imageQuality: 70);
      _isPickerOpen = false;
      if (picked.isNotEmpty) {
        setState(() {
          _prescriptions.addAll(picked);
        });
      }
    }
  }

  void _removePrescription(int index) {
    setState(() => _prescriptions.removeAt(index));
  }

  // ── Step 1: Save order as awaiting_acceptance (NO payment yet) ────────────
  // Payment is triggered ONLY after BOTH seller AND rider accept (within 1 min).
  Future<void> _placeOrder() async {
    _isProcessing.value = true;
    final cart = context.read<CartProvider>();
    final location = context.read<LocationProvider>();

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Your cart is empty!'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _isProcessing.value = false;
      return;
    }

    // Prescription guard
    if (cart.requiresPrescription && _prescriptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Please upload a prescription to order these medicines.',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      _isProcessing.value = false;
      return;
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
            content: Text('Failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
            margin: const EdgeInsets.all(16),
          ),
        );
        _isProcessing.value = false;
      }
    }
  }

  // Verification & payment completion is now handled in TrackOrderPage.

  // ── Save order as 'awaiting_acceptance' — NO payment charged yet ──────────
  // Financial snapshot is stored immediately for transparency.
  // Razorpay is only opened from TrackOrderPage when both seller & rider accept.
  Future<void> _createOrderInDb() async {
    // O1 FIX: Hard idempotency lock — reject concurrent invocations
    if (_isCreatingOrder) return;
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
         throw Exception("Your cart total has changed and the coupon '$code' is no longer valid or its discount amount has been adjusted. Please review your cart and try again.");
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
          throw Exception("Self-Dealing Blocked: You cannot place orders on your own shop (${shop.name}).");
        }
      }

      // Stock Validation
      final productIds = cart.items.map((i) => i.product.id).toList();
      // Phase 25 Fix: Deep join with shops to verify shop is still active, and fetch variants/price to check spoofing.
      final latestProducts = await supabase
          .from('products')
          .select('id, name, price, variants, is_available, total_quantity, shops(id, name, is_active)')
          .inFilter('id', productIds);

      // Aggregated Inventory Guard to prevent Quantity Accumulation Bypass
      final Map<String, int> productQtyMap = {};
      for (var item in cart.items) {
         productQtyMap[item.product.id] = (productQtyMap[item.product.id] ?? 0) + item.quantity;
      }

      for (var cartItem in cart.items) {
        final dbProduct = latestProducts
            .where((p) => p['id'] == cartItem.product.id)
            .firstOrNull;
            
        if (dbProduct == null) {
          throw Exception("${cartItem.product.name} is no longer available.");
        }
        
        // 1. Ghost Kitchens II (Banned Shop Checkout) Guard
        if (dbProduct['shops'] != null && dbProduct['shops']['is_active'] == false) {
          throw Exception("${dbProduct['shops']['name']} is currently not accepting orders.");
        }

        // 2. Availability Guard
        if (dbProduct['is_available'] == false) {
          throw Exception("${cartItem.product.name} is currently out of stock.");
        }
        
        // 3. Stock Quantity Guard
        final totalRequestedQty = productQtyMap[cartItem.product.id] ?? cartItem.quantity;
        if (dbProduct['total_quantity'] != null &&
            dbProduct['total_quantity'] < totalRequestedQty) {
          throw Exception("Only ${dbProduct['total_quantity']} total units of ${cartItem.product.name} are available, but you have $totalRequestedQty in your cart.");
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
                  throw Exception("Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is out of stock.");
                }
                variantFound = true;
                break;
              }
            }
          }
          if (!variantFound) {
             throw Exception("Variant ${cartItem.selectedVariant!.name} for ${cartItem.product.name} is no longer available.");
          }
        }
        
        double cartPrice = cartItem.selectedVariant?.price ?? cartItem.product.price;
        if ((freshPrice - cartPrice).abs() > 0.01) {
           throw Exception("The price of ${cartItem.product.name} has changed from ₹${cartPrice.toStringAsFixed(0)} to ₹${freshPrice.toStringAsFixed(0)}. Please review your cart.");
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
      
      // 100x ARCHITECTURE STRESS-TEST FIX: Free Replacement Delivery
      final isFreeReplacement = widget.activeOrdersCount > 0;
      
      final surcharge = isFreeReplacement ? 0.0 : cart.multiShopSurcharge;
      final heavyFee = isFreeReplacement ? 0.0 : cart.heavyOrderFee;
      final smallCartFee = isFreeReplacement ? 0.0 : cart.smallCartFee;
      final effectiveBase = isFreeReplacement ? 0.0 : (baseDelivery >= 0 ? baseDelivery : 25.0);
      final riderBase = effectiveBase + surcharge + heavyFee;
      final riderEarnings = riderBase * TaxConfig.riderPayoutRatio;

      double totalDelivery = isFreeReplacement ? 0.0 : cart.totalDeliveryCharges(maxDistanceKm);

      // Payment method is always 'upi' now (COD removed)
      const paymentMethod = 'upi';

      final cartGroupId = widget.existingCartGroupId ?? const Uuid().v4();
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

      List<String> uploadedPrescriptionUrls = [];
      if (cart.requiresPrescription && _prescriptions.isNotEmpty) {
        for (int i = 0; i < _prescriptions.length; i++) {
          final file = _prescriptions[i];
          final bytes =
              await ImageCompressionService.compressFile(File(file.path)) ??
                  await file.readAsBytes();
          const ext = 'jpg'; // Compressformat is jpeg
          final path = '${auth.currentUserId}/${cartGroupId}_$i.$ext';

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
                    'Failed to upload prescription image after 3 attempts. Please check your connection and try again.');
              }
              await Future.delayed(Duration(seconds: retries * 2));
            }
          }
          uploadedPaths.add(path);
          uploadedPrescriptionUrls.add(
              supabase.storage.from('prescription_docs').getPublicUrl(path));
        }
      }

      final List<Map<String, dynamic>> allOrders = [];
      final List<Map<String, dynamic>> allItems = [];
      final List<String> orderIds = [];
      final List<Map<String, dynamic>> notificationData = [];

      final nowUtc = DateTime.now().toUtc().toIso8601String();

      bool isTestPhone(String? phone) {
        if (phone == null) return false;
        final envPhones = dotenv.env['TEST_PHONES']?.split(',') ??
            ['9999999996', '9999999997', '9999999998'];
        return envPhones.any((p) => phone.endsWith(p.trim()));
      }

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

        final distanceProportion = totalCartDistanceKm > 0
            ? (shopDistanceKm / totalCartDistanceKm)
            : (1.0 / numShops);

        // Splitting by distance prevents the "Ghost Rider Scam"
        final shopDelivery = totalDelivery * distanceProportion;
        final shopRiderEarnings = riderEarnings * distanceProportion;
        
        // Platform fee is still split by food value
        final shopPlatformFee = cart.platformFee * proportion;

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

        // ── GST TCS (CGST §52) — Category-Precise ───────────────────────────
        double shopTcs = 0.0;
        for (final item in shopItems) {
          final cat = item.product.category;
          final itemBase = (item.selectedVariant?.price ?? item.product.price) *
              item.quantity;
          shopTcs += itemBase * TaxConfig.tcsRateForCategory(cat);
        }

        // ── Income Tax TDS (§194-O, Finance Act 2024) — Universal 0.1% ─────
        final shopTds = shopBaseSubtotal * TaxConfig.itTdsRate;
        final shopGrandTotal = shopBreakdown.grandTotal;

        final orderId = const Uuid().v4();
        orderIds.add(orderId);

        final isMagic = isTestPhone(auth.user?.phone);

        allOrders.add({
          'id': orderId,
          'created_at': nowUtc,
          'updated_at': nowUtc,
          'cart_group_id': cartGroupId,
          'shop_id': shop.id,
          'customer_id': auth.currentUserId,
          'status': isMagic ? 'awaiting_payment' : 'awaiting_acceptance',
          'seller_accepted': isMagic ? true : false,
          'partner_accepted': isMagic ? true : false,
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
          'seller_payout': shopBreakdown.sellerPayout - shopTcs - shopTds,
          'gateway_deduction': shopBreakdown.gatewayDeduction,
          's9_5_gst_amount': shopS9_5Gst,
          'non_food_gst_amount': shopNonFoodGst,
          'tcs_amount': shopTcs,
          'tds_amount': shopTds,
          'grand_total_collected':
              math.max(0.0, shopGrandTotal - (appliedCouponDiscount * proportion)),
          'gst_rate_snapshot': rateSnapshot,
          'prescription_urls': uploadedPrescriptionUrls,
          'estimated_distance_km': shopDistanceKm,
          'shop_prep_time_snapshot': shop.prepTimeMinutes,
          'coupon_id': appliedCouponId,
          'coupon_discount': math.min(shopGrandTotal, appliedCouponDiscount * proportion),
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
          'isMagic': isMagic,
        });
      }

      // Execute atomic transaction RPC
      await supabase.rpc('place_orders_transaction', params: {
        'p_orders': allOrders,
        'p_items': allItems,
        'p_cart_group_id': cartGroupId,
        'p_coupon_id': appliedCouponId,
        'p_idempotency_key': cartGroupId,
        if (widget.orderIdToCancelOnSuccess != null)
          'p_order_id_to_cancel': widget.orderIdToCancelOnSuccess,
      });

      // Notify sellers AFTER successful atomic insertion
      if (mounted) {
        for (final data in notificationData) {
          if (!data['isMagic']) {
            context.read<NotificationProvider>().sendBackgroundPush(
              targetUserId: data['shop'].sellerId,
              title: '🔔 New Order! Accept now',
              body:
                  'Order ₹${(data['grandTotal'] as double).toStringAsFixed(0)} — Tap to accept. Customer pays AFTER you & rider accept. ⏱ 3 min window.',
              data: {'order_id': data['orderId'], 'role': 'seller'},
            );
          }
        }
      }
      
      // 100x Edge Case: Cancel old order logic has been moved INTO place_orders_transaction above for 100% atomicity.

      // Cleanup
      cart.clear();
      if (!mounted) return;
      context.read<CouponProvider>().clearCoupon();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.trackOrder,
          (route) => route.settings.name == AppRoutes.customerHome,
          arguments: {'orderId': orderIds.first},
        );
      }
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
    
    final isFreeReplacement = widget.activeOrdersCount > 0;
    
    final surcharge = isFreeReplacement ? 0.0 : cart.multiShopSurcharge;
    final heavyFee = isFreeReplacement ? 0.0 : cart.heavyOrderFee;
    final smallCartFee = isFreeReplacement ? 0.0 : cart.smallCartFee;
    final effectiveBase = isFreeReplacement ? 0.0 : (baseCharge >= 0 ? baseCharge : 25.0);
    final riderBase = effectiveBase + surcharge + heavyFee;
    final riderEarnings = riderBase * TaxConfig.riderPayoutRatio;

    // BUG-H3 FIX: Compute the breakdown ONCE so UI display and DB insertion
    // use the exact same figures.
    double totalDelivery = isFreeReplacement ? 0.0 : cart.totalDeliveryCharges(distanceKm);

    // ── ADD-ON GST model: GST is a real charge on top of base prices ─────────
    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      riderEarnings: riderEarnings,
      platformFee: cart.platformFee,
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
                if (cart.requiresPrescription) ...[
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: 'Upload Prescription',
                    icon: Icons.medical_information_outlined,
                    iconColor: AppColors.danger,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your order contains medicines that require a valid doctor\'s prescription under Govt of India norms. Please upload it here.',
                          style: GoogleFonts.outfit(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        if (_prescriptions.isEmpty)
                          GestureDetector(
                            onTap: _pickPrescription,
                            child: Container(
                              width: double.infinity,
                              height: 120,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    style: BorderStyle.solid),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_photo_alternate_outlined,
                                      color: AppColors.primary, size: 32),
                                  const SizedBox(height: 8),
                                  Text(
                                      'Tap to upload prescription\n(Clear & readable image)',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _prescriptions.length + 1,
                              itemBuilder: (context, index) {
                                if (index == _prescriptions.length) {
                                  return GestureDetector(
                                    onTap: _pickPrescription,
                                    child: Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: const Center(
                                          child: Icon(Icons.add,
                                              color: AppColors.primary)),
                                    ),
                                  );
                                }
                                return Stack(
                                  children: [
                                    Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        image: DecorationImage(
                                            image: FileImage(File(
                                                _prescriptions[index].path)),
                                            fit: BoxFit.cover),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: () => _removePrescription(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 14),
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
                  ),
                ],
                const SizedBox(height: 16),

                // ── Coupon / Promo Code ──────────────────────────────────────────
                CouponInputWidget(cartTotal: cart.subtotal),
                const SizedBox(height: 16),

                // Delivery Notes
                _sectionCard(
                  title: 'Delivery Notes',
                  icon: Icons.note_alt_outlined,
                  iconColor: AppColors.info,
                  child: TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Add any special instructions...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
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
                        isFreeReplacement ? 'Delivery (Replacement)' : 'Delivery Fee',
                        isFreeReplacement ? 'Free' : '₹${effectiveBase.toStringAsFixed(0)}',
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
                          hint: '₹${(PlatformConfigProvider.instance?.deliveryRatePerKm ?? 10).toInt()}/km between shops',
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
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: AppColors.ctaGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isProcessing,
                    builder: (context, isProcessing, _) {
                      return ElevatedButton(
                        onPressed: isProcessing ? null : _placeOrder,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(
                                'CONFIRM ORDER',
                                style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    height: 1.2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
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
                    color:
                        isBold ? AppColors.textPrimary : AppColors.textSecondary,
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
