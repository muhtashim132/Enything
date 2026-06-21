import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../widgets/admin/kyc_verification_dialog.dart';
import '../../../widgets/common/star_rating_display.dart';
import '../../../theme/app_colors.dart';

class SellersAdminPage extends StatefulWidget {
  const SellersAdminPage({super.key});

  @override
  State<SellersAdminPage> createState() => _SellersAdminPageState();
}

class _SellersAdminPageState extends State<SellersAdminPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _sellers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSellers();
  }

  Future<void> _fetchSellers() async {
    try {
      final res = await _db.rpc('admin_get_all_shops');
      setState(() {
        _sellers = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus(String shopId, bool currentStatus) async {
    try {
      await _db
          .from('shops')
          .update({'is_active': !currentStatus}).eq('id', shopId);
      _fetchSellers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF8B2FC9)))
        : _sellers.isEmpty
            ? Center(
                child: Text('No sellers found',
                    style: GoogleFonts.outfit(color: Colors.white54)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sellers.length,
                itemBuilder: (context, index) {
                  final shop = _sellers[index];
                  final profile = shop['profiles'] ?? {};
                  final isActive = shop['is_active'] == true;
                  final vStatus = shop['verification_status'] ?? 'none';
                  final createdAt = shop['created_at'] != null
                      ? DateFormat('MMM dd, yyyy')
                          .format(DateTime.parse(shop['created_at']))
                      : 'Unknown';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              const Color(0xFF8B2FC9).withValues(alpha: 0.2),
                          child: const Icon(Icons.store_rounded,
                              color: Color(0xFF8B2FC9)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(shop['name'] ?? 'Unnamed Shop',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text(profile['full_name'] ?? 'Unknown Owner',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white70, fontSize: 13)),
                              Text(shop['category'] ?? 'Category',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white38, fontSize: 12)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  StarRatingDisplay(
                                      rating: (shop['average_rating'] ?? 0.0).toDouble(),
                                      color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                      '${(shop['average_rating'] as num?)?.toStringAsFixed(1) ?? '0.0'} (${shop['total_reviews'] ?? 0} reviews)',
                                      style: GoogleFonts.outfit(
                                          color: Colors.white70, fontSize: 12)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.calendar_today_rounded,
                                      color: Colors.white38, size: 12),
                                  const SizedBox(width: 4),
                                  Text(createdAt,
                                      style: GoogleFonts.outfit(
                                          color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildStatusBadge(vStatus),
                                  if (vStatus == 'pending') ...[
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _showVerifyDialog(shop),
                                      icon: const Icon(
                                          Icons.verified_user_rounded,
                                          size: 16),
                                      label: const Text('Review KYC'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 0),
                                        backgroundColor:
                                            AppColors.primary.withValues(alpha: 0.1),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Switch(
                              value: isActive,
                              onChanged: (v) =>
                                  _toggleStatus(shop['id'], isActive),
                              activeThumbColor: const Color(0xFF8B2FC9),
                            ),
                            Text(isActive ? 'Active' : 'Suspended',
                                style: GoogleFonts.outfit(
                                    color: isActive ? Colors.green : Colors.red,
                                    fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    String label = status.toUpperCase();
    if (status == 'verified') color = Colors.green;
    if (status == 'pending') color = Colors.orange;
    if (status == 'rejected') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showVerifyDialog(Map<String, dynamic> shop) {
    showDialog(
      context: context,
      builder: (_) => KycVerificationDialog(
        title: 'Verify Seller: ${shop['name']}',
        data: shop,
        tableName: 'shops',
        idColumn: 'id',
        onRefresh: _fetchSellers,
      ),
    );
  }
}
