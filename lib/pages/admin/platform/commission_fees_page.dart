import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/platform_config_provider.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../theme/admin_theme.dart';
import '../../../../config/app_categories.dart';

class CommissionFeesPage extends StatefulWidget {
  const CommissionFeesPage({super.key});

  @override
  State<CommissionFeesPage> createState() => _CommissionFeesPageState();
}

class _CommissionFeesPageState extends State<CommissionFeesPage> {
  final Map<String, TextEditingController> _ctrls = {};
  String? _editingKey;

  @override
  void dispose() {
    for (var ctrl in _ctrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _startEdit(String key, double initialValue) {
    if (!_ctrls.containsKey(key)) {
      _ctrls[key] = TextEditingController();
    }
    _ctrls[key]!.text = initialValue.toString();
    setState(() => _editingKey = key);
  }

  Future<void> _saveEdit(String key, PlatformConfigProvider config, RbacProvider rbac) async {
    final text = _ctrls[key]?.text.trim() ?? '';
    if (text.isEmpty || double.tryParse(text) == null) {
      setState(() => _editingKey = null);
      return;
    }

    final success = await config.updateSetting(
      key: key,
      value: text,
      actorId: rbac.currentAdmin?.id ?? 'unknown',
      actorRole: rbac.currentAdmin?.role?.name ?? 'Super Admin',
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved successfully!', style: AdminStyles.body(size: 13)),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save setting.', style: AdminStyles.body(size: 13)),
          backgroundColor: AdminColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
      setState(() => _editingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<PlatformConfigProvider>();
    final rbac = context.watch<RbacProvider>();

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Commission & Fees', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: config.loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  title: 'Core Fees',
                  icon: Icons.percent_rounded,
                  color: AdminColors.primary,
                  children: [
                    _buildItem('commission_percent', 'Platform Commission', 'Percentage charged on base item price', config.commissionPercent, '%', config, rbac),
                    _buildItem('platform_fee', 'Handling Fee', 'Flat fee added to customer total', config.platformFee, '₹', config, rbac),
                  ],
                ),
                _buildSection(
                  title: 'Small Cart Penalty',
                  icon: Icons.shopping_basket_rounded,
                  color: AdminColors.warning,
                  children: [
                    _buildItem('small_cart_threshold', 'Small Cart Threshold', 'Orders below this attract the fee', config.smallCartThreshold, '₹', config, rbac),
                    _buildItem('small_cart_fee', 'Small Cart Fee', 'Flat penalty fee applied', config.smallCartFee, '₹', config, rbac),
                  ],
                ),
                _buildSection(
                  title: 'Delivery Rules',
                  icon: Icons.two_wheeler_rounded,
                  color: AdminColors.info,
                  children: [
                    _buildItem('delivery_rate_per_km', 'Delivery Rate', 'Charge per km (₹/km)', config.deliveryRatePerKm, '₹/km', config, rbac),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminColors.cardBorder),
                        ),
                        child: Text(
                          'Preview at ₹${config.deliveryRatePerKm.toInt()}/km: 1km=₹${(1 * config.deliveryRatePerKm).toInt()} · 5km=₹${(5 * config.deliveryRatePerKm).toInt()} · 10km=₹${(10 * config.deliveryRatePerKm).toInt()} · 15km=₹${(15 * config.deliveryRatePerKm).toInt()}',
                          style: AdminStyles.caption(color: AdminColors.textPrimary),
                        ),
                      ),
                    ),
                    _buildItem('max_delivery_radius_km', 'Max Delivery Radius', 'Furthest distance allowed', config.maxDeliveryRadiusKm, 'km', config, rbac),
                    _buildItem('delivery_discount_threshold', 'Discount Threshold', 'Orders above this get discount', config.deliveryDiscountThreshold, '₹', config, rbac),
                    _buildItem('delivery_discount_amount', 'Discount Amount', 'Flat discount applied to delivery', config.deliveryDiscountAmount, '₹', config, rbac),
                  ],
                ),
                _buildSection(
                  title: 'Heavy Orders',
                  icon: Icons.scale_rounded,
                  color: AdminColors.danger,
                  children: [
                    _buildItem('heavy_order_threshold_kg', 'Heavy Weight Threshold', 'Orders above this get penalty', config.heavyOrderThresholdKg, 'kg', config, rbac),
                    _buildItem('heavy_order_fee', 'Heavy Order Fee', 'Flat penalty for heavy orders', config.heavyOrderFee, '₹', config, rbac),
                  ],
                ),
                _buildSection(
                  title: 'Category Overrides',
                  icon: Icons.category_rounded,
                  color: AdminColors.success,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Leave empty when editing to fallback to the global Platform Commission (${config.commissionPercent}%).',
                        style: AdminStyles.caption(color: AdminColors.textPrimary),
                      ),
                    ),
                    ...AppCategories.names.map((cat) {
                      final val = config.getCommissionPercentForCategory(cat);
                      return _buildItem('commission_percent_$cat', cat, 'Override for $cat', val, '%', config, rbac);
                    }),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: 300.ms),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
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
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Text(title, style: AdminStyles.title(size: 15)),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminColors.cardBorder),
          ...children,
        ],
      ),
    );
  }

  Widget _buildItem(String key, String title, String subtitle, double value, String unit, PlatformConfigProvider config, RbacProvider rbac) {
    final isEditing = _editingKey == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AdminStyles.body(size: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: AdminStyles.caption(color: AdminColors.textMuted)),
              ],
            ),
          ),
          if (isEditing)
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrls[key],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AdminStyles.body(),
                      decoration: InputDecoration(
                        suffixText: unit,
                        suffixStyle: AdminStyles.caption(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                        filled: true,
                        fillColor: AdminColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _saveEdit(key, config, rbac),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 24),
                    onPressed: () => _saveEdit(key, config, rbac),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: rbac.isSuperAdmin ? () => _startEdit(key, value) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      unit == '₹' ? '₹$value' : (unit == '%' ? '$value%' : '$value $unit'),
                      style: AdminStyles.title(size: 14, color: AdminColors.primary),
                    ),
                    if (rbac.isSuperAdmin) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_rounded, color: AdminColors.textMuted, size: 14),
                    ]
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
