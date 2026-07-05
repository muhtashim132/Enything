import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../theme/admin_theme.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../providers/platform_config_provider.dart';
import '../../../../config/tax_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tax Settings Page (Updated: September 2025 GST Reform)
// Allows super-admins to override GST rates, slab thresholds, and slab high
// rates per category. Reads from `tax_config` table; falls back to TaxConfig
// code defaults (which themselves reflect the Sept 2025 reform).
// ─────────────────────────────────────────────────────────────────────────────

class TaxSettingsPage extends StatefulWidget {
  const TaxSettingsPage({super.key});

  @override
  State<TaxSettingsPage> createState() => _TaxSettingsPageState();
}

class _TaxSettingsPageState extends State<TaxSettingsPage> {
  SupabaseClient get _db => Supabase.instance.client;

  // Map of category -> tax_config row from DB
  final Map<String, Map<String, dynamic>> _dbRows = {};
  bool _loading = true;

  // Which category row is being edited inline
  String? _editingCategory;
  final _rateCtrl = TextEditingController();
  // Extra controllers for slab threshold and high rate (Clothing/Footwear)
  final _slabThresholdCtrl = TextEditingController();
  final _slabHighRateCtrl = TextEditingController();

  // ── Product-level keyword override state ──────────────────────────────────
  List<Map<String, dynamic>> _productOverrides = [];
  bool _loadingOverrides = false;
  String? _editingOverrideId; // id of the rule being edited inline
  final _overrideKeywordCtrl = TextEditingController();
  final _overrideCatHintCtrl = TextEditingController();
  final _overrideRateCtrl = TextEditingController();
  final _overrideReasonCtrl = TextEditingController();

