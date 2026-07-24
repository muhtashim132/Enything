import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';
import '../../config/app_categories.dart';

class AllCategoriesPage extends StatelessWidget {
  const AllCategoriesPage({super.key});

  static const List<List<Color>> _gradients = [
    [Color(0xFFFF6B6B), Color(0xFFEE5A24)], // Red/Orange
    [Color(0xFF51CF66), Color(0xFF2F9E44)], // Green
    [Color(0xFF4C6EF5), Color(0xFF364FC7)], // Blue
    [Color(0xFFFF8C42), Color(0xFFE8590C)], // Orange
    [Color(0xFFCC5DE8), Color(0xFF9C36B5)], // Purple
    [Color(0xFF20C997), Color(0xFF0CA678)], // Teal
    [Color(0xFF339AF0), Color(0xFF1864AB)], // Light Blue
    [Color(0xFFFCC419), Color(0xFFE67700)], // Yellow
    [Color(0xFFFF8787), Color(0xFFE03131)], // Pink/Red
    [Color(0xFF22B8CF), Color(0xFF0B7285)], // Cyan
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    const categories = AppCategories.all;

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
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final catName = cat['name']!;
              final emoji = cat['emoji']!;
              final grad = _gradients[index % _gradients.length];
              
              final group = AppCategories.groupFor(catName);
              final groupInfo = AppCategories.groupInfo(group);
              final desc = groupInfo['label'] ?? 'Explore $catName';
              
              return GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context, 
                    AppRoutes.categoryProducts,
                    arguments: {'categoryName': catName},
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
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                emoji,
                                style: const TextStyle(fontSize: 38),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                catName,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Flexible(
                                child: Text(
                                  desc,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
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
