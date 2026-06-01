import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';

class AcceptInvitePage extends StatefulWidget {
  const AcceptInvitePage({super.key});

  @override
  State<AcceptInvitePage> createState() => _AcceptInvitePageState();
}

class _AcceptInvitePageState extends State<AcceptInvitePage> {
  final _tokenCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _tokenValidated = false;
  Map<String, dynamic>? _inviteDetails;
  String? _error;

  Future<void> _validateToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final details = await context.read<AuthProvider>().fetchInviteDetails(token);
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (details != null) {
        _inviteDetails = details;
        _tokenValidated = true;
      } else {
        _error = context.read<AuthProvider>().error ?? 'Invalid or expired token.';
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final err = await context.read<AuthProvider>().acceptAdminInvite(
      token: _tokenCtrl.text.trim(),
      email: _inviteDetails!['email'] as String,
      password: _passCtrl.text,
      fullName: _nameCtrl.text.trim(),
    );

    if (!mounted) return;
    
    if (err == null) {
      // Success! Head to Admin Dashboard
      Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
    } else {
      setState(() {
        _isLoading = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0710),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B2FC9).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, size: 48, color: Color(0xFF8B2FC9)),
              ),
              const SizedBox(height: 24),
              Text(
                'Accept Invitation',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Join the admin team securely.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 40),

              if (!_tokenValidated) ...[
                _buildInputField(
                  controller: _tokenCtrl,
                  hint: 'Paste your Invite Code here',
                  icon: Icons.vpn_key_rounded,
                ),
                const SizedBox(height: 24),
                _buildButton(
                  label: 'Verify Code',
                  onPressed: _validateToken,
                ),
              ] else ...[
                // Success Badge
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50)),
                      const SizedBox(height: 8),
                      Text(
                        'Invited as ${_inviteDetails!['role_name']}',
                        style: GoogleFonts.outfit(color: const Color(0xFF4CAF50), fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _inviteDetails!['email'],
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildInputField(
                        controller: _nameCtrl,
                        hint: 'Full Name',
                        icon: Icons.person_rounded,
                        validator: (v) => v!.isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: _passCtrl,
                        hint: 'Secure Password',
                        icon: Icons.lock_rounded,
                        obscure: true,
                        validator: (v) => v!.length < 6 ? 'Min 6 characters' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildButton(
                  label: 'Complete Setup',
                  onPressed: _submit,
                ),
              ],
              
              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.outfit(color: const Color(0xFFFF5722), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: GoogleFonts.outfit(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF8B2FC9))),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFFF5722))),
      ),
    );
  }

  Widget _buildButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8B2FC9),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
