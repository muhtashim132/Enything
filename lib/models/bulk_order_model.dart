// ============================================================================
// bulk_order_model.dart — Enything Bulk & Event Catering Metadata Model
// ============================================================================

import 'package:intl/intl.dart';

class BulkOrderModel {
  final String id;
  final String orderId;
  final String? eventName;
  final DateTime eventDate;
  final DateTime deliveryTimeSlotStart;
  final DateTime deliveryTimeSlotEnd;
  final String? venueAddress;
  final String? venueDeliveryNotes;
  final String contactPersonName;
  final String contactPersonPhone;
  final String? secondaryContactPhone;
  final String? gatePassInstructions;
  final String? bulkDispatchGroupId;
  final String deliveryMethod; // 'platform_fleet' | 'merchant_delivery' | 'customer_pickup'
  final int totalPackagesEstimate;
  final String vehicleTypeRequired; // 'any' | '2_wheeler' | '3_wheeler' | '4_wheeler' | 'van' | 'truck'
  final String sellerResponseStatus; // 'pending' | 'accepted' | 'declined' | 'modification_proposed'
  final DateTime? sellerResponseAt;
  final String? sellerNotes;
  final Map<String, dynamic>? sellerModificationProposal;
  final String? customerModificationResponse; // 'accepted' | 'rejected' | null
  final String? cancellationTier; // 'full_refund' | 'half_refund' | 'no_refund' | null
  final int totalBatches;
  final int batchesPacked;
  final DateTime? prepStartedAt;
  final DateTime? allBatchesPackedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  BulkOrderModel({
    required this.id,
    required this.orderId,
    this.eventName,
    required this.eventDate,
    required this.deliveryTimeSlotStart,
    required this.deliveryTimeSlotEnd,
    this.venueAddress,
    this.venueDeliveryNotes,
    required this.contactPersonName,
    required this.contactPersonPhone,
    this.secondaryContactPhone,
    this.gatePassInstructions,
    this.bulkDispatchGroupId,
    this.deliveryMethod = 'platform_fleet',
    this.totalPackagesEstimate = 1,
    this.vehicleTypeRequired = 'any',
    this.sellerResponseStatus = 'pending',
    this.sellerResponseAt,
    this.sellerNotes,
    this.sellerModificationProposal,
    this.customerModificationResponse,
    this.cancellationTier,
    this.totalBatches = 1,
    this.batchesPacked = 0,
    this.prepStartedAt,
    this.allBatchesPackedAt,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isPending => sellerResponseStatus == 'pending';
  bool get isAccepted => sellerResponseStatus == 'accepted';
  bool get isDeclined => sellerResponseStatus == 'declined';
  bool get isModificationProposed => sellerResponseStatus == 'modification_proposed';

  bool get isAllPacked => totalBatches > 0 && batchesPacked >= totalBatches;
  double get packagingProgress =>
      totalBatches > 0 ? (batchesPacked / totalBatches).clamp(0.0, 1.0) : 0.0;

  String get slotDisplay {
    final startFormat = DateFormat('h:mm a').format(deliveryTimeSlotStart.toLocal());
    final endFormat = DateFormat('h:mm a').format(deliveryTimeSlotEnd.toLocal());
    return '$startFormat – $endFormat';
  }

  String get eventDateDisplay {
    return DateFormat('EEE, MMM d, yyyy').format(eventDate.toLocal());
  }

  factory BulkOrderModel.fromMap(Map<String, dynamic> map) {
    return BulkOrderModel(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString() ?? '',
      eventName: map['event_name']?.toString(),
      eventDate: DateTime.tryParse(map['event_date']?.toString() ?? '') ?? DateTime.now(),
      deliveryTimeSlotStart: DateTime.tryParse(map['delivery_time_slot_start']?.toString() ?? '') ?? DateTime.now(),
      deliveryTimeSlotEnd: DateTime.tryParse(map['delivery_time_slot_end']?.toString() ?? '') ?? DateTime.now(),
      venueAddress: map['venue_address']?.toString(),
      venueDeliveryNotes: map['venue_delivery_notes']?.toString(),
      contactPersonName: map['contact_person_name']?.toString() ?? '',
      contactPersonPhone: map['contact_person_phone']?.toString() ?? '',
      secondaryContactPhone: map['secondary_contact_phone']?.toString(),
      gatePassInstructions: map['gate_pass_instructions']?.toString(),
      bulkDispatchGroupId: map['bulk_dispatch_group_id']?.toString(),
      deliveryMethod: map['delivery_method']?.toString() ?? 'platform_fleet',
      totalPackagesEstimate: (map['total_packages_estimate'] as num?)?.toInt() ?? 1,
      vehicleTypeRequired: map['vehicle_type_required']?.toString() ?? 'any',
      sellerResponseStatus: map['seller_response_status']?.toString() ?? 'pending',
      sellerResponseAt: map['seller_response_at'] != null
          ? DateTime.tryParse(map['seller_response_at'].toString())
          : null,
      sellerNotes: map['seller_notes']?.toString(),
      sellerModificationProposal: map['seller_modification_proposal'] is Map
          ? Map<String, dynamic>.from(map['seller_modification_proposal'] as Map)
          : null,
      customerModificationResponse: map['customer_modification_response']?.toString(),
      cancellationTier: map['cancellation_tier']?.toString(),
      totalBatches: (map['total_batches'] as num?)?.toInt() ?? 1,
      batchesPacked: (map['batches_packed'] as num?)?.toInt() ?? 0,
      prepStartedAt: map['prep_started_at'] != null
          ? DateTime.tryParse(map['prep_started_at'].toString())
          : null,
      allBatchesPackedAt: map['all_batches_packed_at'] != null
          ? DateTime.tryParse(map['all_batches_packed_at'].toString())
          : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'order_id': orderId,
    'event_name': eventName,
    'event_date': DateFormat('yyyy-MM-dd').format(eventDate),
    'delivery_time_slot_start': deliveryTimeSlotStart.toIso8601String(),
    'delivery_time_slot_end': deliveryTimeSlotEnd.toIso8601String(),
    'venue_address': venueAddress,
    'venue_delivery_notes': venueDeliveryNotes,
    'contact_person_name': contactPersonName,
    'contact_person_phone': contactPersonPhone,
    'secondary_contact_phone': secondaryContactPhone,
    'gate_pass_instructions': gatePassInstructions,
    'bulk_dispatch_group_id': bulkDispatchGroupId,
    'delivery_method': deliveryMethod,
    'total_packages_estimate': totalPackagesEstimate,
    'vehicle_type_required': vehicleTypeRequired,
    'seller_response_status': sellerResponseStatus,
    'seller_response_at': sellerResponseAt?.toIso8601String(),
    'seller_notes': sellerNotes,
    'seller_modification_proposal': sellerModificationProposal,
    'customer_modification_response': customerModificationResponse,
    'cancellation_tier': cancellationTier,
    'total_batches': totalBatches,
    'batches_packed': batchesPacked,
    'prep_started_at': prepStartedAt?.toIso8601String(),
    'all_batches_packed_at': allBatchesPackedAt?.toIso8601String(),
  };

  BulkOrderModel copyWith({
    String? id,
    String? orderId,
    String? eventName,
    DateTime? eventDate,
    DateTime? deliveryTimeSlotStart,
    DateTime? deliveryTimeSlotEnd,
    String? venueAddress,
    String? venueDeliveryNotes,
    String? contactPersonName,
    String? contactPersonPhone,
    String? secondaryContactPhone,
    String? gatePassInstructions,
    String? bulkDispatchGroupId,
    String? deliveryMethod,
    int? totalPackagesEstimate,
    String? vehicleTypeRequired,
    String? sellerResponseStatus,
    DateTime? sellerResponseAt,
    String? sellerNotes,
    Map<String, dynamic>? sellerModificationProposal,
    String? customerModificationResponse,
    String? cancellationTier,
    int? totalBatches,
    int? batchesPacked,
    DateTime? prepStartedAt,
    DateTime? allBatchesPackedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BulkOrderModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      eventName: eventName ?? this.eventName,
      eventDate: eventDate ?? this.eventDate,
      deliveryTimeSlotStart: deliveryTimeSlotStart ?? this.deliveryTimeSlotStart,
      deliveryTimeSlotEnd: deliveryTimeSlotEnd ?? this.deliveryTimeSlotEnd,
      venueAddress: venueAddress ?? this.venueAddress,
      venueDeliveryNotes: venueDeliveryNotes ?? this.venueDeliveryNotes,
      contactPersonName: contactPersonName ?? this.contactPersonName,
      contactPersonPhone: contactPersonPhone ?? this.contactPersonPhone,
      secondaryContactPhone: secondaryContactPhone ?? this.secondaryContactPhone,
      gatePassInstructions: gatePassInstructions ?? this.gatePassInstructions,
      bulkDispatchGroupId: bulkDispatchGroupId ?? this.bulkDispatchGroupId,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      totalPackagesEstimate: totalPackagesEstimate ?? this.totalPackagesEstimate,
      vehicleTypeRequired: vehicleTypeRequired ?? this.vehicleTypeRequired,
      sellerResponseStatus: sellerResponseStatus ?? this.sellerResponseStatus,
      sellerResponseAt: sellerResponseAt ?? this.sellerResponseAt,
      sellerNotes: sellerNotes ?? this.sellerNotes,
      sellerModificationProposal: sellerModificationProposal ?? this.sellerModificationProposal,
      customerModificationResponse: customerModificationResponse ?? this.customerModificationResponse,
      cancellationTier: cancellationTier ?? this.cancellationTier,
      totalBatches: totalBatches ?? this.totalBatches,
      batchesPacked: batchesPacked ?? this.batchesPacked,
      prepStartedAt: prepStartedAt ?? this.prepStartedAt,
      allBatchesPackedAt: allBatchesPackedAt ?? this.allBatchesPackedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
