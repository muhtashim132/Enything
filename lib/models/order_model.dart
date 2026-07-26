// ============================================================================
// order_model.dart — Enything Order + Financial Snapshot
// ============================================================================
//
// FINANCIAL SNAPSHOT PATTERN:
//   Every order in Enything permanently stores its complete financial breakdown
//   at the moment of checkout. This means:
//     • GST rates, commission %, and payout amounts are FROZEN in the DB.
//     • Future rate changes will never corrupt historical reporting.
//     • Your CA can generate GSTR-1, GSTR-8 (TCS), and payout reconciliation
//       reports directly from the orders table, no recalculation needed.
//
// INDIA GST COMPLIANCE FIELDS:
//   s9_5GstAmount    — Food/restaurant GST. Enything remits to Govt (§9(5) CGST).
//   nonFoodGstAmount — Retail GST. Seller remits to Govt (declare in GSTR-1/3B).
//   tcsAmount        — 1% TCS Enything deducts (Enything files GSTR-8 by 10th).
//   grandTotalCollected — True INR collected from customer (incl. all GST).
//   gstRateSnapshot  — Frozen {category: rate} map used at checkout.
// ============================================================================

import 'dart:math' as math;
class OrderModel {
  final String id;
  final String customerId;
  String status;
  final double totalAmount;
  final double deliveryCharges;
  final double riderEarnings;
  final double multiShopSurcharge;
  final double platformFee;
  final DateTime createdAt;
  List<OrderItem> items;
  String? deliveryPartnerId;
  final String? shopId;
  final String? address;

  /// Emoji + label string saved at checkout — e.g. "🏠 Home", "💼 Office".
  /// Null for legacy orders placed before this feature.
  final String? addressLabel;
  final String? deliveryNotes;
  final String? customerPhone;
  final String? shopPhone;
  final String? riderPhone;
  final String? paymentMethod;

  // Cancellation metadata
  final String?
      cancelledReason; // 'shop_rejected' | 'no_rider' | 'timeout' | 'customer'
  final String? rejectionMessage; // seller's freetext message to customer
  final String? cartGroupId; // groups orders from same checkout (up to 3 shops)
  final DateTime? acceptanceDeadline; // when the 3-min window expires
  final DateTime? paymentDeadline; // when the 10-min payment window expires

  // Dual-acceptance flags (stored in DB columns)
  bool sellerAccepted;
  bool partnerAccepted;

  // Wait-time compensation fields
  DateTime? arrivedAtShopTime;
  DateTime? orderReadyTime;
  double waitTimePenalty;
  bool waitTimeDisputed;

  // Rating flags
  bool hasCustomerRated;
  bool hasSellerRated;
  bool hasDeliveryRated;

  // Delivery location (stored at checkout, used by track order map)
  final double? deliveryLat;
  final double? deliveryLng;

  // Rider's LIVE GPS position (updated every 15s by delivery partner while out_for_delivery)
  final double? riderLat;
  final double? riderLng;
  final DateTime? riderLocationUpdatedAt;

  // Shop location snapshotted at order accept for arrival geofencing
  final double? shopLat;
  final double? shopLng;

  // Prescription validation
  final List<String> prescriptionUrls;

  // ── Financial Snapshot Fields (India GST Compliance) ─────────────────────
  // These are written ONCE at checkout and never recalculated.
  // They represent the exact financial reality of this specific transaction.

  /// GST charged on items and added on top of base price (ADD-ON model).
  final double gstItemTotal;

  /// GST on Section 9(5) food/restaurant items — Enything remits to Govt.
  /// Seller does NOT declare this in their GSTR-1. It is Enything's liability.
  final double s9_5GstAmount;

  /// GST on non-food retail/grocery/pharma — passed to seller in payout.
  /// Seller MUST declare this in their GSTR-1/3B.
  final double nonFoodGstAmount;

  /// 18% GST embedded in the delivery charge — Enything remits to Govt.
  final double gstDelivery;

  /// 18% GST embedded in the platform/handling fee — Enything remits to Govt.
  final double gstPlatform;

