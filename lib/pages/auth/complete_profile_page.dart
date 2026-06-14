import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../config/routes.dart';
import '../../config/app_categories.dart';
import '../../config/tax_config.dart';
import '../../providers/platform_config_provider.dart';
import '../../widgets/seller/category_extra_fields.dart';
import '../../utils/responsive_layout.dart';

enum _Role { customer, seller, delivery }

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});
  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage>
    with SingleTickerProviderStateMixin {
  _Role _role = _Role.customer;
  final _nameCtrl = TextEditingController();
  // Customer
  final _addressCtrl = TextEditingController();
  // Seller
  final _shopNameCtrl = TextEditingController();
  String _shopCategory = AppCategories.names[0];
  CategoryGroup _shopGroup = AppCategories.groupFor(AppCategories.names[0]);
  final _shopAddressCtrl = TextEditingController();
  final _extraFieldsKey = GlobalKey<CategoryExtraFieldsState>();
  bool _fetchingLocation = false;
  // Delivery
  final _vehicleTypeCtrl = TextEditingController();
  final _vehicleRegCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  // Common
  final _pincodeCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  String? _phoneNumber;

  // Seller specific extra
  final _gstCtrl = TextEditingController();

  bool _loading = false;
  int _step = 0; // 0=role select, 1=details
  bool _showWelcome = false;
  bool _argsRead = false; // guard so didChangeDependencies only reads args once
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _phoneNumber = Supabase.instance.client.auth.currentUser?.phone ?? auth.pendingPhone ?? auth.user?.phone;
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 400), vsync: this)
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return; // only process once
    _argsRead = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) return;
    final roleArg = args['role'] as String?;
    if (roleArg != null) {
      switch (roleArg) {
        case 'customer':
          _role = _Role.customer;
          break;
        case 'seller':
          _role = _Role.seller;
          break;
        case 'delivery_partner':
          _role = _Role.delivery;
          break;
      }
      // Skip the role-picker step — role was already chosen on RoleSelectionPage
      _step = 1;

      // If the user already has a profile (adding a new role), pre-fill their name
      final auth = context.read<AuthProvider>();
      if (auth.user != null && auth.user!.fullName.isNotEmpty) {
        _nameCtrl.text = auth.user!.fullName;
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in [
      _nameCtrl,
      _addressCtrl,
      _shopNameCtrl,
      _shopAddressCtrl,
      _vehicleTypeCtrl,
      _vehicleRegCtrl,
      _insuranceCtrl,
      _pincodeCtrl,
      _landmarkCtrl,
      _gstCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _nextStep() {
    if (_step == 0) {
      _animCtrl.forward(from: 0);
      setState(() => _step = 1);
    }
  }

  /// Fetch current GPS location and reverse-geocode it into the target address field
  Future<void> _fetchLiveLocation(TextEditingController targetCtrl) async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _showSnack('Location permission denied. Enable it in settings.',
            isError: true);
        setState(() => _fetchingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final latLng = ll.LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        final locProv = context.read<LocationProvider>();
        locProv.setManualLocation(latLng, 'Fetching address...');
        final addr = await locProv.getAddressForLocation(latLng);
        locProv.setManualLocation(latLng, addr);
        if (mounted) {
          setState(() {
            targetCtrl.text = addr;
            _fetchingLocation = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Could not get location: $e', isError: true);
        setState(() => _fetchingLocation = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Please enter your full name', isError: true);
      return;
    }
    setState(() => _loading = true);

    Map<String, dynamic>? extra;
    String roleName;

    // Grab location if available (from tapping 📍 or auto-fetching)
    final locProv = context.read<LocationProvider>();
    String? locationPoint;
    if (locProv.currentLocation != null) {
      locationPoint =
          'POINT(${locProv.currentLocation!.longitude} ${locProv.currentLocation!.latitude})';
    } else {
      _showSnack('Please tap the 📍 icon in the address field to set your exact location', isError: true);
      setState(() => _loading = false);
      return;
    }

    switch (_role) {
      case _Role.customer:
        roleName = 'customer';
        extra = {
          'default_address': _addressCtrl.text.trim(),
          'pincode': _pincodeCtrl.text.trim(),
          'landmark': _landmarkCtrl.text.trim(),
          'location': locationPoint,
        };
        break;
      case _Role.seller:
        // Validate category-specific required fields
        final extraValidationError = _extraFieldsKey.currentState?.validate();
        if (extraValidationError != null) {
          _showSnack(extraValidationError, isError: true);
          setState(() => _loading = false);
          return;
        }
        final categoryExtra = _extraFieldsKey.currentState?.collectData() ?? {};
        // Note: Aadhaar, PAN, Bank Details are moved to SellerKycUploadPage
        roleName = 'seller';
        extra = {
          'name': _shopNameCtrl.text.trim().isEmpty
              ? '${_nameCtrl.text.trim()}\'s Shop'
              : _shopNameCtrl.text.trim(),
          'category': _shopCategory,
          'address': _shopAddressCtrl.text.trim(),
          'pincode': _pincodeCtrl.text.trim(),
          'landmark': _landmarkCtrl.text.trim(),
          'is_active': false,
          'verification_status': 'unverified',
          'gst_number': _gstCtrl.text.trim(),
          'location': locationPoint,
          // Merge the group-specific fields directly into the shops row.
          // Supabase ignores keys that don't exist as columns, so unknown
          // fields will be silently dropped unless you add a `metadata` JSONB
          // column — both approaches work.
          ...categoryExtra,
        };
        break;
      case _Role.delivery:
        if (_vehicleRegCtrl.text.trim().isEmpty) {
          _showSnack('Please fill vehicle registration', isError: true);
          setState(() => _loading = false);
          return;
        }

        roleName = 'delivery_partner';
        extra = {
          'vehicle_type': _vehicleTypeCtrl.text.trim(),
          'vehicle_reg_number': _vehicleRegCtrl.text.trim(), // RC
          'insurance_number': _insuranceCtrl.text.trim(),
          'pincode': _pincodeCtrl.text.trim(),
          'landmark': _landmarkCtrl.text.trim(),
          'location': locationPoint,
          'is_available': false,
          'verification_status': 'unverified',
        };
        break;
    }

    final err = await context.read<AuthProvider>().createProfile(
          fullName: _nameCtrl.text.trim(),
          role: roleName,
          additionalData: extra,
        );

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      _showSnack(err, isError: true);
      return;
    }

    // Show welcome splash briefly
    setState(() => _showWelcome = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    switch (_role) {
      case _Role.customer:
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.customerHome, (_) => false);
        break;
      case _Role.seller:
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerKycUpload, (_) => false);
        break;
      case _Role.delivery:
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.deliveryKycUpload, (_) => false);
        break;
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor:
          isError ? const Color(0xFFE03131) : const Color(0xFF2F9E44),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_showWelcome) return _buildWelcomeSplash();

    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      appBar: _step == 1
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 16),
                ),
                onPressed: () {
                  // If role came from RoleSelectionPage, go back to phone auth
                  // rather than showing the internal role-picker (which is skipped)
                  if (_argsRead &&
                      ModalRoute.of(context)?.settings.arguments != null) {
                    Navigator.pop(context);
                  } else {
                    _animCtrl.forward(from: 0);
                    setState(() => _step = 0);
                  }
                },
              ),
            )
          : null,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            Positioned(
                top: -60,
                left: -80,
                child: _blob(280, const Color(0xFF1A35C8), 0.16)),
            Positioned(
                bottom: -80,
                right: -60,
                child: _blob(300, const Color(0xFF5E20D4), 0.14)),
            SafeArea(
              child: MaxWidthContainer(
                child: _step == 0 ? _buildRoleSelect() : _buildDetailsForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Welcome Splash ────────────────────────────────────────────────────────
  Widget _buildWelcomeSplash() {
    final roleIcon = _role == _Role.seller
        ? '🏪'
        : _role == _Role.delivery
            ? '🏍️'
            : '🛍️';
    final roleName = _role == _Role.seller
        ? 'Seller'
        : _role == _Role.delivery
            ? 'Delivery Partner'
            : 'Customer';
    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      body: Stack(
        children: [
          Positioned(
              top: -60,
              left: -80,
              child: _blob(280, const Color(0xFF1A35C8), 0.20)),
          Positioned(
              bottom: -80,
              right: -60,
              child: _blob(300, const Color(0xFF5E20D4), 0.18)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(roleIcon, style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                Text('Welcome aboard!',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text('You\'re now registered as a',
                    style: GoogleFonts.outfit(
                        color: Colors.white54, fontSize: 15)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFF4A800)]),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(roleName,
                      style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 40),
                const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: Color(0xFFF4C542), strokeWidth: 2.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: Role Selection ────────────────────────────────────────────────
  Widget _buildRoleSelect() {
    final config = context.watch<PlatformConfigProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF4C542).withValues(alpha: 0.20),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset('logo/Enything_modern.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 20),
          Text("Choose how you want\nto use Enything",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('You can sign up for multiple roles anytime',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 36),
          _RoleCard(
            icon: '🛍️',
            title: 'Customer',
            subtitle: 'Shop from local stores and get fast delivery',
            selected: _role == _Role.customer,
            onTap: () => setState(() => _role = _Role.customer),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon: '🏪',
            title: 'Seller',
            subtitle: 'List your products — ${config.unifiedCommissionPercent.toStringAsFixed(0)}% commission on sales',
            selected: _role == _Role.seller,
            onTap: () => setState(() => _role = _Role.seller),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon: '🏍️',
            title: 'Delivery Partner',
            subtitle: 'Earn by delivering orders in your area',
            selected: _role == _Role.delivery,
            onTap: () => setState(() => _role = _Role.delivery),
          ),
          const SizedBox(height: 40),
          _GoldButton(label: 'Continue', onTap: _nextStep),
        ],
      ),
    );
  }

  // ── Step 1: Details Form ──────────────────────────────────────────────────
  Widget _buildDetailsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 110,
              height: 110,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF4C542).withValues(alpha: 0.20),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset('logo/Enything_modern.png', fit: BoxFit.cover),
              ),
            ),
          ),
          Text(_roleTitle,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Fill in your details to get started',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          _DarkField(
              label: 'Full Name *',
              controller: _nameCtrl,
              hint: 'Your full name'),
          const SizedBox(height: 16),
          _buildPhoneField(),
          const SizedBox(height: 16),
          ..._roleFields,
          const SizedBox(height: 32),
          _GoldButton(
              label: _loading ? '' : 'Create Account',
              loading: _loading,
              onTap: _submit),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String get _roleTitle {
    switch (_role) {
      case _Role.customer:
        return '🛍️ Customer Setup';
      case _Role.seller:
        return '🏪 Seller Setup';
      case _Role.delivery:
        return '🏍️ Delivery Partner';
    }
  }

  List<Widget> get _roleFields {
    switch (_role) {
      case _Role.customer:
        return [
          _buildAddressAndLocation('Default Delivery Address', _addressCtrl),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Landmark',
              controller: _landmarkCtrl,
              hint: 'e.g. Near City Mall'),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Pincode',
              controller: _pincodeCtrl,
              hint: 'e.g. 400001',
              number: true),
        ];
      case _Role.seller:
        return [
          // ── Shop Name ────────────────────────────────────────────────
          _DarkField(
              label: 'Shop Name *',
              controller: _shopNameCtrl,
              hint: 'e.g. Sharma General Store'),
          const SizedBox(height: 16),

          // ── Business Category — sourced from AppCategories ────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Business Category *',
                  style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _shopCategory,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0D1440),
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white54),
                    items: AppCategories.all
                        .map((cat) => DropdownMenuItem(
                              value: cat['name'],
                              child: Row(
                                children: [
                                  Text(cat['emoji']!,
                                      style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 10),
                                  Text(cat['name']!,
                                      style: GoogleFonts.outfit(
                                          color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _shopCategory = v;
                          _shopGroup = AppCategories.groupFor(v);
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Shop Address with live GPS ────────────────────────────────
          _buildAddressAndLocation('Shop Address *', _shopAddressCtrl),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Landmark',
              controller: _landmarkCtrl,
              hint: 'e.g. Near City Mall'),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Pincode *',
              controller: _pincodeCtrl,
              hint: 'e.g. 400001',
              number: true),
          const SizedBox(height: 24),

          // ── Dynamic category-specific fields ─────────────────────────
          // A section divider so the user knows these next fields are
          // specific to their chosen business category.
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${AppCategories.groupInfo(_shopGroup)["emoji"]} Business Details',
                  style:
                      GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                ),
              ),
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
            ],
          ),
          const SizedBox(height: 20),

          CategoryExtraFields(
            key: _extraFieldsKey,
            group: _shopGroup,
            category: _shopCategory,
          ),
          const SizedBox(height: 24),

          // ── KYC & Legal Details ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Tax Details',
                    style: GoogleFonts.outfit(
                        color: Colors.white38, fontSize: 12)),
              ),
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
            ],
          ),
          const SizedBox(height: 20),
          _DarkField(
              label: TaxConfig.isEnythingDeemedSupplier(_shopCategory)
                  ? 'GSTIN (Optional for Restaurants)'
                  : 'GSTIN Number (Optional)',
              controller: _gstCtrl,
              hint: '22AAAAA0000A1Z5',
              caps: true),
        ];
      case _Role.delivery:
        return [
          // ── Vehicle Details ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Vehicle Details',
                    style: GoogleFonts.outfit(
                        color: Colors.white38, fontSize: 12)),
              ),
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withValues(alpha: 0.08))),
            ],
          ),
          const SizedBox(height: 20),
          _DarkField(
              label: 'Vehicle Type *',
              controller: _vehicleTypeCtrl,
              hint: 'Bike / Scooter / Car'),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Vehicle Reg. Number (RC) *',
              controller: _vehicleRegCtrl,
              hint: 'MH02AB1234',
              caps: true),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Vehicle Insurance Number (Optional)',
              controller: _insuranceCtrl,
              hint: 'e.g. INS12345678',
              caps: true),
          const SizedBox(height: 16),
          _buildAddressAndLocation('Landmark (Home Base) *', _landmarkCtrl),
          const SizedBox(height: 16),
          _DarkField(
              label: 'Pincode (Operational Area) *',
              controller: _pincodeCtrl,
              hint: 'e.g. 400001',
              number: true),
          const SizedBox(height: 24),
        ];
    }
  }

  Widget _buildPhoneField() {
    final displayPhone = (_phoneNumber == null || _phoneNumber!.isEmpty) ? 'Not available' : _phoneNumber!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Phone Number',
            style: GoogleFonts.outfit(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Text(
            displayPhone,
            style: GoogleFonts.outfit(
                color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 6),
        Text('This number was used for verification and will be used for contact.',
            style: GoogleFonts.outfit(color: Colors.white30, fontSize: 11)),
      ],
    );
  }

  Widget _buildAddressAndLocation(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: TextField(
                  controller: ctrl,
                  maxLines: 2,
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Type address or tap 📍',
                    hintStyle: GoogleFonts.outfit(
                        color: Colors.white24, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _fetchingLocation ? null : () => _fetchLiveLocation(ctrl),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A35C8), Color(0xFF0A178C)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _fetchingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded,
                        color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Tap 📍 to auto-fill from your current GPS location',
            style:
                GoogleFonts.outfit(color: Colors.white30, fontSize: 11)),
      ],
    );
  }

  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  RadialGradient(colors: [color, color.withValues(alpha: 0)])),
        ),
      );
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final String icon, title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _RoleCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A35C8).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFF4C542)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: GoogleFonts.outfit(
                          color: Colors.white54, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            if (selected)
              Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                      color: Color(0xFFF4C542), shape: BoxShape.circle),
                  child:
                      const Icon(Icons.check, color: Colors.black, size: 14)),
          ],
        ),
      ),
    );
  }
}

/// Dark-themed text field (white text, semi-transparent dark fill)
class _DarkField extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final bool number, caps;
  const _DarkField(
      {required this.label,
      required this.controller,
      required this.hint,
      this.number = false,
      this.caps = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            textCapitalization:
                caps ? TextCapitalization.characters : TextCapitalization.words,
            // ← KEY FIX: explicit white text so it's visible on dark background
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              border: InputBorder.none,
              // Override any global fillColor from InputDecorationTheme
              filled: true,
              fillColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  const _GoldButton(
      {required this.label, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFF4A800)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFF4C542).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8))
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2.5))
              : Text(label,
                  style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
