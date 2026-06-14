import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/admin/kyc_verification_dialog.dart';

class RidersAdminPage extends StatefulWidget {
  const RidersAdminPage({super.key});

  @override
  State<RidersAdminPage> createState() => _RidersAdminPageState();
}

class _RidersAdminPageState extends State<RidersAdminPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _riders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    try {
      final res = await _db
          .from('delivery_partners')
          .select('*, profiles:id(full_name, phone, avatar_url)')
          .order('created_at', ascending: false)
          .limit(100);
      setState(() {
        _riders = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus(String riderId, bool currentStatus) async {
    try {
      await _db
          .from('delivery_partners')
          .update({'is_active': !currentStatus}).eq('id', riderId);
      _fetchRiders();
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
        : _riders.isEmpty
            ? Center(
                child: Text('No riders found',
                    style: GoogleFonts.outfit(color: Colors.white54)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _riders.length,
                itemBuilder: (context, index) {
                  final rider = _riders[index];
                  final profile = rider['profiles'] ?? {};
                  final isActive = rider['is_active'] == true;
                  final isOnline = rider['is_online'] == true;
                  final vStatus = rider['verification_status'] ?? 'none';

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
                          radius: 24,
                          backgroundColor:
                              const Color(0xFF00BCD4).withValues(alpha: 0.2),
                          backgroundImage: profile['avatar_url'] != null
                              ? NetworkImage(profile['avatar_url'])
                              : null,
                          child: profile['avatar_url'] == null
                              ? const Icon(Icons.delivery_dining_rounded,
                                  color: Color(0xFF00BCD4))
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile['full_name'] ?? 'Unknown Rider',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  profile['phone'] ??
                                      rider['vehicle_number'] ??
                                      'No contact info',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color:
                                          isOnline ? Colors.green : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(isOnline ? 'Online' : 'Offline',
                                      style: GoogleFonts.outfit(
                                          color: isOnline
                                              ? Colors.green
                                              : Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.directions_bike_rounded,
                                      color: Colors.white38, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                      '${rider['total_deliveries'] ?? 0} deliveries',
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
                                      onPressed: () =>
                                          _showVerifyDialog(rider, profile),
                                      icon: const Icon(
                                          Icons.verified_user_rounded,
                                          size: 16),
                                      label: const Text('Review KYC'),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF00BCD4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 0),
                                        backgroundColor: const Color(0xFF00BCD4)
                                            .withValues(alpha: 0.1),
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
                                  _toggleStatus(rider['id'], isActive),
                              activeThumbColor: const Color(0xFF00BCD4),
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

  void _showVerifyDialog(
      Map<String, dynamic> rider, Map<String, dynamic> profile) {
    showDialog(
      context: context,
      builder: (_) => KycVerificationDialog(
        title: 'Verify Rider: ${profile['full_name']}',
        data: rider,
        tableName: 'delivery_partners',
        idColumn: 'id',
        onRefresh: _fetchRiders,
      ),
    );
  }
}
