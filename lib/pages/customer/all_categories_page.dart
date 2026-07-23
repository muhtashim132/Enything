import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';

class AllCategoriesPage extends StatelessWidget {
  const AllCategoriesPage({super.key});

  static const List<Map<String, dynamic>> _categories = [
    {
      'name': 'Food',
      'emoji': '🍔',
      'grad': [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
      'desc': 'Restaurants, fast food, sweets'
    },
    {
      'name': 'Grocery',
      'emoji': '🛒',
      'grad': [Color(0xFF51CF66), Color(0xFF2F9E44)],
      'desc': 'Supermarkets, fruits, daily needs'
    },
    {
      'name': 'Pharmacy',
      'emoji': '💊',
      'grad': [Color(0xFF4C6EF5), Color(0xFF364FC7)],
      'desc': 'Medicines, health, medical stores'
    },
    {
      'name': 'Clothing',
      'emoji': '👕',
      'grad': [Color(0xFFFF8C42), Color(0xFFE8590C)],
      'desc': 'Fashion, apparel, shoes'
    },
    {
      'name': 'Electronics',
      'emoji': '📱',
      'grad': [Color(0xFFCC5DE8), Color(0xFF9C36B5)],
      'desc': 'Mobiles, accessories, gadgets'
    },
    {
      'name': 'More',
      'emoji': '🛍️',
      'grad': [Color(0xFF20C997), Color(0xFF0CA678)],
      'desc': 'Stationery, hardware, beauty'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'All Categories',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = Responsive.getGridCrossAxisCount(context, mobile: 2, tablet: 3, desktop: 4);
          
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.85,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final grad = cat['grad'] as List<Color>;
              
              return GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context, 
                    AppRoutes.categoryProducts,
                    arguments: {'categoryName': cat['name']},
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: grad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: grad.first.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -10,
                        top: -10,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -14,
                        bottom: -14,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat['emoji'] as String,
                              style: const TextStyle(fontSize: 44),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              cat['name'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat['desc'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