  /// GST TCS: Tax Collected at Source deducted from seller by Enything (CGST §52).
  /// Rate: 1% on taxable non-deemed-supplier supplies only.
  /// §9(5) food and 0% GST categories → tcsAmount = 0.
  /// Enything files GSTR-8 by 10th. Seller claims credit via GSTR-2B.
  final double tcsAmount;

  /// Income Tax TDS: Tax Deducted at Source under §194-O (Finance Act 2024).
  /// Rate: 0.1% on gross base consideration. Applies to ALL categories.
  /// Enything files Form 26QE by 7th of next month.
  /// Seller claims credit via Form 26AS / AIS.
  final double tdsAmount;

  /// Penalty fee applied for orders below the minimum cart threshold.
  final double smallCartFee;

  /// Surcharge applied for orders exceeding the maximum base weight limit.
  final double heavyOrderFee;


  /// Gross commission Enything charged on base item subtotal (5% standard).
  final double enythingCommission;

  /// Net payout to seller: (base − commission + nonFoodGst − tcs).
  /// This is what actually lands in the seller's bank account.
  final double sellerPayout;

  /// Razorpay / gateway deduction (2.36% for UPI/Card, 0 for COD).
  /// Absorbed entirely by Enything under the 5% commission plan.
  final double gatewayDeduction;

  /// Actual total collected from the customer including all GST + fees.
  /// This is Enything's "gross turnover" figure for ECO reporting.
  final double grandTotalCollected;

  /// Frozen snapshot of {category: gstRate} used at checkout.
  /// Stored as JSON so future rate changes never affect historical orders.
  final Map<String, dynamic> gstRateSnapshot;

  /// Estimated distance calculated at checkout for rider payout.
  final double estimatedDistanceKm;

  /// Frozen snapshot of shop's prep time at the time of order for wait time calculations.
  final int shopPrepTimeSnapshot;

  /// Coupon applied to this order (nullable — not all orders use a coupon).
  final String? couponId;

  /// Discount amount deducted via coupon (defaults to 0 when no coupon used).
  final double couponDiscount;

