import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rbac_provider.dart';
import '../../services/practice_order_service.dart';
import '../../theme/admin_theme.dart';

class PracticeOrderSimulatorModal extends StatefulWidget {
  const PracticeOrderSimulatorModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PracticeOrderSimulatorModal(),
    );
  }

  @override
  State<PracticeOrderSimulatorModal> createState() =>
      _PracticeOrderSimulatorModalState();
}

class _PracticeOrderSimulatorModalState
    extends State<PracticeOrderSimulatorModal> {
  PracticeTargetType _targetType = PracticeTargetType.specificSeller;
  int _count = 1;
  String? _selectedShopId;
  String? _selectedRiderId;
  final TextEditingController _notesCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isPurging = false;
  bool _isLoadingData = true;
  String? _dataError;
  int _activePracticeCount = 0;

  List<Map<String, dynamic>> _shops = [];
  List<Map<String, dynamic>> _riders = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingData = true;
      _dataError = null;
    });

    final supabase = Supabase.instance.client;

    // 1. Fetch shops — Try admin_get_all_shops RPC first, fallback to direct query
    List<Map<String, dynamic>> loadedShops = [];
    try {
      final rpcRes = await supabase.rpc('admin_get_all_shops');
      if (rpcRes != null && rpcRes is List) {
        loadedShops = List<Map<String, dynamic>>.from(rpcRes);
      }
    } catch (e) {
      debugPrint('[PracticeModal] admin_get_all_shops RPC error/fallback: $e');
    }

    if (loadedShops.isEmpty) {
      try {
        final tableRes = await supabase
            .from('shops')
            .select('id, name, category, address, is_active, is_open')
            .order('name', ascending: true)
            .limit(100);
        loadedShops = (tableRes as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('[PracticeModal] Direct shops query error: $e');
        _dataError = 'Could not load shops from database.';
      }
    }

    // Defensive soft-delete check & sort active shops first
    loadedShops = loadedShops
        .where((s) => s['is_deleted'] != true)
        .toList()
      ..sort((a, b) {
        final aActive = (a['is_active'] == true || a['is_open'] == true) ? 1 : 0;
        final bActive = (b['is_active'] == true || b['is_open'] == true) ? 1 : 0;
        if (aActive != bActive) return bActive.compareTo(aActive);
        final aName = (a['name'] ?? a['shop_name'] ?? '').toString();
        final bName = (b['name'] ?? b['shop_name'] ?? '').toString();
        return aName.compareTo(bName);
      });

    // 2. Fetch riders — Try admin_get_all_riders RPC first, fallback to direct query
    List<Map<String, dynamic>> loadedRiders = [];
    try {
      final rpcRes = await supabase.rpc('admin_get_all_riders');
      if (rpcRes != null && rpcRes is List) {
        loadedRiders = List<Map<String, dynamic>>.from(rpcRes);
      }
    } catch (e) {
      debugPrint('[PracticeModal] admin_get_all_riders RPC error/fallback: $e');
    }

    if (loadedRiders.isEmpty) {
      try {
        final tableRes = await supabase
            .from('delivery_partners')
            .select('id, name, phone, vehicle_type, is_active, is_available')
            .order('phone', ascending: true)
            .limit(100);
        loadedRiders = (tableRes as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('[PracticeModal] Direct delivery_partners query error: $e');
      }
    }

    // 3. Get practice orders count
    int count = 0;
    try {
      count = await PracticeOrderService.instance.getPracticeOrdersCount();
    } catch (e) {
      debugPrint('[PracticeModal] Practice orders count error: $e');
    }

    if (mounted) {
      setState(() {
        _shops = loadedShops;
        _riders = loadedRiders;
        _activePracticeCount = count;
        _isLoadingData = false;

        // Auto-select first shop if current is unselected or missing
        if (_shops.isNotEmpty &&
            (_selectedShopId == null ||
                !_shops.any((s) => s['id']?.toString() == _selectedShopId))) {
          _selectedShopId = _shops.first['id']?.toString();
        }

        // Auto-select first rider if current is unselected or missing
        if (_riders.isNotEmpty &&
            (_selectedRiderId == null ||
                !_riders.any((r) => r['id']?.toString() == _selectedRiderId))) {
          _selectedRiderId = _riders.first['id']?.toString();
        }
      });
    }
  }

  Map<String, dynamic>? get _selectedShop {
    if (_shops.isEmpty) return null;
    return _shops.firstWhere(
      (s) => s['id']?.toString() == _selectedShopId,
      orElse: () => _shops.first,
    );
  }

  String get _selectedShopName {
    final s = _selectedShop;
    if (s == null) return 'Select Target Shop';
    return (s['name'] ?? s['shop_name'] ?? 'Shop').toString();
  }

  String get _selectedShopSubtitle {
    final s = _selectedShop;
    if (s == null) return '';
    final cat = s['category']?.toString() ?? '';
    final addr = s['address']?.toString() ?? '';
    if (cat.isNotEmpty && addr.isNotEmpty) return '$cat • $addr';
    return cat.isNotEmpty ? cat : addr;
  }

  bool get _isSelectedShopActive {
    final s = _selectedShop;
    return s?['is_active'] == true || s?['is_open'] == true;
  }

  Map<String, dynamic>? get _selectedRider {
    if (_riders.isEmpty) return null;
    return _riders.firstWhere(
      (r) => r['id']?.toString() == _selectedRiderId,
      orElse: () => _riders.first,
    );
  }

  String get _selectedRiderName {
    final r = _selectedRider;
    if (r == null) return 'Select Target Rider';
    final profile = r['profiles'] as Map?;
    final fullName = profile?['full_name']?.toString() ?? r['name']?.toString() ?? '';
    final phone = profile?['phone']?.toString() ?? r['phone']?.toString() ?? '';
    if (fullName.isNotEmpty && fullName != 'Unknown') return fullName;
    if (phone.isNotEmpty) return 'Rider ($phone)';
    return 'Rider (${r['id'].toString().substring(0, 8)})';
  }

  String get _selectedRiderSubtitle {
    final r = _selectedRider;
    if (r == null) return '';
    final profile = r['profiles'] as Map?;
    final phone = profile?['phone']?.toString() ?? r['phone']?.toString() ?? '';
    final veh = r['vehicle_type']?.toString() ?? 'Motorcycle';
    return '$phone • $veh';
  }

  bool get _isSelectedRiderActive {
    final r = _selectedRider;
    return r?['is_active'] == true || r?['is_available'] == true;
  }

  void _openShopPicker(BuildContext context) {
    if (_shops.isEmpty) {
      _loadInitialData();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopSearchSheet(
        shops: _shops,
        selectedId: _selectedShopId,
        onSelected: (shopId) {
          setState(() => _selectedShopId = shopId);
        },
      ),
    );
  }

  void _openRiderPicker(BuildContext context) {
    if (_riders.isEmpty) {
      _loadInitialData();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RiderSearchSheet(
        riders: _riders,
        selectedId: _selectedRiderId,
        onSelected: (riderId) {
          setState(() => _selectedRiderId = riderId);
        },
      ),
    );
  }

  Future<void> _dispatch() async {
    final isShopNeeded = _targetType == PracticeTargetType.specificSeller ||
        _targetType == PracticeTargetType.dual;
    final isRiderNeeded = _targetType == PracticeTargetType.specificRider ||
        _targetType == PracticeTargetType.dual ||
        _targetType == PracticeTargetType.bandiporaMultiShop;

    if (isShopNeeded && (_selectedShopId == null || _selectedShopId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AdminColors.warning,
          content: Text(
            'Please select a target shop to dispatch practice orders.',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }

    if (isRiderNeeded && (_selectedRiderId == null || _selectedRiderId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AdminColors.warning,
          content: Text(
            'Please select a target rider to dispatch practice orders.',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final rbac = context.read<RbacProvider>();

    final result = await PracticeOrderService.instance.dispatchPracticeOrders(
      targetType: _targetType,
      targetShopId: _selectedShopId,
      targetRiderId: _selectedRiderId,
      countPerTarget: _count,
      customNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      actorId: auth.currentUserId,
      actorRole: rbac.isSuperAdmin
          ? 'super_admin'
          : (rbac.currentAdmin?.role?.slug ?? 'admin'),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result.success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AdminColors.success,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dispatched ${result.ordersCreated} practice order(s)! Audio bells ringing.',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AdminColors.danger,
            content: Text(
              result.errorMessage ?? 'Failed to dispatch practice orders.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _purgeAll() async {
    final auth = context.read<AuthProvider>();
    final rbac = context.read<RbacProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Purge All Practice Orders?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete all simulation orders and clear test data from the database. Zero leftovers guaranteed.',
          style: GoogleFonts.outfit(color: AdminColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AdminColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Purge Everything', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isPurging = true);

    final count = await PracticeOrderService.instance.purgeAllPracticeOrders(
      actorId: auth.currentUserId,
      actorRole: rbac.isSuperAdmin
          ? 'super_admin'
          : (rbac.currentAdmin?.role?.slug ?? 'admin'),
    );

    if (mounted) {
      setState(() {
        _isPurging = false;
        _activePracticeCount = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AdminColors.danger,
          content: Text(
            'Purged $count practice order(s). Database is completely clean.',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isShopNeeded = _targetType == PracticeTargetType.specificSeller ||
        _targetType == PracticeTargetType.dual;
    final isRiderNeeded = _targetType == PracticeTargetType.specificRider ||
        _targetType == PracticeTargetType.dual ||
        _targetType == PracticeTargetType.bandiporaMultiShop;

    return Container(
      decoration: const BoxDecoration(
        color: AdminColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.science_rounded, color: Color(0xFF06B6D4), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Practice Order Simulator',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Trigger dummy orders with audio bells for merchant & rider training',
                        style: GoogleFonts.outfit(
                          color: AdminColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Purge / Cleanup Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _activePracticeCount > 0
                    ? AdminColors.warning.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _activePracticeCount > 0
                    ? AdminColors.warning.withValues(alpha: 0.3)
                    : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _activePracticeCount > 0 ? Icons.info_outline : Icons.verified_rounded,
                    size: 18,
                    color: _activePracticeCount > 0 ? AdminColors.warning : AdminColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _activePracticeCount > 0
                          ? '$_activePracticeCount practice order(s) currently in DB'
                          : 'Database clean: 0 practice orders',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_activePracticeCount > 0)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isPurging ? null : _purgeAll,
                      icon: _isPurging
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.white),
                      label: Text(
                        'Purge',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Section: Target Selection
            Text(
              'Select Target Audience',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTargetChip(PracticeTargetType.bandiporaMultiShop, 'Bandipora 3-Shop Real Route (1km & 2km) 🗺️'),
                _buildTargetChip(PracticeTargetType.specificSeller, 'Specific Seller 🏪'),
                _buildTargetChip(PracticeTargetType.allSellers, 'All Sellers 🏬'),
                _buildTargetChip(PracticeTargetType.specificRider, 'Specific Rider 🛵'),
                _buildTargetChip(PracticeTargetType.allRiders, 'All Riders 🚴'),
                _buildTargetChip(PracticeTargetType.dual, 'Dual (Store + Rider) 🔗'),
              ],
            ),

            const SizedBox(height: 18),

            // Shop Selector (if needed)
            if (isShopNeeded) _buildShopSelector(),

            // Rider Selector (if needed)
            if (isRiderNeeded) _buildRiderSelector(),

            // Order Count
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orders per Target',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'How many simulation orders to create',
                        style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AdminColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
                        onPressed: _count > 1 ? () => setState(() => _count--) : null,
                      ),
                      Text(
                        '$_count',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                        onPressed: _count < 5 ? () => setState(() => _count++) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Optional Notes
            Text(
              'Custom Training Note (Optional)',
              style: GoogleFonts.outfit(color: AdminColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Peak lunch rush mock scenario',
                hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: AdminColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
              ),
            ),

            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _isLoading ? null : _dispatch,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Dispatch Practice Orders',
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Target Shop',
              style: GoogleFonts.outfit(
                color: AdminColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!_isLoadingData && _shops.isNotEmpty)
              Text(
                '${_shops.length} available',
                style: GoogleFonts.outfit(
                  color: AdminColors.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_isLoadingData)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF06B6D4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading registered shops...',
                  style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          )
        else if (_shops.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AdminColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AdminColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dataError ?? 'No shops found in database',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _loadInitialData,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF06B6D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openShopPicker(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF06B6D4)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedShopName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedShopSubtitle.isNotEmpty)
                            Text(
                              _selectedShopSubtitle,
                              style: GoogleFonts.outfit(
                                color: AdminColors.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isSelectedShopActive
                            ? AdminColors.success.withValues(alpha: 0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isSelectedShopActive ? 'Active' : 'Closed',
                        style: GoogleFonts.outfit(
                          color: _isSelectedShopActive ? AdminColors.success : AdminColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 20),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildRiderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Target Rider',
              style: GoogleFonts.outfit(
                color: AdminColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!_isLoadingData && _riders.isNotEmpty)
              Text(
                '${_riders.length} registered',
                style: GoogleFonts.outfit(
                  color: AdminColors.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_isLoadingData)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF06B6D4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading registered riders...',
                  style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          )
        else if (_riders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AdminColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AdminColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No riders found in database',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _loadInitialData,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Retry',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF06B6D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openRiderPicker(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.two_wheeler_rounded, size: 18, color: Color(0xFF06B6D4)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedRiderName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedRiderSubtitle.isNotEmpty)
                            Text(
                              _selectedRiderSubtitle,
                              style: GoogleFonts.outfit(
                                color: AdminColors.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isSelectedRiderActive
                            ? AdminColors.success.withValues(alpha: 0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isSelectedRiderActive ? 'Active' : 'Offline',
                        style: GoogleFonts.outfit(
                          color: _isSelectedRiderActive ? AdminColors.success : AdminColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 20),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildTargetChip(PracticeTargetType type, String label) {
    final isSelected = _targetType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _targetType = type;
          // Auto-ensure IDs if switching to specific modes
          if ((type == PracticeTargetType.specificSeller || type == PracticeTargetType.dual) &&
              _selectedShopId == null &&
              _shops.isNotEmpty) {
            _selectedShopId = _shops.first['id']?.toString();
          }
          if ((type == PracticeTargetType.specificRider || type == PracticeTargetType.dual) &&
              _selectedRiderId == null &&
              _riders.isNotEmpty) {
            _selectedRiderId = _riders.first['id']?.toString();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF06B6D4).withValues(alpha: 0.2) : AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF06B6D4) : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? const Color(0xFF06B6D4) : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 100x Searchable Shop Selector Bottom Sheet
class _ShopSearchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> shops;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _ShopSearchSheet({
    required this.shops,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_ShopSearchSheet> createState() => _ShopSearchSheetState();
}

class _ShopSearchSheetState extends State<_ShopSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.shops.where((s) {
      if (_query.isEmpty) return true;
      final name = (s['name'] ?? s['shop_name'] ?? '').toString().toLowerCase();
      final cat = (s['category'] ?? '').toString().toLowerCase();
      final addr = (s['address'] ?? '').toString().toLowerCase();
      return name.contains(_query) || cat.contains(_query) || addr.contains(_query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AdminColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded, color: Color(0xFF06B6D4), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Target Shop',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Choose which store receives the dummy order & bell alert',
                      style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search box
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _query = val.trim().toLowerCase()),
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by store name, category, or address...',
              hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AdminColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
            ),
          ),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching shops found',
                      style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (ctx, idx) {
                      final s = filtered[idx];
                      final sId = s['id']?.toString() ?? '';
                      final isSelected = sId == widget.selectedId;
                      final name = (s['name'] ?? s['shop_name'] ?? 'Shop').toString();
                      final cat = s['category']?.toString() ?? '';
                      final addr = s['address']?.toString() ?? '';
                      final isActive = s['is_active'] == true || s['is_open'] == true;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onTap: () {
                          widget.onSelected(sId);
                          Navigator.pop(ctx);
                        },
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF06B6D4).withValues(alpha: 0.2)
                                : AdminColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF06B6D4) : Colors.white12,
                            ),
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 20,
                            color: isSelected ? const Color(0xFF06B6D4) : Colors.white54,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AdminColors.success.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Closed',
                                style: GoogleFonts.outfit(
                                  color: isActive ? AdminColors.success : AdminColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: (cat.isNotEmpty || addr.isNotEmpty)
                            ? Text(
                                cat.isNotEmpty && addr.isNotEmpty ? '$cat • $addr' : (cat.isNotEmpty ? cat : addr),
                                style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF06B6D4), size: 20)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 100x Searchable Rider Selector Bottom Sheet
class _RiderSearchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> riders;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _RiderSearchSheet({
    required this.riders,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_RiderSearchSheet> createState() => _RiderSearchSheetState();
}

class _RiderSearchSheetState extends State<_RiderSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.riders.where((r) {
      if (_query.isEmpty) return true;
      final profile = r['profiles'] as Map?;
      final name = (profile?['full_name'] ?? r['name'] ?? '').toString().toLowerCase();
      final phone = (profile?['phone'] ?? r['phone'] ?? '').toString().toLowerCase();
      final veh = (r['vehicle_type'] ?? '').toString().toLowerCase();
      return name.contains(_query) || phone.contains(_query) || veh.contains(_query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AdminColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF06B6D4), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Target Rider',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Choose which delivery partner receives the simulation pickup task',
                      style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search box
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _query = val.trim().toLowerCase()),
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by rider name, phone, or vehicle...',
              hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AdminColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
            ),
          ),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching riders found',
                      style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (ctx, idx) {
                      final r = filtered[idx];
                      final rId = r['id']?.toString() ?? '';
                      final isSelected = rId == widget.selectedId;
                      final profile = r['profiles'] as Map?;
                      final fullName = profile?['full_name']?.toString() ?? r['name']?.toString() ?? '';
                      final phone = profile?['phone']?.toString() ?? r['phone']?.toString() ?? '';
                      final veh = r['vehicle_type']?.toString() ?? 'Motorcycle';
                      final isActive = r['is_active'] == true || r['is_available'] == true;

                      final displayName = (fullName.isNotEmpty && fullName != 'Unknown')
                          ? fullName
                          : (phone.isNotEmpty ? 'Rider ($phone)' : 'Rider (${rId.substring(0, 8)})');

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onTap: () {
                          widget.onSelected(rId);
                          Navigator.pop(ctx);
                        },
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF06B6D4).withValues(alpha: 0.2)
                                : AdminColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF06B6D4) : Colors.white12,
                            ),
                          ),
                          child: Icon(
                            Icons.two_wheeler_rounded,
                            size: 20,
                            color: isSelected ? const Color(0xFF06B6D4) : Colors.white54,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AdminColors.success.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Offline',
                                style: GoogleFonts.outfit(
                                  color: isActive ? AdminColors.success : AdminColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          phone.isNotEmpty ? '$phone • $veh' : veh,
                          style: GoogleFonts.outfit(color: AdminColors.textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF06B6D4), size: 20)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
