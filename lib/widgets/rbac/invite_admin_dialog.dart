import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _selectedTab = 0; // 0 = Phone (Recommended), 1 = Email

  // Form controllers
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  RoleModel? _selectedRole;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
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

    String? err;
    if (_selectedTab == 0) {
      // Add by Phone
      final cleanDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      final fullPhone = cleanDigits.startsWith('91') && cleanDigits.length == 12
          ? '+$cleanDigits'
          : '+91$cleanDigits';

      err = await team.addMemberByPhone(
        phone: fullPhone,
        fullName: _nameCtrl.text.trim(),
        roleId: _selectedRole!.id,
        adminPassword: _passwordCtrl.text.trim(),
        actorId: actorId,
        actorRole: actorRole,
      );
    } else {
      // Invite by Email
      err = await team.inviteMember(
        email: _emailCtrl.text.trim(),
        roleId: _selectedRole!.id,
        invitedBy: actorId,
        actorRole: actorRole,
      );
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });

    if (err == null) {
      Navigator.pop(context);
      final msg = _selectedTab == 0
          ? 'Staff member added! They can log in with their phone & password.'
          : 'Invitation sent to ${_emailCtrl.text.trim()}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF4CAF50),
          content: Text(
            msg,
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
                    Expanded(
                      child: Text(
                        'Add Team Member',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white38),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tab Selector (Phone vs Email)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedTab = 0;
                            _error = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0
                                  ? const Color(0xFF8B2FC9)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone_iphone_rounded,
                                  size: 15,
                                  color: _selectedTab == 0
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Phone (Direct)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: _selectedTab == 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedTab == 0
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedTab = 1;
                            _error = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1
                                  ? const Color(0xFF8B2FC9)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 15,
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Email Invite',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: _selectedTab == 1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedTab == 1
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (_selectedTab == 0) ...[
                  // Full Name
                  Text('Full Name',
                      style: GoogleFonts.outfit(
                          color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration:
                        _inputDecoration('e.g. John Doe', Icons.badge_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Phone Number
                  Text('Phone Number (10 digits)',
                      style: GoogleFonts.outfit(
                          color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration(
                      '9876543210',
                      Icons.phone_rounded,
                      prefixText: '+91 ',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      final digits = v.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 10) {
                        return 'Enter a valid 10-digit phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Admin Password
                  Text('Admin Password (min. 6 characters)',
                      style: GoogleFonts.outfit(
                          color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration(
                      'e.g. StaffPass@123',
                      Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  // Email
                  Text('Email Address',
                      style: GoogleFonts.outfit(
                          color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    maxLength: 100,
                    buildCounter: (BuildContext context,
                            {int? currentLength,
                            int? maxLength,
                            bool? isFocused}) =>
                        null,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration(
                        'e.g. john@company.com', Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                // Role
                Text('Assign Role',
                    style: GoogleFonts.outfit(
                        color: Colors.white60, fontSize: 12)),
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
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _parseColor(r.color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    r.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                        color: const Color(0xDEFFFFFF)),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedRole = v),
                  validator: (v) => v == null ? 'Please select a role' : null,
                ),

                // Helper tip for Phone mode
                if (_selectedTab == 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B2FC9).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF8B2FC9).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 15, color: Color(0xFF8B2FC9)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The member will log into the app using this phone number (OTP), then enter this admin password to access their assigned admin tools.',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.white70,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: GoogleFonts.outfit(
                          color: const Color(0xFFFF5722), fontSize: 12)),
                ],

                const SizedBox(height: 20),
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
                        : Text(
                            _selectedTab == 0
                                ? 'Add Staff Member'
                                : 'Send Invitation',
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

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF8B2FC9);
    }
  }

  InputDecoration _inputDecoration(String hint, IconData icon,
      {String? prefixText, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefixText,
      prefixStyle: GoogleFonts.outfit(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white24, size: 18),
      suffixIcon: suffixIcon,
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
