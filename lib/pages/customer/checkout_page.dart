import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/cart_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/enything_map.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../config/payment_config.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool _isProcessing = false;
  final _notesController = TextEditingController();
  String? _selectedPaymentMethod = 'upi';
  final List<XFile> _prescriptions = [];

  late Razorpay _razorpay;

  // Stored while Razorpay sheet is open so we can use them in callbacks
  double _pendingTotal = 0;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _notesController.dispose();
    super.dispose();
  }

  // ── Razorpay callbacks ────────────────────────────────────────────────────
  void _onPaymentSuccess(PaymentSuccessResponse response) {
    debugPrint('Razorpay success: paymentId=${response.paymentId} orderId=${response.orderId}');
    _verifyAndCreateOrder(
      paymentId:  response.paymentId  ?? '',
      orderId:    response.orderId    ?? '',
      signature:  response.signature  ?? '',
    );
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? "Unknown error"}'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('External wallet selected: ${response.walletName}'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

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

  // ── Step 1: validate → (COD fast-path OR Razorpay order creation) ────────
  Future<void> _placeOrder() async {
    setState(() => _isProcessing = true);
    final cart     = context.read<CartProvider>();
    final location = context.read<LocationProvider>();

    // Prescription guard
    if (cart.requiresPrescription && _prescriptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A valid prescription is required for medicines in your cart.'),
            backgroundColor: AppColors.danger),
      );
      setState(() => _isProcessing = false);
      return;
    }

    try {
      double distanceKm = 3.0;
      if (location.currentLocation != null && cart.shops.isNotEmpty) {
        distanceKm = location.distanceTo(cart.shops.first.location);
      }
      final baseDelivery  = cart.calculateDeliveryCharges(distanceKm);
      final surcharge     = cart.multiShopSurcharge;
      final heavyFee      = cart.heavyOrderFee;
      final discount      = cart.calculateDeliveryDiscount(distanceKm);
      final effectiveBase = baseDelivery >= 0 ? baseDelivery : 25.0;
      final riderEarnings = effectiveBase + surcharge + heavyFee;
      final totalDelivery = riderEarnings + cart.smallCartFee - discount;

      final breakdown = OrderTaxBreakdown.calculate(
        items:         cart.taxBreakdownItems,
        deliveryCharge: totalDelivery,
        platformFee:   cart.platformFee,
        paymentMethod: _selectedPaymentMethod!,
      );
      debugPrint(breakdown.toString());
      _pendingTotal = breakdown.grandTotal;

      // ── COD: skip Razorpay entirely ───────────────────────────────────────
      final auth = context.read<AuthProvider>();
      if (_selectedPaymentMethod == 'cod') {
        await _createOrderInDb(razorpayPaymentId: null, razorpayOrderId: null);
        return;
      }

      // ── Online Payment: create a server-side Razorpay order first ─────────
      final supabase = Supabase.instance.client;
      final amountInPaise = (_pendingTotal * 100).toInt();

      final orderRes = await supabase.functions.invoke(
        'create-razorpay-order',
        body: {
          'amount':   amountInPaise,
          'currency': 'INR',
          'receipt':  'enything_${auth.currentUserId}_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (orderRes.status != 200) {
        throw Exception('Could not create payment order: ${orderRes.data?['error'] ?? 'Unknown error'}');
      }

      final razorpayOrderId = orderRes.data['id'] as String;

      // ── Open Razorpay checkout with the server-issued order_id ────────────
      final razorpayKey = dotenv.maybeGet('RAZORPAY_KEY') ?? '';
      final options = <String, dynamic>{
        'key':         razorpayKey,
        'amount':      amountInPaise,
        'currency':    'INR',
        'order_id':    razorpayOrderId,   // ← CRITICAL: required for production
        'name':        'Enything',
        'description': 'Order Payment',
        'prefill': {
          'contact': auth.user?.phone ?? '',
          'name':    auth.user?.fullName ?? '',
        },
        'theme': {'color': '#4C6EF5'},
      };
      _razorpay.open(options);
      // Callbacks (_onPaymentSuccess / _onPaymentError) handle the rest
    } catch (e) {
      debugPrint('Payment initiation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  // ── Step 2 (online pay): verify signature server-side, then write order ──
  Future<void> _verifyAndCreateOrder({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final verifyRes = await supabase.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'razorpay_payment_id': paymentId,
          'razorpay_order_id':   orderId,
          'razorpay_signature':  signature,
        },
      );

      final verified = verifyRes.data?['verified'] == true;
      if (!verified) {
        debugPrint('Signature verification failed: ${verifyRes.data}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment verification failed. Please contact support if amount was deducted.'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 6),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      // Signature verified — safe to record the order
      await _createOrderInDb(
        razorpayPaymentId: paymentId,
        razorpayOrderId:   orderId,
      );
    } catch (e) {
      debugPrint('Verify payment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment confirmed but order save failed. Please contact support.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8),
          ),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  // ── Step 3: write order to Supabase (COD: direct | Online: after verification) ──
  Future<void> _createOrderInDb({String? razorpayPaymentId, String? razorpayOrderId}) async {
    final cart = context.read<CartProvider>();
    final auth = context.read<AuthProvider>();
    final location = context.read<LocationProvider>();
    final supabase = Supabase.instance.client;

    try {
      double distanceKm = 3.0;
      if (location.currentLocation != null && cart.shops.isNotEmpty) {
        distanceKm = location.distanceTo(cart.shops.first.location);
      }
      final baseDelivery = cart.calculateDeliveryCharges(distanceKm);
      final surcharge = cart.multiShopSurcharge;
      final heavyFee = cart.heavyOrderFee;
      final discount = cart.calculateDeliveryDiscount(distanceKm);
      final effectiveBase = baseDelivery >= 0 ? baseDelivery : 25.0;
      final riderEarnings = effectiveBase + surcharge + heavyFee;
      final totalDelivery = riderEarnings + cart.smallCartFee - discount;

      final breakdown = OrderTaxBreakdown.calculate(
        items: cart.taxBreakdownItems,
        deliveryCharge: totalDelivery,
        platformFee: cart.platformFee,
        paymentMethod: _selectedPaymentMethod!,
      );

      final cartGroupId = const Uuid().v4();
      final numShops = cart.shops.length;

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

      // Fetch shop phones (which are the sellers' phones)
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
          final bytes = await file.readAsBytes();
          final ext = file.name.split('.').last;
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
        final shopItems =
            cart.items.where((i) => i.shop.id == shop.id).toList();
        // Base subtotal for this shop (pre-GST)
        final shopBaseSubtotal =
            shopItems.fold(0.0, (sum, i) => sum + i.totalPrice);

        // Split fees evenly across grouped orders
        final shopDelivery = totalDelivery / numShops;
        final shopRiderEarnings = riderEarnings / numShops;
        final shopPlatformFee = cart.platformFee / numShops;

        // ── Build frozen GST rate snapshot for this shop's items ─────────────
        // Maps each unique category → rate used. Immutable for audit purposes.
        final Map<String, dynamic> rateSnapshot = {};
        for (final item in shopItems) {
          final cat = item.product.category;
          if (!rateSnapshot.containsKey(cat)) {
            rateSnapshot[cat] = TaxConfig.gstRateForCategory(
              cat,
              itemPrice: item.product.price,
            );
          }
        }

        // ── Per-shop GST split (S9(5) food vs non-food retail) ───────────────
        double shopS9_5Gst = 0;
        double shopNonFoodGst = 0;
        for (final item in shopItems) {
          final cat = item.product.category;
          final rate =
              TaxConfig.gstRateForCategory(cat, itemPrice: item.product.price);
          final lineGst = item.totalPrice * rate;
          if (TaxConfig.isEnythingDeemedSupplier(cat)) {
            shopS9_5Gst += lineGst;
          } else {
            shopNonFoodGst += lineGst;
          }
        }

        // ── TCS: 1% on net taxable supply per CGST §52 ───────────────────────
        // TCS basis = seller's base subtotal (pre-GST). Rate = 0.5% CGST + 0.5% SGST = 1%.
        final shopTcs = shopBaseSubtotal * 0.01;

        // ── True grand total collected from customer (for this shop's share) ─
        final shopGrandTotal = shopBaseSubtotal +
            (shopS9_5Gst + shopNonFoodGst) + // item GST
            shopDelivery +
            shopPlatformFee;

        final orderResponse = await supabase
            .from('orders')
            .insert({
              'cart_group_id': cartGroupId,
              'shop_id': shop.id,
              'customer_id': auth.currentUserId,
              'status': 'pending',
              // total_amount = BASE subtotal (seller's revenue, excl. GST)
              'total_amount': shopBaseSubtotal,
              'delivery_charges': shopDelivery,
              'rider_earnings': shopRiderEarnings,
              'platform_fee': shopPlatformFee,
              'address': location.currentAddress,
              'delivery_lat': location.currentLocation?.latitude,
              'delivery_lng': location.currentLocation?.longitude,
              'delivery_notes':
                  _notesController.text.isEmpty ? null : _notesController.text,
              'payment_method': _selectedPaymentMethod,
              'payment_status': razorpayPaymentId != null ? 'captured' : 'cod',
              'razorpay_payment_id': razorpayPaymentId,
              'razorpay_order_id':   razorpayOrderId,
              'customer_phone': customerPhone,
              'shop_phone': shopPhones[shop.id],
              // ── Financial Snapshot — written ONCE, never recalculated ────
              // Existing columns
              'gst_item_total': (breakdown.itemGstTotal / numShops),
              'gst_delivery': (breakdown.deliveryGst / numShops),
              'gst_platform': (breakdown.platformFeeGst / numShops),
              'enything_commission': (breakdown.enythingGrossCommission / numShops),
              'seller_payout': (breakdown.sellerPayout / numShops) - shopTcs,
              'gateway_deduction': (breakdown.gatewayDeduction / numShops),
              // New GST compliance columns
              's9_5_gst_amount': shopS9_5Gst, // Enything remits to Govt
              'non_food_gst_amount': shopNonFoodGst, // Seller remits in GSTR-1
              'tcs_amount': shopTcs, // Enything files GSTR-8
              'grand_total_collected': shopGrandTotal,
              'gst_rate_snapshot': rateSnapshot, // Frozen rate map
              'prescription_urls': uploadedPrescriptionUrls,
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
                })
            .toList();

        await supabase.from('order_items').insert(itemsToInsert);
      }

      cart.clear();
      if (mounted) {
        if (orderIds.length == 1) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.trackOrder,
            (route) => route.settings.name == AppRoutes.customerHome,
            arguments: {'orderId': orderIds.first},
          );
        } else {
          // Multi-shop order: send them to history to see all their concurrent orders
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.orderHistory,
            (route) => route.settings.name == AppRoutes.customerHome,
          );
        }
      }
    } catch (e) {
      debugPrint('Order placement error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to place order. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
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
      distanceKm = location.distanceTo(cart.shops.first.location);
    }

    final baseCharge = cart.calculateDeliveryCharges(distanceKm);
    final surcharge = cart.multiShopSurcharge;
    final heavyFee = cart.heavyOrderFee;
    final discount = cart.calculateDeliveryDiscount(distanceKm);
    final effectiveBase = baseCharge >= 0 ? baseCharge : 25.0;
    final totalDelivery =
        effectiveBase + surcharge + heavyFee + cart.smallCartFee - discount;

    // ── ADD-ON GST model: GST is a real charge on top of base prices ─────────
    final gstBreakdown = OrderTaxBreakdown.calculate(
      items: cart.taxBreakdownItems,
      deliveryCharge: totalDelivery,
      platformFee: cart.platformFee,
      paymentMethod: _selectedPaymentMethod ?? 'cod',
    );
    // Grand total = base items + item GST + delivery + platform
    final total = gstBreakdown.grandTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
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
                  Text(
                    location.currentAddress.isEmpty
                        ? 'Location not set'
                        : location.currentAddress,
                    style: const TextStyle(fontSize: 14),
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
                        onPressed: () =>
                            context.read<LocationProvider>().requestLocation(),
                        icon: const Icon(Icons.my_location, size: 16),
                        label: const Text('Update Location'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      if (location.hasLocation)
                        OutlinedButton.icon(
                          onPressed: () => _showEditAddressSheet(context, location),
                          icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                          label: const Text('Add/Edit Details'),
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
                              Text('Tap to upload prescription\n(Clear & readable image)',
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
                                    color: AppColors.primary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color:
                                            AppColors.primary.withValues(alpha: 0.3)),
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

            // Payment Method
            _sectionCard(
              title: 'Payment Method',
              icon: Icons.payments_outlined,
              iconColor: AppColors.warning,
              child: Column(
                children: [
                  _paymentOption(
                    value: 'upi',
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'UPI / Online',
                    subtitle: 'Pay via any UPI app (GPay, PhonePe, etc.)',
                    iconColor: AppColors.primary,
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
      bottomNavigationBar: Container(
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
              height: 52,
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
                onPressed: (_isProcessing || _selectedPaymentMethod == null)
                    ? null
                    : _placeOrder,
                style: ElevatedButton.styleFrom(
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
                    : Text(
                        _selectedPaymentMethod == null
                            ? 'SELECT PAYMENT METHOD'
                            : 'PLACE ORDER',
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
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
                  if (title == 'Delivery Address')
                    TextButton(
                      onPressed: () => _showEditAddressSheet(context, context.read<LocationProvider>()),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Edit', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _paymentOption({
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color iconColor,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: 0.07)
              : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isSelected ? iconColor : AppColors.textPrimary,
                      )),
                  Text(subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('checked'),
                      color: iconColor,
                      size: 22)
                  : const Icon(Icons.radio_button_unchecked,
                      key: ValueKey('unchecked'),
                      color: AppColors.divider,
                      size: 22),
            ),
          ],
        ),
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

  void _showEditAddressSheet(BuildContext context, LocationProvider location) {
    final houseCtrl = TextEditingController(text: location.houseNumber);
    final landmarkCtrl = TextEditingController(text: location.landmark);
    final pincodeCtrl = TextEditingController(text: location.pincode);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Address Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: houseCtrl,
              decoration: const InputDecoration(
                labelText: 'House / Flat / Block No.',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: landmarkCtrl,
              decoration: const InputDecoration(
                labelText: 'Landmark (Optional)',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pincodeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pincode',
                prefixIcon: Icon(Icons.pin_drop_outlined),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final auth = context.read<AuthProvider>();
                  if (auth.currentUserId != null) {
                    await location.updateAddressDetails(
                      auth.currentUserId!,
                      house: houseCtrl.text.trim(),
                      mark: landmarkCtrl.text.trim(),
                      pin: pincodeCtrl.text.trim(),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save Details'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
