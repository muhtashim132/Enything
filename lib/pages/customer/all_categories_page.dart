import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/theme_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';
import '../../config/app_categories.dart';

class AllCategoriesPage extends StatelessWidget {
  const AllCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final config = context.watch<PlatformConfigProvider>();
    // Show only active categories (filtering disabled ones)
    final categories = config.activeCategoryMaps.isNotEmpty
        ? config.activeCategoryMaps
        : AppCategories.all; // fallback to full list if provider not ready

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
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = Responsive.getGridCrossAxisCount(context,
              mobile: 2, tablet: 3, desktop: 4);

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
              final catImage = cat['image'];
              final imageUrl = (catImage != null && catImage.isNotEmpty)
                  ? catImage
                  : AppCategories.getImageUrl(catName);

              final group = AppCategories.groupFor(catName);
              final groupInfo = AppCategories.groupInfo(group);
              final desc = groupInfo['label'] ?? 'Explore $catName';

              final emoji = cat['emoji'] ?? '🏪';

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
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 300),
                          placeholder: (context, url) => Container(
                            color: isDark
                                ? const Color(0xFF1E2235)
                                : const Color(0xFFE2E8F0),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 32),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: isDark
                                ? const Color(0xFF1E2235)
                                : const Color(0xFFE2E8F0),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 36),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
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
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
