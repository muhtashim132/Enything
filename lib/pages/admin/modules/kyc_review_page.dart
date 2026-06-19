import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../providers/notification_provider.dart';
import '../rbac/forbidden_page.dart';
import '../../../theme/admin_theme.dart';

class KycReviewPage extends StatefulWidget {
  const KycReviewPage({super.key});
  @override
  State<KycReviewPage> createState() => _KycReviewPageState();
}

class _KycReviewPageState extends State<KycReviewPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tab;

  List<Map<String, dynamic>> _sellerPending = [];
  List<Map<String, dynamic>> _riderPending = [];
  bool _loadingSellers = true;
  bool _loadingRiders = true;
  String? _sellerError;
  String? _riderError;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadSellers();
    _loadRiders();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Data Loading ─────────────────────────────────────────────────────────

  Future<void> _loadSellers() async {
    setState(() { _loadingSellers = true; _sellerError = null; });
    try {
      // Use the admin RPC which bypasses column-level RLS restrictions.
      // Direct .select() from 'shops' is blocked for sensitive columns.
      final rows = await _supabase.rpc('admin_get_all_shops');
      final allShops = List<Map<String, dynamic>>.from(rows);
      final pending = allShops
          .where((s) => (s['verification_status'] as String?) == 'pending')
          .toList();
      if (mounted) setState(() { _sellerPending = pending; _loadingSellers = false; });
    } catch (e) {
      debugPrint('Error loading seller KYC: $e');
      if (mounted) setState(() { _loadingSellers = false; _sellerError = e.toString(); });
    }
  }

  Future<void> _loadRiders() async {
    setState(() { _loadingRiders = true; _riderError = null; });
    try {
      // Use the admin RPC which bypasses column-level RLS restrictions.
      final rows = await _supabase.rpc('admin_get_all_riders');
      final allRiders = List<Map<String, dynamic>>.from(rows);
      final pending = allRiders
          .where((r) => (r['verification_status'] as String?) == 'pending')
          .toList();
      if (mounted) setState(() { _riderPending = pending; _loadingRiders = false; });
    } catch (e) {
      debugPrint('Error loading rider KYC: $e');
      if (mounted) setState(() { _loadingRiders = false; _riderError = e.toString(); });
    }
  }

  // ── Approve / Reject ─────────────────────────────────────────────────────

  Future<void> _approveSeller(Map<String, dynamic> shop) async {
    final shopId = shop['id'] as String;
    final sellerId = shop['seller_id'] as String;
    try {
      await _supabase.from('shops').update({
        'verification_status': 'approved',
      }).eq('id', shopId).select('id');
      await _supabase.from('profiles').update({
        'kyc_status': 'approved',
        'verification_status': 'verified',
      }).eq('id', sellerId).select('id');

      // Push seller: KYC approved
      if (mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: sellerId,
          title: '✅ KYC Approved!',
          body: 'Congratulations! Your shop KYC has been verified. You can now start accepting orders.',
        );
      }

      _showSnack('✅ Seller approved!', isError: false);
      _loadSellers();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _rejectSeller(Map<String, dynamic> shop) async {
    final shopId = shop['id'] as String;
    final sellerId = shop['seller_id'] as String;
    final reason = await _showRejectDialog();
    if (reason == null) return;
    try {
      await _supabase.from('shops').update({
        'verification_status': 'rejected',
      }).eq('id', shopId).select('id');
      await _supabase.from('profiles').update({
        'kyc_status': 'rejected',
        'verification_status': 'rejected',
      }).eq('id', sellerId).select('id');

      // Push seller: KYC rejected with reason
      if (mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: sellerId,
          title: '❌ KYC Application Rejected',
          body: 'Reason: $reason. Please re-upload your documents and reapply.',
        );
      }

      _showSnack('Seller rejected.', isError: true);
      _loadSellers();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _approveRider(Map<String, dynamic> rider) async {
    final riderId = rider['id'] as String;
    try {
      await _supabase.from('delivery_partners').update({
        'verification_status': 'approved',
      }).eq('id', riderId).select('id');
      final userId = rider['user_id'] as String? ?? (rider['profiles'] is Map ? rider['profiles']['id'] as String? : null) ?? riderId;
      await _supabase.from('profiles').update({
        'kyc_status': 'approved',
        'verification_status': 'verified',
      }).eq('id', userId).select('id');

      // Push rider: KYC approved
      if (mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: userId,
          title: '✅ KYC Approved!',
          body: 'Congratulations! Your rider KYC has been verified. You can now go online and start earning.',
        );
      }

      _showSnack('✅ Rider approved!', isError: false);
      _loadRiders();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _rejectRider(Map<String, dynamic> rider) async {
    final riderId = rider['id'] as String;
    final reason = await _showRejectDialog();
    if (reason == null) return;
    try {
      await _supabase.from('delivery_partners').update({
        'verification_status': 'rejected',
      }).eq('id', riderId).select('id');
      final userId = rider['user_id'] as String? ?? (rider['profiles'] is Map ? rider['profiles']['id'] as String? : null) ?? riderId;
      await _supabase.from('profiles').update({
        'kyc_status': 'rejected',
        'verification_status': 'rejected',
      }).eq('id', userId).select('id');

      // Push rider: KYC rejected with reason
      if (mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: userId,
          title: '❌ KYC Application Rejected',
          body: 'Reason: $reason. Please re-upload your documents and reapply.',
        );
      }

      _showSnack('Rider rejected.', isError: true);
      _loadRiders();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<String?> _showRejectDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rejection Reason', style: AdminStyles.title()),
        content: TextField(
          controller: ctrl,
          style: AdminStyles.body(),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Explain why the application is rejected...',
            hintStyle: AdminStyles.body(color: AdminColors.textMuted),
            filled: true,
            fillColor: AdminColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AdminColors.cardBorder),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: AdminStyles.body())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? 'Documents unclear or invalid.' : ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            child: const Text('Confirm Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: isError ? AdminColors.danger : AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    if (!rbac.isSuperAdmin && !rbac.can('sellers.approve') && !rbac.can('riders.approve')) {
      return const ForbiddenPage(fullPage: false);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('KYC Verification', style: AdminStyles.title(size: 18)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AdminColors.primary,
          labelColor: AdminColors.primary,
          unselectedLabelColor: AdminColors.textMuted,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.store_outlined, size: 16),
                const SizedBox(width: 6),
                const Text('Sellers'),
                if (_sellerPending.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _badge(_sellerPending.length),
                ],
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.delivery_dining_outlined, size: 16),
                const SizedBox(width: 6),
                const Text('Riders'),
                if (_riderPending.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _badge(_riderPending.length),
                ],
              ]),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList(
            loading: _loadingSellers,
            items: _sellerPending,
            onRefresh: _loadSellers,
            isRider: false,
            error: _sellerError,
          ),
          _buildList(
            loading: _loadingRiders,
            items: _riderPending,
            onRefresh: _loadRiders,
            isRider: true,
            error: _riderError,
          ),
        ],
      ),
    );
  }

  Widget _badge(int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: AdminColors.warning, borderRadius: BorderRadius.circular(10)),
    child: Text('$count', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800)),
  );

  Widget _buildList({
    required bool loading,
    required List<Map<String, dynamic>> items,
    required Future<void> Function() onRefresh,
    required bool isRider,
    String? error,
  }) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AdminColors.primary));
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AdminColors.danger),
            const SizedBox(height: 16),
            Text('Failed to load KYC data', style: AdminStyles.title(color: AdminColors.danger)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: AdminDecorations.glassCard(borderColor: AdminColors.danger.withValues(alpha: 0.4)),
              child: SelectableText(
                error,
                style: AdminStyles.caption(color: AdminColors.warning),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary),
            ),
          ]),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.verified_outlined, size: 64, color: AdminColors.success),
          const SizedBox(height: 16),
          Text('All caught up!', style: AdminStyles.title()),
          const SizedBox(height: 8),
          Text('No pending KYC applications.', style: AdminStyles.body(color: AdminColors.textMuted)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AdminColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) => isRider
            ? _buildRiderCard(items[i])
            : _buildSellerCard(items[i]),
      ),
    );
  }

  // ── Seller Card ──────────────────────────────────────────────────────────

  Widget _buildSellerCard(Map<String, dynamic> shop) {
    // RPC returns profiles as a JSONB object (already a Map)
    final profileData = shop['profiles'];
    final profile = (profileData is Map<String, dynamic>) ? profileData : <String, dynamic>{};
    final name = profile['full_name'] as String? ?? (shop['shop_name'] as String? ?? 'Unknown');
    final phone = profile['phone'] as String? ?? '';
    // kyc_documents comes as Map from JSONB
    final docs = (shop['kyc_documents'] as Map<String, dynamic>?) ?? {};
    final submittedAt = DateTime.tryParse(shop['created_at']?.toString() ?? '');

    return _KycCard(
      emoji: '🏪',
      accentColor: AdminColors.primary,
      name: name,
      phone: phone,
      submittedAt: submittedAt,
      details: [
        _DetailRow('Shop', shop['shop_name']?.toString() ?? '-'),
        _DetailRow('Aadhaar', shop['aadhar_number']?.toString() ?? '-'),
        _DetailRow('PAN', shop['pan_number']?.toString() ?? '-'),
        if ((shop['gst_number']?.toString() ?? '').isNotEmpty)
          _DetailRow('GSTIN', shop['gst_number'].toString()),
        _DetailRow('Bank Holder', shop['bank_account_holder']?.toString() ?? '-'),
        _DetailRow('Account No.', shop['bank_account_number']?.toString() ?? '-'),
        _DetailRow('IFSC', shop['bank_ifsc']?.toString() ?? '-'),
      ],
      docImages: _extractDocImages(docs, ['aadhar_front', 'aadhar_back', 'pan_front', 'pan_back', 'shop_proof_1', 'shop_proof_2', 'bank_proof']),
      onApprove: () => _approveSeller(shop),
      onReject: () => _rejectSeller(shop),
      canApprove: context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('sellers.approve'),
      canReject: context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('sellers.approve'),
    );
  }

  // ── Rider Card ───────────────────────────────────────────────────────────

  Widget _buildRiderCard(Map<String, dynamic> rider) {
    // RPC returns profiles as a JSONB object (already a Map)
    final profileData = rider['profiles'];
    final profile = (profileData is Map<String, dynamic>) ? profileData : <String, dynamic>{};
    final name = profile['full_name'] as String? ?? 'Unknown';
    final phone = profile['phone'] as String? ?? '';
    final docs = (rider['kyc_documents'] as Map<String, dynamic>?) ?? {};
    final submittedAt = DateTime.tryParse(rider['created_at']?.toString() ?? '');

    return _KycCard(
      emoji: '🏍️',
      accentColor: const Color(0xFF51CF66),
      name: name,
      phone: phone,
      submittedAt: submittedAt,
      details: [
        _DetailRow('Aadhaar', rider['aadhar_number']?.toString() ?? '-'),
        _DetailRow('PAN', rider['pan_number']?.toString() ?? '-'),
        _DetailRow('Driving License', rider['driving_license']?.toString() ?? '-'),
        _DetailRow('Vehicle Type', rider['vehicle_type']?.toString() ?? '-'),
        _DetailRow('Reg. No.', rider['vehicle_reg_number']?.toString() ?? '-'),
        _DetailRow('Bank Holder', rider['bank_account_holder']?.toString() ?? '-'),
        _DetailRow('Account No.', rider['bank_account_number']?.toString() ?? '-'),
        _DetailRow('IFSC', rider['bank_ifsc']?.toString() ?? '-'),
      ],
      docImages: _extractDocImages(docs, ['aadhar_front', 'aadhar_back', 'pan_front', 'pan_back', 'dl_front', 'dl_back', 'rc_front', 'rc_back']),
      onApprove: () => _approveRider(rider),
      onReject: () => _rejectRider(rider),
      canApprove: context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('riders.approve'),
      canReject: context.read<RbacProvider>().isSuperAdmin || context.read<RbacProvider>().can('riders.approve'),
    );
  }

  List<_DocImage> _extractDocImages(Map<String, dynamic> docs, List<String> keys) {
    return keys
        .where((k) => docs[k] != null && (docs[k] as String).isNotEmpty)
        .map((k) => _DocImage(label: k.replaceAll('_', ' ').toUpperCase(), url: docs[k] as String))
        .toList();
  }
}

