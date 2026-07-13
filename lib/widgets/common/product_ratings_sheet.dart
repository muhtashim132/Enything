import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../models/order_model.dart';

class ProductRatingData {
  final String productId;
  final int rating;
  final String review;

  ProductRatingData({
    required this.productId,
    required this.rating,
    required this.review,
  });
}

class ProductRatingsSheet extends StatefulWidget {
  final List<OrderItem> items;
  final Function(List<ProductRatingData> ratings) onSubmit;

  const ProductRatingsSheet({
    super.key,
    required this.items,
    required this.onSubmit,
  });

  @override
  State<ProductRatingsSheet> createState() => _ProductRatingsSheetState();
}

class _ProductRatingsSheetState extends State<ProductRatingsSheet> {
  final Map<String, int> _ratings = {};
  final Map<String, TextEditingController> _reviewControllers = {};

  // Deduplicate products based on productId to avoid multiple rating boxes for the same product
  late final List<OrderItem> _uniqueProducts;

  @override
  void initState() {
    super.initState();
    final Map<String, OrderItem> uniqueMap = {};
    for (final item in widget.items) {
      if (!uniqueMap.containsKey(item.productId)) {
        uniqueMap[item.productId] = item;
      }
    }
    _uniqueProducts = uniqueMap.values.toList();

    for (final item in _uniqueProducts) {
      _ratings[item.productId] = 0;
      _reviewControllers[item.productId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _reviewControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    // True if at least one product has a rating > 0
    return _ratings.values.any((r) => r > 0);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Rate Products 🛍️',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'How was the quality of the items?',
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: _uniqueProducts.length,
                separatorBuilder: (context, index) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                ),
                itemBuilder: (context, index) {
                  final item = _uniqueProducts[index];
                  final currentRating = _ratings[item.productId] ?? 0;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.shopping_bag_outlined, color: AppColors.textLight),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.variantName != null && item.variantName!.isNotEmpty)
                                  Text(
                                    item.variantName!,
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (starIndex) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _ratings[item.productId] = starIndex + 1;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Icon(
                                starIndex < currentRating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: starIndex < currentRating
                                    ? Colors.amber
                                    : Colors.grey[300],
                                size: 40,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _reviewControllers[item.productId],
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Add an optional review...',
                          hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _canSubmit
                    ? () {
                        Navigator.pop(context);
                        final results = <ProductRatingData>[];
                        for (final item in _uniqueProducts) {
                          final r = _ratings[item.productId] ?? 0;
                          if (r > 0) {
                            results.add(ProductRatingData(
                              productId: item.productId,
                              rating: r,
                              review: _reviewControllers[item.productId]!.text.trim(),
                            ));
                          }
                        }
                        widget.onSubmit(results);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Submit Ratings',
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
