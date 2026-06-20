import 'package:flutter/material.dart';
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
import '../../config/payment_config.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../utils/responsive_layout.dart';
import '../../services/image_compression_service.dart';
import '../../utils/delivery_calculator.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool _isProcessing = false;
  final _notesController = TextEditingController();
  final List<XFile> _prescriptions = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // No Razorpay callbacks here — payment is triggered from TrackOrderPage
  // after both seller & rider accept the order.

  Future<void> _pickPrescription() async {
    final picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage(imageQuality: 70);
    if (picked.isNotEmpty) {
      setState(() {
        _prescriptions.addAll(picked);
      });
    }
  }

  void _removePrescription(int index) {
    setState(() => _prescriptions.removeAt(index));
  }

  // ── Step 1: Save order as awaiting_acceptance (NO payment yet) ────────────
  // Payment is triggered ONLY after BOTH seller AND rider accept (within 1 min).
  Future<void> _placeOrder() async {
    setState(() => _isProcessing = true);
    final cart = context.read<CartProvider>();
    final location = context.read<LocationProvider>();

    // Prescription guard
    if (cart.requiresPrescription && _prescriptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'A valid prescription is required for medicines in your cart.'),
            backgroundColor: AppColors.danger),
      );
      setState(() => _isProcessing = false);
      return;
    }

    if (!location.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please set your delivery location first.'),
            backgroundColor: AppColors.danger),
      );
      setState(() => _isProcessing = false);
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
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  // Verification & payment completion is now handled in TrackOrderPage.

  // ── Save order as 'awaiting_acceptance' — NO payment charged yet ──────────
  // Financial snapshot is stored immediately for transparency.
  // Razorpay is only opened from TrackOrderPage when both seller & rider accept.
  Future<void> _createOrderInDb() async {
    final cart = context.read<CartProvider>();
    final auth = context.read<AuthProvider>();
    final location = context.read<LocationProvider>();
    final supabase = Supabase.instance.client;

    try {
      // Stock Validation
      final productIds = cart.items.map((i) => i.product.id).toList();
      final latestProducts = await supabase.from('products').select('id, name, is_available, total_quantity').inFilter('id', productIds);
      
      for (var cartItem in cart.items) {
        final dbProduct = latestProducts.where((p) => p['id'] == cartItem.product.id).firstOrNull;
        if (dbProduct == null) {
          throw Exception("\${cartItem.product.name} is no longer available.");
        }
        if (dbProduct['is_available'] == false) {
          throw Exception("\${cartItem.product.name} is currently out of stock.");
        }
        if (dbProduct['total_quantity'] != null && dbProduct['total_quantity'] < cartItem.quantity) {
          throw Exception("Only \${dbProduct['total_quantity']} units of \${cartItem.product.name} are available.");
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
      final surcharge = cart.multiShopSurcharge;
      final heavyFee = cart.heavyOrderFee;
      final smallCartFee = cart.smallCartFee;
      final deliveryDiscount = cart.calculateDeliveryDiscount(maxDistanceKm);
      final effectiveBase = baseDelivery >= 0 ? baseDelivery : 25.0;
      final riderBase = effectiveBase + surcharge + heavyFee;
      final riderEarnings = riderBase * TaxConfig.riderPayoutRatio;
      final totalDelivery = cart.totalDeliveryCharges(maxDistanceKm);

      // Payment method is always 'upi' now (COD removed)
      const paymentMethod = 'upi';

      final cartGroupId = const Uuid().v4();
      final numShops = cart.shops.length;

      // Acceptance deadline: 2 minutes from now (enforces 2-minute cancellation rule)
      final acceptanceDeadline =
          DateTime.now().toUtc().add(const Duration(minutes: 2));

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
          final bytes = await ImageCompressionService.compressFile(File(file.path)) ?? await file.readAsBytes();
          const ext = 'jpg'; // Compressformat is jpeg
          final path = '${auth.currentUserId}/${cartGroupId}_$i.$ext';
          await supabase.storage
              .from('prescription_docs')
              .uploadBinary(path, bytes);
          uploadedPrescriptionUrls.add(
              supabase.storage.from('prescription_docs').getPublicUrl(path));
        }
      }

      final List<String> orderIds = [];

      for (final shop in cart.shops) {
        final shopItems = cart.items.where((i) => i.shop.id == shop.id).toList();
        final shopBaseSubtotal = shopItems.fold(0.0, (sum, i) => sum + i.totalPrice);

        double shopDistanceKm = 3.0;
        if (location.currentLocation != null) {
          shopDistanceKm = location.distanceTo(shop.location);
        }

        final shopDelivery = totalDelivery / numShops;
        final shopRiderEarnings = riderEarnings / numShops;
        final shopPlatformFee = cart.platformFee / numShops;

        final shopTaxBreakdownItems = shopItems.map((i) => {
          'category': i.product.category,
          'price': i.product.price,
          'quantity': i.quantity,
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
          if (!rateSnapshot.containsKey(cat)) {
            rateSnapshot[cat] = PlatformConfigProvider.instance?.getGstRate(
                  cat,
                  itemPrice: item.product.price,
                ) ??
                TaxConfig.gstRateForCategory(cat, itemPrice: item.product.price);
          }
        }

        final shopS9_5Gst = shopBreakdown.s9_5GstToRemit;
        final shopNonFoodGst = shopBreakdown.nonFoodGstPassThrough;

        final shopTcs = shopBaseSubtotal * 0.01;
        final shopGrandTotal = shopBreakdown.grandTotal;

        final orderResponse = await supabase
            .from('orders')
            .insert({
              'cart_group_id': cartGroupId,
              'shop_id': shop.id,
              'customer_id': auth.currentUserId,
              // NEW STATUS — no money charged yet
              'status': 'awaiting_acceptance',
              'acceptance_deadline': acceptanceDeadline.toIso8601String(),
              'total_amount': shopBaseSubtotal,
              'delivery_charges': shopDelivery,
              'rider_earnings': shopRiderEarnings,
              'multi_shop_surcharge': surcharge / numShops,
              'small_cart_fee': smallCartFee / numShops,
              'heavy_order_fee': heavyFee / numShops,
              'delivery_discount': deliveryDiscount / numShops,
              'platform_fee': shopPlatformFee,
              'address': location.currentAddress,
              'delivery_lat': location.currentLocation?.latitude,
              'delivery_lng': location.currentLocation?.longitude,
              'delivery_notes':
                  _notesController.text.isEmpty ? null : _notesController.text,
              'payment_method': paymentMethod,
              'payment_status': 'pending',    // not captured yet
              'razorpay_payment_id': null,
              'razorpay_order_id': null,
              'customer_phone': customerPhone,
              'shop_phone': shopPhones[shop.id],
              'gst_item_total': shopBreakdown.itemGstTotal,
              'gst_delivery': shopBreakdown.deliveryGst,
              'gst_platform': shopBreakdown.platformFeeGst,
              'enything_commission': shopBreakdown.enythingGrossCommission,
              'seller_payout': shopBreakdown.sellerPayout - shopTcs,
              'gateway_deduction': shopBreakdown.gatewayDeduction,
              's9_5_gst_amount': shopS9_5Gst,
              'non_food_gst_amount': shopNonFoodGst,
              'tcs_amount': shopTcs,
              'grand_total_collected': shopGrandTotal,
              'gst_rate_snapshot': rateSnapshot,
              'prescription_urls': uploadedPrescriptionUrls,
              'estimated_distance_km': shopDistanceKm,
              'shop_prep_time_snapshot': shop.prepTimeMinutes,
            })
            .select()
            .single();

        final orderId = orderResponse['id'];
        orderIds.add(orderId);

        final itemsToInsert = shopItems
            .map((item) => {
                  'order_id': orderId,
                  'product_id': item.product.id,
                  'product_name': item.product.name,
                  'quantity': item.quantity,
                  'price': item.product.price,
                  'weight_kg': item.weightKg,
                  // BUG-23 FIX: Persist prescription flag so seller knows
                  // which item requires a valid prescription.
                  'requires_prescription': item.product.requiresPrescription,
                  'special_instructions': item.specialInstructions,
                })
            .toList();
        await supabase.from('order_items').insert(itemsToInsert);

        // Notify seller: payment NOT charged yet — safe to accept or decline
        if (mounted) {
          context.read<NotificationProvider>().sendBackgroundPush(
                targetUserId: shop.sellerId,
                title: '🔔 New Order! Accept now',
                body:
                    'Order ₹${shopGrandTotal.toStringAsFixed(0)} — Tap to accept. Customer pays AFTER you & rider accept. ⏱ 2 min window.',
                data: {'order_id': orderId, 'role': 'seller'},
              );
        }
      }



      cart.clear();
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
      rethrow;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final location = context.watch<LocationProvider>();

    double distanceKm = 3.0;
    if (location.currentLocation != null && cart.shops.isNotEmpty) {
      for (var s in cart.shops) {
        final d = location.distanceTo(s.location);
        if (d > distanceKm) distanceKm = d;
      }
    }

    final baseCharge = cart.calculateDeliveryCharges(distanceKm);
    final surcharge = cart.multiShopSurcharge;
    final heavyFee = cart.heavyOrderFee;
    final discount = cart.calculateDeliveryDiscount(distanceKm);
    final effectiveBase = baseCharge >= 0 ? baseCharge : 25.0;
    final totalDelivery = cart.totalDeliveryCharges(distanceKm);
    final riderBase = effectiveBase + surcharge + heavyFee;
    final riderEarnings = riderBase * TaxConfig.riderPayoutRatio;

    // ── ADD-ON GST model: GST is a real charge on top of base prices ─────────
    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      riderEarnings: riderEarnings,
      platformFee: cart.platformFee,
      paymentMethod: 'upi',
    );
    // Grand total = base items + item GST + delivery + platform
    final total = gstBreakdown.grandTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Text(location.activeLabelIcon, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(
                                location.activeLabel,
                                style: const TextStyle(
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
                          style: const TextStyle(fontSize: 14),
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
                        icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                        label: const Text('Change Address'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12)),
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
              if (location.currentLocation != null && cart.shops.isNotEmpty) {
                for (final s in cart.shops) {
                  final d = location.distanceTo(s.location);
                  if (d > maxDist) maxDist = d;
                  if (s.prepTimeMinutes > maxPrep) maxPrep = s.prepTimeMinutes;
                }
              }
              final etaStr = DeliveryCalculator.etaLabel(maxDist, maxPrep);
              final arrivalStr = DeliveryCalculator.etaArrivalTime(maxDist, maxPrep);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary.withValues(alpha: 0.7),
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            etaStr,
                            style: const TextStyle(
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
                        const Text(
                          'Arrives by',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          arrivalStr,
                          style: const TextStyle(
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
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '₹${item.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
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
                    const Text(
                      'Your order contains medicines that require a valid doctor\'s prescription under Govt of India norms. Please upload it here.',
                      style: TextStyle(
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
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                style: BorderStyle.solid),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  color: AppColors.primary, size: 32),
                              SizedBox(height: 8),
                              Text(
                                  'Tap to upload prescription\n(Clear & readable image)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
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
                                        image: FileImage(
                                            File(_prescriptions[index].path)),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pay after confirmation',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        SizedBox(height: 2),
                        Text(
                          'No money is charged now. Payment via UPI/Card is only requested after the shop & rider both accept your order.',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
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
                  if (gstBreakdown.itemGstTotal > 0) ...[
                    const SizedBox(height: 8),
                    _billRow(
                      'GST on Items',
                      '+₹${gstBreakdown.itemGstTotal.toStringAsFixed(2)}',
                      hint: 'Govt. tax • charged to you',
                      valueColor: const Color(0xFF1565C0), // deep blue
                    ),
                  ],
                  const SizedBox(height: 8),
                  _billRow(
                    'Delivery Fee',
                    '₹${effectiveBase.toStringAsFixed(0)}',
                  ),
                  if (discount > 0) ...[
                    const SizedBox(height: 8),
                    _billRow(
                      'Delivery Discount',
                      '-₹${discount.toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                  ],
                  if (cart.smallCartFee > 0) ...[
                    const SizedBox(height: 8),
                    _billRow(
                      'Small Cart Fee',
                      '+₹${cart.smallCartFee.toStringAsFixed(0)}',
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
                      hint: '₹7/km between shops',
                    ),
                  ],
                  const SizedBox(height: 8),
                  _billRow(
                    'Handling Fee',
                    '+₹${cart.platformFee.toStringAsFixed(0)}',
                    hint: 'Covers payment gateway & app operations',
                  ),
                  const Divider(height: 20),
                  _billRow(
                    'Grand Total',
                    '₹${total.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppColors.primary,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Incl. ₹${gstBreakdown.itemGstTotal.toStringAsFixed(2)} GST on items',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
                const Text('Total Amount',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    if (gstBreakdown.itemGstTotal > 0)
                      Text(
                        '+ ₹${gstBreakdown.itemGstTotal.toStringAsFixed(2)} GST',
                        style: const TextStyle(
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
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'CONFIRM ORDER',
                        style: TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
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
                style: const TextStyle(
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  color:
                      isBold ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: isBold ? 15 : 13,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                )),
            if (hint != null)
              Text(hint,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  )),
          ],
        ),
        Text(value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: isBold ? 17 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            )),
      ],
    );
  }
}
