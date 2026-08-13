import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../models/order_model.dart';

class DisputeSheet extends StatefulWidget {
  final OrderModel order;
  const DisputeSheet({super.key, required this.order});

  @override
  State<DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<DisputeSheet> {
  final _supabase = Supabase.instance.client;
  String _selectedReason = 'Damaged Food / Items';
  final _descriptionController = TextEditingController();
  final _photoUrlController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'Damaged Food / Items',
    'Missing Items',
    'Cold / Quality Issue',
    'Wrong Item Delivered',
    'Package Tampered',
    'Other Issue'
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitDispute() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final photoUrls = _photoUrlController.text.trim().isNotEmpty
          ? [_photoUrlController.text.trim()]
          : [];

      await _supabase.from('order_disputes').insert({
        'order_id': widget.order.id,
        'customer_id': userId,
        'shop_id': widget.order.shopId,
        'reason': _selectedReason,
        'description': _descriptionController.text.trim(),
        'photo_urls': photoUrls,
        'refund_amount_requested': widget.order.grandTotal,
        'status': 'pending',
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dispute claim submitted! Admin team will review.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting dispute: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit dispute: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.report_problem_outlined,
                    color: AppColors.danger, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Report Issue / Dispute',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select the reason for your dispute claim. Our admin dispatch team will inspect and process your claim.',
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Reason for Issue',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: _reasons.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(
                        r,
                        style: GoogleFonts.outfit(
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedReason = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Description of Problem',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Describe what was missing, damaged, or wrong...',
                hintStyle: GoogleFonts.outfit(
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey[300]!,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Photo Evidence URL (Optional)',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _photoUrlController,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'https://... (URL of item photo)',
                hintStyle: GoogleFonts.outfit(
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey[300]!,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitDispute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Submit Dispute Claim',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
