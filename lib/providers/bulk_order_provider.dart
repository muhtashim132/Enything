// ============================================================================
// bulk_order_provider.dart — State Management for Bulk & Event Catering
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bulk_order_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/platform_config_provider.dart';
import '../config/payment_config.dart';

class BulkCartItem {
  final ProductModel product;
  int quantity;
  String? specialInstructions;

  BulkCartItem({
    required this.product,
    required this.quantity,
    this.specialInstructions,
  });

  double get unitPrice => product.getPriceForQuantity(quantity);
  double get totalPrice => unitPrice * quantity;
  double get totalWeightKg => (product.weightPerUnit ?? 0.5) * quantity;

  Map<String, dynamic> toMap() => {
    'product': product.toMap(),
    'quantity': quantity,
    'special_instructions': specialInstructions,
  };

  factory BulkCartItem.fromMap(Map<String, dynamic> map) {
    return BulkCartItem(
      product: ProductModel.fromMap(Map<String, dynamic>.from(map['product'] as Map)),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      specialInstructions: map['special_instructions']?.toString(),
    );
  }
}

class BulkOrderProvider with ChangeNotifier {
  SupabaseClient get _supabase => Supabase.instance.client;

  ShopModel? _selectedShop;
  ShopModel? get selectedShop => _selectedShop;

  final Map<String, BulkCartItem> _items = {};
  Map<String, BulkCartItem> get items => Map.unmodifiable(_items);

  // Event Metadata
  String _eventName = '';
  String get eventName => _eventName;

  DateTime? _eventDate;
  DateTime? get eventDate => _eventDate;

  TimeOfDay? _slotStartTime;
  TimeOfDay? get slotStartTime => _slotStartTime;

  TimeOfDay? _slotEndTime;
  TimeOfDay? get slotEndTime => _slotEndTime;

  String _venueAddress = '';
  String get venueAddress => _venueAddress;

  double? _deliveryLat;
  double? get deliveryLat => _deliveryLat;

  double? _deliveryLng;
  double? get deliveryLng => _deliveryLng;

  String _venueDeliveryNotes = '';
  String get venueDeliveryNotes => _venueDeliveryNotes;

  String _contactPersonName = '';
  String get contactPersonName => _contactPersonName;

  String _contactPersonPhone = '';
  String get contactPersonPhone => _contactPersonPhone;

  String _secondaryContactPhone = '';
  String get secondaryContactPhone => _secondaryContactPhone;

  String _gatePassInstructions = '';
  String get gatePassInstructions => _gatePassInstructions;

  String _deliveryMethod = 'platform_fleet';
  String get deliveryMethod => _deliveryMethod;

  String _vehicleTypeRequired = 'any';
  String get vehicleTypeRequired => _vehicleTypeRequired;

  // Slots State
  bool _isLoadingSlots = false;
  bool get isLoadingSlots => _isLoadingSlots;

  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> get availableSlots => _availableSlots;

  // Customer Bulk Orders State
  bool _isLoadingOrders = false;
  bool get isLoadingOrders => _isLoadingOrders;

  List<OrderModel> _customerBulkOrders = [];
  List<OrderModel> get customerBulkOrders => _customerBulkOrders;

  final Map<String, BulkOrderModel> _bulkMetadataMap = {};
  Map<String, BulkOrderModel> get bulkMetadataMap => _bulkMetadataMap;

  StreamSubscription? _bulkOrdersSubscription;

  BulkOrderProvider() {
    loadDraft();
  }

  @override
  void dispose() {
    _bulkOrdersSubscription?.cancel();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shop Selection & Cart Operations
  // ───────────────────────────────────────────────────────────────────────────
  void setShop(ShopModel shop) {
    if (_selectedShop?.id != shop.id) {
      _selectedShop = shop;
      _items.clear();
      saveDraft();
      notifyListeners();
    }
  }

  void addToCart(ProductModel product, {int? quantity, String? specialInstructions}) {
    if (_selectedShop != null && _selectedShop!.id != product.shopId) {
      _items.clear();
    }

    final minQty = product.minBulkQuantity ?? 20;
    final initialQty = quantity ?? minQty;

    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity += initialQty;
      if (specialInstructions != null) {
        _items[product.id]!.specialInstructions = specialInstructions;
      }
    } else {
      _items[product.id] = BulkCartItem(
        product: product,
        quantity: initialQty,
        specialInstructions: specialInstructions,
      );
    }

    saveDraft();
    notifyListeners();
  }

