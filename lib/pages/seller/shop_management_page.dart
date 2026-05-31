import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../theme/app_colors.dart';

class ShopManagementPage extends StatefulWidget {
  const ShopManagementPage({super.key});

  @override
  State<ShopManagementPage> createState() => _ShopManagementPageState();
}

class _ShopManagementPageState extends State<ShopManagementPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;

  String? _shopId;
  bool _isActive = false;
  String? _currentAddress;

  final _bannerCtrl = TextEditingController();
  final _openTimeCtrl = TextEditingController();
  final _closeTimeCtrl = TextEditingController();

  File? _selectedImage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  @override
  void dispose() {
    _bannerCtrl.dispose();
    _openTimeCtrl.dispose();
    _closeTimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShop() async {
    final auth = context.read<AuthProvider>();
    try {
      final resp = await _supabase
          .from('shops')
          .select('id, is_active, banner_url, open_time, close_time, address')
          .eq('seller_id', auth.currentUserId ?? '')
          .maybeSingle();

      if (resp == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _shopId = resp['id'];
        _isActive = resp['is_active'] ?? false;
        _currentAddress = resp['address'];
        _bannerCtrl.text = resp['banner_url'] ?? '';
        _openTimeCtrl.text = resp['open_time'] ?? '09:00';
        _closeTimeCtrl.text = resp['close_time'] ?? '21:00';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleShopStatus(bool value) async {
    if (_shopId == null) return;
    setState(() => _isActive = value);
    try {
      await _supabase
          .from('shops')
          .update({'is_active': value}).eq('id', _shopId!);
      _showSnack(value ? '🟢 Shop is now Open' : '🔴 Shop is now Closed');
    } catch (e) {
      setState(() => _isActive = !value); // revert
      _showSnack('Failed to update shop status', isError: true);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null && mounted) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveDetails() async {
    if (_shopId == null) return;
    setState(() => _isSaving = true);
    try {
      String? uploadedUrl = _bannerCtrl.text.trim().isEmpty ? null : _bannerCtrl.text.trim();
      
      if (_selectedImage != null) {
        final fileExt = _selectedImage!.path.split('.').last;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final filePath = 'banners/$_shopId/$fileName';
        await _supabase.storage.from('shops').upload(filePath, _selectedImage!);
        uploadedUrl = _supabase.storage.from('shops').getPublicUrl(filePath);
        _bannerCtrl.text = uploadedUrl;
      }

      await _supabase.from('shops').update({
        'banner_url': uploadedUrl,
        'open_time': _openTimeCtrl.text.trim(),
        'close_time': _closeTimeCtrl.text.trim(),
      }).eq('id', _shopId!);
      _showSnack('✅ Shop details updated!');
    } catch (e) {
      _showSnack('Failed to save changes', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final parts = ctrl.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 9,
      minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      ctrl.text = '$h:$m';
    }
  }

  Future<void> _updateLocation(BuildContext context) async {
    if (_shopId == null) return;
    setState(() => _isSaving = true);
    try {
      final locProv = context.read<LocationProvider>();
      if (!locProv.hasLocation) {
        await locProv.requestLocation();
      }
      final currentLoc = locProv.currentLocation;
      if (currentLoc == null) {
        _showSnack('Could not fetch location', isError: true);
        return;
      }
      
      final point = 'POINT(${currentLoc.longitude} ${currentLoc.latitude})';
      final addr = await locProv.getAddressForLocation(currentLoc);
      
      await _supabase.from('shops').update({
        'location': point,
        'address': addr
      }).eq('id', _shopId!);
      
      if (mounted) {
        setState(() => _currentAddress = addr);
      }
      _showSnack('✅ Location updated to current position!');
    } catch (e) {
      _showSnack('Failed to update location: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A14) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: Text('Shop Management',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A1260),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopId == null
              ? Center(
                  child: Text('No shop found. Set up your shop first.',
                      style: GoogleFonts.outfit(
                          color: AppColors.textSecondary, fontSize: 15)),
                )
              : RefreshIndicator(
                  onRefresh: _loadShop,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Open / Closed Toggle ────────────────────────────
                        _sectionCard(
                          isDark: isDark,
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: (_isActive
                                          ? AppColors.success
                                          : AppColors.danger)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _isActive
                                      ? Icons.store_rounded
                                      : Icons.store_mall_directory_outlined,
                                  color: _isActive
                                      ? AppColors.success
                                      : AppColors.danger,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Shop Status',
                                        style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF0A0A14))),
                                    Text(
                                        _isActive
                                            ? 'Open — accepting orders'
                                            : 'Closed — not visible to customers',
                                        style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            color: _isActive
                                                ? AppColors.success
                                                : AppColors.danger)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isActive,
                                onChanged: _toggleShopStatus,
                                activeThumbColor: AppColors.success,
                                inactiveThumbColor: AppColors.danger,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Update Location ──────────────────────────────────────
                        _sectionCard(
                          isDark: isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Shop Location',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: isDark ? Colors.white : const Color(0xFF0A0A14))),
                              const SizedBox(height: 8),
                              if (_currentAddress != null && _currentAddress!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _currentAddress!,
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text('Update your shop location to your current GPS location so customers can find you within 9km.',
                                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _updateLocation(context),
                                icon: const Icon(Icons.my_location),
                                label: const Text('Update to Current GPS'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                  foregroundColor: AppColors.primary,
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Banner Image Upload ────────────────────────────────────
                        _sectionCard(
                          isDark: isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Banner Image', isDark),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  width: double.infinity,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1.5),
                                  ),
                                  child: _selectedImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(15),
                                          child: Image.file(_selectedImage!, fit: BoxFit.cover),
                                        )
                                      : _bannerCtrl.text.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(15),
                                              child: Image.network(_bannerCtrl.text, fit: BoxFit.cover),
                                            )
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.primary),
                                                const SizedBox(height: 8),
                                                Text('Tap to upload banner\nRecommended size: 16:9 or 2:1', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Opening Hours ───────────────────────────────────
                        _sectionCard(
                          isDark: isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Opening Hours',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0A0A14))),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _label('Opens at', isDark),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () => _pickTime(_openTimeCtrl),
                                          child: AbsorbPointer(
                                            child: _inputField(
                                              controller: _openTimeCtrl,
                                              hint: '09:00',
                                              icon: Icons.access_time_rounded,
                                              isDark: isDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _label('Closes at', isDark),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () =>
                                              _pickTime(_closeTimeCtrl),
                                          child: AbsorbPointer(
                                            child: _inputField(
                                              controller: _closeTimeCtrl,
                                              hint: '21:00',
                                              icon: Icons.access_time_outlined,
                                              isDark: isDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Save Button ─────────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveDetails,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0A1260),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text('Save Changes',
                                    style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _sectionCard({required Widget child, required bool isDark}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141425) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  Widget _label(String text, bool isDark) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      style: GoogleFonts.outfit(
          fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0A0A14)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
        filled: true,
        fillColor:
            isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
