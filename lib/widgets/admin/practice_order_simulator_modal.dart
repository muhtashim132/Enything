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
    final supabase = Supabase.instance.client;
    try {
      // 1. Fetch active shops (with soft delete filter)
      final shopsResp = await supabase
          .from('shops')
          .select('id, name')
          .eq('is_deleted', false)
          .eq('is_active', true)
          .order('name')
          .limit(100);

      // 2. Fetch active riders
      final ridersResp = await supabase
          .from('delivery_partners')
          .select('id, phone')
          .eq('is_active', true)
          .limit(100);

      // 3. Get practice orders count
      final count = await PracticeOrderService.instance.getPracticeOrdersCount();

      if (mounted) {
        setState(() {
          _shops = (shopsResp as List).cast<Map<String, dynamic>>();
          _riders = (ridersResp as List).cast<Map<String, dynamic>>();
          _activePracticeCount = count;
          if (_shops.isNotEmpty && _selectedShopId == null) {
            _selectedShopId = _shops.first['id'] as String;
          }
          if (_riders.isNotEmpty && _selectedRiderId == null) {
            _selectedRiderId = _riders.first['id'] as String;
          }
        });
      }
    } catch (e) {
      debugPrint('[PracticeModal] Data fetch error: $e');
    }
  }

  Future<void> _dispatch() async {
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
        _targetType == PracticeTargetType.dual;

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
                _buildTargetChip(PracticeTargetType.specificSeller, 'Specific Seller 🏪'),
                _buildTargetChip(PracticeTargetType.allSellers, 'All Sellers 🏬'),
                _buildTargetChip(PracticeTargetType.specificRider, 'Specific Rider 🛵'),
                _buildTargetChip(PracticeTargetType.allRiders, 'All Riders 🚴'),
                _buildTargetChip(PracticeTargetType.dual, 'Dual (Store + Rider) 🔗'),
              ],
            ),

            const SizedBox(height: 18),

            // Shop Selector (if needed)
            if (isShopNeeded) ...[
              Text(
                'Target Shop',
                style: GoogleFonts.outfit(color: AdminColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedShopId,
                    dropdownColor: AdminColors.surfaceHigh,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: _shops.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'] as String,
                        child: Text(
                          s['name'] as String? ?? 'Shop',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedShopId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Rider Selector (if needed)
            if (isRiderNeeded) ...[
              Text(
                'Target Rider',
                style: GoogleFonts.outfit(color: AdminColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRiderId,
                    dropdownColor: AdminColors.surfaceHigh,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: _riders.map((r) {
                      return DropdownMenuItem<String>(
                        value: r['id'] as String,
                        child: Text(
                          'Rider: ${r['phone'] ?? r['id']}',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRiderId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

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

  Widget _buildTargetChip(PracticeTargetType type, String label) {
    final isSelected = _targetType == type;
    return GestureDetector(
      onTap: () => setState(() => _targetType = type),
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
