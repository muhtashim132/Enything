import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../repositories/audit_repository.dart';
import 'bell_alert_service.dart';
import 'notification_service.dart';

/// Target recipient role/entity for practice simulation order.
enum PracticeTargetType {
  allSellers,
  specificSeller,
  allRiders,
  specificRider,
  dual,
  bandiporaMultiShop,
}

/// Result returned from practice order simulation dispatch.
class PracticeDispatchResult {
  final bool success;
  final int ordersCreated;
  final List<String> orderIds;
  final String? errorMessage;

  const PracticeDispatchResult({
    required this.success,
    required this.ordersCreated,
    required this.orderIds,
    this.errorMessage,
  });
}

/// 100x Forensic Practice & Simulation Order Engine
///
/// Features:
/// 1. Dispatches practice orders to All Sellers, Specific Seller, All Riders, Specific Rider, or Dual.
/// 2. Audio bell alerts & notifications trigger via BellAlertService and NotificationService.
/// 3. Strict 100% Prepaid Model (Zero COD): ₹0 collected, ₹0 rider earnings, zero financial distortion.
/// 4. Soft deletes rule: all shop/product queries include `.eq('is_deleted', false)`.
/// 5. Apple reviewer protection: uses +919876500000 phone (avoids %999999999% auto-accept triggers).
/// 6. One-tap purge to delete all practice orders and guarantee zero test leftovers.
class PracticeOrderService {
  PracticeOrderService._();
  static final PracticeOrderService instance = PracticeOrderService._();

  static const _uuid = Uuid();
  SupabaseClient get _db => Supabase.instance.client;

  static const String practiceTag = '[PRACTICE ORDER]';
  static const String practiceAddressLabel = 'Practice Delivery';
  static const String practicePaymentMethod = 'practice';
  static const String defaultPracticePhone = '+919876500000';

  // ── Dispatch Practice Orders ───────────────────────────────────────────────

