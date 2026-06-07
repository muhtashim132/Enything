import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/time_utils.dart';

/// Rider withdrawal page — mirrors SellerWithdrawalsPage but reads
/// earnings from the delivery_partners earnings column instead of orders.
class RiderWithdrawalsPage extends StatefulWidget {
  const RiderWithdrawalsPage({super.key});

  @override
  State<RiderWithdrawalsPage> createState() => _RiderWithdrawalsPageState();
}

class _RiderWithdrawalsPageState extends State<RiderWithdrawalsPage> {
  final _db = Supabase.instance.client;

  final _amountCtrl     = TextEditingController();
  final _upiCtrl        = TextEditingController();
  final _bankAccCtrl    = TextEditingController();
  final _bankIfscCtrl   = TextEditingController();
  final _bankHolderCtrl = TextEditingController();
  final _formKey        = GlobalKey<FormState>();
  bool _useUpi          = true;
  bool _submitting      = false;

  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;
  double _availableBalance = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _upiCtrl.dispose();
    _bankAccCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankHolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = context.read<AuthProvider>().currentUserId ?? '';
    try {
      // Past withdrawals
      final histRes = await _db
          .from('withdrawals')
          .select()
          .eq('user_id', userId)
          .eq('user_role', 'delivery_partner')
          .order('requested_at', ascending: false)
          .limit(50);
      _history = List<Map<String, dynamic>>.from(histRes);

      double totalPaid = 0;
      for (final w in _history) {
        if (w['status'] == 'processed') {
          totalPaid += (w['amount'] as num).toDouble();
        }
      }

      // Total earnings = sum of rider_earnings on delivered orders
      final earningsRes = await _db
          .from('orders')
          .select('rider_earnings')
          .eq('rider_id', userId)
          .eq('status', 'delivered');

      double totalEarned = 0;
      for (final o in earningsRes as List) {
        totalEarned += (o['rider_earnings'] as num? ?? 0).toDouble();
      }

      _availableBalance = totalEarned - totalPaid;
    } catch (_) {}

    if (mounted) setState(() => _loadingHistory = false);
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount > _availableBalance) {
      _showSnack('Amount exceeds available balance (₹${_availableBalance.toStringAsFixed(2)})', isError: true);
      return;
    }

    setState(() => _submitting = true);
    final userId = context.read<AuthProvider>().currentUserId ?? '';

    try {
      await _db.from('withdrawals').insert({
        'user_id':             userId,
        'user_role':           'delivery_partner',
        'amount':              amount,
        'upi_id':              _useUpi ? _upiCtrl.text.trim() : null,
        'bank_account_number': !_useUpi ? _bankAccCtrl.text.trim() : null,
        'bank_ifsc':           !_useUpi ? _bankIfscCtrl.text.trim() : null,
        'bank_account_holder': !_useUpi ? _bankHolderCtrl.text.trim() : null,
        'status':              'pending',
      });

      _showSnack('Withdrawal request submitted! Admin will process it within 2 business days.', isError: false);
      _amountCtrl.clear();
      _upiCtrl.clear();
      await _loadData();
    } catch (e) {
      _showSnack('Failed to submit request. Please try again.', isError: true);
    }

    if (mounted) setState(() => _submitting = false);
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Withdraw Earnings', style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: _loadingHistory
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2ECC71), Color(0xFF1ABC9C)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(
                          rupee.format(_availableBalance),
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        const Text('From delivered orders (minus processed withdrawals)',
                            style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ).animate().fadeIn().slideY(begin: -0.1),

                  const SizedBox(height: 24),
                  const Text('Request Withdrawal', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _amountCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDec('Amount (₹)', Icons.currency_rupee_rounded),
                            validator: (v) {
                              final d = double.tryParse(v ?? '');
                              if (d == null || d <= 0) return 'Enter a valid amount';
                              if (d < 100) return 'Minimum withdrawal is ₹100';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _TabBtn('UPI',          _useUpi,  () => setState(() => _useUpi = true)),
                              const SizedBox(width: 8),
                              _TabBtn('Bank Account', !_useUpi, () => setState(() => _useUpi = false)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_useUpi)
                            TextFormField(
                              controller: _upiCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDec('UPI ID (e.g. name@upi)', Icons.account_balance_wallet_rounded),
                              validator: (v) => (v == null || v.isEmpty) ? 'Enter UPI ID' : null,
                            )
                          else ...[
                            TextFormField(
                              controller: _bankHolderCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDec('Account Holder Name', Icons.person_rounded),
                              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bankAccCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDec('Account Number', Icons.account_balance_rounded),
                              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bankIfscCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDec('IFSC Code', Icons.tag_rounded),
                              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submitRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2ECC71),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _submitting
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 28),
                  const Text('Past Requests', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  if (_history.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No withdrawal requests yet.', style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  else
                    ..._history.map((w) => _WithdrawalCard(w)),
                ],
              ),
            ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
      );
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2ECC71) : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(color: active ? Colors.white : Colors.white54, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
}

class _WithdrawalCard extends StatelessWidget {
  final Map<String, dynamic> w;
  const _WithdrawalCard(this.w);
  @override
  Widget build(BuildContext context) {
    final rupee  = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final status = w['status'] as String;
    final statusColor = switch (status) {
      'processed' => Colors.greenAccent,
      'rejected'  => Colors.redAccent,
      'approved'  => Colors.blueAccent,
      _           => Colors.orangeAccent,
    };
    final date = w['requested_at'] != null
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(w['requested_at'].toIST()).toIST())
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(w['upi_id'] != null ? Icons.account_balance_wallet_rounded : Icons.account_balance_rounded,
              color: Colors.white38, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rupee.format((w['amount'] as num).toDouble()),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text(w['upi_id'] ?? w['bank_account_number'] ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(date, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(status.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