  OrderModel({
    required this.id,
    required this.customerId,
    required this.status,
    required this.totalAmount,
    required this.deliveryCharges,
    this.riderEarnings = 0.0,
    this.multiShopSurcharge = 0,
    this.platformFee = 0,
    required this.createdAt,
    this.items = const [],
    this.deliveryPartnerId,
    this.shopId,
    this.address,
    this.addressLabel,
    this.deliveryNotes,
    this.customerPhone,
    this.shopPhone,
    this.riderPhone,
    this.paymentMethod,
    this.cancelledReason,
    this.rejectionMessage,
    this.cartGroupId,
    this.acceptanceDeadline,
    this.paymentDeadline,
    this.sellerAccepted = false,
    this.partnerAccepted = false,
    this.arrivedAtShopTime,
    this.orderReadyTime,
    this.waitTimePenalty = 0.0,
    this.waitTimeDisputed = false,
    this.hasCustomerRated = false,
    this.hasSellerRated = false,
    this.hasDeliveryRated = false,
    this.deliveryLat,
    this.deliveryLng,
    this.riderLat,
    this.riderLng,
    this.riderLocationUpdatedAt,
    this.shopLat,
    this.shopLng,
    // Financial snapshot fields
    this.gstItemTotal = 0.0,
    this.s9_5GstAmount = 0.0,
    this.nonFoodGstAmount = 0.0,
    this.gstDelivery = 0.0,
    this.gstPlatform = 0.0,
    this.tcsAmount = 0.0,
    this.tdsAmount = 0.0,
    this.enythingCommission = 0.0,
    this.sellerPayout = 0.0,
    this.gatewayDeduction = 0.0,
    this.grandTotalCollected = 0.0,
    this.gstRateSnapshot = const {},
    this.prescriptionUrls = const [],
    this.estimatedDistanceKm = 0.0,
    this.shopPrepTimeSnapshot = 30,
    this.smallCartFee = 0.0,
    this.heavyOrderFee = 0.0,
    this.couponId,
    this.couponDiscount = 0.0,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      totalAmount: _parseDouble(map['total_amount']),
      deliveryCharges: _parseDouble(map['delivery_charges']),
      riderEarnings: _parseDouble(map['rider_earnings']) > 0 
          ? _parseDouble(map['rider_earnings']) 
          : _parseDouble(map['delivery_charges']),
      multiShopSurcharge: _parseDouble(map['multi_shop_surcharge']),
      platformFee: _parseDouble(map['platform_fee']),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      deliveryPartnerId: map['delivery_partner_id']?.toString(),
      shopId: map['shop_id']?.toString(),
      address: map['address']?.toString(),
      addressLabel: map['address_label']?.toString(),
      deliveryNotes: map['delivery_notes']?.toString(),
      customerPhone: map['customer_phone']?.toString(),
      shopPhone: map['shop_phone']?.toString(),
      riderPhone: map['rider_phone']?.toString(),
      paymentMethod: map['payment_method']?.toString(),
      cancelledReason: map['cancelled_reason']?.toString(),
      rejectionMessage: map['rejection_message']?.toString(),
      cartGroupId: map['cart_group_id']?.toString(),
      acceptanceDeadline: map['acceptance_deadline'] != null
          ? DateTime.tryParse(map['acceptance_deadline'].toString())
          : null,
      paymentDeadline: map['payment_deadline'] != null
          ? DateTime.tryParse(map['payment_deadline'].toString())
          : null,
      sellerAccepted: map['seller_accepted'] == true || map['seller_accepted'] == 'true',
      partnerAccepted: map['partner_accepted'] == true || map['partner_accepted'] == 'true',
      arrivedAtShopTime: map['arrived_at_shop_time'] != null
          ? DateTime.tryParse(map['arrived_at_shop_time'].toString())
          : null,
      orderReadyTime: map['order_ready_time'] != null
          ? DateTime.tryParse(map['order_ready_time'].toString())
          : null,
      waitTimePenalty: _parseDouble(map['wait_time_penalty']),
      waitTimeDisputed: map['wait_time_disputed'] == true || map['wait_time_disputed'] == 'true',
      hasCustomerRated: map['has_customer_rated'] == true || map['has_customer_rated'] == 'true',
      hasSellerRated: map['has_seller_rated'] == true || map['has_seller_rated'] == 'true',
      hasDeliveryRated: map['has_delivery_rated'] == true || map['has_delivery_rated'] == 'true',
      deliveryLat: _parseDoubleNullable(map['delivery_lat']),
      deliveryLng: _parseDoubleNullable(map['delivery_lng']),
      riderLat: _parseDoubleNullable(map['rider_lat']),
      riderLng: _parseDoubleNullable(map['rider_lng']),
      riderLocationUpdatedAt: map['rider_location_updated_at'] != null
          ? DateTime.tryParse(map['rider_location_updated_at'].toString())
          : null,
      shopLat: _parseDoubleNullable(map['shop_lat']),
      shopLng: _parseDoubleNullable(map['shop_lng']),
      // ── Financial snapshot — read from frozen DB values ────────────────
      gstItemTotal: _parseDouble(map['gst_item_total']),
      s9_5GstAmount: _parseDouble(map['s9_5_gst_amount']),
      nonFoodGstAmount: _parseDouble(map['non_food_gst_amount']),
      gstDelivery: _parseDouble(map['gst_delivery']),
      gstPlatform: _parseDouble(map['gst_platform']),
      tcsAmount: _parseDouble(map['tcs_amount']),
      tdsAmount: _parseDouble(map['tds_amount']),
      enythingCommission: _parseDouble(map['enything_commission']),
      sellerPayout: _parseDouble(map['seller_payout']),
      gatewayDeduction: _parseDouble(map['gateway_deduction']),
      grandTotalCollected: _parseDouble(map['grand_total_collected']),
      gstRateSnapshot: map['gst_rate_snapshot'] is Map
          ? Map<String, dynamic>.from(map['gst_rate_snapshot'] as Map)
          : {},
      prescriptionUrls: map['prescription_urls'] is List
          ? (map['prescription_urls'] as List).map((e) => e.toString()).toList()
          : [],
      estimatedDistanceKm: _parseDouble(map['estimated_distance_km']),
      shopPrepTimeSnapshot: map['shop_prep_time_snapshot'] is int 
          ? map['shop_prep_time_snapshot'] 
          : int.tryParse(map['shop_prep_time_snapshot']?.toString() ?? '30') ?? 30,
      smallCartFee: _parseDouble(map['small_cart_fee']),
      heavyOrderFee: _parseDouble(map['heavy_order_fee']),
      couponId: map['coupon_id']?.toString(),
      couponDiscount: _parseDouble(map['coupon_discount']),
    );
  }