  void updateQuantity(String productId, int newQuantity) {
    if (!_items.containsKey(productId)) return;

    final item = _items[productId]!;
    final minQty = item.product.minBulkQuantity ?? 20;

    if (newQuantity < minQty) {
      _items.remove(productId);
    } else {
      item.quantity = newQuantity;
    }

    saveDraft();
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _items.remove(productId);
    saveDraft();
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _selectedShop = null;
    clearDraft();
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Event Metadata Setters
  // ───────────────────────────────────────────────────────────────────────────
  void setEventDetails({
    String? name,
    DateTime? date,
    TimeOfDay? start,
    TimeOfDay? end,
    String? venue,
    double? lat,
    double? lng,
    String? notes,
    String? contactName,
    String? contactPhone,
    String? secondaryPhone,
    String? gatePass,
    String? method,
    String? vehicleType,
  }) {
    if (name != null) _eventName = name;
    if (date != null) _eventDate = date;
    if (start != null) _slotStartTime = start;
    if (end != null) _slotEndTime = end;
    if (venue != null) _venueAddress = venue;
    if (lat != null) _deliveryLat = lat;
    if (lng != null) _deliveryLng = lng;
    if (notes != null) _venueDeliveryNotes = notes;
    if (contactName != null) _contactPersonName = contactName;
    if (contactPhone != null) _contactPersonPhone = contactPhone;
    if (secondaryPhone != null) _secondaryContactPhone = secondaryPhone;
    if (gatePass != null) _gatePassInstructions = gatePass;
    if (method != null) _deliveryMethod = method;
    if (vehicleType != null) _vehicleTypeRequired = vehicleType;

    saveDraft();
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Financial Computations
  // ───────────────────────────────────────────────────────────────────────────
  double get subtotal => _items.values.fold(0.0, (sum, i) => sum + i.totalPrice);
  int get totalItems => _items.values.fold(0, (sum, i) => sum + i.quantity);
  double get totalWeightKg => _items.values.fold(0.0, (sum, i) => sum + i.totalWeightKg);

  int get estimatedPackages => (totalItems / 30.0).ceil().clamp(1, 100);

  double get deliveryCharges {
    const baseFee = 150.0;
    final extraPackageFee = (estimatedPackages > 1) ? (estimatedPackages - 1) * 40.0 : 0.0;
    return baseFee + extraPackageFee;
  }

  double get platformFee =>
      PlatformConfigProvider.instance?.platformFee ??
      PaymentConfig.platformFee;

  double get heavyOrderFee {
    if (totalWeightKg > 15.0) {
      return ((totalWeightKg - 15.0) * 5.0).roundToDouble();
    }
    return 0.0;
  }

  double get estimatedGst => (subtotal * 0.05);

  double get grandTotal => subtotal + deliveryCharges + platformFee + heavyOrderFee;

  // ───────────────────────────────────────────────────────────────────────────
  // Slot Availability
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> fetchSlotAvailability(String shopId, DateTime date) async {
    _isLoadingSlots = true;
    notifyListeners();

    try {
      final formattedDate =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final response = await _supabase.rpc(
        'get_bulk_slot_availability',
        params: {
          'p_shop_id': shopId,
          'p_date': formattedDate,
        },
      );

      if (response is List) {
        _availableSlots = response.map((s) => Map<String, dynamic>.from(s as Map)).toList();
      } else {
        _availableSlots = [];
      }
    } catch (e) {
      debugPrint('Error fetching bulk slot availability: $e');
      _availableSlots = [];
    } finally {
      _isLoadingSlots = false;
      notifyListeners();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Draft Persistence & Restoration (Edge Case 4)
  // ───────────────────────────────────────────────────────────────────────────
  static const String _draftKey = 'enything_bulk_order_draft_v1';

  Future<void> saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'shop': _selectedShop?.toMap(),
        'items': _items.map((key, val) => MapEntry(key, val.toMap())),
        'eventName': _eventName,
        'eventDate': _eventDate?.toIso8601String(),
        'slotStartH': _slotStartTime?.hour,
        'slotStartM': _slotStartTime?.minute,
        'slotEndH': _slotEndTime?.hour,
        'slotEndM': _slotEndTime?.minute,
        'venueAddress': _venueAddress,
        'deliveryLat': _deliveryLat,
        'deliveryLng': _deliveryLng,
        'venueDeliveryNotes': _venueDeliveryNotes,
        'contactPersonName': _contactPersonName,
        'contactPersonPhone': _contactPersonPhone,
        'secondaryContactPhone': _secondaryContactPhone,
        'gatePassInstructions': _gatePassInstructions,
        'deliveryMethod': _deliveryMethod,
        'vehicleTypeRequired': _vehicleTypeRequired,
      };
      await prefs.setString(_draftKey, jsonEncode(draft));
    } catch (e) {
      debugPrint('Failed to save bulk order draft: $e');
    }
  }

  Future<void> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString(_draftKey);
      if (draftStr == null) return;

      final draft = jsonDecode(draftStr) as Map<String, dynamic>;

      if (draft['shop'] != null) {
        _selectedShop = ShopModel.fromMap(Map<String, dynamic>.from(draft['shop'] as Map));
      }

      if (draft['items'] != null) {
        final itemsMap = draft['items'] as Map<String, dynamic>;
        _items.clear();
        itemsMap.forEach((k, v) {
          _items[k] = BulkCartItem.fromMap(Map<String, dynamic>.from(v as Map));
        });
      }

      _eventName = draft['eventName']?.toString() ?? '';
      if (draft['eventDate'] != null) {
        _eventDate = DateTime.tryParse(draft['eventDate'].toString());
      }
      if (draft['slotStartH'] != null && draft['slotStartM'] != null) {
        _slotStartTime = TimeOfDay(
          hour: draft['slotStartH'] as int,
          minute: draft['slotStartM'] as int,
        );
      }
      if (draft['slotEndH'] != null && draft['slotEndM'] != null) {
        _slotEndTime = TimeOfDay(
          hour: draft['slotEndH'] as int,
          minute: draft['slotEndM'] as int,
        );
      }

      _venueAddress = draft['venueAddress']?.toString() ?? '';
      _deliveryLat = (draft['deliveryLat'] as num?)?.toDouble();
      _deliveryLng = (draft['deliveryLng'] as num?)?.toDouble();
      _venueDeliveryNotes = draft['venueDeliveryNotes']?.toString() ?? '';
      _contactPersonName = draft['contactPersonName']?.toString() ?? '';
      _contactPersonPhone = draft['contactPersonPhone']?.toString() ?? '';
      _secondaryContactPhone = draft['secondaryContactPhone']?.toString() ?? '';
      _gatePassInstructions = draft['gatePassInstructions']?.toString() ?? '';
      _deliveryMethod = draft['deliveryMethod']?.toString() ?? 'platform_fleet';
      _vehicleTypeRequired = draft['vehicleTypeRequired']?.toString() ?? 'any';

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load bulk order draft: $e');
    }
  }

  Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Place Bulk Order via RPC
  // ───────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> placeOrder({
    String? idempotencyKey,
  }) async {
    if (_selectedShop == null) {
      throw StateError('Please select a shop for your bulk order');
    }
    if (_items.isEmpty) {
      throw StateError('Your bulk cart is empty');
    }
    if (_eventDate == null || _slotStartTime == null || _slotEndTime == null) {
      throw StateError('Please specify an event date and delivery time slot');
    }
    if (_contactPersonName.trim().isEmpty || _contactPersonPhone.trim().isEmpty) {
      throw StateError('Contact person name and phone number are required');
    }

    final formattedEventDate =
        '${_eventDate!.year.toString().padLeft(4, '0')}-${_eventDate!.month.toString().padLeft(2, '0')}-${_eventDate!.day.toString().padLeft(2, '0')}';

    final startDateTime = DateTime(
      _eventDate!.year,
      _eventDate!.month,
      _eventDate!.day,
      _slotStartTime!.hour,
      _slotStartTime!.minute,
    );

    final endDateTime = DateTime(
      _eventDate!.year,
      _eventDate!.month,
      _eventDate!.day,
      _slotEndTime!.hour,
      _slotEndTime!.minute,
    );

    final orderPayload = {
      'shop_id': _selectedShop!.id,
      'address': _venueAddress,
      'address_label': 'Event Venue',
      'customer_phone': _contactPersonPhone,
      'delivery_lat': _deliveryLat ?? _selectedShop!.location.latitude,
      'delivery_lng': _deliveryLng ?? _selectedShop!.location.longitude,
      'total_amount': subtotal,
      'delivery_charges': deliveryCharges,
      'platform_fee': platformFee,
      'heavy_order_fee': heavyOrderFee,
      'grand_total_collected': grandTotal,
    };

    final itemsPayload = _items.values.map((i) => {
      'product_id': i.product.id,
      'product_name': i.product.name,
      'quantity': i.quantity,
      'price': i.unitPrice,
      'weight_kg': i.totalWeightKg,
      'special_instructions': i.specialInstructions,
    }).toList();

    final eventMetadataPayload = {
      'event_name': _eventName.isEmpty ? 'Catering Event' : _eventName,
      'event_date': formattedEventDate,
      'delivery_time_slot_start': startDateTime.toIso8601String(),
      'delivery_time_slot_end': endDateTime.toIso8601String(),
      'venue_address': _venueAddress,
      'venue_delivery_notes': _venueDeliveryNotes,
      'contact_person_name': _contactPersonName,
      'contact_person_phone': _contactPersonPhone,
      'secondary_contact_phone': _secondaryContactPhone,
      'gatePassInstructions': _gatePassInstructions,
      'delivery_method': _deliveryMethod,
      'total_packages_estimate': estimatedPackages,
      'vehicle_type_required': _vehicleTypeRequired,
    };

    final response = await _supabase.rpc(
      'place_bulk_order_transaction',
      params: {
        'p_order': orderPayload,
        'p_items': itemsPayload,
        'p_event_metadata': eventMetadataPayload,
        'p_idempotency_key': idempotencyKey,
      },
    );

    final resultMap = Map<String, dynamic>.from(response as Map);

    // Order placed successfully: clear cart & draft
    clearCart();

    return resultMap;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Customer Bulk Order History & Realtime Tracking
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> loadCustomerBulkOrders() async {
    _isLoadingOrders = true;
    notifyListeners();

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _customerBulkOrders = [];
        return;
      }

      final ordersData = await _supabase
          .from('orders')
          .select()
          .eq('customer_id', user.id)
          .inFilter('order_type', ['bulk', 'manual_quote'])
          .order('created_at', ascending: false);

      _customerBulkOrders = (ordersData as List)
          .map((m) => OrderModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();

      if (_customerBulkOrders.isNotEmpty) {
        final orderIds = _customerBulkOrders.map((o) => o.id).toList();
        final bulkData = await _supabase
            .from('bulk_orders')
            .select()
            .inFilter('order_id', orderIds);

        _bulkMetadataMap.clear();
        for (final b in (bulkData as List)) {
          final model = BulkOrderModel.fromMap(Map<String, dynamic>.from(b as Map));
          _bulkMetadataMap[model.orderId] = model;
        }
      }
    } catch (e) {
      debugPrint('Error loading customer bulk orders: $e');
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> cancelBulkOrder(String orderId, {String? reason}) async {
    await _supabase.rpc(
      'cancel_bulk_order',
      params: {
        'p_order_id': orderId,
        'p_reason': reason ?? 'Customer cancelled bulk catering order',
      },
    );

    await loadCustomerBulkOrders();
  }

  Future<void> respondToModification(String orderId, bool accept) async {
    await _supabase.rpc(
      'respond_bulk_order_customer_modification',
      params: {
        'p_order_id': orderId,
        'p_accept': accept,
      },
    );

    await loadCustomerBulkOrders();
  }
}
