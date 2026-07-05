import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/time_utils.dart';
import '../../config/routes.dart';

class RiderOrderHistoryPage extends StatefulWidget {
  const RiderOrderHistoryPage({super.key});

  @override
  State<RiderOrderHistoryPage> createState() => _RiderOrderHistoryPageState();
}

class _RiderOrderHistoryPageState extends State<RiderOrderHistoryPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final auth = context.read<AuthProvider>();
    try {
      final res = await _supabase
          .from('orders')
          .select('id, created_at, status, rider_earnings, delivery_charges, shops!shop_id(name)')
          .eq('delivery_partner_id', auth.currentUserId ?? '')
          .inFilter('status', ['delivered', 'cancelled', 'partner_rejected'])
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading rider order history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        title: Text('Order History', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No order history found.'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      final date = (DateTime.tryParse(order['created_at'] ?? '')?.toIST()) ?? DateTime.now();
                      final amount = (order['rider_earnings'] ?? order['delivery_charges'] ?? 0.0).toDouble();
                      final shopName = order['shops']?['name'] ?? 'Shop';
                      final status = order['status'] as String? ?? 'unknown';

                      Color statusColor;
                      switch (status) {
                        case 'delivered':
                          statusColor = AppColors.success;
                          break;
                        case 'cancelled':
                        case 'partner_rejected':
                          statusColor = AppColors.danger;
                          break;
                        default:
                          statusColor = AppColors.textSecondary;
                      }

                      return Container(
                        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                status == 'delivered' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Order #${order['id'].toString().substring(0, 8).toUpperCase()}',
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  Text(
                                    shopName,
                                    style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMM dd, hh:mm a').format(date),
                                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '+₹${amount.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    color: status == 'delivered' ? AppColors.success : AppColors.textSecondary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    decoration: status != 'delivered' ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      color: statusColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