  // ── Categories (updated: Sept 2025 — new categories added) ───────────────
  static const _sections = [
    _Section(
      title: 'Food & Restaurant (Section 9(5))',
      icon: Icons.restaurant_rounded,
      color: AdminColors.warning,
      categories: [
        'Restaurant',
        'Fast Food',
        'Bakery',
        'Sweets & Mithai',
        'Tea & Coffee',
        'Ice Cream',
        'Paan Shop',
      ],
    ),
    _Section(
      title: 'Perishables & Fresh',
      icon: Icons.eco_rounded,
      color: AdminColors.success,
      categories: [
        'Fruits & Vegs',
        'Butcher',
        'Fish & Seafood',
        'Dairy & Eggs',
      ],
    ),
    _Section(
      title: 'Grocery & Pharmacy',
      icon: Icons.local_grocery_store_rounded,
      color: AdminColors.info,
      categories: [
        'Grocery',
        'Organic',
        'Supermarket / Hypermarket',
        'Beverages',
        'Pharmacy',
        'Medical Store',
      ],
    ),
    _Section(
      title: 'Fashion & Electronics',
      icon: Icons.devices_rounded,
      color: AdminColors.primary,
      categories: [
        'Clothing',
        'Footwear',
        'Electronics',
        'Mobile & Repair',
        'Jewellery',
      ],
    ),
    _Section(
      title: 'General Retail',
      icon: Icons.store_rounded,
      color: Color(0xFFEC4899),
      categories: [
        'Stationery',
        'Toys & Games',
        'Sports',
        'Pet Supplies',
        'Salon & Beauty',
        'Cosmetics & Beauty',
        'Flowers',
        'Home Decor',
        'Furniture',
        'Hardware Store',
        'Auto Parts',
        'Other',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchTaxConfig();
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    _slabThresholdCtrl.dispose();
    _slabHighRateCtrl.dispose();
    _overrideKeywordCtrl.dispose();
    _overrideCatHintCtrl.dispose();
    _overrideRateCtrl.dispose();
    _overrideReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTaxConfig() async {
    setState(() => _loading = true);
    try {
      final data = await _db.from('tax_config').select();
      _dbRows.clear();
      for (final row in (data as List)) {
        _dbRows[row['category'] as String] = Map<String, dynamic>.from(row);
      }
      // Also fetch product keyword overrides
      await _fetchProductOverrides();
    } catch (e) {
      _showSnack('Failed to load: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchProductOverrides() async {
    setState(() => _loadingOverrides = true);
    try {
      final data = await _db
          .from('product_gst_overrides')
          .select()
          .order('keyword', ascending: true);
      if (mounted) {
        setState(() {
          _productOverrides = List<Map<String, dynamic>>.from(data as List);
        });
      }
    } catch (e) {
      _showSnack('Could not load product overrides: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingOverrides = false);
    }
  }

  // ── Data helpers ────────────────────────────────────────────────────────────

  double _getRate(String category) {
    if (_dbRows.containsKey(category)) {
      final v = _dbRows[category]!['gst_rate'];
      return (double.tryParse(v.toString()) ?? 0) * 100;
    }
    return TaxConfig.gstRateForCategory(category) * 100;
  }

  double? _getSlabThreshold(String category) {
    if (_dbRows.containsKey(category)) {
      final v = _dbRows[category]!['slab_threshold'];
      if (v != null) return double.tryParse(v.toString());
    }
    if (category == 'Clothing' || category == 'Footwear') {
      return TaxConfig.defaultSlabThreshold;
    }
    return null;
  }

  double? _getSlabHighRate(String category) {
    if (_dbRows.containsKey(category)) {
      final v = _dbRows[category]!['slab_high_rate'];
      if (v != null) return double.tryParse(v.toString());
    }
    if (category == 'Clothing' || category == 'Footwear') {
      return TaxConfig.defaultSlabHighRate;
    }
    return null;
  }

  bool _getDeemedSupplier(String category) {
    if (_dbRows.containsKey(category)) {
      return _dbRows[category]!['is_deemed_supplier'] as bool? ?? false;
    }
    return TaxConfig.isEnythingDeemedSupplier(category);
  }

  bool _isCustom(String category) =>
      _dbRows[category]?['is_custom'] as bool? ?? false;

  // ── Edit helpers ────────────────────────────────────────────────────────────

  void _startEdit(String category) {
    _rateCtrl.text = _getRate(category).toStringAsFixed(0);
    final threshold = _getSlabThreshold(category);
    final highRate = _getSlabHighRate(category);
    _slabThresholdCtrl.text =
        threshold != null ? threshold.toStringAsFixed(0) : '';
    _slabHighRateCtrl.text =
        highRate != null ? (highRate * 100).toStringAsFixed(0) : '';
    setState(() => _editingCategory = category);
  }

  Future<void> _saveRate(String category, RbacProvider rbac) async {
    final val = double.tryParse(_rateCtrl.text.trim());
    if (val == null || val < 0 || val > 100) {
      _showSnack('Enter a valid rate between 0 and 100', error: true);
      return;
    }
    final rateDecimal = val / 100;
    final isDeemedSupplier = _getDeemedSupplier(category);

    // Parse optional slab fields (Clothing/Footwear only)
    final slabThresholdText = _slabThresholdCtrl.text.trim();
    final slabHighRateText = _slabHighRateCtrl.text.trim();
    final double? slabThreshold = slabThresholdText.isNotEmpty
        ? double.tryParse(slabThresholdText)
        : null;
    final double? slabHighRate = slabHighRateText.isNotEmpty
        ? (double.tryParse(slabHighRateText) ?? 18.0) / 100
        : null;

    try {
      await _db.from('tax_config').upsert({
        'category': category,
        'gst_rate': rateDecimal,
        'slab_threshold': slabThreshold,
        'slab_high_rate': slabHighRate,
        'is_deemed_supplier': isDeemedSupplier,
        'is_custom': true,
        'updated_by': rbac.currentAdmin?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'category');

      // Audit log (best-effort)
      try {
        await _db.from('audit_logs').insert({
          'actor_id': rbac.currentAdmin?.id,
          'actor_role': rbac.currentAdmin?.role?.name ?? 'Super Admin',
          'action': 'update_tax_config',
          'entity_type': 'tax_config',
          'metadata': {
            'category': category,
            'new_rate': '$val%',
            if (slabThreshold != null) 'slab_threshold': slabThreshold,
            if (slabHighRate != null)
              'slab_high_rate_pct':
                  '${(slabHighRate * 100).toStringAsFixed(0)}%',
          },
        });
      } catch (_) {}

      setState(() {
        _dbRows[category] = {
          ...(_dbRows[category] ?? {}),
          'gst_rate': rateDecimal,
          'slab_threshold': slabThreshold,
          'slab_high_rate': slabHighRate,
          'is_deemed_supplier': isDeemedSupplier,
          'is_custom': true,
        };
        _editingCategory = null;
      });
      _showSnack('$category GST rate updated to $val%');
    } catch (e) {
      _showSnack('Failed to save: $e', error: true);
    }
  }

  Future<void> _toggleDeemedSupplier(
      String category, bool value, RbacProvider rbac) async {
    final rate = _getRate(category) / 100;
    try {
      await _db.from('tax_config').upsert({
        'category': category,
        'gst_rate': rate,
        'is_deemed_supplier': value,
        'is_custom': true,
        'updated_by': rbac.currentAdmin?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'category');

      setState(() {
        _dbRows[category] = {
          ...(_dbRows[category] ?? {}),
          'gst_rate': rate,
          'is_deemed_supplier': value,
          'is_custom': true,
        };
      });
    } catch (e) {
      _showSnack('Failed to update: $e', error: true);
    }
  }

  Future<void> _resetToDefault(String category, RbacProvider rbac) async {
    final defaultRate = TaxConfig.gstRateForCategory(category);
    final defaultDeemed = TaxConfig.isEnythingDeemedSupplier(category);
    final defaultThreshold = (category == 'Clothing' || category == 'Footwear')
        ? TaxConfig.defaultSlabThreshold
        : null;
    final defaultHighRate = (category == 'Clothing' || category == 'Footwear')
        ? TaxConfig.defaultSlabHighRate
        : null;

    try {
      await _db.from('tax_config').upsert({
        'category': category,
        'gst_rate': defaultRate,
        'slab_threshold': defaultThreshold,
        'slab_high_rate': defaultHighRate,
        'is_deemed_supplier': defaultDeemed,
        'is_custom': false,
        'updated_by': rbac.currentAdmin?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'category');

      setState(() {
        _dbRows[category] = {
          'category': category,
          'gst_rate': defaultRate,
          'slab_threshold': defaultThreshold,
          'slab_high_rate': defaultHighRate,
          'is_deemed_supplier': defaultDeemed,
          'is_custom': false,
        };
        if (_editingCategory == category) _editingCategory = null;
      });
      _showSnack(
          '$category reset to Sept 2025 default (${(defaultRate * 100).toStringAsFixed(0)}%)');
    } catch (e) {
      _showSnack('Failed to reset: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminStyles.body(size: 13)),
      backgroundColor: error ? AdminColors.danger : AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    final config = context.watch<PlatformConfigProvider>();
    final canEdit = rbac.isSuperAdmin;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Tax Settings', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh_rounded, color: AdminColors.textMuted),
            onPressed: _fetchTaxConfig,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AdminColors.primary))
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Sept 2025 GST Reform Banner ─────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AdminColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AdminColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.new_releases_rounded,
                          color: AdminColors.warning, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sept 2025 GST Reform Applied',
                              style: AdminStyles.body(
                                  size: 13, color: AdminColors.warning),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'India\'s GST simplification (Notification 9/2025-CT Rate, Sep 22 2025) '
                              'removed the 12% & 28% slabs for most goods. '
                              'Clothing/Footwear threshold raised to ₹2,500 per item/pair. '
                              'Beverages, Stationery, Toys & Games, Sports raised to 18%. '
                              'Use this page to update rates when the government issues new notifications.',
                              style: AdminStyles.caption(
                                  color: AdminColors.warning),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 30.ms),

                // ── Add-On GST Info Banner ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AdminColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AdminColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AdminColors.info, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'GST rates are added ON TOP of the seller\'s base price (add-on model). '
                          'Custom overrides apply to all new orders immediately.',
                          style: AdminStyles.caption(color: AdminColors.info),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Service Tax Overrides ───────────────────────────────────
                _buildServiceTaxSection(config, rbac, canEdit),
                const SizedBox(height: 8),

                // ── Per-Category Sections ───────────────────────────────────
                ..._sections.asMap().entries.map((entry) {
                  final i = entry.key;
                  final section = entry.value;
                  return _buildSection(section, rbac, canEdit,
                      delay: (i + 1) * 80);
                }),

                const SizedBox(height: 16),
                    ]),
                  ),
                ),

                // ── Product GST Keyword Overrides Section ───────────────────
                ..._buildProductOverridesSectionSlivers(canEdit),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }

  // ── Product GST Keyword Overrides ─────────────────────────────────────────

  List<Widget> _buildProductOverridesSectionSlivers(bool canEdit) {
    const slabOptions = [0.00, 0.03, 0.05, 0.18, 0.40];

    String rateLabel(double r) => '${(r * 100).toStringAsFixed(0)}%';

    Color rateColor(double r) {
      if (r == 0.00) return const Color(0xFF00C853);
      if (r == 0.03) return const Color(0xFF9C27B0);
      if (r == 0.05) return AdminColors.info;
      if (r == 0.18) return AdminColors.warning;
      return AdminColors.danger;
    }

    Future<void> saveRule({
      String? existingId,
      required String keyword,
      required String? categoryHint,
      required double rate,
      required String reason,
    }) async {
      try {
        final row = {
          'keyword': keyword.toLowerCase().trim(),
          'category_hint': categoryHint?.trim().isEmpty ?? true
              ? null
              : categoryHint!.trim(),
          'gst_rate': rate,
          'reason': reason.trim(),
          'is_active': true,
        };
        if (existingId != null) {
          await _db
              .from('product_gst_overrides')
              .update(row)
              .eq('id', existingId);
        } else {
          await _db.from('product_gst_overrides').insert(row);
        }
        // Reload engine so seller's next recommendation is fresh
        await _fetchProductOverrides();
        setState(() => _editingOverrideId = null);
        _showSnack('Saved: "$keyword" → ${rateLabel(rate)}');
      } catch (e) {
        _showSnack('Failed to save: $e', error: true);
      }
    }

    Future<void> deleteRule(String id, String keyword) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.cardBg,
          title: Text('Delete Rule', style: AdminStyles.title(size: 16)),
          content: Text(
            'Remove keyword rule "$keyword"? Sellers adding new products will no longer see this recommendation.',
            style: AdminStyles.body(size: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: AdminStyles.body(color: AdminColors.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: AdminStyles.body(color: AdminColors.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await _db.from('product_gst_overrides').delete().eq('id', id);
        await _fetchProductOverrides();
        _showSnack('Keyword rule "$keyword" deleted.');
      } catch (e) {
        _showSnack('Failed to delete: $e', error: true);
      }
    }

    void startEdit(Map<String, dynamic> rule) {
      setState(() {
        _editingOverrideId = rule['id'];
        _overrideKeywordCtrl.text = rule['keyword'] ?? '';
        _overrideCatHintCtrl.text = rule['category_hint'] ?? '';
        _overrideRateCtrl.text = rule['gst_rate']?.toString() ?? '0.18';
        _overrideReasonCtrl.text = rule['reason'] ?? '';
      });
    }

    void startAdd() {
      setState(() {
        _editingOverrideId = 'new';
        _overrideKeywordCtrl.text = '';
        _overrideCatHintCtrl.text = '';
        _overrideRateCtrl.text = '0.18';
        _overrideReasonCtrl.text = '';
      });
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: AdminColors.cardBg,
              borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(16),
                  bottom: _productOverrides.isEmpty && !_loadingOverrides
                      ? const Radius.circular(16)
                      : Radius.zero),
              border: Border(
                top: const BorderSide(color: AdminColors.cardBorder),
                left: const BorderSide(color: AdminColors.cardBorder),
                right: const BorderSide(color: AdminColors.cardBorder),
                bottom: _productOverrides.isEmpty && !_loadingOverrides
                    ? const BorderSide(color: AdminColors.cardBorder)
                    : BorderSide.none,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section Header ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Color(0xFF7C4DFF), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Product GST Keyword Rules',
                                style: AdminStyles.title(size: 15)),
                            Text(
                              'Auto-recommend correct GST rate when seller types a product name. '
                              'Matched case-insensitively. Category hint narrows match to that category only.',
                              style:
                                  AdminStyles.caption(color: AdminColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (_loadingOverrides)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AdminColors.primary)),
                      if (canEdit) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: Color(0xFF7C4DFF)),
                          tooltip: 'Add keyword rule',
                          onPressed: startAdd,
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(height: 1, color: AdminColors.cardBorder),

                // ── Add New Rule Row (shown when _editingOverrideId == 'new') ────
                if (_editingOverrideId == 'new') ...[
                  _buildOverrideEditRow(
                    rateLabel: rateLabel,
                    rateColor: rateColor,
                    slabOptions: slabOptions,
                    onSave: () async {
                      final rate = double.tryParse(_overrideRateCtrl.text) ?? 0.18;
                      final kw = _overrideKeywordCtrl.text.trim();
                      if (kw.isEmpty) {
                        _showSnack('Keyword cannot be empty', error: true);
                        return;
                      }
                      await saveRule(
                        keyword: kw,
                        categoryHint: _overrideCatHintCtrl.text.trim().isEmpty
                            ? null
                            : _overrideCatHintCtrl.text.trim(),
                        rate: rate,
                        reason: _overrideReasonCtrl.text.trim(),
                      );
                    },
                    onCancel: () => setState(() => _editingOverrideId = null),
                  ),
                  const Divider(height: 1, color: AdminColors.cardBorder),
                ],

                // ── Empty State ────────────────────────────────────────────
                if (_productOverrides.isEmpty && !_loadingOverrides)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No custom keyword rules.\nThe engine uses 200+ built-in rules from the migration seed.',
                        textAlign: TextAlign.center,
                        style: AdminStyles.caption(color: AdminColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      if (_productOverrides.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: _productOverrides.length,
            itemBuilder: (ctx, i) {
              final rule = _productOverrides[i];
              final id = rule['id'] as String;
              final keyword = rule['keyword'] as String? ?? '';
              final catHint = rule['category_hint'] as String?;
              final rate = double.tryParse(rule['gst_rate'].toString()) ?? 0.18;
              final reason = rule['reason'] as String? ?? '';
              final isActive = rule['is_active'] as bool? ?? true;
              final isEditing = _editingOverrideId == id;
              final isLast = i == _productOverrides.length - 1;

              Widget child;
              if (isEditing) {
                child = _buildOverrideEditRow(
                  rateLabel: rateLabel,
                  rateColor: rateColor,
                  slabOptions: slabOptions,
                  onSave: () async {
                    final r = double.tryParse(_overrideRateCtrl.text) ?? 0.18;
                    await saveRule(
                      existingId: id,
                      keyword: _overrideKeywordCtrl.text.trim(),
                      categoryHint: _overrideCatHintCtrl.text.trim().isEmpty
                          ? null
                          : _overrideCatHintCtrl.text.trim(),
                      rate: r,
                      reason: _overrideReasonCtrl.text.trim(),
                    );
                  },
                  onCancel: () => setState(() => _editingOverrideId = null),
                );
              } else {
                child = Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      // Rate badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: rateColor(rate).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: rateColor(rate).withValues(alpha: 0.3)),
                        ),
                        child: Text(rateLabel(rate),
                            style: AdminStyles.title(
                                size: 13, color: rateColor(rate))),
                      ),
                      const SizedBox(width: 12),
                      // Keyword + category hint + reason
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(keyword,
                                    style: AdminStyles.body(
                                        size: 13,
                                        color: isActive
                                            ? AdminColors.textPrimary
                                            : AdminColors.textMuted)),
                                if (catHint != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(catHint,
                                        style: AdminStyles.caption(
                                            color: AdminColors.primary)),
                                  ),
                              ],
                            ),
                            if (reason.isNotEmpty)
                              Text(reason,
                                  style: AdminStyles.caption(
                                      color: AdminColors.textMuted)),
                          ],
                        ),
                      ),
                      // Actions
                      if (canEdit) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              color: AdminColors.textMuted, size: 18),
                          tooltip: 'Edit',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                          onPressed: () => startEdit(rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AdminColors.danger, size: 18),
                          tooltip: 'Delete',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                          onPressed: () => deleteRule(id, keyword),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: AdminColors.cardBg,
                  borderRadius: isLast
                      ? const BorderRadius.vertical(bottom: Radius.circular(16))
                      : BorderRadius.zero,
                  border: Border(
                    left: const BorderSide(color: AdminColors.cardBorder),
                    right: const BorderSide(color: AdminColors.cardBorder),
                    bottom: isLast ? const BorderSide(color: AdminColors.cardBorder) : BorderSide.none,
                  ),
                ),
                child: Column(
                  children: [
                    if (i != 0) const Divider(height: 1, color: AdminColors.cardBorder),
                    child,
                  ],
                ),
              );
            },
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// Shared inline edit row for both add-new and edit-existing keyword rules.
  Widget _buildOverrideEditRow({
    required String Function(double) rateLabel,
    required Color Function(double) rateColor,
    required List<double> slabOptions,
    required VoidCallback onSave,
    required VoidCallback onCancel,
  }) {
    final currentRate = double.tryParse(_overrideRateCtrl.text) ?? 0.18;

    return StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keyword + category hint row
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _overrideKeywordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Keyword (lowercase)',
                      hintText: 'e.g., shampoo',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    style: AdminStyles.body(size: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _overrideCatHintCtrl,
                    decoration: InputDecoration(
                      labelText: 'Category hint (opt.)',
                      hintText: 'e.g., Pharmacy',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    style: AdminStyles.body(size: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Reason field
            TextField(
              controller: _overrideReasonCtrl,
              decoration: InputDecoration(
                labelText: 'Reason shown to seller',
                hintText: 'e.g., Shampoo — 5% FMCG Merit Rate',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: AdminStyles.body(size: 13),
            ),
            const SizedBox(height: 10),
            // Rate selector
            Text('GST Rate:', style: AdminStyles.caption()),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: slabOptions.map((r) {
                final selected = currentRate == r;
                return GestureDetector(
                  onTap: () {
                    setLocal(() {
                      _overrideRateCtrl.text = r.toString();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? rateColor(r).withValues(alpha: 0.15)
                          : AdminColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              selected ? rateColor(r) : AdminColors.cardBorder,
                          width: selected ? 2.0 : 1.0),
                    ),
                    child: Text(rateLabel(r),
                        style: AdminStyles.title(
                            size: 13,
                            color: selected
                                ? rateColor(r)
                                : AdminColors.textMuted)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: Text('Cancel',
                      style: AdminStyles.body(
                          size: 13, color: AdminColors.textMuted)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C4DFF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  onPressed: onSave,
                  child: Text('Save Rule',
                      style: AdminStyles.body(size: 13, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Service tax section (delivery + platform GST) ──────────────────────────

  Widget _buildServiceTaxSection(
      PlatformConfigProvider config, RbacProvider rbac, bool canEdit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: AdminColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text('Enything Service Taxes',
                    style: AdminStyles.title(size: 15)),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminColors.cardBorder),
          _buildServiceItem(
            key: 'delivery_gst_rate',
            label: 'Delivery Charge GST',
            subtitle: 'SAC 9965/9967 — Enything remits to govt',
            currentValue: config.deliveryGstRate * 100,
            config: config,
            rbac: rbac,
            canEdit: canEdit,
          ),
          const Divider(height: 1, color: AdminColors.cardBorder),
          _buildServiceItem(
            key: 'platform_fee_gst_rate',
            label: 'Platform Fee GST',
            subtitle: 'SAC 9985 — Enything remits to govt',
            currentValue: config.platformFeeGstRate * 100,
            config: config,
            rbac: rbac,
            canEdit: canEdit,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 50.ms).slideX(begin: -0.05);
  }

  Widget _buildServiceItem({
    required String key,
    required String label,
    required String subtitle,
    required double currentValue,
    required PlatformConfigProvider config,
    required RbacProvider rbac,
    required bool canEdit,
  }) {
    final isEditing = _editingCategory == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AdminStyles.body(size: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AdminStyles.caption(color: AdminColors.textMuted)),
              ],
            ),
          ),
          if (isEditing)
            SizedBox(
              width: 130,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AdminStyles.body(),
                      decoration: InputDecoration(
                        suffixText: '%',
                        suffixStyle: AdminStyles.caption(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        isDense: true,
                        filled: true,
                        fillColor: AdminColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded,
                        color: AdminColors.success, size: 24),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final val = double.tryParse(_rateCtrl.text.trim());
                      if (val == null) return;
                      await config.updateSetting(
                        key: key,
                        value: (val / 100).toString(),
                        actorId: rbac.currentAdmin?.id ?? '',
                        actorRole:
                            rbac.currentAdmin?.role?.name ?? 'Super Admin',
                      );
                      setState(() => _editingCategory = null);
                    },
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: canEdit
                  ? () {
                      _rateCtrl.text = currentValue.toStringAsFixed(0);
                      setState(() => _editingCategory = key);
                    }
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${currentValue.toStringAsFixed(0)}%',
                        style: AdminStyles.title(
                            size: 14, color: AdminColors.primary)),
                    if (canEdit) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_rounded,
                          color: AdminColors.textMuted, size: 14),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Category section builder ────────────────────────────────────────────────

  Widget _buildSection(_Section section, RbacProvider rbac, bool canEdit,
      {int delay = 0}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: section.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(section.icon, color: section.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(section.title,
                        style: AdminStyles.title(size: 14))),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminColors.cardBorder),
          ...section.categories.asMap().entries.map((e) {
            final isLast = e.key == section.categories.length - 1;
            return Column(
              children: [
                _buildCategoryRow(e.value, rbac, canEdit),
                if (!isLast)
                  const Divider(height: 1, color: AdminColors.cardBorder),
              ],
            );
          }),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay))
        .slideX(begin: -0.05);
  }

  // ── Category row ────────────────────────────────────────────────────────────

  Widget _buildCategoryRow(String category, RbacProvider rbac, bool canEdit) {
    final isEditing = _editingCategory == category;
    final rate = _getRate(category);
    final deemed = _getDeemedSupplier(category);
    final custom = _isCustom(category);
    final isSlab = (category == 'Clothing' || category == 'Footwear');
    final slabThreshold = _getSlabThreshold(category);
    final slabHighRate = _getSlabHighRate(category);
    final slabDesc = isSlab
        ? TaxConfig.slabDescription(
            category,
            slabThreshold: slabThreshold,
            slabHighRate: slabHighRate,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Category name + badges ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(category, style: AdminStyles.body(size: 13)),
                        if (custom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  AdminColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('CUSTOM',
                                style: AdminStyles.label(
                                    color: AdminColors.primary, size: 9)),
                          ),
                        ],
                      ],
                    ),
                    if (deemed)
                      Text('Enything deemed supplier (S.9(5))',
                          style: AdminStyles.label(
                              color: AdminColors.warning, size: 9)),
                    if (slabDesc != null && !isEditing)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          slabDesc,
                          style: AdminStyles.label(
                              color: AdminColors.info, size: 9),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Inline editor ──────────────────────────────────────────
              if (isEditing)
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Base / low-slab rate row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: AdminStyles.body(size: 13),
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: isSlab ? 'Low slab %' : 'GST %',
                                labelStyle: AdminStyles.label(size: 10),
                                suffixText: '%',
                                suffixStyle: AdminStyles.caption(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                isDense: true,
                                filled: true,
                                fillColor: AdminColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _saveRate(category, rbac),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check_circle_rounded,
                                color: AdminColors.success, size: 22),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _saveRate(category, rbac),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: AdminColors.textMuted, size: 20),
                            padding: const EdgeInsets.only(left: 2),
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                setState(() => _editingCategory = null),
                          ),
                        ],
                      ),
                      // Slab-specific fields (Clothing / Footwear only)
                      if (isSlab) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: _slabThresholdCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: false),
                          style: AdminStyles.body(size: 12),
                          decoration: InputDecoration(
                            labelText: 'Threshold ₹',
                            labelStyle: AdminStyles.label(size: 10),
                            hintText: '2500',
                            hintStyle: AdminStyles.caption(
                                color: AdminColors.textMuted),
                            prefixText: '₹',
                            prefixStyle: AdminStyles.caption(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            filled: true,
                            fillColor: AdminColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _slabHighRateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: AdminStyles.body(size: 12),
                          decoration: InputDecoration(
                            labelText: 'High slab %',
                            labelStyle: AdminStyles.label(size: 10),
                            suffixText: '%',
                            hintText: '18',
                            hintStyle: AdminStyles.caption(
                                color: AdminColors.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            isDense: true,
                            filled: true,
                            fillColor: AdminColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                // ── Read-only chip + controls ──────────────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Deemed supplier toggle
                    if (canEdit)
                      GestureDetector(
                        onTap: () =>
                            _toggleDeemedSupplier(category, !deemed, rbac),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: deemed
                                ? AdminColors.warning.withValues(alpha: 0.15)
                                : AdminColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: deemed
                                  ? AdminColors.warning.withValues(alpha: 0.4)
                                  : AdminColors.cardBorder,
                            ),
                          ),
                          child: Text(
                            'S.9(5)',
                            style: AdminStyles.label(
                              color: deemed
                                  ? AdminColors.warning
                                  : AdminColors.textMuted,
                              size: 9,
                            ),
                          ),
                        ),
                      ),
                    // Rate chip
                    GestureDetector(
                      onTap: canEdit ? () => _startEdit(category) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AdminColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminColors.cardBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${rate.toStringAsFixed(0)}%',
                                style: AdminStyles.title(
                                    size: 13, color: AdminColors.primary)),
                            if (canEdit) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_rounded,
                                  color: AdminColors.textMuted, size: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Reset button (only if customised)
                    if (canEdit && custom) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.restart_alt_rounded,
                            color: AdminColors.textMuted, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Reset to Sept 2025 default',
                        onPressed: () => _resetToDefault(category, rbac),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> categories;
  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.categories,
  });
}