  /// True when both the seller and delivery partner have accepted.
  bool get isFullyConfirmed => sellerAccepted && partnerAccepted;

  /// Grand total as displayed to customer at checkout.
  /// O6 FIX: Fallback now includes ALL fee components so legacy orders
  /// (where grandTotalCollected == -1) display the correct amount.
  /// NOTE: deliveryCharges in the DB already includes multiShopSurcharge,
  /// smallCartFee, and heavyOrderFee — do NOT add them again here.
  double get grandTotal => grandTotalCollected >= 0
      ? grandTotalCollected
      : math.max(
          0.0,
          totalAmount +
              gstItemTotal +
              deliveryCharges +
              platformFee -
              couponDiscount);

  /// Total GST across the entire order (items + delivery + platform).
  double get totalGstInOrder => gstItemTotal + gstDelivery + gstPlatform;

  /// Amount seller must declare in their GSTR-1 (their GST liability only).
  double get sellerGstrLiability => nonFoodGstAmount;

  /// Net seller taxable turnover for TCS basis (base amount only).
  double get sellerNetTaxableSupply => totalAmount;

  OrderModel copyWith({
    String? status,
    String? deliveryPartnerId,
    String? shopId,
    String? address,
    String? addressLabel,
    String? customerPhone,
    String? shopPhone,
    String? riderPhone,
    bool? sellerAccepted,
    bool? partnerAccepted,
    bool? hasCustomerRated,
    bool? hasSellerRated,
    bool? hasDeliveryRated,
    double? deliveryLat,
    double? deliveryLng,
    double? riderLat,
    double? riderLng,
    DateTime? riderLocationUpdatedAt,
    double? shopLat,
    double? shopLng,
    String? cancelledReason,
    double? waitTimePenalty,
    bool? waitTimeDisputed,
    List<String>? prescriptionUrls,
    String? rejectionMessage,
    double? gstItemTotal,
    // C1 FIX: These fields were missing from copyWith — they'd silently reset to 0.0 on any copy
    double? smallCartFee,
    double? heavyOrderFee,
    String? couponId,
    double? couponDiscount,
  }) {
    return OrderModel(
      id: id,
      customerId: customerId,
      status: status ?? this.status,
      totalAmount: totalAmount,
      deliveryCharges: deliveryCharges,
      riderEarnings: riderEarnings,
      multiShopSurcharge: multiShopSurcharge,
      platformFee: platformFee,
      createdAt: createdAt,
      items: items,
      deliveryPartnerId: deliveryPartnerId ?? this.deliveryPartnerId,
      shopId: shopId ?? this.shopId,
      address: address ?? this.address,
      addressLabel: addressLabel ?? this.addressLabel,
      deliveryNotes: deliveryNotes,
      customerPhone: customerPhone ?? this.customerPhone,
      shopPhone: shopPhone ?? this.shopPhone,
      riderPhone: riderPhone ?? this.riderPhone,
      paymentMethod: paymentMethod,
      cancelledReason: cancelledReason ?? this.cancelledReason,
      rejectionMessage: rejectionMessage ?? this.rejectionMessage,
      cartGroupId: cartGroupId,
      acceptanceDeadline: acceptanceDeadline,
      paymentDeadline: paymentDeadline,
      sellerAccepted: sellerAccepted ?? this.sellerAccepted,
      partnerAccepted: partnerAccepted ?? this.partnerAccepted,
      arrivedAtShopTime: arrivedAtShopTime,
      orderReadyTime: orderReadyTime,
      waitTimePenalty: waitTimePenalty ?? this.waitTimePenalty,
      waitTimeDisputed: waitTimeDisputed ?? this.waitTimeDisputed,
      hasCustomerRated: hasCustomerRated ?? this.hasCustomerRated,
      hasSellerRated: hasSellerRated ?? this.hasSellerRated,
      hasDeliveryRated: hasDeliveryRated ?? this.hasDeliveryRated,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      riderLat: riderLat ?? this.riderLat,
      riderLng: riderLng ?? this.riderLng,
      riderLocationUpdatedAt:
          riderLocationUpdatedAt ?? this.riderLocationUpdatedAt,
      shopLat: shopLat ?? this.shopLat,
      shopLng: shopLng ?? this.shopLng,
      // Preserve frozen financial fields unchanged
      gstItemTotal: gstItemTotal ?? this.gstItemTotal,
      s9_5GstAmount: s9_5GstAmount,
      nonFoodGstAmount: nonFoodGstAmount,
      gstDelivery: gstDelivery,
      gstPlatform: gstPlatform,
      tcsAmount: tcsAmount,
      tdsAmount: tdsAmount,
      enythingCommission: enythingCommission,
      sellerPayout: sellerPayout,
      gatewayDeduction: gatewayDeduction,
      grandTotalCollected: grandTotalCollected,
      gstRateSnapshot: gstRateSnapshot,
      prescriptionUrls: prescriptionUrls ?? this.prescriptionUrls,
      estimatedDistanceKm: estimatedDistanceKm,
      shopPrepTimeSnapshot: shopPrepTimeSnapshot,
      // C1 FIX: Preserve the 3 previously-dropped fee fields
      smallCartFee: smallCartFee ?? this.smallCartFee,
      heavyOrderFee: heavyOrderFee ?? this.heavyOrderFee,
      couponId: couponId ?? this.couponId,
      couponDiscount: couponDiscount ?? this.couponDiscount,
    );
  }

