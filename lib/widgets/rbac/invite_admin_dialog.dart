import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/rbac_provider.dart';
import '../../providers/team_provider.dart';
import '../../models/rbac/role_model.dart';

class InviteAdminDialog extends StatefulWidget {
  const InviteAdminDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const InviteAdminDialog(),
    );
  }

  @override
  State<InviteAdminDialog> createState() => _InviteAdminDialogState();
}

class _InviteAdminDialogState extends State<InviteAdminDialog> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  RoleModel? _selectedRole;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedRole == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final rbac = context.read<RbacProvider>();
    final team = context.read<TeamProvider>();
    final actorId = rbac.currentAdmin?.id ?? '';
    final actorRole = rbac.currentAdmin?.role?.slug ?? 'super_admin';

    final err = await team.inviteMember(
      email: _emailCtrl.text.trim(),
      roleId: _selectedRole!.id,
      invitedBy: actorId,
      actorRole: actorRole,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
    if (err == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF4CAF50),
          content: Text(
            'Invitation sent to ${_emailCtrl.text.trim()}',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.watch<RbacProvider>().allRoles;

    return Dialog(
      backgroundColor: const Color(0xFF12091F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B2FC9).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add_rounded,
                          color: Color(0xFF8B2FC9), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Invite Team Member',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white38),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Email
                Text('Email Address',
                    style:
                        GoogleFonts.outfit(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: _inputDecoration(
                      'e.g. john@company.com', Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Role
                Text('Assign Role',
                    style:
                        GoogleFonts.outfit(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<RoleModel>(
                  isExpanded: true,
                  initialValue: _selectedRole,
                  dropdownColor: const Color(0xFF1A1030),
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: _inputDecoration(
                      'Select a role', Icons.admin_panel_settings_outlined),
                  items: roles
                      .where((r) => r.slug != 'super_admin')
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                    color: const Color(0xDEFFFFFF))),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedRole = v),
                  validator: (v) => v == null ? 'Please select a role' : null,
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: GoogleFonts.outfit(
                          color: const Color(0xFFFF5722), fontSize: 12)),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B2FC9),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text('Send Invitation',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white24, size: 18),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF8B2FC9)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFFF5722)),
      ),
    );
  }
}
