import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';
import '../../config/app_categories.dart';
import '../../utils/image_picker_utils.dart';
import '../../services/image_compression_service.dart';
import '../../services/kyc_draft_service.dart';

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
  final _enrolmentIdCtrl = TextEditingController();
  final _tradeLicenseCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  String? _shopId;
  String? _shopCategory;
  String? _shopName;
  bool _argsRead = false;
  bool _loadingCategory = true;
  bool _isGstRegistered = true; // Non-food: true = has GSTIN, false = exempt <40L
  bool _exemptionDeclared = false;

  File? _aadharFront;
  File? _aadharBack;
  File? _panFront;
  File? _panBack;
  File? _shopProof1;
  File? _shopProof2;
  File? _bankProof;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsRead) {
      _argsRead = true;
      _initCategory();
    }
  }

  Future<void> _initCategory() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final catArg = args?['category'] as String?;
    _shopId = args?['shop_id'] as String?;

    if (catArg != null && catArg.isNotEmpty) {
      _shopCategory = catArg;
      _loadingCategory = false;
    }

    final userId =
        context.read<AuthProvider>().currentUserId ?? _db.auth.currentUser?.id;

    try {
      // Self-healing fallback: If shop_id is not in route arguments, query DB by seller_id!
      if ((_shopId == null || _shopId!.isEmpty) && userId != null) {
        final res = await _db
            .from('shops')
            .select('id, category, name, shop_type')
            .eq('seller_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null && mounted) {
          final rawCat = (res['category'] as String?)?.isNotEmpty == true
              ? res['category'] as String
              : (res['shop_type'] as String?);
          setState(() {
            _shopId ??= res['id'] as String?;
            _shopCategory ??= rawCat;
            _shopName ??= res['name'] as String?;
          });
        }
      } else if (_shopId != null && _shopId!.isNotEmpty) {
        final res = await _db
            .from('shops')
            .select('category, name, shop_type')
            .eq('id', _shopId!)
            .maybeSingle();
        if (res != null && mounted) {
          final rawCat = (res['category'] as String?)?.isNotEmpty == true
              ? res['category'] as String
              : (res['shop_type'] as String?);
          setState(() {
            _shopCategory ??= rawCat;
            _shopName ??= res['name'] as String?;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading seller shop: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingCategory = false);
      }
    }
  }

  bool get _isFoodCategory {
    if (_shopCategory == null) return false;
    final cat = _shopCategory!.trim().toLowerCase();
    if (cat == 'food' ||
        cat == 'restaurant' ||
        cat == 'fast food' ||
        cat == 'bakery' ||
        cat == 'sweets & mithai' ||
        cat == 'sweets and mithai' ||
        cat == 'tea & coffee' ||
        cat == 'ice cream' ||
        cat == 'paan shop' ||
        cat == 'cafe' ||
        cat == 'beverages') {
      return true;
    }
    return AppCategories.groupFor(_shopCategory!) == CategoryGroup.food;
  }

  @override
  void initState() {
    super.initState();
    _aadharCtrl.addListener(_saveDraft);
    _panCtrl.addListener(_saveDraft);
    _gstCtrl.addListener(_saveDraft);
    _enrolmentIdCtrl.addListener(_saveDraft);
    _tradeLicenseCtrl.addListener(_saveDraft);
    _accountHolderCtrl.addListener(_saveDraft);
    _bankAccountCtrl.addListener(_saveDraft);
    _ifscCtrl.addListener(_saveDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLostDataAndRestoreDraft();
    });
  }

  @override
  void dispose() {
    _aadharCtrl.removeListener(_saveDraft);
    _panCtrl.removeListener(_saveDraft);
    _gstCtrl.removeListener(_saveDraft);
    _enrolmentIdCtrl.removeListener(_saveDraft);
    _tradeLicenseCtrl.removeListener(_saveDraft);
    _accountHolderCtrl.removeListener(_saveDraft);
    _bankAccountCtrl.removeListener(_saveDraft);
    _ifscCtrl.removeListener(_saveDraft);
    _aadharCtrl.dispose();
    _panCtrl.dispose();
    _gstCtrl.dispose();
    _enrolmentIdCtrl.dispose();
    _tradeLicenseCtrl.dispose();
    _accountHolderCtrl.dispose();
    _bankAccountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  void _saveDraft() {
    final userId =
        context.read<AuthProvider>().currentUserId ?? _db.auth.currentUser?.id;
    if (userId == null) return;
    KycDraftService.saveSellerDraft(
      userId: userId,
      textFields: {
        'aadhar': _aadharCtrl.text,
        'pan': _panCtrl.text,
        'gst': _gstCtrl.text,
        'enrolmentId': _enrolmentIdCtrl.text,
        'tradeLicense': _tradeLicenseCtrl.text,
        'accountHolder': _accountHolderCtrl.text,
        'bankAccount': _bankAccountCtrl.text,
        'ifsc': _ifscCtrl.text,
      },
      filePaths: {
        'aadharFront': _aadharFront?.path,
        'aadharBack': _aadharBack?.path,
        'panFront': _panFront?.path,
        'panBack': _panBack?.path,
        'shopProof1': _shopProof1?.path,
        'shopProof2': _shopProof2?.path,
        'bankProof': _bankProof?.path,
      },
      isGstRegistered: _isGstRegistered,
      exemptionDeclared: _exemptionDeclared,
    );
  }

  Future<void> _checkLostDataAndRestoreDraft() async {
    final userId =
        context.read<AuthProvider>().currentUserId ?? _db.auth.currentUser?.id;
    if (userId == null) return;

    // 1. Restore saved form draft if available
    try {
      final draft = await KycDraftService.getSellerDraft(userId);
      if (draft != null && mounted) {
        final textFields =
            (draft['textFields'] as Map?)?.cast<String, String>() ?? {};
        final filePaths =
            (draft['filePaths'] as Map?)?.cast<String, String?>() ?? {};

        setState(() {
          if (_aadharCtrl.text.isEmpty && textFields['aadhar'] != null) {
            _aadharCtrl.text = textFields['aadhar']!;
          }
          if (_panCtrl.text.isEmpty && textFields['pan'] != null) {
            _panCtrl.text = textFields['pan']!;
          }
          if (_gstCtrl.text.isEmpty && textFields['gst'] != null) {
            _gstCtrl.text = textFields['gst']!;
          }
          if (_enrolmentIdCtrl.text.isEmpty &&
              textFields['enrolmentId'] != null) {
            _enrolmentIdCtrl.text = textFields['enrolmentId']!;
          }
          if (_tradeLicenseCtrl.text.isEmpty &&
              textFields['tradeLicense'] != null) {
            _tradeLicenseCtrl.text = textFields['tradeLicense']!;
          }
          if (_accountHolderCtrl.text.isEmpty &&
              textFields['accountHolder'] != null) {
            _accountHolderCtrl.text = textFields['accountHolder']!;
          }
          if (_bankAccountCtrl.text.isEmpty &&
              textFields['bankAccount'] != null) {
            _bankAccountCtrl.text = textFields['bankAccount']!;
          }
          if (_ifscCtrl.text.isEmpty && textFields['ifsc'] != null) {
            _ifscCtrl.text = textFields['ifsc']!;
          }
          if (draft['isGstRegistered'] != null) {
            _isGstRegistered = draft['isGstRegistered'] as bool;
          }
          if (draft['exemptionDeclared'] != null) {
            _exemptionDeclared = draft['exemptionDeclared'] as bool;
          }

          _aadharFront ??=
              KycDraftService.fileFromPath(filePaths['aadharFront']);
          _aadharBack ??=
              KycDraftService.fileFromPath(filePaths['aadharBack']);
          _panFront ??= KycDraftService.fileFromPath(filePaths['panFront']);
          _panBack ??= KycDraftService.fileFromPath(filePaths['panBack']);
          _shopProof1 ??=
              KycDraftService.fileFromPath(filePaths['shopProof1']);
          _shopProof2 ??=
              KycDraftService.fileFromPath(filePaths['shopProof2']);
          _bankProof ??= KycDraftService.fileFromPath(filePaths['bankProof']);
        });
      }
    } catch (e) {
      debugPrint('Error restoring seller KYC draft: $e');
    }

    // 2. Check if Android OS killed MainActivity during camera intent
    try {
      final picker = ImagePicker();
      final lostData = await picker.retrieveLostData();
      if (!lostData.isEmpty && lostData.file != null && mounted) {
        final pendingSlot = await KycDraftService.getPendingSlot('seller');
        final recoveredFile = File(lostData.file!.path);
        String restoredDocName = 'Document';

        setState(() {
          switch (pendingSlot) {
            case 'aadhar_front':
              _aadharFront = recoveredFile;
              restoredDocName = 'Aadhaar (Front)';
              break;
            case 'aadhar_back':
              _aadharBack = recoveredFile;
              restoredDocName = 'Aadhaar (Back)';
              break;
            case 'pan_front':
              _panFront = recoveredFile;
              restoredDocName = 'PAN Card (Front)';
              break;
            case 'pan_back':
              _panBack = recoveredFile;
              restoredDocName = 'PAN Card (Back)';
              break;
            case 'shop_proof_1':
              _shopProof1 = recoveredFile;
              restoredDocName = 'Shop Proof (Page 1)';
              break;
            case 'shop_proof_2':
              _shopProof2 = recoveredFile;
              restoredDocName = 'Shop Proof (Page 2)';
              break;
            case 'bank_proof':
              _bankProof = recoveredFile;
              restoredDocName = 'Bank Proof';
              break;
          }
        });

        await KycDraftService.clearPendingSlot('seller');
        _saveDraft();
        _showSnack('Restored your captured photo: $restoredDocName');
      }
    } catch (e) {
      debugPrint('Error retrieving lost image data: $e');
    }
  }

  Future<void> _pickImage(String slotKey, Function(File) onPicked) async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    await KycDraftService.setPendingSlot('seller', slotKey);
    final pickedFile = await pickSafeImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (pickedFile != null) {
      await KycDraftService.clearPendingSlot('seller');
      final file = File(pickedFile.path);
      setState(() => onPicked(file));
      _saveDraft();
    }
  }

  Future<String?> _uploadFile(File file, String path) async {
    try {
      final bytes = await ImageCompressionService.compressFile(file) ??
          await file.readAsBytes();
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
    if (_aadharCtrl.text.trim().isEmpty ||
        _panCtrl.text.trim().isEmpty ||
        _accountHolderCtrl.text.trim().isEmpty ||
        _bankAccountCtrl.text.trim().isEmpty ||
        _ifscCtrl.text.trim().isEmpty) {
      _showSnack('Please fill all mandatory text fields', isError: true);
      return;
    }

    // Validate PAN format (10 characters: 5 letters, 4 numbers, 1 letter)
    final pan = _panCtrl.text.trim().toUpperCase();
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    if (!panRegex.hasMatch(pan)) {
      _showSnack('Please enter a valid 10-character PAN (e.g. ABCDE1234F)',
          isError: true);
      return;
    }

    // Category-specific GST validation
    if (_isFoodCategory) {
      final gst = _gstCtrl.text.trim().toUpperCase();
      if (gst.isNotEmpty) {
        final gstRegex = RegExp(
            r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
        if (!gstRegex.hasMatch(gst)) {
          _showSnack('Invalid GSTIN format. Example: 07AAAAA0000A1Z5',
              isError: true);
          return;
        }
        final gstinPan = gst.substring(2, 12);
        if (gstinPan != pan) {
          _showSnack(
              'GSTIN PAN ($gstinPan) does not match your entered PAN ($pan)',
              isError: true);
          return;
        }
      }
    } else {
      if (_isGstRegistered) {
        final gst = _gstCtrl.text.trim().toUpperCase();
        if (gst.isEmpty) {
          _showSnack('GSTIN is required for registered non-food businesses',
              isError: true);
          return;
        }
        final gstRegex = RegExp(
            r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
        if (!gstRegex.hasMatch(gst)) {
          _showSnack(
              'Invalid 15-character GSTIN format (e.g. 07AAAAA0000A1Z5)',
              isError: true);
          return;
        }
        final gstinPan = gst.substring(2, 12);
        if (gstinPan != pan) {
          _showSnack(
              'The PAN embedded in GSTIN ($gstinPan) does not match your PAN ($pan)',
              isError: true);
          return;
        }
      } else {
        if (!_exemptionDeclared) {
          _showSnack(
              'Please confirm the statutory declaration for GST exemption under Notification 34/2023-CT',
              isError: true);
          return;
        }
        if (_enrolmentIdCtrl.text.trim().isNotEmpty) {
          final enr = _enrolmentIdCtrl.text.trim();
          if (enr.length < 8 || enr.length > 25) {
            _showSnack('Enrolment ID must be between 8 and 25 characters',
                isError: true);
            return;
          }
        }
      }
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

      // Cache route args before async gaps to avoid BuildContext-across-await lint
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      String? shopId = _shopId ?? (args?['shop_id'] as String?);

      // Autonomous DB recovery fallback if shop_id is missing from memory/arguments
      if (shopId == null || shopId.isEmpty) {
        final shopRes = await _db
            .from('shops')
            .select('id, category, name')
            .eq('seller_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (shopRes != null) {
          shopId = shopRes['id'] as String?;
          _shopId = shopId;
          _shopCategory ??= shopRes['category'] as String?;
          _shopName ??= shopRes['name'] as String?;
        }
      }

      if (shopId == null || shopId.isEmpty) {
        throw Exception(
            'No registered shop found for this seller account. Please register your shop first.');
      }

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

      final cleanGst = (_isFoodCategory || _isGstRegistered)
          ? _gstCtrl.text.trim().toUpperCase()
          : '';

      final kycDocs = {
        'aadhar_front': aadharFrontUrl,
        'aadhar_back': aadharBackUrl,
        'pan_front': panFrontUrl,
        'pan_back': panBackUrl,
        'shop_proof_1': shopProof1Url,
        if (shopProof2Url != null) 'shop_proof_2': shopProof2Url,
        'bank_proof': bankProofUrl,
        'gst_mode': _isFoodCategory
            ? 'food_optional'
            : (_isGstRegistered ? 'registered' : 'exempt_under_40l'),
        'is_gst_exempt': !_isFoodCategory && !_isGstRegistered,
        if (!_isFoodCategory &&
            !_isGstRegistered &&
            _enrolmentIdCtrl.text.trim().isNotEmpty)
          'enrolment_id': _enrolmentIdCtrl.text.trim().toUpperCase(),
        if (!_isFoodCategory && !_isGstRegistered)
          'exemption_declared': true,
        if (!_isFoodCategory && !_isGstRegistered)
          'exemption_declared_at': DateTime.now().toIso8601String(),
      };

      // Update Shops Table via RPC
      await _db.rpc('submit_seller_kyc_v2', params: {
        'p_shop_id': shopId,
        'p_aadhar_number': _aadharCtrl.text.trim().toUpperCase(),
        'p_pan_number': pan,
        'p_gst_number': cleanGst.isEmpty ? null : cleanGst,
        'p_trade_license': _tradeLicenseCtrl.text.trim(),
        'p_bank_account_holder': _accountHolderCtrl.text.trim(),
        'p_bank_account_number': _bankAccountCtrl.text.trim(),
        'p_bank_ifsc': _ifscCtrl.text.trim().toUpperCase(),
        'p_kyc_documents': kycDocs,
      });

      if (mounted) {
        final notifProvider = context.read<NotificationProvider>();
        final adminRows =
            await _db.from('admin_users').select('id').eq('is_active', true);
        for (final admin in (adminRows as List)) {
          notifProvider.sendBackgroundPush(
            targetUserId: admin['id'] as String,
            title: '🏪 New Shop KYC!',
            body: 'A seller has submitted their KYC documents for review.',
          );
        }

        // Purge local draft and pending slot on successful submission
        await KycDraftService.clearSellerDraft(userId);
        await KycDraftService.clearPendingSlot('seller');

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

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.roleSelect, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
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
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
            onPressed: _handleBack,
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
                    _shopName != null
                        ? 'Please provide tax details and verification documents for $_shopName. Clear images speed up the approval process.'
                        : 'Please provide your tax details and upload verification documents. Clear images speed up the approval process.',
                    style: GoogleFonts.outfit(
                        color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 32),
                const _SectionHeader(title: 'Tax & Identity Details'),
                _DarkField(
                    label: 'Aadhaar Number *',
                    controller: _aadharCtrl,
                    number: true),
                const SizedBox(height: 16),
                _DarkField(
                    label: 'PAN Number *', controller: _panCtrl, caps: true),
                const SizedBox(height: 16),
                _buildGstSection(),
                const SizedBox(height: 16),
                _DarkField(
                    label: 'Trade License Number (Optional)',
                    controller: _tradeLicenseCtrl),
                const SizedBox(height: 32),
                const _SectionHeader(title: 'Bank Account Details'),
                _DarkField(
                    label: 'Account Holder Name *',
                    controller: _accountHolderCtrl),
                const SizedBox(height: 16),
                _DarkField(
                    label: 'Account Number *',
                    controller: _bankAccountCtrl,
                    number: true),
                const SizedBox(height: 16),
                _DarkField(
                    label: 'IFSC Code *', controller: _ifscCtrl, caps: true),
                const SizedBox(height: 32),
                const _SectionHeader(title: 'Document Uploads'),
                _UploadRow(
                  title: 'Aadhaar Card (Front & Back) *',
                  file1: _aadharFront,
                  file2: _aadharBack,
                  label1: 'Front',
                  label2: 'Back',
                  onPick1: () => _pickImage('aadhar_front', (f) => _aadharFront = f),
                  onPick2: () => _pickImage('aadhar_back', (f) => _aadharBack = f),
                ),
                const SizedBox(height: 24),
                _UploadRow(
                  title: 'PAN Card (Front & Back) *',
                  file1: _panFront,
                  file2: _panBack,
                  label1: 'Front',
                  label2: 'Back',
                  onPick1: () => _pickImage('pan_front', (f) => _panFront = f),
                  onPick2: () => _pickImage('pan_back', (f) => _panBack = f),
                ),
                const SizedBox(height: 24),
                _UploadRow(
                  title: 'Shop Proof (Electricity Bill / Rent Agreement) *',
                  file1: _shopProof1,
                  file2: _shopProof2,
                  label1: 'Page 1',
                  label2: 'Page 2 (Opt)',
                  onPick1: () => _pickImage('shop_proof_1', (f) => _shopProof1 = f),
                  onPick2: () => _pickImage('shop_proof_2', (f) => _shopProof2 = f),
                ),
                const SizedBox(height: 24),
                _UploadRow(
                  title: 'Bank Proof (Cancelled Cheque / Passbook) *',
                  file1: _bankProof,
                  file2: null,
                  label1: 'Upload Image',
                  label2: '',
                  onPick1: () => _pickImage('bank_proof', (f) => _bankProof = f),
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
    ),
  );
}

  Widget _buildGstSection() {
    if (_loadingCategory && _shopCategory == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Color(0xFFF4C542),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_isFoodCategory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF4DABF7).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF4DABF7).withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.restaurant_rounded,
                    color: Color(0xFF4DABF7), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Food Category: Section 9(5) Deemed Platform',
                        style: GoogleFonts.outfit(
                            color: const Color(0xFF4DABF7),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'As a Food & Beverage partner, Enything collects and pays 5% GST directly to the government on your behalf under Section 9(5) of the CGST Act. Providing a GSTIN is optional.',
                        style: GoogleFonts.outfit(
                            color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DarkField(
            label: 'GSTIN (Optional for Food Outlets)',
            controller: _gstCtrl,
            caps: true,
          ),
        ],
      );
    }

    // Non-food category: Dual-Path compliance selector
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GST Registration Status *',
          style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSelectorTile(
                title: 'I have a GSTIN',
                subtitle: 'Registered Business',
                isSelected: _isGstRegistered,
                icon: Icons.verified_rounded,
                onTap: () => setState(() => _isGstRegistered = true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSelectorTile(
                title: 'Turnover < ₹40L',
                subtitle: 'Exempt (Notif 34/2023)',
                isSelected: !_isGstRegistered,
                icon: Icons.shield_outlined,
                onTap: () => setState(() => _isGstRegistered = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isGstRegistered) ...[
          _DarkField(
            label: 'GSTIN (Mandatory - 15 Characters) *',
            controller: _gstCtrl,
            caps: true,
          ),
          const SizedBox(height: 6),
          Text(
            '• Mandatory for registered non-food sellers under Section 52 (GSTR-8 TCS).\n• Characters 3-12 must match your PAN entered above.',
            style: GoogleFonts.outfit(
                color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4C542).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFF4C542).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFFF4C542), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'CBIC Notification No. 34/2023-Central Tax',
                      style: GoogleFonts.outfit(
                          color: const Color(0xFFF4C542),
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Small sellers with annual turnover up to ₹40 Lakhs are legally exempt from mandatory GST registration to sell goods online. Your PAN entered above will be used for Income Tax Section 194-O TDS compliance.',
                  style: GoogleFonts.outfit(
                      color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DarkField(
            label: 'GST Enrolment ID (Optional)',
            controller: _enrolmentIdCtrl,
            caps: true,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () =>
                setState(() => _exemptionDeclared = !_exemptionDeclared),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _exemptionDeclared
                    ? const Color(0xFF51CF66).withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _exemptionDeclared
                      ? const Color(0xFF51CF66).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _exemptionDeclared,
                    activeColor: const Color(0xFF51CF66),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    onChanged: (val) =>
                        setState(() => _exemptionDeclared = val ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'I declare that my aggregate annual turnover is under ₹40 Lakhs and I am exempt from mandatory GST registration under Notification 34/2023-CT. My PAN is genuine and valid for Income Tax Section 194-O TDS compliance. *',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectorTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF4C542).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF4C542)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? const Color(0xFFF4C542) : Colors.white38,
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Color(0xFFF4C542),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.outfit(
                color: isSelected ? const Color(0xFFF4C542) : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
              child: Container(
                  height: 1, color: Colors.white.withValues(alpha: 0.08))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(title,
                style: GoogleFonts.outfit(
                    color: const Color(0xFFF4C542),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
              child: Container(
                  height: 1, color: Colors.white.withValues(alpha: 0.08))),
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
          buildCounter: (BuildContext context,
                  {int? currentLength, int? maxLength, bool? isFocused}) =>
              null,
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
              color: file != null
                  ? Colors.green
                  : Colors.white.withValues(alpha: 0.15)),
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