// ── Reusable KYC Card Widget ─────────────────────────────────────────────────

class _KycCard extends StatefulWidget {
  final String emoji;
  final Color accentColor;
  final String name;
  final String phone;
  final DateTime? submittedAt;
  final List<_DetailRow> details;
  final List<_DocImage> docImages;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final bool canApprove;
  final bool canReject;

  const _KycCard({
    required this.emoji,
    required this.accentColor,
    required this.name,
    required this.phone,
    required this.submittedAt,
    required this.details,
    required this.docImages,
    required this.onApprove,
    required this.onReject,
    required this.canApprove,
    required this.canReject,
  });

  @override
  State<_KycCard> createState() => _KycCardState();
}

class _KycCardState extends State<_KycCard> {
  bool _expanded = false;
  bool _approving = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
              ),
              child: Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, style: AdminStyles.title(size: 15)),
              const SizedBox(height: 2),
              Text(widget.phone, style: AdminStyles.body(color: AdminColors.textMuted, size: 12)),
              if (widget.submittedAt != null)
                Text('Submitted ${_timeAgo(widget.submittedAt!)}',
                    style: AdminStyles.body(color: AdminColors.textMuted, size: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AdminColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AdminColors.warning.withValues(alpha: 0.4)),
              ),
              child: Text('PENDING', style: GoogleFonts.poppins(
                color: AdminColors.warning, fontSize: 10, fontWeight: FontWeight.w800,
              )),
            ),
          ]),
        ),

        // ── Details (collapsible) ──────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: AdminColors.textMuted, size: 18,
              ),
              const SizedBox(width: 6),
              Text(_expanded ? 'Hide Documents' : 'View Documents & Details',
                  style: AdminStyles.body(color: widget.accentColor, size: 13)),
            ]),
          ),
        ),

        if (_expanded) ...[
          const Divider(color: AdminColors.cardBorder, height: 1),
          // Identity Details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identity & Bank Details', style: AdminStyles.label()),
                const SizedBox(height: 8),
                ...widget.details.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 120,
                      child: Text(d.label, style: AdminStyles.body(color: AdminColors.textMuted, size: 12)),
                    ),
                    Expanded(child: Text(d.value, style: AdminStyles.body(size: 12))),
                  ]),
                )),
              ],
            ),
          ),

          if (widget.docImages.isNotEmpty) ...[
            const Divider(color: AdminColors.cardBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Document Images', style: AdminStyles.label()),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.docImages.length,
                    itemBuilder: (_, i) {
                      final doc = widget.docImages[i];
                      return GestureDetector(
                        onTap: () => _showFullImage(doc),
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AdminColors.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AdminColors.cardBorder),
                          ),
                          child: Column(children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                child: CachedNetworkImage(
                                  imageUrl: doc.url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  placeholder: (_, __) => const Center(
                                    child: CircularProgressIndicator(
                                      color: AdminColors.primary, strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image, color: AdminColors.textMuted),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(doc.label,
                                  style: AdminStyles.body(color: AdminColors.textMuted, size: 9),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ],
        ],

        // ── Action Buttons ────────────────────────────────────────────────
        const Divider(color: AdminColors.cardBorder, height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (widget.canReject)
              Expanded(
                child: OutlinedButton(
                  onPressed: _rejecting ? null : () async {
                    setState(() => _rejecting = true);
                    await widget.onReject();
                    if (mounted) setState(() => _rejecting = false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.danger,
                    side: const BorderSide(color: AdminColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _rejecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AdminColors.danger, strokeWidth: 2))
                      : Text('Reject', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
            if (widget.canReject && widget.canApprove)
              const SizedBox(width: 12),
            if (widget.canApprove)
              Expanded(
                child: ElevatedButton(
                  onPressed: _approving ? null : () async {
                    setState(() => _approving = true);
                    await widget.onApprove();
                    if (mounted) setState(() => _approving = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _approving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Approve', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  void _showFullImage(_DocImage doc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(doc.label, style: AdminStyles.body()),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: CachedNetworkImage(
              imageUrl: doc.url,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AdminColors.primary),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }
}

class _DetailRow {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
}

class _DocImage {
  final String label;
  final String url;
  const _DocImage({required this.label, required this.url});
}
