// ============================================================================
// seller_bulk_modification_sheet.dart — Seller Modification Proposal
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../models/order_model.dart';

class SellerBulkModificationSheet extends StatefulWidget {
  final OrderModel order;
  final VoidCallback onSubmitted;

  const SellerBulkModificationSheet({
    super.key,
    required this.order,
    required this.onSubmitted,
  });

  @override
  State<SellerBulkModificationSheet> createState() =>
      _SellerBulkModificationSheetState();
}

class _SellerBulkModificationSheetState
    extends State<SellerBulkModificationSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _notesController = TextEditingController();
  final Map<String, int> _modifiedQuantities = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (final item in widget.order.items) {
      _modifiedQuantities[item.productId] = item.quantity;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitProposal() async {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please explain the proposed modification to the customer'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final proposedItems = widget.order.items.map((i) {
        return {
          'product_id': i.productId,
          'product_name': i.productName,
          'original_quantity': i.quantity,
          'proposed_quantity': _modifiedQuantities[i.productId] ?? i.quantity,
        };
      }).toList();

      final modificationPayload = {
        'notes': notes,
        'proposed_items': proposedItems,
        'proposed_at': DateTime.now().toIso8601String(),
      };

      await _supabase.rpc(
        'respond_bulk_order_seller',
        params: {
          'p_order_id': widget.order.id,
          'p_response': 'modification_proposed',
          'p_notes': notes,
          'p_modification': modificationPayload,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modification proposal sent to customer!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error proposing bulk order modification: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit proposal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Propose Menu Changes ✏️',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Running short on ingredients or prep capacity? Suggest quantity adjustments or dish substitutions. The customer must approve before confirmation.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Adjust Quantities:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ...widget.order.items.map((item) {
                final qty = _modifiedQuantities[item.productId] ?? item.quantity;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            memCacheWidth: 80,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.restaurant_rounded,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          item.productName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: qty > 5
                            ? () {
                                setState(() {
                                  _modifiedQuantities[item.productId] = qty - 5;
                                });
                              }
                            : null,
                      ),
                      Text(
                        '$qty',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () {
                          setState(() {
                            _modifiedQuantities[item.productId] = qty + 5;
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Explanation for Customer',
                  hintText: 'e.g. Can prepare 40 burgers instead of 60 due to bun stock...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitProposal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Send Proposal to Customer',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
