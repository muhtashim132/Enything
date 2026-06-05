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
  final String? deliveryNotes;
  final String? customerPhone;
  final String? shopPhone;
  final String? riderPhone;
  final String? paymentMethod;

  // Cancellation metadata
  final String? cancelledReason;    // 'shop_rejected' | 'no_rider' | 'timeout' | 'customer'
  final String? rejectionMessage;   // seller's freetext message to customer
  final String? cartGroupId;        // groups orders from same checkout (up to 3 shops)
  final DateTime? acceptanceDeadline; // when the 2-min window expires
  final DateTime? paymentDeadline;    // when the 10-min payment window expires

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

  /// 1% Tax Collected at Source deducted from seller by Enything (CGST §52).
  /// Enything files GSTR-8 by 10th. Seller claims credit via GSTR-2B.
  final double tcsAmount;

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
    this.enythingCommission = 0.0,
    this.sellerPayout = 0.0,
    this.gatewayDeduction = 0.0,
    this.grandTotalCollected = 0.0,
    this.gstRateSnapshot = const {},
    this.prescriptionUrls = const [],
    this.estimatedDistanceKm = 0.0,
    this.shopPrepTimeSnapshot = 30,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'] ?? '',
      customerId: map['customer_id'] ?? '',
      status: map['status'] ?? 'pending',
      totalAmount: (map['total_amount'] ?? 0.0).toDouble(),
      deliveryCharges: (map['delivery_charges'] ?? 0.0).toDouble(),
      riderEarnings: (map['rider_earnings'] ?? (map['delivery_charges'] ?? 0.0)).toDouble(),
      multiShopSurcharge: (map['multi_shop_surcharge'] ?? 0.0).toDouble(),
      platformFee: (map['platform_fee'] ?? 0.0).toDouble(),
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      deliveryPartnerId: map['delivery_partner_id'],
      shopId: map['shop_id'],
      address: map['address'],
      deliveryNotes: map['delivery_notes'],
      customerPhone: map['customer_phone'],
      shopPhone: map['shop_phone'],
      riderPhone: map['rider_phone'],
      paymentMethod: map['payment_method'],
      cancelledReason: map['cancelled_reason'],
      rejectionMessage: map['rejection_message'],
      cartGroupId: map['cart_group_id'],
      acceptanceDeadline: map['acceptance_deadline'] != null
          ? DateTime.tryParse(map['acceptance_deadline'])
          : null,
      paymentDeadline: map['payment_deadline'] != null
          ? DateTime.tryParse(map['payment_deadline'])
          : null,
      sellerAccepted: map['seller_accepted'] ?? false,
      partnerAccepted: map['partner_accepted'] ?? false,
      arrivedAtShopTime: map['arrived_at_shop_time'] != null
          ? DateTime.tryParse(map['arrived_at_shop_time'])
          : null,
      orderReadyTime: map['order_ready_time'] != null
          ? DateTime.tryParse(map['order_ready_time'])
          : null,
      waitTimePenalty: (map['wait_time_penalty'] ?? 0.0).toDouble(),
      waitTimeDisputed: map['wait_time_disputed'] ?? false,
      hasCustomerRated: map['has_customer_rated'] ?? false,
      hasSellerRated: map['has_seller_rated'] ?? false,
      hasDeliveryRated: map['has_delivery_rated'] ?? false,
      deliveryLat: (map['delivery_lat'] as num?)?.toDouble(),
      deliveryLng: (map['delivery_lng'] as num?)?.toDouble(),
      riderLat: (map['rider_lat'] as num?)?.toDouble(),
      riderLng: (map['rider_lng'] as num?)?.toDouble(),
      riderLocationUpdatedAt: map['rider_location_updated_at'] != null
          ? DateTime.tryParse(map['rider_location_updated_at'])
          : null,
      shopLat: (map['shop_lat'] as num?)?.toDouble(),
      shopLng: (map['shop_lng'] as num?)?.toDouble(),
      // ── Financial snapshot — read from frozen DB values ────────────────
      gstItemTotal: (map['gst_item_total'] ?? 0.0).toDouble(),
      s9_5GstAmount: (map['s9_5_gst_amount'] ?? 0.0).toDouble(),
      nonFoodGstAmount: (map['non_food_gst_amount'] ?? 0.0).toDouble(),
      gstDelivery: (map['gst_delivery'] ?? 0.0).toDouble(),
      gstPlatform: (map['gst_platform'] ?? 0.0).toDouble(),
      tcsAmount: (map['tcs_amount'] ?? 0.0).toDouble(),
      enythingCommission: (map['enything_commission'] ?? 0.0).toDouble(),
      sellerPayout: (map['seller_payout'] ?? 0.0).toDouble(),
      gatewayDeduction: (map['gateway_deduction'] ?? 0.0).toDouble(),
      grandTotalCollected: (map['grand_total_collected'] ?? 0.0).toDouble(),
      gstRateSnapshot: (map['gst_rate_snapshot'] as Map<String, dynamic>?) ?? {},
      prescriptionUrls: map['prescription_urls'] != null 
          ? List<String>.from(map['prescription_urls']) 
          : [],
      estimatedDistanceKm: (map['estimated_distance_km'] ?? 0.0).toDouble(),
      shopPrepTimeSnapshot: map['shop_prep_time_snapshot'] ?? 30,
    );
  }

  /// True when both the seller and delivery partner have accepted.
  bool get isFullyConfirmed => sellerAccepted && partnerAccepted;

  /// Grand total as displayed to customer at checkout.
  double get grandTotal =>
      totalAmount + deliveryCharges + multiShopSurcharge + platformFee;

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
      address: address,
      deliveryNotes: deliveryNotes,
      customerPhone: customerPhone ?? this.customerPhone,
      shopPhone: shopPhone ?? this.shopPhone,
      riderPhone: riderPhone ?? this.riderPhone,
      paymentMethod: paymentMethod,
      cancelledReason: cancelledReason ?? this.cancelledReason,
      rejectionMessage: rejectionMessage,
      cartGroupId: cartGroupId,
      acceptanceDeadline: acceptanceDeadline,
      paymentDeadline: paymentDeadline,
      sellerAccepted: sellerAccepted ?? this.sellerAccepted,
      partnerAccepted: partnerAccepted ?? this.partnerAccepted,
      arrivedAtShopTime: arrivedAtShopTime,
      orderReadyTime: orderReadyTime,
      waitTimePenalty: waitTimePenalty,
      waitTimeDisputed: waitTimeDisputed,
      hasCustomerRated: hasCustomerRated ?? this.hasCustomerRated,
      hasSellerRated: hasSellerRated ?? this.hasSellerRated,
      hasDeliveryRated: hasDeliveryRated ?? this.hasDeliveryRated,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      riderLat: riderLat ?? this.riderLat,
      riderLng: riderLng ?? this.riderLng,
      riderLocationUpdatedAt: riderLocationUpdatedAt ?? this.riderLocationUpdatedAt,
      shopLat: shopLat ?? this.shopLat,
      shopLng: shopLng ?? this.shopLng,
      // Preserve frozen financial fields unchanged
      gstItemTotal: gstItemTotal,
      s9_5GstAmount: s9_5GstAmount,
      nonFoodGstAmount: nonFoodGstAmount,
      gstDelivery: gstDelivery,
      gstPlatform: gstPlatform,
      tcsAmount: tcsAmount,
      enythingCommission: enythingCommission,
      sellerPayout: sellerPayout,
      gatewayDeduction: gatewayDeduction,
      grandTotalCollected: grandTotalCollected,
      gstRateSnapshot: gstRateSnapshot,
      prescriptionUrls: prescriptionUrls,
      estimatedDistanceKm: estimatedDistanceKm,
      shopPrepTimeSnapshot: shopPrepTimeSnapshot,
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
          case 'shop_rejected': return 'Shop Declined';
          case 'no_rider':      return 'No Rider Available';
          case 'timeout':       return 'Order Expired';
          case 'customer':      return 'Cancelled by You';
          default:              return 'Cancelled';
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
  final int quantity;
  final double price;
  final double weightKg;
  final String? specialInstructions;
  final bool requiresPrescription;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.weightKg,
    this.specialInstructions,
    this.requiresPrescription = false,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] ?? '',
      productId: map['product_id'] ?? '',
      productName: map['product_name'] ?? '',
      quantity: map['quantity'] ?? 1,
      price: (map['price'] ?? 0.0).toDouble(),
      weightKg: (map['weight_kg'] ?? 0.0).toDouble(),
      specialInstructions: map['special_instructions'],
      requiresPrescription: map['requires_prescription'] ?? false,
    );
  }

  double get totalPrice => price * quantity;
}
