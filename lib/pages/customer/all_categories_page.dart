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
import '../../theme/sensory_haptics.dart';
import '../../widgets/3d/perspective_card.dart';

class AllCategoriesPage extends StatefulWidget {
  const AllCategoriesPage({super.key});

  @override
  State<AllCategoriesPage> createState() => _AllCategoriesPageState();
}

class _AllCategoriesPageState extends State<AllCategoriesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCollection = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final config = context.watch<PlatformConfigProvider>();

    // Show only active categories (filtering admin-disabled ones)
    final allCategories = config.activeCategoryMaps;

    // Filter categories based on search query and selected collection
    final filteredCategories = allCategories.where((cat) {
      final name = (cat['name'] ?? '').toLowerCase();
      final emoji = (cat['emoji'] ?? '');
      final subtitle =
          AppCategories.getCustomerSubtitle(cat['name'] ?? '').toLowerCase();
      final collection =
          AppCategories.getCustomerCollection(cat['name'] ?? '');

      // Collection filter
      if (_selectedCollection != 'All' && collection != _selectedCollection) {
        return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = name.contains(query);
        final matchesSubtitle = subtitle.contains(query);
        final matchesEmoji = emoji.contains(query);
        final matchesCollection = collection.toLowerCase().contains(query);
        return matchesName ||
            matchesSubtitle ||
            matchesEmoji ||
            matchesCollection;
      }

      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Explore Categories',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              '${allCategories.length} categories available',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
      ),
      body: Column(
        children: [
          // ── Search & Filter Header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A1D30)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search food, groceries, medicines, clothes...',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white38 : AppColors.textSecondary,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: isDark ? Colors.white60 : Colors.black54,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),

          // ── Collection Segment Filter Chips ────────────────────────────────
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: AppCategories.customerCollections.length,
              itemBuilder: (context, index) {
                final collection = AppCategories.customerCollections[index];
                final isSelected = _selectedCollection == collection;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      SensoryHaptics.light();
                      setState(() => _selectedCollection = collection);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryDark,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected
                            ? null
                            : isDark
                                ? const Color(0xFF16192B)
                                : const Color(0xFFF1F3F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          collection,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : isDark
                                    ? Colors.white70
                                    : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // ── Category Grid / Empty State ────────────────────────────────────
          Expanded(
            child: filteredCategories.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.18 : 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search_off_rounded,
                              size: 32,
                              color: isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No categories found',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try searching with a different term or resetting the collection filter.',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              SensoryHaptics.light();
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedCollection = 'All';
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              'Reset Filters',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = Responsive.getGridCrossAxisCount(
                        context,
                        mobile: 2,
                        tablet: 3,
                        desktop: 4,
                      );

                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.86,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        itemCount: filteredCategories.length,
                        itemBuilder: (context, index) {
                          final cat = filteredCategories[index];
                          final catName = cat['name']!;
                          final catImage = cat['image'];
                          final imageUrl =
                              (catImage != null && catImage.isNotEmpty)
                                  ? catImage
                                  : AppCategories.getImageUrl(catName);

                          final subtitle =
                              AppCategories.getCustomerSubtitle(catName);
                          final emoji = cat['emoji'] ?? '🏪';

                          return PerspectiveCard(
                            borderRadius: 22,
                            maxTiltAngle: 0.08,
                            pressScale: 0.96,
                            onTap: () {
                              SensoryHaptics.light();
                              Navigator.pushNamed(
                                context,
                                AppRoutes.categoryProducts,
                                arguments: {'categoryName': catName},
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.black.withValues(alpha: 0.06),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.35)
                                        : Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(21),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Category Hero Image
                                    CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 400,
                                      maxWidthDiskCache: 600,
                                      fadeInDuration:
                                          const Duration(milliseconds: 250),
                                      placeholder: (context, url) => Container(
                                        color: isDark
                                            ? const Color(0xFF1E2235)
                                            : const Color(0xFFE2E8F0),
                                        child: Center(
                                          child: Text(
                                            emoji,
                                            style:
                                                const TextStyle(fontSize: 32),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: isDark
                                            ? const Color(0xFF1E2235)
                                            : const Color(0xFFE2E8F0),
                                        child: Center(
                                          child: Text(
                                            emoji,
                                            style:
                                                const TextStyle(fontSize: 36),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Multi-layer Scrim for high legibility
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.25),
                                            Colors.black.withValues(alpha: 0.88),
                                          ],
                                          stops: const [0.0, 0.40, 1.0],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),

                                    // Top Emoji Micro-Capsule
                                    Positioned(
                                      top: 10,
                                      left: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.45),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.20),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),

                                    // Bottom Text Content
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            catName,
                                            style: GoogleFonts.outfit(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              height: 1.15,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            subtitle,
                                            style: GoogleFonts.outfit(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white
                                                  .withValues(alpha: 0.82),
                                              height: 1.1,
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
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
