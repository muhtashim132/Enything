import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../models/rbac/role_model.dart';
import '../../../widgets/rbac/rbac_widgets.dart';
import '../../../repositories/roles_repository.dart';
import 'role_editor_page.dart';

class RolesListPage extends StatefulWidget {
  const RolesListPage({super.key});

  @override
  State<RolesListPage> createState() => _RolesListPageState();
}

class _RolesListPageState extends State<RolesListPage> {
  final _searchCtrl = TextEditingController();
  List<RoleModel> _filtered = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRoles();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    setState(() => _loading = true);
    await context.read<RbacProvider>().reloadRoles();
    _applySearch();
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch() => setState(_applySearch);

  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase();
    final all = context.read<RbacProvider>().allRoles;
    _filtered = q.isEmpty
        ? all
        : all
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                r.description.toLowerCase().contains(q))
            .toList();
  }

  Future<void> _deleteRole(RoleModel role) async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Delete Role',
      message: 'Delete "${role.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: const Color(0xFFFF5722),
    );
    if (!confirmed) return;
    try {
      await RolesRepository().deleteRole(role.id);
      await _loadRoles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF4CAF50),
            content: Text('Role deleted',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF5722),
            content: Text('Error: $e',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _cloneRole(RoleModel role) async {
    try {
      await RolesRepository().cloneRole(role.id, 'Copy of ${role.name}');
      await _loadRoles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF8B2FC9),
            content: Text('Role cloned',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF5722),
            content: Text('Error: $e',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    final isSuperAdmin = rbac.isSuperAdmin;

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Roles & Permissions',
            style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RoleEditorPage(),
                    ),
                  );
                  _loadRoles();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B2FC9),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_rounded,
                    size: 16, color: Colors.white),
                label: Text('New Role',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search roles...',
                hintStyle:
                    GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Colors.white30, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: Colors.white30, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        })
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B2FC9)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${_filtered.length} roles',
                  style:
                      GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  '${_filtered.where((r) => r.isSystem).length} system · '
                  '${_filtered.where((r) => !r.isSystem).length} custom',
                  style:
                      GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? _buildSkeletons()
                : _filtered.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadRoles,
                        color: const Color(0xFF8B2FC9),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _RoleCard(
                            role: _filtered[i],
                            isSuperAdmin: isSuperAdmin,
                            onEdit: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RoleEditorPage(role: _filtered[i]),
                                ),
                              );
                              _loadRoles();
                            },
                            onClone: () => _cloneRole(_filtered[i]),
                            onDelete: () => _deleteRole(_filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletons() => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 14),
              SizedBox(height: 8),
              SkeletonBox(height: 11),
              SizedBox(height: 10),
              Row(children: [
                SkeletonBox(width: 60, height: 22, radius: 12),
                SizedBox(width: 8),
                SkeletonBox(width: 80, height: 22, radius: 12),
              ]),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white12, size: 56),
            const SizedBox(height: 16),
            Text('No roles found',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
}

class _RoleCard extends StatelessWidget {
  final RoleModel role;
  final bool isSuperAdmin;
  final VoidCallback onEdit;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  const _RoleCard({
    required this.role,
    required this.isSuperAdmin,
    required this.onEdit,
    required this.onClone,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: role.badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.shield_rounded,
                      color: role.badgeColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (role.description.isNotEmpty)
                        Text(
                          role.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                if (isSuperAdmin)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Colors.white38, size: 18),
                    color: const Color(0xFF1A1030),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) {
                      HapticFeedback.lightImpact();
                      if (v == 'edit') onEdit();
                      if (v == 'clone') onClone();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      if (!role.isSystem)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_rounded,
                                color: Colors.white54, size: 16),
                            const SizedBox(width: 10),
                            Text('Edit',
                                style:
                                    GoogleFonts.outfit(color: Colors.white70)),
                          ]),
                        ),
                      PopupMenuItem(
                        value: 'clone',
                        child: Row(children: [
                          const Icon(Icons.copy_rounded,
                              color: Colors.white54, size: 16),
                          const SizedBox(width: 10),
                          Text('Duplicate',
                              style: GoogleFonts.outfit(color: Colors.white70)),
                        ]),
                      ),
                      if (!role.isSystem)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_rounded,
                                color: Color(0xFFFF5722), size: 16),
                            const SizedBox(width: 10),
                            Text('Delete',
                                style: GoogleFonts.outfit(
                                    color: const Color(0xFFFF5722))),
                          ]),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                RoleBadge(
                  name: role.isSystem ? 'SYSTEM' : 'CUSTOM',
                  color: role.isSystem
                      ? const Color(0xFF2196F3)
                      : const Color(0xFF9C27B0),
                  isSystem: role.isSystem,
                  small: true,
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${role.permissionCount} permissions',
                    style:
                        GoogleFonts.outfit(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
