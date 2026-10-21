// ============================================================================
// quote_request_provider.dart — State Management for Custom Event Quotes
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/quote_request_model.dart';

class QuoteRequestProvider extends ChangeNotifier {
  final SupabaseClient? mockClient;
  QuoteRequestProvider({this.mockClient});

  SupabaseClient get _supabase => mockClient ?? Supabase.instance.client;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<QuoteRequestModel> _customerQuotes = [];
  List<QuoteRequestModel> get customerQuotes => List.unmodifiable(_customerQuotes);

  List<QuoteRequestModel> _allAdminQuotes = [];
  List<QuoteRequestModel> get allAdminQuotes => List.unmodifiable(_allAdminQuotes);

  List<QuoteRequestModel> _adminQuotes = [];
  List<QuoteRequestModel> get adminQuotes => List.unmodifiable(_adminQuotes);

  String _currentAdminTab = 'pending';
  String get currentAdminTab => _currentAdminTab;

  int get adminPendingCount =>
      _allAdminQuotes.where((q) => q.quoteStatus == 'pending_review').length;

  int get adminQuotedCount => _allAdminQuotes
      .where((q) => q.quoteStatus == 'quoted' || q.quoteStatus == 'customer_accepted')
      .length;

  int get adminAcceptedWaitingPaymentCount => _allAdminQuotes
      .where((q) => q.quoteStatus == 'customer_accepted')
      .length;

  int get adminDoneCount => _allAdminQuotes
      .where((q) =>
          q.quoteStatus == 'order_placed' ||
          q.quoteStatus == 'customer_rejected' ||
          q.quoteStatus == 'expired' ||
          q.quoteStatus == 'cancelled')
      .length;

  Map<String, dynamic>? _activeCateringOrder;
  Map<String, dynamic>? get activeCateringOrder => _activeCateringOrder;

  StreamSubscription? _customerStreamSub;
  StreamSubscription? _adminStreamSub;
  RealtimeChannel? _adminRealtimeChannel;
  RealtimeChannel? _customerOrderChannel;