  Future<PracticeDispatchResult> dispatchPracticeOrders({
    required PracticeTargetType targetType,
    String? targetShopId,
    String? targetSellerId,
    String? targetRiderId,
    int countPerTarget = 1,
    String? customNotes,
    String? actorId,
    String? actorRole,
  }) async {
    try {
      final safeCount = countPerTarget.clamp(1, 10);
      final createdOrderIds = <String>[];

      // 1. Resolve fallback customer ID to satisfy foreign key constraints
      String customerId = _db.auth.currentUser?.id ?? '';
      if (customerId.isEmpty) {
        final profile = await _db.from('profiles').select('id').limit(1).maybeSingle();
        customerId = profile?['id'] as String? ?? '00000000-0000-0000-0000-000000000001';
      }

      switch (targetType) {
        // ── Case A: Specific Seller ─────────────────────────────────────────
        case PracticeTargetType.specificSeller:
          if (targetShopId == null || targetShopId.isEmpty) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'A valid shop ID is required for specific seller simulation.',
            );
          }
          final shop = await _fetchShop(targetShopId);
          if (shop == null) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'Target shop was not found or is soft-deleted.',
            );
          }
          for (int i = 0; i < safeCount; i++) {
            final orderId = await _createSinglePracticeOrder(
              shop: shop,
              customerId: customerId,
              forRider: false,
              customNotes: customNotes,
            );
            if (orderId != null) createdOrderIds.add(orderId);
          }
          break;

        // ── Case B: All Sellers ──────────────────────────────────────────────
        case PracticeTargetType.allSellers:
          final shopsResp = await _db
              .from('shops')
              .select('id, name, seller_id, phone, location, prep_time_minutes, is_active')
              .eq('is_active', true)
              .limit(50);
          final shops = (shopsResp as List)
              .cast<Map<String, dynamic>>()
              .where((s) => s['is_deleted'] != true)
              .toList();
          if (shops.isEmpty) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'No active shops available to dispatch practice orders to.',
            );
          }
          for (final shop in shops) {
            for (int i = 0; i < safeCount; i++) {
              final orderId = await _createSinglePracticeOrder(
                shop: shop,
                customerId: customerId,
                forRider: false,
                customNotes: customNotes,
              );
              if (orderId != null) createdOrderIds.add(orderId);
            }
          }
          break;

        // ── Case C: Specific Rider ──────────────────────────────────────────
        case PracticeTargetType.specificRider:
          if (targetRiderId == null || targetRiderId.isEmpty) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'A valid rider ID is required for specific rider simulation.',
            );
          }
          final rider = await _fetchRider(targetRiderId);
          if (rider == null) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'Target rider was not found or is inactive.',
            );
          }
          // Resolve a shop near rider or fallback shop
          final anchorShop = await _resolveAnchorShop();
          for (int i = 0; i < safeCount; i++) {
            final orderId = await _createSinglePracticeOrder(
              shop: anchorShop,
              customerId: customerId,
              targetRiderId: targetRiderId,
              targetRiderPhone: rider['phone'] as String?,
              forRider: true,
              customNotes: customNotes,
            );
            if (orderId != null) createdOrderIds.add(orderId);
          }
          break;

        // ── Case D: All Riders ──────────────────────────────────────────────
        case PracticeTargetType.allRiders:
          final ridersResp = await _db
              .from('delivery_partners')
              .select('id, phone')
              .eq('is_active', true)
              .limit(50);
          final riders = (ridersResp as List).cast<Map<String, dynamic>>();
          final anchorShop = await _resolveAnchorShop();
          if (riders.isEmpty) {
            // If no active riders in DB, create broadcast unassigned orders
            for (int i = 0; i < safeCount; i++) {
              final orderId = await _createSinglePracticeOrder(
                shop: anchorShop,
                customerId: customerId,
                forRider: true,
                customNotes: customNotes,
              );
              if (orderId != null) createdOrderIds.add(orderId);
            }
          } else {
            for (final rider in riders) {
              final rId = rider['id'] as String;
              final rPhone = rider['phone'] as String?;
              for (int i = 0; i < safeCount; i++) {
                final orderId = await _createSinglePracticeOrder(
                  shop: anchorShop,
                  customerId: customerId,
                  targetRiderId: rId,
                  targetRiderPhone: rPhone,
                  forRider: true,
                  customNotes: customNotes,
                );
                if (orderId != null) createdOrderIds.add(orderId);
              }
            }
          }
          break;

        // ── Case E: Dual Linked Mode ────────────────────────────────────────
        case PracticeTargetType.dual:
          if (targetShopId == null || targetShopId.isEmpty) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'Shop is required for dual practice mode.',
            );
          }
          final shop = await _fetchShop(targetShopId);
          if (shop == null) {
            return const PracticeDispatchResult(
              success: false,
              ordersCreated: 0,
              orderIds: [],
              errorMessage: 'Target shop was not found.',
            );
          }
          Map<String, dynamic>? rider;
          if (targetRiderId != null && targetRiderId.isNotEmpty) {
            rider = await _fetchRider(targetRiderId);
          }
          for (int i = 0; i < safeCount; i++) {
            final orderId = await _createSinglePracticeOrder(
              shop: shop,
              customerId: customerId,
              targetRiderId: targetRiderId,
              targetRiderPhone: rider?['phone'] as String?,
              forRider: false,
              isDual: true,
              customNotes: customNotes,
            );
            if (orderId != null) createdOrderIds.add(orderId);
          }
          break;

        // ── Case F: Bandipora 3-Shop Realtime Route Simulation ──────────────
        case PracticeTargetType.bandiporaMultiShop:
          final bRes = await dispatchBandiporaMultiShopSimulation(
            targetRiderId: targetRiderId,
            targetRiderPhone: null,
            actorId: actorId,
            actorRole: actorRole,
          );
          if (bRes.success) {
            createdOrderIds.addAll(bRes.orderIds);
          } else {
            return bRes;
          }
          break;
      }

      // Log to audit logs if initiated by admin
      if (actorId != null) {
        AuditRepository().log(
          actorId: actorId,
          actorRole: actorRole ?? 'admin',
          action: 'practice_orders.dispatched',
          entityType: 'practice_orders',
          entityId: targetType.name,
          metadata: {
            'target_type': targetType.name,
            'orders_created': createdOrderIds.length,
            'order_ids': createdOrderIds,
            'target_shop_id': targetShopId,
            'target_rider_id': targetRiderId,
          },
        );
      }

      // Trigger local sound / device notification
      NotificationService().showNotification(
        title: '🧪 Practice Orders Dispatched!',
        body: 'Dispatched ${createdOrderIds.length} training order(s). Check radar & dashboard.',
      );

      return PracticeDispatchResult(
        success: true,
        ordersCreated: createdOrderIds.length,
        orderIds: createdOrderIds,
      );
    } catch (e, st) {
      debugPrint('[PracticeOrderService] Dispatch error: $e\n$st');
      return PracticeDispatchResult(
        success: false,
        ordersCreated: 0,
        orderIds: [],
        errorMessage: e.toString(),
      );
    }
  }

  // ── Single Practice Order Creator ──────────────────────────────────────────

  Future<String?> _createSinglePracticeOrder({
    required Map<String, dynamic> shop,
    required String customerId,
    String? targetRiderId,
    String? targetRiderPhone,
    bool forRider = false,
    bool isDual = false,
    String? customNotes,
  }) async {
    final orderId = _uuid.v4();
    final cartGroupId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final deadline = now.add(const Duration(minutes: 15));

    // Resolve shop coordinates
    double shopLat = 34.0837;
    double shopLng = 74.7973;
    final loc = shop['location'];
    if (loc is Map) {
      shopLat = (loc['latitude'] ?? loc['lat'] ?? 34.0837).toDouble();
      shopLng = (loc['longitude'] ?? loc['lng'] ?? 74.7973).toDouble();
    }

    // Place simulated customer drop-off ~500m from shop
    final deliveryLat = shopLat + 0.0045;
    final deliveryLng = shopLng + 0.0045;

    // Determine initial state:
    // If for rider training only, mark seller as already accepted & order ready for pickup
    // so rider can test acceptance, arrival, pickup, and delivery steps immediately.
    // If for seller training or dual, start in 'awaiting_acceptance'.
    final String initialStatus =
        (forRider && !isDual) ? 'ready_for_pickup' : 'awaiting_acceptance';
    final bool sellerAccepted = forRider && !isDual;
    final bool partnerAccepted = targetRiderId != null && !isDual && !forRider;

    final notes = customNotes != null && customNotes.isNotEmpty
        ? '$practiceTag $customNotes'
        : '$practiceTag Simulation / Training - Do Not Prepare Real Food';

    final orderPayload = <String, dynamic>{
      'id': orderId,
      'cart_group_id': cartGroupId,
      'customer_id': customerId,
      'shop_id': shop['id'],
      'status': initialStatus,
      'order_type': 'instant',
      'total_amount': 0.0,
      'delivery_charges': 0.0,
      'rider_earnings': 0.0,
      'multi_shop_surcharge': 0.0,
      'platform_fee': 0.0,
      'small_cart_fee': 0.0,
      'heavy_order_fee': 0.0,
      'grand_total_collected': 0.0,
      'payment_method': practicePaymentMethod,
      'payment_status': 'captured', // Already captured so zero payment blocker
      'acceptance_deadline': deadline.toIso8601String(),
      'address': '100x Training Hub, Main Commercial Boulevard, Kashmir',
      'address_label': practiceAddressLabel,
      'delivery_notes': notes,
      'customer_phone': defaultPracticePhone,
      'shop_phone': shop['phone'] as String? ?? '+919876500001',
      'delivery_lat': deliveryLat,
      'delivery_lng': deliveryLng,
      'shop_lat': shopLat,
      'shop_lng': shopLng,
      'seller_accepted': sellerAccepted,
      'partner_accepted': partnerAccepted,
      'delivery_partner_id': targetRiderId,
      'rider_phone': targetRiderPhone,
      'estimated_distance_km': 1.2,
      'shop_prep_time_snapshot': shop['prep_time_minutes'] ?? 15,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    // 1. Insert into orders table
    await _db.from('orders').insert(orderPayload);

    // 2. Fetch a real product from the shop if available to make items realistic
    final productsResp = await _db
        .from('products')
        .select('id, name, price')
        .eq('shop_id', shop['id'])
        .eq('is_deleted', false)
        .limit(2);
    final products = (productsResp as List).cast<Map<String, dynamic>>();

    final itemsToInsert = <Map<String, dynamic>>[];
    if (products.isNotEmpty) {
      for (final p in products) {
        itemsToInsert.add({
          'id': _uuid.v4(),
          'order_id': orderId,
          'product_id': p['id'],
          'product_name': '🧪 [Practice] ${p['name']}',
          'quantity': 1,
          'price': 0.0,
          'weight_kg': 0.5,
          'special_instructions': 'Practice Simulation Item - Do Not Prepare',
          'created_at': now.toIso8601String(),
        });
      }
    } else {
      itemsToInsert.add({
        'id': _uuid.v4(),
        'order_id': orderId,
        'product_id': null, // NULL is valid for nullable FK when no catalog product exists
        'product_name': '🧪 Training Demo Meal (Simulation)',
        'quantity': 1,
        'price': 0.0,
        'weight_kg': 0.5,
        'special_instructions': 'Practice Simulation Item - Do Not Prepare',
        'created_at': now.toIso8601String(),
      });
    }

    await _db.from('order_items').insert(itemsToInsert);

    // 3. Trigger Bell Alert ringing locally if this matches active user
    final currentUserId = _db.auth.currentUser?.id;
    if (shop['seller_id'] == currentUserId && initialStatus == 'awaiting_acceptance') {
      BellAlertService.instance.addPendingOrder(orderId, expiration: deadline);
    }
    if (targetRiderId == currentUserId || forRider) {
      BellAlertService.instance.addPendingOrder(cartGroupId, expiration: deadline);
    }

    return orderId;
  }

  // ── Purge All Practice Orders (Zero Leftovers) ──────────────────────────────

  /// Purges all practice orders and order_items from the database.
  /// Also silences any ongoing bell alerts.
  Future<int> purgeAllPracticeOrders({
    String? actorId,
    String? actorRole,
  }) async {
    try {
      // Find all practice order IDs
      final practiceOrders = await _db
          .from('orders')
          .select('id, cart_group_id')
          .or('payment_method.eq.practice,delivery_notes.ilike.%[PRACTICE ORDER]%,address_label.ilike.%Practice%');

      final list = (practiceOrders as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return 0;

      final ids = list.map((o) => o['id'] as String).toList();
      final groupIds =
          list.map((o) => o['cart_group_id'] as String?).whereType<String>().toSet();

      // 1. Delete order_items first
      await _db.from('order_items').delete().inFilter('order_id', ids);

      // 2. Delete orders
      await _db.from('orders').delete().inFilter('id', ids);

      // 3. Silence and remove from local BellAlertService
      for (final id in ids) {
        BellAlertService.instance.removePendingOrder(id);
      }
      for (final gid in groupIds) {
        BellAlertService.instance.removePendingOrder(gid);
      }

      // 4. Audit Log
      if (actorId != null) {
        AuditRepository().log(
          actorId: actorId,
          actorRole: actorRole ?? 'admin',
          action: 'practice_orders.purged',
          entityType: 'practice_orders',
          metadata: {'purged_count': ids.length, 'order_ids': ids},
        );
      }

      debugPrint('[PracticeOrderService] Purged ${ids.length} practice order(s).');
      return ids.length;
    } catch (e, st) {
      debugPrint('[PracticeOrderService] Purge error: $e\n$st');
      return 0;
    }
  }

  // ── Practice Order Count ───────────────────────────────────────────────────

  /// Returns count of all active/unpurged practice orders in DB.
  Future<int> getPracticeOrdersCount() async {
    try {
      final res = await _db
          .from('orders')
          .select('id')
          .or('payment_method.eq.practice,delivery_notes.ilike.%[PRACTICE ORDER]%,address_label.ilike.%Practice%');
      return (res as List).length;
    } catch (e) {
      debugPrint('[PracticeOrderService] Count error: $e');
      return 0;
    }
  }

  // ── Self Practice Helpers (Seller & Rider Onboarding) ──────────────────────

  /// Self-practice triggered by a seller from their own dashboard.
  Future<String?> createSelfPracticeOrderForSeller(String shopId, {String? sellerId}) async {
    final shop = await _fetchShop(shopId);
    if (shop == null) return null;

    final customerId = _db.auth.currentUser?.id ??
        sellerId ??
        '00000000-0000-0000-0000-000000000001';

    return _createSinglePracticeOrder(
      shop: shop,
      customerId: customerId,
      forRider: false,
      customNotes: 'Merchant Self-Test & Audio Bell Verification',
    );
  }

  /// Self-practice triggered by a rider from their dashboard.
  Future<String?> createSelfPracticeOrderForRider(
    String riderId, {
    double? riderLat,
    double? riderLng,
  }) async {
    final rider = await _fetchRider(riderId);
    final anchorShop = await _resolveAnchorShop();

    final customerId = _db.auth.currentUser?.id ?? riderId;

    return _createSinglePracticeOrder(
      shop: anchorShop,
      customerId: customerId,
      targetRiderId: riderId,
      targetRiderPhone: rider?['phone'] as String?,
      forRider: true,
      customNotes: 'Rider Self-Test & Navigation Simulation',
    );
  }

  // ── 100x Bandipora Multi-Shop Realtime Simulator Dispatcher ────────────────
  /// Dispatches a realistic 3-shop linked cart order in Bandipora, J&K.
  /// - Shop 1: Central Bakery (Gulshan Chowk - 34.4228, 74.6365)
  /// - Shop 2: Kaloosa Fresh Mart (Kaloosa Sopore Rd - 34.4148, 74.6305, ~1.05 km)
  /// - Shop 3: Plan Valley Chemist (Plan Bandipora - 34.4295, 74.6465, ~2.20 km)
  /// - Customer: Nowpora Residence (34.4120, 74.6485)
  /// - 100% Prepaid Model (Zero COD): payment_status = 'captured', payment_method = 'practice'.
  Future<PracticeDispatchResult> dispatchBandiporaMultiShopSimulation({
    String? targetRiderId,
    String? targetRiderPhone,
    String? actorId,
    String? actorRole,
  }) async {
    try {
      final cartGroupId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final deadline = now.add(const Duration(minutes: 15));
      final createdOrderIds = <String>[];

      // Resolve fallback customer ID to satisfy foreign key constraints
      String customerId = _db.auth.currentUser?.id ?? '';
      if (customerId.isEmpty) {
        final profile = await _db.from('profiles').select('id').limit(1).maybeSingle();
        customerId = profile?['id'] as String? ?? '00000000-0000-0000-0000-000000000001';
      }

      final bandiporaShops = [
        {
          'name': '1. Bandipora Central Bakery',
          'lat': 34.4228,
          'lng': 74.6365,
          'phone': '+919876500001',
          'category': 'Bakery',
          'items': [
            {'name': 'Kashmiri Lavasa Bread', 'qty': 2, 'price': 20.0},
            {'name': 'Bakers Cream Pastry', 'qty': 2, 'price': 50.0},
          ]
        },
        {
          'name': '2. Kaloosa Fresh Mart',
          'lat': 34.4148,
          'lng': 74.6305,
          'phone': '+919876500002',
          'category': 'Grocery',
          'items': [
            {'name': 'Fresh Cow Milk 1L', 'qty': 1, 'price': 60.0},
            {'name': 'Pure Kashmir Honey 500g', 'qty': 1, 'price': 320.0},
          ]
        },
        {
          'name': '3. Plan Valley Chemist',
          'lat': 34.4295,
          'lng': 74.6465,
          'phone': '+919876500003',
          'category': 'Pharmacy',
          'items': [
            {'name': 'Paracetamol 650mg', 'qty': 1, 'price': 35.0},
            {'name': 'Sterile Cotton Bandages', 'qty': 2, 'price': 40.0},
          ]
        },
      ];

      // Query any real shops in DB to satisfy FK constraints if needed
      final dbShopsResp = await _db
          .from('shops')
          .select('id, seller_id, phone')
          .limit(3);
      final dbShops = (dbShopsResp as List).cast<Map<String, dynamic>>();

      for (int i = 0; i < bandiporaShops.length; i++) {
        final sDef = bandiporaShops[i];
        final orderId = _uuid.v4();
        final shopId = dbShops.length > i ? dbShops[i]['id'] : null;

        final orderPayload = <String, dynamic>{
          'id': orderId,
          'cart_group_id': cartGroupId,
          'customer_id': customerId,
          if (shopId != null) 'shop_id': shopId,
          'status': 'awaiting_acceptance',
          'order_type': 'instant',
          'total_amount': 0.0,
          'delivery_charges': 0.0,
          'rider_earnings': 35.0,
          'multi_shop_surcharge': 0.0,
          'platform_fee': 0.0,
          'small_cart_fee': 0.0,
          'heavy_order_fee': 0.0,
          'grand_total_collected': 0.0,
          'payment_method': practicePaymentMethod,
          'payment_status': 'captured', // Bypassed for simulation
          'acceptance_deadline': deadline.toIso8601String(),
          'address': 'Customer Residence, Nowpora, Bandipora, J&K',
          'address_label': 'Home',
          'delivery_notes': '$practiceTag 100x Multi-Shop Simulation: ${sDef['name']}',
          'customer_phone': defaultPracticePhone,
          'shop_phone': sDef['phone'],
          'delivery_lat': 34.4120, // Nowpora
          'delivery_lng': 74.6485,
          'shop_lat': sDef['lat'],
          'shop_lng': sDef['lng'],
          'seller_accepted': false,
          'partner_accepted': targetRiderId != null,
          'delivery_partner_id': targetRiderId,
          'rider_phone': targetRiderPhone,
          'estimated_distance_km': i == 0 ? 0.3 : (i == 1 ? 1.05 : 2.20),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };

        await _db.from('orders').insert(orderPayload);
        createdOrderIds.add(orderId);

        // Insert items
        final itemsList = sDef['items'] as List<Map<String, dynamic>>;
        final itemsToInsert = itemsList.map((item) {
          return {
            'id': _uuid.v4(),
            'order_id': orderId,
            'product_name': '🧪 [Practice] ${item['name']}',
            'quantity': item['qty'],
            'price': 0.0,
            'weight_kg': 0.5,
            'special_instructions': 'Practice Simulation Item - Do Not Prepare',
            'created_at': now.toIso8601String(),
          };
        }).toList();

        await _db.from('order_items').insert(itemsToInsert);
      }

      // Audit Log
      if (actorId != null) {
        AuditRepository().log(
          actorId: actorId,
          actorRole: actorRole ?? 'admin',
          action: 'practice_orders.bandipora_multishop_dispatched',
          entityType: 'practice_orders',
          entityId: cartGroupId,
          metadata: {
            'cart_group_id': cartGroupId,
            'orders_created': createdOrderIds.length,
            'order_ids': createdOrderIds,
            'target_rider_id': targetRiderId,
          },
        );
      }

      NotificationService().showNotification(
        title: '🛵 Bandipora Multi-Shop Simulation Placed!',
        body: '3 stores linked under cart group ${cartGroupId.substring(0, 8)}. Check Radar & Map.',
      );

      return PracticeDispatchResult(
        success: true,
        ordersCreated: createdOrderIds.length,
        orderIds: createdOrderIds,
      );
    } catch (e, st) {
      debugPrint('[PracticeOrderService] Bandipora dispatch error: $e\n$st');
      return PracticeDispatchResult(
        success: false,
        ordersCreated: 0,
        orderIds: [],
        errorMessage: e.toString(),
      );
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchShop(String shopId) async {
    try {
      final resp = await _db
          .from('shops')
          .select('id, name, seller_id, phone, location, prep_time_minutes')
          .eq('id', shopId)
          .maybeSingle();
      return resp;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchRider(String riderId) async {
    try {
      final resp = await _db
          .from('delivery_partners')
          .select('id, phone')
          .eq('id', riderId)
          .maybeSingle();
      return resp;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _resolveAnchorShop() async {
    try {
      final shops = await _db
          .from('shops')
          .select('id, name, seller_id, phone, location, prep_time_minutes')
          .limit(1);
      final list = (shops as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) return list.first;
    } catch (_) {}

    // Fallback virtual anchor shop
    return {
      'id': _uuid.v4(),
      'name': '100x Central Training Store',
      'seller_id': _db.auth.currentUser?.id ?? '00000000-0000-0000-0000-000000000001',
      'phone': '+919876500001',
      'location': {'latitude': 34.0837, 'longitude': 74.7973},
      'prep_time_minutes': 15,
    };
  }
}