  String get statusDisplay {
    switch (status) {
      case 'pending_verification':
        return 'Pending Prescription Verification';
      case 'verification_failed':
        return 'Prescription Rejected';
      case 'awaiting_acceptance':
        return 'Waiting for Confirmation';
      case 'awaiting_payment':
        return 'Pay Now';
      case 'pending':
        if (sellerAccepted && !partnerAccepted) return 'Awaiting Rider';
        if (!sellerAccepted && partnerAccepted) return 'Awaiting Shop';
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'preparing':
        return 'Preparing';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'picked_up':
        return 'Picked Up';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        switch (cancelledReason) {
          case 'shop_rejected':
            return 'Shop Declined';
          case 'no_rider':
            return 'No Rider Available';
          case 'timeout':
            return 'Order Expired';
          case 'customer':
            return 'Cancelled by You';
          case 'shop_dispute':
            return 'Cancelled — Shop Issue';
          default:
            return 'Cancelled';
        }
      case 'seller_rejected':
        return 'Shop Declined';
      case 'partner_rejected':
        return 'Rider Declined';
      // Legacy statuses (backward compat)
      case 'seller_accepted':
        return 'Shop Accepted';
      case 'partner_assigned':
        return 'Rider Assigned';
      default:
        return status;
    }
  }
}

class OrderItem {
  final String id;
  final String productId;
  final String productName;
  final String? variantName;
  final int quantity;
  final double price;
  final double weightKg;
  final String? specialInstructions;
  final bool requiresPrescription;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.price,
    required this.weightKg,
    this.specialInstructions,
    this.requiresPrescription = false,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      variantName: map['variant_name']?.toString(),
      quantity: (map['quantity'] is num) ? (map['quantity'] as num).toInt() : int.tryParse(map['quantity']?.toString() ?? '1') ?? 1,
      price: OrderModel._parseDouble(map['price']),
      weightKg: OrderModel._parseDouble(map['weight_kg']),
      specialInstructions: map['special_instructions']?.toString(),
      requiresPrescription: map['requires_prescription'] == true || map['requires_prescription'] == 'true',
    );
  }

  double get totalPrice => price * quantity;
}