  @override
  void dispose() {
    _customerStreamSub?.cancel();
    _adminStreamSub?.cancel();
    if (_customerOrderChannel != null) {
      _supabase.removeChannel(_customerOrderChannel!);
    }
    if (_adminRealtimeChannel != null) {
      _supabase.removeChannel(_adminRealtimeChannel!);
    }
    super.dispose();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Customer: Submit Quote Request ─────────────────────────────────────────
  Future<Map<String, dynamic>> submitQuoteRequest(Map<String, dynamic> data) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final res = await _supabase.rpc('submit_quote_request', params: {
        'p_data': data,
      });

      final map = Map<String, dynamic>.from(res as Map);
      await loadCustomerQuotes();
      _setLoading(false);
      return map;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      rethrow;
    }
  }

  // ─── Customer: Load Quotes & Active Orders ──────────────────────────────────
  Future<void> loadCustomerQuotes() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      _customerQuotes = [];
      _activeCateringOrder = null;
      notifyListeners();
      return;
    }

    try {
      final res = await _supabase
          .from('bulk_quote_requests')
          .select()
          .eq('customer_id', uid)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((m) => QuoteRequestModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();

      _customerQuotes = list;

      // Also fetch live active catering order
      final activeOrderRes = await _supabase
          .from('orders')
          .select('id, status, address_label, total_amount, delivery_otp, created_at, order_type')
          .eq('customer_id', uid)
          .inFilter('order_type', ['bulk', 'manual_quote'])
          .inFilter('status', [
            'bulk_pending',
            'bulk_confirmed',
            'bulk_preparing',
            'bulk_ready',
            'bulk_dispatched',
          ])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _activeCateringOrder = activeOrderRes != null ? Map<String, dynamic>.from(activeOrderRes) : null;
      if (_activeCateringOrder != null) {
        final orderId = _activeCateringOrder!['id']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          final matchedQuote = _customerQuotes.where((q) => q.resultingOrderId == orderId).firstOrNull;
          if (matchedQuote != null) {
            _activeCateringOrder!['event_name'] = matchedQuote.eventName;
            _activeCateringOrder!['guest_count'] = matchedQuote.estimatedGuestCount;
          } else {
            try {
              final bq = await _supabase
                  .from('bulk_quote_requests')
                  .select('event_name, estimated_guest_count')
                  .eq('resulting_order_id', orderId)
                  .maybeSingle();
              if (bq != null) {
                _activeCateringOrder!['event_name'] = bq['event_name'];
                _activeCateringOrder!['guest_count'] = bq['estimated_guest_count'];
              }
            } catch (_) {}
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading customer quote requests / active orders: $e');
    }
  }

  // ─── Customer: Realtime Subscription ────────────────────────────────────────
  void subscribeToCustomerQuotes() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    _customerStreamSub?.cancel();
    _customerStreamSub = _supabase
        .from('bulk_quote_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', uid)
        .order('created_at', ascending: false)
        .listen((data) {
          _customerQuotes = data
              .map((m) => QuoteRequestModel.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (_activeCateringOrder != null && _activeCateringOrder!['event_name'] == null) {
            final orderId = _activeCateringOrder!['id']?.toString();
            final matched = _customerQuotes.where((q) => q.resultingOrderId == orderId).firstOrNull;
            if (matched != null) {
              _activeCateringOrder!['event_name'] = matched.eventName;
              _activeCateringOrder!['guest_count'] = matched.estimatedGuestCount;
            }
          }
          notifyListeners();
        }, onError: (e) {
          debugPrint('Customer quote stream error: $e');
        });

    // Realtime channel for live active catering orders
    if (_customerOrderChannel != null) {
      _supabase.removeChannel(_customerOrderChannel!);
    }
    _customerOrderChannel = _supabase
        .channel('cust-active-catering-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final orderType = row['order_type']?.toString();
            final status = row['status']?.toString();
            if (orderType == 'bulk' || orderType == 'manual_quote') {
              if (status != null && {
                'bulk_pending',
                'bulk_confirmed',
                'bulk_preparing',
                'bulk_ready',
                'bulk_dispatched',
              }.contains(status)) {
                final map = Map<String, dynamic>.from(row);
                final orderId = map['id']?.toString();
                final matchedQuote = _customerQuotes.where((q) => q.resultingOrderId == orderId).firstOrNull;
                if (matchedQuote != null) {
                  map['event_name'] = matchedQuote.eventName;
                  map['guest_count'] = matchedQuote.estimatedGuestCount;
                } else if (_activeCateringOrder?['id'] == orderId && _activeCateringOrder?['event_name'] != null) {
                  map['event_name'] = _activeCateringOrder!['event_name'];
                  map['guest_count'] = _activeCateringOrder!['guest_count'];
                }
                _activeCateringOrder = map;
              } else if (status == 'delivered' || status == 'cancelled' || status == 'seller_rejected') {
                if (_activeCateringOrder?['id'] == row['id']) {
                  _activeCateringOrder = null;
                }
              }
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  // ─── Get Quote By ID ────────────────────────────────────────────────────────
  Future<QuoteRequestModel?> getQuoteById(String id) async {
    try {
      final res = await _supabase
          .from('bulk_quote_requests')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (res == null) return null;
      return QuoteRequestModel.fromMap(Map<String, dynamic>.from(res));
    } catch (e) {
      debugPrint('Error fetching quote $id: $e');
      return null;
    }
  }

  // ─── Customer: Respond to Quote (Accept / Decline) ──────────────────────────
  Future<Map<String, dynamic>> respondToQuote({
    required String quoteId,
    required bool accept,
    String? rejectionReason,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final res = await _supabase.rpc('customer_respond_to_quote', params: {
        'p_quote_id': quoteId,
        'p_accept': accept,
        'p_rejection_reason': rejectionReason,
      });

      final map = Map<String, dynamic>.from(res as Map);
      await loadCustomerQuotes();
      _setLoading(false);
      return map;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      rethrow;
    }
  }

  // ─── Customer: Cancel Quote Request ─────────────────────────────────────────
  Future<Map<String, dynamic>> cancelQuote({
    required String quoteId,
    String? reason,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final res = await _supabase.rpc('cancel_quote_request', params: {
        'p_quote_id': quoteId,
        'p_reason': reason,
      });

      final map = Map<String, dynamic>.from(res as Map);
      await loadCustomerQuotes();
      _setLoading(false);
      return map;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      rethrow;
    }
  }

  void setAdminTab(String tab) {
    _currentAdminTab = tab;
    _filterAdminQuotes();
    notifyListeners();
  }

  void _filterAdminQuotes() {
    if (_currentAdminTab == 'pending') {
      _adminQuotes = _allAdminQuotes
          .where((q) => q.quoteStatus == 'pending_review')
          .toList();
    } else if (_currentAdminTab == 'quoted') {
      _adminQuotes = _allAdminQuotes
          .where((q) =>
              q.quoteStatus == 'quoted' || q.quoteStatus == 'customer_accepted')
          .toList();
    } else if (_currentAdminTab == 'done') {
      _adminQuotes = _allAdminQuotes
          .where((q) =>
              q.quoteStatus == 'order_placed' ||
              q.quoteStatus == 'customer_rejected' ||
              q.quoteStatus == 'expired' ||
              q.quoteStatus == 'cancelled')
          .toList();
    } else {
      _adminQuotes = List.from(_allAdminQuotes);
    }
  }

  // ─── Admin: Realtime Subscription ──────────────────────────────────────────
  void subscribeToAdminQuotes() {
    _adminStreamSub?.cancel();
    _adminStreamSub = _supabase
        .from('bulk_quote_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((data) {
          _allAdminQuotes = data
              .map((m) => QuoteRequestModel.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          _filterAdminQuotes();
          notifyListeners();
        }, onError: (e) {
          debugPrint('Admin quote stream error: $e');
        });
  }

  // ─── Admin: Load All Quotes ─────────────────────────────────────────────────
  Future<void> loadAdminQuotes({String? statusFilter}) async {
    _setLoading(true);
    _errorMessage = null;
    if (statusFilter != null) {
      _currentAdminTab = statusFilter;
    }
    try {
      final res = await _supabase.rpc('admin_get_quote_requests');

      final list = (res as List)
          .map((m) => QuoteRequestModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();

      _allAdminQuotes = list;
      _filterAdminQuotes();
      _setLoading(false);
    } catch (e) {
      debugPrint('Error loading admin quote requests via RPC, trying direct fallback: $e');
      try {
        final fallbackRes = await _supabase
            .from('bulk_quote_requests')
            .select()
            .order('created_at', ascending: false);
        final list = (fallbackRes as List)
            .map((m) => QuoteRequestModel.fromMap(Map<String, dynamic>.from(m as Map)))
            .toList();
        _allAdminQuotes = list;
        _filterAdminQuotes();
      } catch (err) {
        _errorMessage = err.toString();
      }
      _setLoading(false);
    }
  }

  // ─── Admin: Submit Quoted Price ─────────────────────────────────────────────
  Future<Map<String, dynamic>> adminSubmitQuote({
    required String quoteId,
    required double quotedAmount,
    String? notes,
    int validHours = 48,
    List<Map<String, dynamic>> lineItems = const [],
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final res = await _supabase.rpc('admin_submit_quote', params: {
        'p_quote_id': quoteId,
        'p_quoted_amount': quotedAmount,
        'p_notes': notes,
        'p_valid_hours': validHours,
        'p_line_items': lineItems,
      });

      final map = Map<String, dynamic>.from(res as Map);
      await loadAdminQuotes();
      _setLoading(false);
      return map;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      rethrow;
    }
  }

  // ─── Admin: Mark Payment Received & Place Order ─────────────────────────────
  Future<Map<String, dynamic>> adminMarkPaid({
    required String quoteId,
    String paymentMethod = 'upi',
    String? paymentReference,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final res = await _supabase.rpc('admin_mark_quote_paid', params: {
        'p_quote_id': quoteId,
        'p_payment_method': paymentMethod,
        'p_payment_reference': paymentReference,
      });

      final map = Map<String, dynamic>.from(res as Map);
      await loadAdminQuotes();
      _setLoading(false);
      return map;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      rethrow;
    }
  }
}
