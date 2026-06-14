import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrescriptionsAdminPage extends StatefulWidget {
  const PrescriptionsAdminPage({super.key});

  @override
  State<PrescriptionsAdminPage> createState() => _PrescriptionsAdminPageState();
}

class _PrescriptionsAdminPageState extends State<PrescriptionsAdminPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pendingOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPrescriptions();
  }

  Future<void> _fetchPrescriptions() async {
    try {
      final response = await _supabase
          .from('orders')
          .select(
              '*, order_items(*), profiles!orders_customer_id_fkey(full_name, phone)')
          .eq('status', 'pending_verification')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingOrders = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching prescriptions: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus}).eq('id', orderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newStatus == 'pending'
              ? 'Prescription Approved!'
              : 'Prescription Rejected!'),
          backgroundColor: newStatus == 'pending' ? Colors.green : Colors.red,
        ));
      }
      _fetchPrescriptions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showPrescriptionImages(List<String> urls) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF141425),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: double.infinity,
          height: 500,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prescription Images',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: urls.length,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 300,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                        image: DecorationImage(
                            image: NetworkImage(urls[index]),
                            fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFFE8590C)))
        : _pendingOrders.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.white38, size: 64),
                    const SizedBox(height: 16),
                    Text('No pending prescriptions!',
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 18)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingOrders.length,
                itemBuilder: (context, index) {
                  final order = _pendingOrders[index];
                  final customer = order['profiles'] ?? {};
                  final items = List<Map<String, dynamic>>.from(
                      order['order_items'] ?? []);
                  final urls =
                      List<String>.from(order['prescription_urls'] ?? []);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141425),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                'Order ID: ${order['id'].toString().substring(0, 8).toUpperCase()}',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            Text('Wait time: 30m max',
                                style: GoogleFonts.outfit(
                                    color: const Color(0xFFFF8C42),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Customer: ${customer['full_name'] ?? 'Unknown'} (${customer['phone'] ?? 'No phone'})',
                            style: GoogleFonts.outfit(color: Colors.white70)),
                        const Divider(color: Colors.white10, height: 24),
                        Text('Medicines Ordered:',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...items.map((i) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                  '• ${i['quantity']}x ${i['product_name']}',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white54, fontSize: 13)),
                            )),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: urls.isEmpty
                                    ? null
                                    : () => _showPrescriptionImages(urls),
                                icon: const Icon(Icons.image_outlined,
                                    size: 16, color: Colors.white),
                                label: Text('View ${urls.length} Images',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Colors.white24)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _updateStatus(
                                    order['id'], 'verification_failed'),
                                icon: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                                label: const Text('Reject (Refund)',
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.red.withValues(alpha: 0.8)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _updateStatus(order['id'], 'pending'),
                                icon: const Icon(Icons.check,
                                    size: 16, color: Colors.white),
                                label: const Text('Approve (Send to Shop)',
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
  }
}
