import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';
import '../../utils/image_picker_utils.dart';
import '../../services/image_compression_service.dart';

class SellerKycUploadPage extends StatefulWidget {
  const SellerKycUploadPage({super.key});

  @override
  State<SellerKycUploadPage> createState() => _SellerKycUploadPageState();
}

class _SellerKycUploadPageState extends State<SellerKycUploadPage> {
  SupabaseClient get _db => Supabase.instance.client;
  bool _loading = false;

  final _aadharCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _tradeLicenseCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  File? _aadharFront;
  File? _aadharBack;
  File? _panFront;
  File? _panBack;
  File? _shopProof1;
  File? _shopProof2;
  File? _bankProof;

  @override
  void dispose() {
    _aadharCtrl.dispose();
    _panCtrl.dispose();
    _gstCtrl.dispose();
    _tradeLicenseCtrl.dispose();
    _accountHolderCtrl.dispose();
    _bankAccountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(Function(File) onPicked) async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => onPicked(File(pickedFile.path)));
    }
  }

  Future<String?> _uploadFile(File file, String path) async {
    try {
      final bytes = await ImageCompressionService.compressFile(file) ?? await file.readAsBytes();
      const ext = 'jpg';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$path.$ext';
      await _db.storage.from('seller_kyc_docs').uploadBinary(fileName, bytes);
      return _db.storage.from('seller_kyc_docs').getPublicUrl(fileName);
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
    if (_aadharCtrl.text.isEmpty ||
        _panCtrl.text.isEmpty ||
        _accountHolderCtrl.text.isEmpty ||
        _bankAccountCtrl.text.isEmpty ||
        _ifscCtrl.text.isEmpty) {
      _showSnack('Please fill all mandatory text fields', isError: true);
      return;
    }
    if (_aadharFront == null || _aadharBack == null) {
      _showSnack('Aadhaar Front and Back images are required', isError: true);
      return;
    }
    if (_panFront == null || _panBack == null) {
      _showSnack('PAN Front and Back images are required', isError: true);
      return;
    }
    if (_shopProof1 == null) {
      _showSnack('At least one Shop Proof image is required', isError: true);
      return;
    }
    if (_bankProof == null) {
      _showSnack(
          'Bank Account Verification image (Cancelled Cheque/Passbook) is required',
          isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      final userId = context.read<AuthProvider>().currentUserId;
      if (userId == null) throw Exception('User not logged in');

      // Upload Images
      final aadharFrontUrl =
          await _uploadFile(_aadharFront!, '${userId}_aadhar_front');
      final aadharBackUrl =
          await _uploadFile(_aadharBack!, '${userId}_aadhar_back');
      final panFrontUrl = await _uploadFile(_panFront!, '${userId}_pan_front');
      final panBackUrl = await _uploadFile(_panBack!, '${userId}_pan_back');
      final shopProof1Url = await _uploadFile(_shopProof1!, '${userId}_shop_1');
      final shopProof2Url = _shopProof2 != null
          ? await _uploadFile(_shopProof2!, '${userId}_shop_2')
          : null;
      final bankProofUrl = await _uploadFile(_bankProof!, '${userId}_bank');

      final kycDocs = {
        'aadhar_front': aadharFrontUrl,
        'aadhar_back': aadharBackUrl,
        'pan_front': panFrontUrl,
        'pan_back': panBackUrl,
        'shop_proof_1': shopProof1Url,
        if (shopProof2Url != null) 'shop_proof_2': shopProof2Url,
        'bank_proof': bankProofUrl,
      };

      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final shopId = args?['shop_id'] as String?;
      if (shopId == null) throw Exception('Shop ID not provided. Please restart the app.');

      // Update Shops Table via RPC
      await _db.rpc('submit_seller_kyc_v2', params: {
        'p_shop_id': shopId,
        'p_aadhar_number': _aadharCtrl.text.trim(),
        'p_pan_number': _panCtrl.text.trim(),
        'p_gst_number': _gstCtrl.text.trim(),
        'p_trade_license': _tradeLicenseCtrl.text.trim(),
        'p_bank_account_holder': _accountHolderCtrl.text.trim(),
        'p_bank_account_number': _bankAccountCtrl.text.trim(),
        'p_bank_ifsc': _ifscCtrl.text.trim(),
        'p_kyc_documents': kycDocs,
      });

      if (mounted) {
        final notifProvider = context.read<NotificationProvider>();
        final adminRows = await _db.from('admin_users').select('id').eq('is_active', true);
        for (final admin in (adminRows as List)) {
          notifProvider.sendBackgroundPush(
            targetUserId: admin['id'] as String,
            title: '🏪 New Shop KYC!',
            body: 'A seller has submitted their KYC documents for review.',
          );
        }

        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerPendingVerification, (_) => false);
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
        title: Text('KYC Verification',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white)),
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Final Step: Legal & KYC',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Please provide your tax details and upload verification documents. Clear images speed up the approval process.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 32),
            const _SectionHeader(title: 'Tax & Identity Details'),
            _DarkField(
                label: 'Aadhaar Number *',
                controller: _aadharCtrl,
                number: true),
            const SizedBox(height: 16),
            _DarkField(label: 'PAN Number *', controller: _panCtrl, caps: true),
            const SizedBox(height: 16),
            _DarkField(
                label: 'GSTIN (Optional depending on category)',
                controller: _gstCtrl,
                caps: true),
            const SizedBox(height: 16),
            _DarkField(
                label: 'Trade License Number (Optional)',
                controller: _tradeLicenseCtrl),
            const SizedBox(height: 32),
            const _SectionHeader(title: 'Bank Account Details'),
            _DarkField(
                label: 'Account Holder Name *', controller: _accountHolderCtrl),
            const SizedBox(height: 16),
            _DarkField(
                label: 'Account Number *',
                controller: _bankAccountCtrl,
                number: true),
            const SizedBox(height: 16),
            _DarkField(label: 'IFSC Code *', controller: _ifscCtrl, caps: true),
            const SizedBox(height: 32),
            const _SectionHeader(title: 'Document Uploads'),
            _UploadRow(
              title: 'Aadhaar Card (Front & Back) *',
              file1: _aadharFront,
              file2: _aadharBack,
              label1: 'Front',
              label2: 'Back',
              onPick1: () => _pickImage((f) => _aadharFront = f),
              onPick2: () => _pickImage((f) => _aadharBack = f),
            ),
            const SizedBox(height: 24),
            _UploadRow(
              title: 'PAN Card (Front & Back) *',
              file1: _panFront,
              file2: _panBack,
              label1: 'Front',
              label2: 'Back',
              onPick1: () => _pickImage((f) => _panFront = f),
              onPick2: () => _pickImage((f) => _panBack = f),
            ),
            const SizedBox(height: 24),
            _UploadRow(
              title: 'Shop Proof (Electricity Bill / Rent Agreement) *',
              file1: _shopProof1,
              file2: _shopProof2,
              label1: 'Page 1',
              label2: 'Page 2 (Opt)',
              onPick1: () => _pickImage((f) => _shopProof1 = f),
              onPick2: () => _pickImage((f) => _shopProof2 = f),
            ),
            const SizedBox(height: 24),
            _UploadRow(
              title: 'Bank Proof (Cancelled Cheque / Passbook) *',
              file1: _bankProof,
              file2: null,
              label1: 'Upload Image',
              label2: '',
              onPick1: () => _pickImage((f) => _bankProof = f),
              onPick2: () {},
              single: true,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF4C542),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : Text('Submit Application',
                        style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
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
                        color: Color(0xFFF4C542),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
              child:
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.08))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(title,
                style: GoogleFonts.outfit(
                    color: const Color(0xFFF4C542),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
              child:
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.08))),
        ],
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool number;
  final bool caps;

  const _DarkField(
      {required this.label,
      required this.controller,
      this.number = false,
      this.caps = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          maxLength: 200,
          buildCounter: (BuildContext context, { int? currentLength, int? maxLength, bool? isFocused }) => null,
          textCapitalization:
              caps ? TextCapitalization.characters : TextCapitalization.none,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _UploadRow extends StatelessWidget {
  final String title;
  final File? file1;
  final File? file2;
  final String label1;
  final String label2;
  final VoidCallback onPick1;
  final VoidCallback onPick2;
  final bool single;

  const _UploadRow(
      {required this.title,
      required this.file1,
      required this.file2,
      required this.label1,
      required this.label2,
      required this.onPick1,
      required this.onPick2,
      this.single = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _UploadBox(file: file1, label: label1, onTap: onPick1)),
            if (!single) const SizedBox(width: 16),
            if (!single)
              Expanded(
                  child:
                      _UploadBox(file: file2, label: label2, onTap: onPick2)),
          ],
        ),
      ],
    );
  }
}

class _UploadBox extends StatelessWidget {
  final File? file;
  final String label;
  final VoidCallback onTap;
  const _UploadBox(
      {required this.file, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(
              color:
                  file != null ? Colors.green : Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(12),
          image: file != null
              ? DecorationImage(
                  image: FileImage(file!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.4), BlendMode.darken))
              : null,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  file != null
                      ? Icons.check_circle_rounded
                      : Icons.add_photo_alternate_rounded,
                  color: file != null ? Colors.green : Colors.white54,
                  size: 28),
              const SizedBox(height: 8),
              Text(file != null ? 'Uploaded' : '$label\n(Clear & readable)',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      color: file != null ? Colors.green : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
