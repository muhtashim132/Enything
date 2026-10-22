// ============================================================================
// quote_request_model.dart — Manual Quotation & Custom Event Catering Request
// ============================================================================

class QuoteLineItem {
  final String item;
  final double price;

  const QuoteLineItem({
    required this.item,
    required this.price,
  });

  factory QuoteLineItem.fromMap(Map<String, dynamic> map) {
    return QuoteLineItem(
      item: map['item'] as String? ?? '',
      price: map['price'] is num
          ? (map['price'] as num).toDouble()
          : (double.tryParse(map['price']?.toString() ?? '') ?? 0.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'item': item,
        'price': price,
      };
}

class QuoteRequestModel {
  final String id;
  final String customerId;
  final String? customerName;
  final String customerPhone;

  // Event Details
  final String eventName;
  final String eventType;
  final DateTime eventDate;
  final int estimatedGuestCount;
  final String? dietaryPreferences;
  final String requirementsDescription;

  // Venue & Delivery
  final String? venueAddress;
  final double? venueLat;
  final double? venueLng;
  final String? venueDeliveryNotes;
  final String? preferredDeliveryTime;
  final String contactPersonName;
  final String contactPersonPhone;
  final String? secondaryContactPhone;
  final String? gatePassInstructions;

  // Optional Preferred Shop
  final String? preferredShopId;
  final String? preferredShopName;

  // Lifecycle Status
  final String quoteStatus;

  // Admin Review
  final String? reviewedBy;
  final DateTime? reviewedAt;

  // Quoted Financials (Offline model — simple flat amount)
  final double? quotedAmount;
  final String? quotedNotes;
  final DateTime? quotedValidUntil;
  final List<QuoteLineItem> quotedLineItems;

  // Customer Response
  final DateTime? customerResponseAt;
  final String? customerRejectionReason;

  // Offline Payment Tracking
  final String? paymentMethod;
  final String? paymentReference;
  final DateTime? paymentReceivedAt;
  final String? paymentConfirmedBy;

  // Resulting Order
  final String? resultingOrderId;

  // Timestamps
  final DateTime createdAt;
  final DateTime? updatedAt;

  const QuoteRequestModel({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.customerPhone,
    required this.eventName,
    this.eventType = 'custom',
    required this.eventDate,
    required this.estimatedGuestCount,
    this.dietaryPreferences,
    required this.requirementsDescription,
    this.venueAddress,
    this.venueLat,
    this.venueLng,
    this.venueDeliveryNotes,
    this.preferredDeliveryTime,
    required this.contactPersonName,
    required this.contactPersonPhone,
    this.secondaryContactPhone,
    this.gatePassInstructions,
    this.preferredShopId,
    this.preferredShopName,
    this.quoteStatus = 'pending_review',
    this.reviewedBy,
    this.reviewedAt,
    this.quotedAmount,
    this.quotedNotes,
    this.quotedValidUntil,
    this.quotedLineItems = const [],
    this.customerResponseAt,
    this.customerRejectionReason,
    this.paymentMethod,
    this.paymentReference,
    this.paymentReceivedAt,
    this.paymentConfirmedBy,
    this.resultingOrderId,
    required this.createdAt,
    this.updatedAt,
  });

  factory QuoteRequestModel.fromMap(Map<String, dynamic> map) {
    // Parse line items
    List<QuoteLineItem> lineItems = [];
    if (map['quoted_line_items'] != null && map['quoted_line_items'] is List) {
      lineItems = (map['quoted_line_items'] as List)
          .map((item) => QuoteLineItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    return QuoteRequestModel(
      id: map['id'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String? ?? '',
      eventName: map['event_name'] as String? ?? 'Catering Event',
      eventType: map['event_type'] as String? ?? 'custom',
      eventDate: map['event_date'] != null
          ? DateTime.tryParse(map['event_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      estimatedGuestCount: (map['estimated_guest_count'] as num?)?.toInt() ?? 1,
      dietaryPreferences: map['dietary_preferences'] as String?,
      requirementsDescription: map['requirements_description'] as String? ?? '',
      venueAddress: map['venue_address'] as String?,
      venueLat: map['venue_lat'] is num
          ? (map['venue_lat'] as num).toDouble()
          : (double.tryParse(map['venue_lat']?.toString() ?? '')),
      venueLng: map['venue_lng'] is num
          ? (map['venue_lng'] as num).toDouble()
          : (double.tryParse(map['venue_lng']?.toString() ?? '')),
      venueDeliveryNotes: map['venue_delivery_notes'] as String?,
      preferredDeliveryTime: map['preferred_delivery_time'] as String?,
      contactPersonName: map['contact_person_name'] as String? ?? '',
      contactPersonPhone: map['contact_person_phone'] as String? ?? '',
      secondaryContactPhone: map['secondary_contact_phone'] as String?,
      gatePassInstructions: map['gate_pass_instructions'] as String?,
      preferredShopId: map['preferred_shop_id'] as String?,
      preferredShopName: map['preferred_shop_name'] as String?,
      quoteStatus: map['quote_status'] as String? ?? 'pending_review',
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] != null
          ? DateTime.tryParse(map['reviewed_at'].toString())
          : null,
      quotedAmount: map['quoted_amount'] is num
          ? (map['quoted_amount'] as num).toDouble()
          : (double.tryParse(map['quoted_amount']?.toString() ?? '')),
      quotedNotes: map['quoted_notes'] as String?,
      quotedValidUntil: map['quoted_valid_until'] != null
          ? DateTime.tryParse(map['quoted_valid_until'].toString())
          : null,
      quotedLineItems: lineItems,
      customerResponseAt: map['customer_response_at'] != null
          ? DateTime.tryParse(map['customer_response_at'].toString())
          : null,
      customerRejectionReason: map['customer_rejection_reason'] as String?,
      paymentMethod: map['payment_method'] as String?,
      paymentReference: map['payment_reference'] as String?,
      paymentReceivedAt: map['payment_received_at'] != null
          ? DateTime.tryParse(map['payment_received_at'].toString())
          : null,
      paymentConfirmedBy: map['payment_confirmed_by'] as String?,
      resultingOrderId: map['resulting_order_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'event_name': eventName,
      'event_type': eventType,
      'event_date': eventDate.toIso8601String().split('T').first,
      'estimated_guest_count': estimatedGuestCount,
      'dietary_preferences': dietaryPreferences,
      'requirements_description': requirementsDescription,
      'venue_address': venueAddress,
      'venue_lat': venueLat,
      'venue_lng': venueLng,
      'venue_delivery_notes': venueDeliveryNotes,
      'preferred_delivery_time': preferredDeliveryTime,
      'contact_person_name': contactPersonName,
      'contact_person_phone': contactPersonPhone,
      'secondary_contact_phone': secondaryContactPhone,
      'gate_pass_instructions': gatePassInstructions,
      'preferred_shop_id': preferredShopId,
      'preferred_shop_name': preferredShopName,
      'quote_status': quoteStatus,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'quoted_amount': quotedAmount,
      'quoted_notes': quotedNotes,
      'quoted_valid_until': quotedValidUntil?.toIso8601String(),
      'quoted_line_items': quotedLineItems.map((e) => e.toMap()).toList(),
      'customer_response_at': customerResponseAt?.toIso8601String(),
      'customer_rejection_reason': customerRejectionReason,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'payment_received_at': paymentReceivedAt?.toIso8601String(),
      'payment_confirmed_by': paymentConfirmedBy,
      'resulting_order_id': resultingOrderId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // ─── Computed Getters ───
  bool get isPendingReview => quoteStatus == 'pending_review';
  bool get isQuoted => quoteStatus == 'quoted';
  bool get isAccepted => quoteStatus == 'customer_accepted';
  bool get isRejected => quoteStatus == 'customer_rejected';
  bool get isPaid => quoteStatus == 'payment_received' || quoteStatus == 'order_placed';
  bool get isOrderPlaced => quoteStatus == 'order_placed';
  bool get isExpired => quoteStatus == 'expired' || isQuoteExpired;
  bool get isCancelled => quoteStatus == 'cancelled';
  bool get isTerminal => isRejected || isExpired || isCancelled || isOrderPlaced;

  bool get isQuoteExpired =>
      quotedValidUntil != null && DateTime.now().isAfter(quotedValidUntil!);

  bool get canAccept => isQuoted && !isQuoteExpired;
  bool get canMarkPaid => (isAccepted || isQuoted) && !isQuoteExpired;

  String get statusDisplay {
    switch (quoteStatus) {
      case 'pending_review':
        return 'Under Review';
      case 'quoted':
        return isQuoteExpired ? 'Quote Expired' : 'Quote Ready';
      case 'customer_accepted':
        return 'Accepted — Awaiting Payment';
      case 'customer_rejected':
        return 'Declined';
      case 'payment_received':
        return 'Payment Received';
      case 'order_placed':
        return 'Order Created';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return quoteStatus;
    }
  }

  QuoteRequestModel copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? eventName,
    String? eventType,
    DateTime? eventDate,
    int? estimatedGuestCount,
    String? dietaryPreferences,
    String? requirementsDescription,
    String? venueAddress,
    double? venueLat,
    double? venueLng,
    String? venueDeliveryNotes,
    String? preferredDeliveryTime,
    String? contactPersonName,
    String? contactPersonPhone,
    String? secondaryContactPhone,
    String? gatePassInstructions,
    String? preferredShopId,
    String? preferredShopName,
    String? quoteStatus,
    String? reviewedBy,
    DateTime? reviewedAt,
    double? quotedAmount,
    String? quotedNotes,
    DateTime? quotedValidUntil,
    List<QuoteLineItem>? quotedLineItems,
    DateTime? customerResponseAt,
    String? customerRejectionReason,
    String? paymentMethod,
    String? paymentReference,
    DateTime? paymentReceivedAt,
    String? paymentConfirmedBy,
    String? resultingOrderId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuoteRequestModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      eventName: eventName ?? this.eventName,
      eventType: eventType ?? this.eventType,
      eventDate: eventDate ?? this.eventDate,
      estimatedGuestCount: estimatedGuestCount ?? this.estimatedGuestCount,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      requirementsDescription: requirementsDescription ?? this.requirementsDescription,
      venueAddress: venueAddress ?? this.venueAddress,
      venueLat: venueLat ?? this.venueLat,
      venueLng: venueLng ?? this.venueLng,
      venueDeliveryNotes: venueDeliveryNotes ?? this.venueDeliveryNotes,
      preferredDeliveryTime: preferredDeliveryTime ?? this.preferredDeliveryTime,
      contactPersonName: contactPersonName ?? this.contactPersonName,
      contactPersonPhone: contactPersonPhone ?? this.contactPersonPhone,
      secondaryContactPhone: secondaryContactPhone ?? this.secondaryContactPhone,
      gatePassInstructions: gatePassInstructions ?? this.gatePassInstructions,
      preferredShopId: preferredShopId ?? this.preferredShopId,
      preferredShopName: preferredShopName ?? this.preferredShopName,
      quoteStatus: quoteStatus ?? this.quoteStatus,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      quotedAmount: quotedAmount ?? this.quotedAmount,
      quotedNotes: quotedNotes ?? this.quotedNotes,
      quotedValidUntil: quotedValidUntil ?? this.quotedValidUntil,
      quotedLineItems: quotedLineItems ?? this.quotedLineItems,
      customerResponseAt: customerResponseAt ?? this.customerResponseAt,
      customerRejectionReason: customerRejectionReason ?? this.customerRejectionReason,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      paymentReceivedAt: paymentReceivedAt ?? this.paymentReceivedAt,
      paymentConfirmedBy: paymentConfirmedBy ?? this.paymentConfirmedBy,
      resultingOrderId: resultingOrderId ?? this.resultingOrderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
