import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../providers/rbac_provider.dart';
import '../../../models/rbac/role_model.dart';
import '../../../models/rbac/audit_log_model.dart';
import '../../../repositories/roles_repository.dart';
import '../../../widgets/rbac/rbac_widgets.dart';

class RoleEditorPage extends StatefulWidget {
  final RoleModel? role; // null = create new

  const RoleEditorPage({super.key, this.role});

  @override
  State<RoleEditorPage> createState() => _RoleEditorPageState();
}

class _RoleEditorPageState extends State<RoleEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Set<String> _selectedCodes = {};
  String _selectedColor = '#8B2FC9';
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.role != null;

  static const List<String> _colors = [
    '#8B2FC9', '#2196F3', '#4CAF50', '#FF9800',
    '#E91E63', '#00BCD4', '#FF5722', '#F4C542',
    '#9C27B0', '#607D8B',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.role!.name;
      _descCtrl.text = widget.role!.description;
      _selectedColor = widget.role!.color;
      _selectedCodes = widget.role!.permissions.map((p) => p.code).toSet();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });

    final repo = RolesRepository();
    final rbac = context.read<RbacProvider>();
    final actorId = rbac.currentAdmin?.id ?? '';
    final actorRole = rbac.currentAdmin?.role?.slug ?? 'super_admin';

    try {
      if (_isEditing) {
        await repo.updateRole(
          roleId: widget.role!.id,
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          color: _selectedColor,
          permissionCodes: _selectedCodes.toList(),
        );
        // Audit
        await repo.logAudit(AuditLogModel(
          id: '',
          actorId: actorId,
          actorRole: actorRole,
          action: 'role_updated',
          entityType: 'role',
          entityId: widget.role!.id,
          metadata: {'name': _nameCtrl.text.trim(), 'permission_count': _selectedCodes.length},
          createdAt: DateTime.now(),
        ));
      } else {
        final newRole = await repo.createRole(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          color: _selectedColor,
          permissionCodes: _selectedCodes.toList(),
        );
        await repo.logAudit(AuditLogModel(
          id: '',
          actorId: actorId,
          actorRole: actorRole,
          action: 'role_created',
          entityType: 'role',
          entityId: newRole.id,
          metadata: {'name': newRole.name},
          createdAt: DateTime.now(),
        ));
      }
      await rbac.reloadRoles();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    final permsByModule = rbac.permissionsByModule;
    final totalSelected = _selectedCodes.length;
    final totalPerms = rbac.allPermissions.length;
    final canEdit = !_isEditing || !(widget.role?.isSystem ?? false);

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Role' : 'New Role',
          style: GoogleFonts.outfit(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Color(0xFF8B2FC9), strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.outfit(
                            color: const Color(0xFF8B2FC9),
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Role Info Card ─────────────────────────────────────
            _section('Role Information', [
              _label('Role Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                enabled: canEdit,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: _inputDec('e.g. Content Moderator'),
                validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              _label('Description'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                enabled: canEdit,
                maxLines: 2,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: _inputDec('What can this role do?'),
              ),
              const SizedBox(height: 14),
              _label('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colors.map((c) {
                  final isSelected = c == _selectedColor;
                  Color color;
                  try {
                    color = Color(int.parse('FF${c.replaceAll('#', '')}', radix: 16));
                  } catch (_) {
                    color = const Color(0xFF8B2FC9);
                  }
                  return GestureDetector(
                    onTap: canEdit ? () => setState(() => _selectedColor = c) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ]),

            const SizedBox(height: 16),

            // ── Permission Summary ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF8B2FC9).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8B2FC9).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF8B2FC9), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    '$totalSelected of $totalPerms permissions selected',
                    style: GoogleFonts.outfit(
                        color: const Color(0xFF8B2FC9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (canEdit)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (_selectedCodes.length == totalPerms) {
                          _selectedCodes.clear();
                        } else {
                          _selectedCodes = rbac.allPermissions.map((p) => p.code).toSet();
                        }
                      }),
                      child: Text(
                        _selectedCodes.length == totalPerms ? 'Clear All' : 'Select All',
                        style: GoogleFonts.outfit(
                            color: const Color(0xFF8B2FC9),
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Permission Groups ───────────────────────────────────
            if (permsByModule.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF8B2FC9)),
                ),
              )
            else
              ...permsByModule.entries.map((entry) {
                final perms = entry.value.map((p) => {
                  'code': p.code,
                  'name': p.name,
                }).toList();
                return PermissionGroupCard(
                  module: entry.key,
                  permissions: perms,
                  selected: _selectedCodes,
                  enabled: canEdit,
                  onChanged: (updated) => setState(() => _selectedCodes = updated),
                );
              }),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5722).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF5722).withValues(alpha: 0.3)),
                ),
                child: Text(_error!,
                    style: GoogleFonts.outfit(
                        color: const Color(0xFFFF5722), fontSize: 12)),
              ),
            ],

            if (_isEditing && widget.role!.isSystem)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'System roles cannot be edited. Duplicate it to create a custom version.',
                        style: GoogleFonts.outfit(color: Colors.amber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _label(String text) => Text(text,
      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12));

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF8B2FC9)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF5722)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
