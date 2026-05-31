import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/routes.dart';

class DeliveryKycUploadPage extends StatefulWidget {
  const DeliveryKycUploadPage({super.key});

  @override
  State<DeliveryKycUploadPage> createState() => _DeliveryKycUploadPageState();
}

class _DeliveryKycUploadPageState extends State<DeliveryKycUploadPage> {
  final _db = Supabase.instance.client;
  bool _loading = false;

  final _aadharCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _dlCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  File? _aadharFront;
  File? _aadharBack;
  File? _panFront;
  File? _panBack;
  File? _dlFront;
  File? _dlBack;
  File? _rcFront;
  File? _rcBack;

  @override
  void dispose() {
    _aadharCtrl.dispose();
    _panCtrl.dispose();
    _dlCtrl.dispose();
    _accountHolderCtrl.dispose();
    _bankAccountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(Function(File) onPicked) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => onPicked(File(pickedFile.path)));
    }
  }

  Future<String?> _uploadFile(File file, String path) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$path.$ext';
      await _db.storage.from('delivery_kyc_docs').uploadBinary(fileName, bytes);
      return _db.storage.from('delivery_kyc_docs').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _submit() async {
    if (_aadharCtrl.text.isEmpty || _panCtrl.text.isEmpty || _dlCtrl.text.isEmpty || _accountHolderCtrl.text.isEmpty || _bankAccountCtrl.text.isEmpty || _ifscCtrl.text.isEmpty) {
      _showSnack('Please fill all mandatory text fields', isError: true);
      return;
    }
    if (_aadharFront == null || _aadharBack == null) {
      _showSnack('Both Aadhaar images are required', isError: true);
      return;
    }
    if (_panFront == null || _panBack == null) {
      _showSnack('Both PAN images are required', isError: true);
      return;
    }
    if (_dlFront == null || _dlBack == null) {
      _showSnack('Both Driving License images are required', isError: true);
      return;
    }
    if (_rcFront == null) {
      _showSnack('RC Front image is required', isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      // Upload Images
      final aadharFrontUrl = _aadharFront != null ? await _uploadFile(_aadharFront!, '${userId}_aadhar_front') : null;
      final aadharBackUrl = _aadharBack != null ? await _uploadFile(_aadharBack!, '${userId}_aadhar_back') : null;
      final panFrontUrl = _panFront != null ? await _uploadFile(_panFront!, '${userId}_pan_front') : null;
      final panBackUrl = _panBack != null ? await _uploadFile(_panBack!, '${userId}_pan_back') : null;
      final dlFrontUrl = _dlFront != null ? await _uploadFile(_dlFront!, '${userId}_dl_front') : null;
      final dlBackUrl = _dlBack != null ? await _uploadFile(_dlBack!, '${userId}_dl_back') : null;
      final rcFrontUrl = _rcFront != null ? await _uploadFile(_rcFront!, '${userId}_rc_front') : null;
      final rcBackUrl = _rcBack != null ? await _uploadFile(_rcBack!, '${userId}_rc_back') : null;

      final kycDocs = {
        if (aadharFrontUrl != null) 'aadhar_front': aadharFrontUrl,
        if (aadharBackUrl != null) 'aadhar_back': aadharBackUrl,
        if (panFrontUrl != null) 'pan_front': panFrontUrl,
        if (panBackUrl != null) 'pan_back': panBackUrl,
        if (dlFrontUrl != null) 'dl_front': dlFrontUrl,
        if (dlBackUrl != null) 'dl_back': dlBackUrl,
        if (rcFrontUrl != null) 'rc_front': rcFrontUrl,
        if (rcBackUrl != null) 'rc_back': rcBackUrl,
      };

      // Update Delivery Partners Table
      await _db.from('delivery_partners').update({
        'aadhar_number': _aadharCtrl.text.trim(),
        'pan_number': _panCtrl.text.trim(),
        'driving_license': _dlCtrl.text.trim(),
        'bank_account_holder': _accountHolderCtrl.text.trim(),
        'bank_account_number': _bankAccountCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim(),
        'kyc_documents': kycDocs,
        'verification_status': 'pending',
      }).eq('id', userId);

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.deliveryPendingVerification, (_) => false);
      }
    } catch (e) {
      _showSnack('Submission failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      appBar: AppBar(
        title: Text('KYC Verification', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF51CF66).withValues(alpha: 0.2), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF51CF66).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security_rounded, color: Color(0xFF51CF66), size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Secure Upload', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Your documents are encrypted and reviewed securely.', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('Contact Details'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                _db.auth.currentUser?.phone ?? 'Phone number not available',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 6),
            Text('This phone number is linked to your delivery partner profile.',
                style: GoogleFonts.outfit(color: Colors.white30, fontSize: 11)),
            const SizedBox(height: 32),
            const SizedBox(height: 32),

            _buildSectionTitle('Identity Details'),
            _buildInputField('Aadhaar Number *', _aadharCtrl, isNumber: true, hint: '12-digit Aadhaar Number'),
            _buildInputField('PAN Number *', _panCtrl, isCaps: true, hint: 'ABCDE1234F'),
            _buildInputField('Driving License Number *', _dlCtrl, isCaps: true, hint: 'DL-1420110012345'),
            const SizedBox(height: 32),

            _buildSectionTitle('Bank Account Details'),
            _buildInputField('Account Holder Name *', _accountHolderCtrl, hint: 'Name exactly as per bank'),
            _buildInputField('Account Number *', _bankAccountCtrl, isNumber: true, hint: 'Your bank account number'),
            _buildInputField('IFSC Code *', _ifscCtrl, isCaps: true, hint: 'e.g., SBIN0001234'),
            const SizedBox(height: 32),

            _buildSectionTitle('Document Proofs'),
            _buildDocumentCard(
              title: 'Aadhaar Card *',
              subtitle: 'Front and Back images required',
              file1: _aadharFront,
              file2: _aadharBack,
              label1: 'Front',
              label2: 'Back',
              onPick1: () => _pickImage((f) => _aadharFront = f),
              onPick2: () => _pickImage((f) => _aadharBack = f),
            ),
            const SizedBox(height: 20),
            _buildDocumentCard(
              title: 'PAN Card *',
              subtitle: 'Front and Back images required',
              file1: _panFront,
              file2: _panBack,
              label1: 'Front',
              label2: 'Back',
              onPick1: () => _pickImage((f) => _panFront = f),
              onPick2: () => _pickImage((f) => _panBack = f),
            ),
            const SizedBox(height: 20),
            _buildDocumentCard(
              title: 'Driving License *',
              subtitle: 'Front and Back images required',
              file1: _dlFront,
              file2: _dlBack,
              label1: 'Front',
              label2: 'Back',
              onPick1: () => _pickImage((f) => _dlFront = f),
              onPick2: () => _pickImage((f) => _dlBack = f),
            ),
            const SizedBox(height: 20),
            _buildDocumentCard(
              title: 'Vehicle RC *',
              subtitle: 'Front required, Back optional',
              file1: _rcFront,
              file2: _rcBack,
              label1: 'Front',
              label2: 'Back (Opt)',
              onPick1: () => _pickImage((f) => _rcFront = f),
              onPick2: () => _pickImage((f) => _rcBack = f),
            ),
            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF51CF66),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : Text('Submit Application', style: GoogleFonts.outfit(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
          if (_loading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF51CF66),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Uploading Documents...\nPlease do not close the app',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF51CF66),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, {bool isNumber = false, bool isCaps = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 16),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF51CF66))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard({
    required String title,
    required String subtitle,
    required File? file1,
    required File? file2,
    required String label1,
    required String label2,
    required VoidCallback onPick1,
    required VoidCallback onPick2,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildUploadBox(file1, label1, onPick1)),
              const SizedBox(width: 16),
              Expanded(child: _buildUploadBox(file2, label2, onPick2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadBox(File? file, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: file != null ? Colors.transparent : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: file != null ? const Color(0xFF51CF66) : Colors.white.withValues(alpha: 0.1),
            style: file != null ? BorderStyle.solid : BorderStyle.none,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
          image: file != null ? DecorationImage(image: FileImage(file), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.4), BlendMode.darken)) : null,
        ),
        child: file != null
            ? const Center(child: Icon(Icons.check_circle_rounded, color: Color(0xFF51CF66), size: 36))
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_a_photo_rounded, color: Colors.white54, size: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(label + '\n(Clear & readable)', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
      ),
    );
  }
}
