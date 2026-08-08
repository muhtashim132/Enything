import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_categories.dart';
import '../../../../providers/platform_config_provider.dart';
import '../../../../providers/rbac_provider.dart';
import '../../../../theme/admin_theme.dart';

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage>
    with SingleTickerProviderStateMixin {
  Map<String, int> _shopCounts = {};
  bool _loadingCounts = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final config = context.read<PlatformConfigProvider>();
    final counts = await config.getCategoryShopCounts();
    if (mounted) {
      setState(() {
        _shopCounts = counts;
        _loadingCounts = false;
      });
    }
  }

  // ── Create Category Sheet ───────────────────────────────────────────────
  void _showCreateSheet() {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController(text: '🏪');
    final imageCtrl = TextEditingController();
    String selectedGroup = 'retail';
    bool creating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                const Icon(Icons.add_circle_outline_rounded,
                    color: AdminColors.primary, size: 24),
                const SizedBox(width: 10),
                Text('Create New Category', style: AdminStyles.title(size: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              const SizedBox(height: 8),
              const Divider(color: AdminColors.cardBorder),
              const SizedBox(height: 16),
              // Emoji + Name row
              Row(children: [
                SizedBox(
                  width: 72,
                  child: _buildSheetField(
                    controller: emojiCtrl,
                    label: 'Emoji',
                    hint: '🏪',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSheetField(
                    controller: nameCtrl,
                    label: 'Category Name *',
                    hint: 'e.g. Art Supplies',
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // Group picker
              Text('Category Group *',
                  style: AdminStyles.caption(color: AdminColors.textPrimary)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AdminColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedGroup,
                    isExpanded: true,
                    dropdownColor: AdminColors.surface,
                    style: AdminStyles.body(size: 14),
                    items: const [
                      DropdownMenuItem(
                          value: 'food', child: Text('🍔 Food & Restaurant')),
                      DropdownMenuItem(
                          value: 'perishable',
                          child: Text('🛒 Grocery / Perishable')),
                      DropdownMenuItem(
                          value: 'pharmacy',
                          child: Text('💊 Pharmacy / Medical')),
                      DropdownMenuItem(
                          value: 'retail', child: Text('🏪 Retail / General')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheet(() => selectedGroup = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Image URL (optional)
              _buildSheetField(
                controller: imageCtrl,
                label: 'Image URL (optional)',
                hint: 'https://images.unsplash.com/...',
              ),
              const SizedBox(height: 24),
              // Create button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text(creating ? 'Creating…' : 'Create Category',
                      style: AdminStyles.body(size: 15)),
                  onPressed: creating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _showSnack(ctx, 'Category name is required.',
                                isError: true);
                            return;
                          }
                          // Check for duplicate
                          final config = context.read<PlatformConfigProvider>();
                          if (config.allCategoryNames
                              .map((n) => n.toLowerCase())
                              .contains(name.toLowerCase())) {
                            _showSnack(
                                ctx, '"$name" already exists as a category.',
                                isError: true);
                            return;
                          }
                          setSheet(() => creating = true);
                          // Capture refs before await
                          final nav = Navigator.of(ctx);
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await config.createCategory(
                            name: name,
                            emoji: emojiCtrl.text.trim().isEmpty
                                ? '🏪'
                                : emojiCtrl.text.trim(),
                            group: selectedGroup,
                            imageUrl: imageCtrl.text.trim().isEmpty
                                ? null
                                : imageCtrl.text.trim(),
                          );
                          if (mounted) {
                            nav.pop();
                            messenger.showSnackBar(SnackBar(
                              content: Text(
                                ok
                                    ? '"$name" created successfully!'
                                    : 'Failed to create category.',
                                style: AdminStyles.body(size: 13),
                              ),
                              backgroundColor:
                                  ok ? AdminColors.success : AdminColors.danger,
                              behavior: SnackBarBehavior.floating,
                            ));
                            if (ok) _loadCounts();
                          }
                        },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSheetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AdminStyles.caption(color: AdminColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textAlign: textAlign,
          style: AdminStyles.body(size: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AdminStyles.caption(color: AdminColors.textMuted),
            filled: true,
            fillColor: AdminColors.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AdminColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AdminColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AdminColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _showSnack(BuildContext ctx, String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg, style: AdminStyles.body(size: 13)),
      backgroundColor: isError ? AdminColors.danger : AdminColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Toggle with confirmation for categories that have shops ──────────────
  Future<void> _toggleCategory(
      BuildContext ctx, PlatformConfigProvider config, String name) async {
    final rbac = context.read<RbacProvider>();
    if (!rbac.isSuperAdmin) return;

    final isCurrentlyActive = config.isActiveCategory(name);
    final shopCount = _shopCounts[name] ?? 0;

    // If disabling and there are active shops → confirm
    if (isCurrentlyActive && shopCount > 0) {
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (dCtx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Disable "$name"?', style: AdminStyles.title(size: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$shopCount active shop${shopCount == 1 ? "" : "s"} belong to this category.',
                style: AdminStyles.body(size: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Disabling it will hide this category from customers. Existing shops\' data is untouched.',
                style: AdminStyles.caption(color: AdminColors.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text('Cancel',
                    style: AdminStyles.body(color: Colors.white54))),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AdminColors.danger),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text('Disable', style: AdminStyles.body(size: 13)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final ok = await config.toggleCategory(name);
    if (mounted) {
      final msg = ok
          ? '"$name" ${isCurrentlyActive ? "disabled" : "enabled"} successfully.'
          : 'Failed to update "$name".';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: AdminStyles.body(size: 13)),
        backgroundColor: ok ? AdminColors.success : AdminColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Delete custom category ────────────────────────────────────────────────
  Future<void> _deleteCustomCategory(
      BuildContext ctx, PlatformConfigProvider config, String name) async {
    final shopCount = _shopCounts[name] ?? 0;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "$name"?', style: AdminStyles.title(size: 16)),
        content: Text(
          shopCount > 0
              ? 'This category has $shopCount active shop(s). Deleting it won\'t delete those shops but they will show under "Other" until manually updated.'
              : 'This custom category will be permanently deleted.',
          style: AdminStyles.body(size: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text('Cancel',
                  style: AdminStyles.body(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text('Delete', style: AdminStyles.body(size: 13)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await config.deleteCustomCategory(name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          ok ? '"$name" deleted.' : 'Failed to delete "$name".',
          style: AdminStyles.body(size: 13),
        ),
        backgroundColor: ok ? AdminColors.success : AdminColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      if (ok) _loadCounts();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = context.watch<PlatformConfigProvider>();
    final rbac = context.watch<RbacProvider>();
    final isSuperAdmin = rbac.isSuperAdmin;

    const builtInCategories = AppCategories.all;
    final customCategories = config.customCategories;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        title: Text('Category Management', style: AdminStyles.title()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded,
                    size: 18, color: Colors.white),
                label: Text('New', style: AdminStyles.body(size: 13)),
                onPressed: _showCreateSheet,
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AdminColors.primary,
          unselectedLabelColor: AdminColors.textMuted,
          indicatorColor: AdminColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            Tab(
              child: Text('Built-in (${builtInCategories.length})',
                  style: AdminStyles.body(size: 13)),
            ),
            Tab(
              child: Text('Custom (${customCategories.length})',
                  style: AdminStyles.body(size: 13)),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Built-in Categories Tab ─────────────────────────────────────
          _buildCategoryList(
            context,
            config,
            categories: builtInCategories,
            isBuiltIn: true,
            isSuperAdmin: isSuperAdmin,
          ),
          // ── Custom Categories Tab ────────────────────────────────────────
          customCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined,
                          color: AdminColors.textMuted, size: 64),
                      const SizedBox(height: 16),
                      Text('No custom categories yet',
                          style: AdminStyles.title(size: 15)),
                      const SizedBox(height: 8),
                      Text('Tap "+ New" above to create one.',
                          style: AdminStyles.caption(
                              color: AdminColors.textMuted)),
                    ],
                  ).animate().fadeIn(duration: 400.ms),
                )
              : _buildCategoryList(
                  context,
                  config,
                  categories: customCategories,
                  isBuiltIn: false,
                  isSuperAdmin: isSuperAdmin,
                ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(
    BuildContext context,
    PlatformConfigProvider config, {
    required List<Map<String, String>> categories,
    required bool isBuiltIn,
    required bool isSuperAdmin,
  }) {
    return RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _loadCounts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final name = cat['name'] ?? '';
          final emoji = cat['emoji'] ?? '🏪';
          final shopCount = _shopCounts[name] ?? 0;
          final isActive = config.isActiveCategory(name);

          return _CategoryTile(
            name: name,
            emoji: emoji,
            shopCount: shopCount,
            isActive: isActive,
            isBuiltIn: isBuiltIn,
            isSuperAdmin: isSuperAdmin,
            isLoadingCounts: _loadingCounts,
            onToggle: () => _toggleCategory(ctx, config, name),
            onDelete: isBuiltIn
                ? null
                : () => _deleteCustomCategory(ctx, config, name),
          ).animate().fadeIn(
                delay: Duration(milliseconds: 40 * i),
                duration: 300.ms,
              );
        },
      ),
    );
  }
}

// ── Category Tile Widget ─────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final String name;
  final String emoji;
  final int shopCount;
  final bool isActive;
  final bool isBuiltIn;
  final bool isSuperAdmin;
  final bool isLoadingCounts;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  const _CategoryTile({
    required this.name,
    required this.emoji,
    required this.shopCount,
    required this.isActive,
    required this.isBuiltIn,
    required this.isSuperAdmin,
    required this.isLoadingCounts,
    required this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AdminColors.cardBorder
              : AdminColors.danger.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive
                ? AdminColors.primary.withValues(alpha: 0.15)
                : AdminColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Row(
          children: [
            Text(name, style: AdminStyles.body(size: 14)),
            const SizedBox(width: 8),
            if (!isBuiltIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Custom',
                    style: AdminStyles.caption(
                        color: AdminColors.primary, size: 10)),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            if (isLoadingCounts)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AdminColors.textMuted))
            else
              Text(
                '$shopCount active shop${shopCount == 1 ? "" : "s"}',
                style: AdminStyles.caption(
                  color: shopCount > 0
                      ? AdminColors.textMuted
                      : AdminColors.textMuted,
                ),
              ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? AdminColors.success.withValues(alpha: 0.2)
                    : AdminColors.danger.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isActive ? 'Active' : 'Disabled',
                style: AdminStyles.caption(
                  color: isActive ? AdminColors.success : AdminColors.danger,
                  size: 10,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null && isSuperAdmin)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AdminColors.danger, size: 20),
                onPressed: onDelete,
                tooltip: 'Delete custom category',
              ),
            if (isSuperAdmin)
              Switch(
                value: isActive,
                activeThumbColor: AdminColors.success,
                inactiveTrackColor: AdminColors.danger.withValues(alpha: 0.4),
                onChanged: (_) => onToggle(),
              ),
          ],
        ),
      ),
    );
  }
}
