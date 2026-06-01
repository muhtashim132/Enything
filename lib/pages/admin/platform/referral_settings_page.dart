import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/platform_config_provider.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../theme/admin_theme.dart';

class ReferralSettingsPage extends StatefulWidget {
  const ReferralSettingsPage({super.key});

  @override
  State<ReferralSettingsPage> createState() => _ReferralSettingsPageState();
}

class _ReferralSettingsPageState extends State<ReferralSettingsPage> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startEdit(double initialValue) {
    _ctrl.text = initialValue.toString();
    setState(() => _isEditing = true);
  }

  Future<void> _saveEdit(PlatformConfigProvider config, RbacProvider rbac) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || double.tryParse(text) == null) {
      setState(() => _isEditing = false);
      return;
    }

    final success = await config.updateSetting(
      key: 'referral_bonus_amount',
      value: text,
      actorId: rbac.currentAdmin?.id ?? 'unknown',
      actorRole: rbac.currentAdmin?.role?.name ?? 'Super Admin',
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Referral bonus updated!', style: AdminStyles.body(size: 13)),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
      setState(() => _isEditing = false);
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
        title: Text('Referral Rewards', style: AdminStyles.title()),
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
                _buildBonusCard(config, rbac),
                const SizedBox(height: 24),
                _buildStatsCard(),
              ],
            ).animate().fadeIn(duration: 300.ms),
    );
  }

  Widget _buildBonusCard(PlatformConfigProvider config, RbacProvider rbac) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.card_giftcard_rounded, color: AdminColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Referral Bonus Amount', style: AdminStyles.title(size: 16)),
                    const SizedBox(height: 4),
                    Text('Amount credited to both referrer and referee', style: AdminStyles.caption(color: AdminColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isEditing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: AdminStyles.title(size: 24),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: AdminStyles.title(size: 24),
                      filled: true,
                      fillColor: AdminColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _saveEdit(config, rbac),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _saveEdit(config, rbac),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: Text('Save', style: AdminStyles.title(color: Colors.white, size: 16)),
                ),
              ],
            )
          else
            GestureDetector(
              onTap: rbac.isSuperAdmin ? () => _startEdit(config.referralBonusAmount) : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '₹${config.referralBonusAmount}',
                      style: AdminStyles.title(size: 36, color: AdminColors.primary),
                    ),
                    const SizedBox(height: 4),
                    if (rbac.isSuperAdmin)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit_rounded, color: AdminColors.textMuted, size: 14),
                          const SizedBox(width: 4),
                          Text('Tap to edit', style: AdminStyles.caption(color: AdminColors.textMuted)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Referral Statistics', style: AdminStyles.title(size: 16)),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildStatItem('Total Referrals', '0', Icons.people_rounded),
              _buildStatItem('Bonus Paid Out', '₹0', Icons.account_balance_wallet_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AdminColors.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stats will populate when the referral system goes live.',
                    style: AdminStyles.caption(color: AdminColors.warning),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AdminColors.textMuted),
              const SizedBox(width: 6),
              Text(label, style: AdminStyles.caption(color: AdminColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: AdminStyles.title(size: 24)),
        ],
      ),
    );
  }
}
