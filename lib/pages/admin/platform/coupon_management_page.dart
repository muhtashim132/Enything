import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../theme/admin_theme.dart';

class CouponManagementPage extends StatefulWidget {
  const CouponManagementPage({super.key});

  @override
  State<CouponManagementPage> createState() => _CouponManagementPageState();
}

class _CouponManagementPageState extends State<CouponManagementPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _coupons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCoupons();
  }

  Future<void> _fetchCoupons() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('coupons')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _coupons = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error loading coupons: $e'),
          backgroundColor: AdminColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus(String id, bool currentStatus) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin) return;

    try {
      await _db.from('coupons').update({'is_active': !currentStatus}).eq('id', id);
      
      // Update local state
      final idx = _coupons.indexWhere((c) => c['id'] == id);
      if (idx != -1) {
        setState(() {
          _coupons[idx]['is_active'] = !currentStatus;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update coupon status'),
          backgroundColor: AdminColors.danger,
        ));
      }
    }
  }

  Future<void> _deleteCoupon(String id) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin) return;

    try {
      await _db.from('coupons').delete().eq('id', id);
      setState(() {
        _coupons.removeWhere((c) => c['id'] == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Coupon deleted'),
          backgroundColor: AdminColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to delete coupon'),
          backgroundColor: AdminColors.danger,
        ));
      }
    }
  }

  void _showCreateBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateCouponSheet(
        onCreated: _fetchCoupons,
        adminId: context.read<RbacProvider>().currentAdmin?.id ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Coupon Management', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.primary))
          : _coupons.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _coupons.length,
                  itemBuilder: (context, index) => _buildCouponCard(_coupons[index], rbac),
                ),
      floatingActionButton: rbac.isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateBottomSheet,
              backgroundColor: AdminColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Create Coupon', style: AdminStyles.title(color: Colors.white, size: 14)),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_offer_rounded, size: 64, color: AdminColors.cardBorder),
          const SizedBox(height: 16),
          Text('No coupons yet', style: AdminStyles.title(color: AdminColors.textMuted)),
          const SizedBox(height: 8),
          Text('Create your first discount code', style: AdminStyles.caption(color: AdminColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon, RbacProvider rbac) {
    final isActive = coupon['is_active'] as bool;
    final isFlat = coupon['discount_type'] == 'flat';
    final val = coupon['discount_value'];
    final valStr = isFlat ? '₹$val OFF' : '$val% OFF';
    
    DateTime? validUntil;
    if (coupon['valid_until'] != null) {
      validUntil = DateTime.parse(coupon['valid_until']).toLocal();
    }
    final isExpired = validUntil != null && validUntil.isBefore(DateTime.now());
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? AdminColors.primary.withValues(alpha: 0.3) : AdminColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AdminColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        coupon['code'].toString().toUpperCase(),
                        style: AdminStyles.title(color: AdminColors.primary, size: 16),
                      ),
                    ),
                    if (isExpired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AdminColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('EXPIRED', style: AdminStyles.caption(color: AdminColors.danger, size: 10)),
                      ),
                    ]
                  ],
                ),
                Text(valStr, style: AdminStyles.title(color: AdminColors.success, size: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (coupon['description'] != null && coupon['description'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(coupon['description'], style: AdminStyles.body(size: 13, color: AdminColors.textMuted)),
              ),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text('Min: ₹${coupon['min_order_value']}', style: AdminStyles.caption(color: AdminColors.textMuted)),
                const SizedBox(width: 16),
                Icon(Icons.people_outline, size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text('Used: ${coupon['usage_count']}${coupon['usage_limit'] != null ? '/${coupon['usage_limit']}' : ''}', style: AdminStyles.caption(color: AdminColors.textMuted)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AdminColors.cardBorder),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  validUntil != null ? 'Ends ${DateFormat('MMM d, yyyy').format(validUntil)}' : 'No Expiry',
                  style: AdminStyles.caption(color: AdminColors.textMuted),
                ),
                Row(
                  children: [
                    if (rbac.isSuperAdmin)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger, size: 20),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: AdminColors.surface,
                              title: Text('Delete Coupon?', style: AdminStyles.title()),
                              content: Text('Are you sure you want to delete ${coupon['code']}?', style: AdminStyles.body()),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel', style: AdminStyles.body())),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(c);
                                    _deleteCoupon(coupon['id']);
                                  },
                                  child: Text('Delete', style: AdminStyles.title(color: AdminColors.danger)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    Switch(
                      value: isActive,
                      onChanged: rbac.isSuperAdmin ? (v) => _toggleStatus(coupon['id'], isActive) : null,
                      activeThumbColor: AdminColors.primary,
                      activeTrackColor: AdminColors.primary.withValues(alpha: 0.3),
                      inactiveThumbColor: AdminColors.textMuted,
                      inactiveTrackColor: AdminColors.surface,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCouponSheet extends StatefulWidget {
  final VoidCallback onCreated;
  final String adminId;

  const _CreateCouponSheet({required this.onCreated, required this.adminId});

  @override
  State<_CreateCouponSheet> createState() => _CreateCouponSheetState();
}

class _CreateCouponSheetState extends State<_CreateCouponSheet> {
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  
  String _type = 'flat';
  DateTime? _validUntil;
  bool _loading = false;

  Future<void> _create() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final val = double.tryParse(_valCtrl.text.trim());

    if (code.isEmpty || val == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code and Value are required'), backgroundColor: AdminColors.warning)
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.from('coupons').insert({
        'code': code,
        'description': _descCtrl.text.trim(),
        'discount_type': _type,
        'discount_value': val,
        'min_order_value': double.tryParse(_minOrderCtrl.text.trim()) ?? 0,
        'usage_limit': int.tryParse(_limitCtrl.text.trim()),
        'valid_until': _validUntil?.toIso8601String(),
        'created_by': widget.adminId,
      });
      
      if (mounted) {
        widget.onCreated();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coupon created successfully!'), backgroundColor: AdminColors.success)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AdminColors.danger)
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AdminColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Create Coupon', style: AdminStyles.title(size: 20)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: AdminStyles.body(),
              decoration: _inputDec('Coupon Code (e.g. ENYTHING50)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: AdminStyles.body(),
              decoration: _inputDec('Description (Optional)'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'flat', label: Text('Flat (₹)', style: AdminStyles.body())),
                      ButtonSegment(value: 'percent', label: Text('Percent (%)', style: AdminStyles.body())),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AdminColors.surface,
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: AdminColors.primary,
                      side: const BorderSide(color: AdminColors.cardBorder),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valCtrl,
                    keyboardType: TextInputType.number,
                    style: AdminStyles.body(),
                    decoration: _inputDec('Discount Value'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minOrderCtrl,
                    keyboardType: TextInputType.number,
                    style: AdminStyles.body(),
                    decoration: _inputDec('Min Order (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limitCtrl,
              keyboardType: TextInputType.number,
              style: AdminStyles.body(),
              decoration: _inputDec('Usage Limit (Optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) {
                  setState(() => _validUntil = d);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _validUntil == null ? 'Valid Until (Optional)' : 'Ends: ${DateFormat('MMM d, yyyy').format(_validUntil!)}',
                      style: AdminStyles.body(color: _validUntil == null ? AdminColors.textMuted : Colors.white),
                    ),
                    const Icon(Icons.calendar_today_rounded, color: AdminColors.textMuted, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Create Coupon', style: AdminStyles.title(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AdminStyles.body(color: AdminColors.textMuted),
      filled: true,
      fillColor: AdminColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    );
  }
}
