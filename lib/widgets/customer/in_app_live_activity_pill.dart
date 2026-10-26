import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/routes.dart';
import '../../services/live_activity_service.dart';
import '../../theme/sensory_haptics.dart';
import '../../utils/order_messaging_helper.dart';

/// Floating Dynamic Island / Live Activity Pill rendered at the top of customer pages
/// while an order is actively in-flight. Automatically hides when TrackOrderPage is opened.
class InAppLiveActivityPill extends StatelessWidget {
  const InAppLiveActivityPill({super.key});

  IconData _categoryIcon(OrderFulfillmentCategory category) {
    switch (category) {
      case OrderFulfillmentCategory.pharmacy:
        return Icons.medication_rounded;
      case OrderFulfillmentCategory.grocery:
        return Icons.shopping_basket_rounded;
      case OrderFulfillmentCategory.retail:
        return Icons.inventory_2_rounded;
      case OrderFulfillmentCategory.cateringFood:
        return Icons.restaurant_menu_rounded;
      case OrderFulfillmentCategory.cateringSupplies:
        return Icons.inventory_2_rounded;
      case OrderFulfillmentCategory.mixed:
        return Icons.storefront_rounded;
      case OrderFulfillmentCategory.food:
        return Icons.soup_kitchen_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LiveActivityService().isTrackOrderPageOpenNotifier,
      builder: (context, isTrackOpen, child) {
        if (isTrackOpen) return const SizedBox.shrink();

        return ValueListenableBuilder<LiveActivityState?>(
          valueListenable: LiveActivityService().activeStateNotifier,
          builder: (context, state, child) {
            if (state == null || state.isTerminal) {
              return const SizedBox.shrink();
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  builder: (context, animValue, child) {
                    return Transform.translate(
                      offset: Offset(0, (1 - animValue) * -20),
                      child: Opacity(
                        opacity: animValue.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        SensoryHaptics.light();
                        Navigator.pushNamed(
                          context,
                          AppRoutes.trackOrder,
                          arguments: {'orderId': state.orderId},
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14151C).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFFF5200).withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF5200).withValues(alpha: 0.18),
                              blurRadius: 16,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                // Left Glyph: Pulsing Orange Icon Badge
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5200).withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFFF5200).withValues(alpha: 0.6),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      state.status == 'out_for_delivery'
                                          ? Icons.two_wheeler_rounded
                                          : _categoryIcon(state.fulfillmentCategory),
                                      color: const Color(0xFFFF5200),
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Center Content: "Arriving in X mins" + Headline
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Arriving in ',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${state.etaMinutes} mins',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFFFF5200),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (state.isMultiShop) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF5200).withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Multi-Store',
                                                style: GoogleFonts.outfit(
                                                  color: const Color(0xFFFF6D00),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        state.statusHeadline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white.withValues(alpha: 0.82),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Right Chevron Indicator
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),

                            // Sleek Orange Progress Bar (matching Swiggy Lock Screen)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: state.progress.clamp(0.05, 1.0),
                                minHeight: 3.5,
                                backgroundColor: Colors.white.withValues(alpha: 0.12),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF5200)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
