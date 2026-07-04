import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../models/saved_address_model.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../widgets/map_pin_picker_page.dart';
import '../../services/bell_alert_service.dart';
import '../../services/bell_settings_service.dart';

// Helper dialogs for Profile Settings Page

/// Legacy wrapper — now opens the new address picker sheet
void showSavedAddressesDialog(BuildContext context) {
  showAddressPickerSheet(context);
}

// ─── 2-step Add / Edit Address ─────────────────────────────────────────────
//
// Step 1 – MapPinPickerPage (full-screen map, pin at centre)
// Step 2 – _AddressDetailSheet (house/flat, landmark, pincode, label, save)

/// Opens the Swiggy/Zomato-style two-step address flow.
///
/// [existingAddress] → pass to edit an existing saved address.
void showAddEditAddressDialog(BuildContext context,
    {SavedAddress? existingAddress}) async {
  final auth = context.read<AuthProvider>();
  final locProv = context.read<LocationProvider>();
  final user = auth.user;
  if (user == null) return;

  // ── Step 1: Map Pin Picker ────────────────────────────────────────────────
  final seedLocation = existingAddress?.hasValidCoordinates == true
      ? existingAddress!.location
      : locProv.currentLocation;
  final seedAddress =
      existingAddress?.address ?? (locProv.rawAddress != 'Fetching address...' ? locProv.rawAddress : null);

  final result = await Navigator.push<MapPickResult?>(
    context,
    MaterialPageRoute(
      builder: (_) => MapPinPickerPage(
        initialLocation: seedLocation,
        initialAddress: seedAddress,
        initialHouseNumber: existingAddress?.flatNumber,
        initialLandmark: existingAddress?.landmark,
        title: existingAddress != null
            ? 'Move Pin to Edit Location'
            : 'Select Your Location',
        confirmLabel: 'Confirm Location',
        tooltip: 'Place the pin to your exact location',
      ),
    ),
  );

  if (result == null || !context.mounted) return;

  // ── Step 2: Address Detail Sheet ──────────────────────────────────────────
  _showAddressDetailSheet(
    context,
    user: user,
    locProv: locProv,
    pickedLocation: result.location,
    pickedAddress: result.address,
    houseFromMap: result.houseNumber,
    landmarkFromMap: result.landmark,
    existingAddress: existingAddress,
  );
}

void _showAddressDetailSheet(
  BuildContext context, {
  required dynamic user,
  required LocationProvider locProv,
  required dynamic pickedLocation,
  required String pickedAddress,
  /// House/Building name captured on the map page (takes priority over locProv)
  String houseFromMap = '',
  /// Landmark captured on the map page (takes priority over locProv)
  String landmarkFromMap = '',
  SavedAddress? existingAddress,
}) {
  String selectedLabel = existingAddress?.label ?? 'Home';

  // Priority: map-page input > existing saved address > locProv defaults
  final flatCtrl = TextEditingController(
      text: houseFromMap.isNotEmpty
          ? houseFromMap
          : (existingAddress?.flatNumber ?? locProv.houseNumber));
  final landmarkCtrl = TextEditingController(
      text: landmarkFromMap.isNotEmpty
          ? landmarkFromMap
          : (existingAddress?.landmark ?? locProv.landmark));
  final pincodeCtrl = TextEditingController(
      text: existingAddress?.pincode ?? locProv.pincode);
  final customLabelCtrl =
      TextEditingController(text: existingAddress?.customLabel ?? '');

  // Address text comes from the map — shown read-only
  final pickedAddressDisplay = pickedAddress;

  final labels = ['Home', 'Office', 'Hotel', 'Hospital', 'Other'];
  final labelIcons = {
    'Home': '🏠',
    'Office': '💼',
    'Hotel': '🏨',
    'Hospital': '🏥',
    'Other': '📍',
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Row(
                      children: [
                        Text(
                          existingAddress != null
                              ? 'Edit Address'
                              : 'Add Address Details',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close_rounded,
                              color:
                                  isDark ? Colors.white54 : Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // ── Picked address (read-only, from map) ────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_rounded,
                              color: Theme.of(context).primaryColor,
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pickedAddressDisplay,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 12,
                                        color: Colors.green.shade600),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Location pinned on map',
                                      style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: Colors.green.shade600,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Label selector ──────────────────────────────────
                    Text('Save as',
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: labels.map((label) {
                        final isSelected = selectedLabel == label;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => selectedLabel = label),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(labelIcons[label] ?? '📍',
                                    style:
                                        const TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // Custom label for "Other"
                    if (selectedLabel == 'Other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: customLabelCtrl,
                        decoration: InputDecoration(
                          labelText: 'Custom label name',
                          hintText: 'e.g. Gym, College, Friend\'s place',
                          labelStyle: GoogleFonts.outfit(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Flat / House number ─────────────────────────────
                    TextField(
                      controller: flatCtrl,
                      decoration: InputDecoration(
                        labelText: 'House No. / Building Name *',
                        hintText: 'e.g. A-404, Green Valley Apartments',
                        labelStyle: GoogleFonts.outfit(),
                        prefixIcon: const Icon(Icons.home_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Landmark ────────────────────────────────────────
                    TextField(
                      controller: landmarkCtrl,
                      decoration: InputDecoration(
                        labelText: 'Landmark *',
                        hintText: 'e.g. Near City Mall, Opp. Police Station',
                        labelStyle: GoogleFonts.outfit(),
                        prefixIcon: const Icon(Icons.flag_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Pincode ─────────────────────────────────────────
                    TextField(
                      controller: pincodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Pincode',
                        hintText: 'e.g. 400001',
                        labelStyle: GoogleFonts.outfit(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Save button ─────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final addr = SavedAddress(
                            id: existingAddress?.id ?? '',
                            userId: user.id,
                            label: selectedLabel,
                            customLabel: selectedLabel == 'Other'
                                ? customLabelCtrl.text.trim()
                                : null,
                            flatNumber: flatCtrl.text.trim(),
                            address: pickedAddressDisplay,
                            landmark: landmarkCtrl.text.trim(),
                            pincode: pincodeCtrl.text.trim(),
                            latitude: pickedLocation.latitude,
                            longitude: pickedLocation.longitude,
                            isDefault: locProv.savedAddresses.isEmpty,
                          );

                          String? error;
                          if (existingAddress != null) {
                            error =
                                await locProv.updateSavedAddress(addr);
                          } else {
                            error = await locProv.addSavedAddress(addr);
                          }

                          if (ctx.mounted) {
                            if (error != null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(error),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            } else {
                              locProv.setLocalAddressDetails(
                                house: flatCtrl.text.trim(),
                                mark: landmarkCtrl.text.trim(),
                                pin: pincodeCtrl.text.trim(),
                                addressText: pickedAddressDisplay,
                              );
                              final messenger = ScaffoldMessenger.of(ctx);
                              Navigator.pop(ctx);
                              
                              messenger.showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                                  backgroundColor: Colors.green.shade700,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.white),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          existingAddress != null 
                                            ? 'Address updated successfully!' 
                                            : 'Address saved successfully!',
                                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          backgroundColor:
                              Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          existingAddress != null
                              ? 'Update ${labelIcons[selectedLabel]} $selectedLabel'
                              : 'Save ${labelIcons[selectedLabel]} $selectedLabel',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

void showBusinessHoursDialog(BuildContext context) {
  final auth = context.read<AuthProvider>();
  if (auth.currentUserId == null) return;

  final openCtrl = TextEditingController(text: '09:00 AM');
  final closeCtrl = TextEditingController(text: '10:00 PM');

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text('Business Hours',
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(
              controller: openCtrl,
              decoration: const InputDecoration(
                  labelText: 'Opening Time', hintText: 'e.g. 09:00 AM')),
          const SizedBox(height: 16),
          TextField(
              controller: closeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Closing Time', hintText: 'e.g. 10:00 PM')),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              await Supabase.instance.client.from('shops').update({
                // BUG-17 FIX: Schema expects a single 'opening_hours' string
                'opening_hours':
                    '${openCtrl.text.trim()} - ${closeCtrl.text.trim()}'
              }).eq('seller_id', auth.currentUserId!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56)),
            child: const Text('Save Hours'),
          ),
        ],
        ),
      ),
    ),
  );
}

void showPayoutSettingsDialog(
    BuildContext context, String table, String idField) {
  final auth = context.read<AuthProvider>();
  if (auth.currentUserId == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return FutureBuilder(
          future: table == 'shops'
              ? Supabase.instance.client
                  .rpc('get_my_shop_kyc')
                  .maybeSingle()
              : Supabase.instance.client
                  .rpc('get_my_rider_kyc')
                  .maybeSingle(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()));
            }

            final data = snapshot.data ?? {};
            final holder = data['bank_account_holder'] ?? 'Not set';
            final acc = data['bank_account_number'] ?? 'Not set';
            final ifsc = data['bank_ifsc'] ?? 'Not set';

            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text('Bank Details (Payouts)',
                      style: GoogleFonts.outfit(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'These details were verified during signup and cannot be edited. Please contact support to change your payout settings.',
                            style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.blue.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                      controller: TextEditingController(text: holder),
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: 'Account Holder Name',
                          filled: true,
                          fillColor: Color(0xFFF5F5F5))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: TextEditingController(text: acc),
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: 'Account Number',
                          filled: true,
                          fillColor: Color(0xFFF5F5F5))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: TextEditingController(text: ifsc),
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: 'IFSC Code',
                          filled: true,
                          fillColor: Color(0xFFF5F5F5))),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87),
                    child: const Text('Close'),
                  ),
                ],
              ),
              ),
            );
          });
    },
  );
}

void showDocumentsDialog(BuildContext context) {
  final auth = context.read<AuthProvider>();
  if (auth.currentUserId == null) return;

  showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator()));

  Supabase.instance.client
      .from('delivery_partners')
      .select('aadhar_number, pan_number, driving_license')
      .eq('id', auth.currentUserId ?? '')
      .maybeSingle()
      .then((res) {
    if (context.mounted) Navigator.pop(context); // close loader
    if (res != null && context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KYC Documents',
                      style: GoogleFonts.outfit(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                _buildReadOnlyFieldDialog(
                    'Aadhaar Number',
                    res['aadhar_number'] ?? 'Not provided',
                    isDark),
                const SizedBox(height: 16),
                _buildReadOnlyFieldDialog(
                    'PAN Number',
                    res['pan_number'] ?? 'Not provided',
                    isDark),
                const SizedBox(height: 16),
                _buildReadOnlyFieldDialog(
                    'Driving License',
                    res['driving_license'] ?? 'Not provided',
                    isDark),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Close',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                ),
              ],
            ),
            ),
          );
        },
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Document details not found.')));
      }
    }
  }).catchError((_) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
          backgroundColor: Colors.redAccent.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Permission denied: Ask admin to grant SELECT on KYC columns.',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }
  });
}

Widget _buildReadOnlyFieldDialog(
    String label, String value, bool isDark) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      border:
          Border.all(color: isDark ? Colors.white12 : Colors.black12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.outfit(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

void showGenericInfoDialog(
    BuildContext context, String title, String content) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title:
          Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      content: Text(content),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'))
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification & Bell Settings Dialog
// Role-aware bottom sheet:
//   • All roles  : push notification toggles (notif_orders/promos/system)
//   •  + Sellers & Riders : Continuous Bell toggle + Change Bell Sound
//   •  + Customers        : Change Bell Sound only
// Uses DraggableScrollableSheet to prevent pixel overflow on small screens.
// ─────────────────────────────────────────────────────────────────────────────

void showNotificationSettingsDialog(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final userId = auth.currentUserId;
  if (userId == null) return;
  final role = auth.user?.activeSessionRole ?? 'customer';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        expand: false,
        builder: (_, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              child: _BellNotifSettingsSheet(
                userId: userId,
                role: role,
                scrollController: scrollController,
              ),
            ),
          );
        },
      );
    },
  );
}

// ─── Private StatefulWidget for the settings sheet ───────────────────────────

class _BellNotifSettingsSheet extends StatefulWidget {
  final String userId;
  final String role;
  final ScrollController scrollController;

  const _BellNotifSettingsSheet({
    required this.userId,
    required this.role,
    required this.scrollController,
  });

  @override
  State<_BellNotifSettingsSheet> createState() => _BellNotifSettingsSheetState();
}

class _BellNotifSettingsSheetState extends State<_BellNotifSettingsSheet> {
  bool _isLoading   = true;
  bool _orderUpdates = true;
  bool _promoOffers  = true;
  bool _sysAlerts    = true;
  bool _loopBellEnabled = true;
  String? _customBellPath;
  bool _isPickingFile = false;

  bool get _isSellerOrRider =>
      widget.role == 'seller' || widget.role == 'delivery_partner';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('notif_orders, notif_promos, notif_system')
          .eq('id', widget.userId)
          .maybeSingle();

      final loopEnabled =
          await BellSettingsService.instance.isLoopBellEnabled(widget.userId);
      final customPath =
          await BellSettingsService.instance.getCustomBellPath(widget.userId);

      if (mounted) {
        setState(() {
          if (res != null) {
            _orderUpdates = res['notif_orders'] as bool? ?? true;
            _promoOffers  = res['notif_promos'] as bool? ?? true;
            _sysAlerts    = res['notif_system'] as bool? ?? true;
          }
          _loopBellEnabled = loopEnabled;
          _customBellPath  = customPath;
          _isLoading       = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _audioPicker =
      MethodChannel('com.enything/audio_picker');

  Future<void> _pickBellSound() async {
    setState(() => _isPickingFile = true);
    try {
      // Invoke native audio picker (MainActivity MethodChannel)
      final uriString = await _audioPicker
          .invokeMethod<String?>('pickAudioFile');

      if (uriString != null && uriString.isNotEmpty && mounted) {
        await BellSettingsService.instance
            .setCustomBellPath(widget.userId, uriString);
        setState(() => _customBellPath = uriString);
      }
    } on PlatformException catch (e) {
      debugPrint('[BellSettings] pickBellSound PlatformException: $e');
    } catch (e) {
      debugPrint('[BellSettings] pickBellSound error: $e');
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  Future<void> _resetBellSound() async {
    await BellSettingsService.instance.setCustomBellPath(widget.userId, null);
    if (mounted) setState(() => _customBellPath = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      children: [
        // ── Drag handle ──────────────────────────────────────────────────────
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white30 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ───────────────────────────────────────────────────
              Text(
                'Notification & Bell Settings',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage push alerts and bell sound preferences.',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 24),

              if (_isLoading) ...[       
                const Center(
                  heightFactor: 3,
                  child: CircularProgressIndicator(),
                ),
              ] else ...[
                // ── Push Notifications section ───────────────────────────
                _sectionLabel('Push Notifications', isDark),
                const SizedBox(height: 4),
                _switchTile(
                  context: context,
                  title: 'Order Updates',
                  subtitle: 'Status changes, rider assignments, tracking',
                  value: _orderUpdates,
                  isDark: isDark,
                  onChanged: (val) async {
                    setState(() => _orderUpdates = val);
                    await Supabase.instance.client
                        .from('profiles')
                        .update({'notif_orders': val})
                        .eq('id', widget.userId);
                  },
                ),
                _switchTile(
                  context: context,
                  title: 'Promotions & Offers',
                  subtitle: 'Discounts, coupons, and marketing alerts',
                  value: _promoOffers,
                  isDark: isDark,
                  onChanged: (val) async {
                    setState(() => _promoOffers = val);
                    await Supabase.instance.client
                        .from('profiles')
                        .update({'notif_promos': val})
                        .eq('id', widget.userId);
                  },
                ),
                _switchTile(
                  context: context,
                  title: 'System Alerts',
                  subtitle: 'App updates, security notices, maintenance',
                  value: _sysAlerts,
                  isDark: isDark,
                  onChanged: (val) async {
                    setState(() => _sysAlerts = val);
                    await Supabase.instance.client
                        .from('profiles')
                        .update({'notif_system': val})
                        .eq('id', widget.userId);
                  },
                ),

                const SizedBox(height: 12),
                Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
                const SizedBox(height: 12),

                // ── Alert Bell section ───────────────────────────────────
                _sectionLabel('Alert Bell', isDark),
                const SizedBox(height: 8),

                if (_isSellerOrRider) ...[        
                  // Continuous bell toggle (sellers & riders only)
                  _switchTile(
                    context: context,
                    title: 'Continuous Alert Bell',
                    subtitle:
                        'Rings in a loop until you accept or cancel the order.\nTurn off for a single ring per notification.',
                    value: _loopBellEnabled,
                    isDark: isDark,
                    onChanged: (val) async {
                      setState(() => _loopBellEnabled = val);
                      await BellSettingsService.instance
                          .setLoopBellEnabled(widget.userId, enabled: val);
                      // Update mode on any currently playing bell immediately
                      await BellAlertService.instance.refreshMode();
                    },
                  ),
                  const SizedBox(height: 8),
                ],

                // Bell sound card (all roles)
                _bellSoundCard(context, isDark, primary),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text('Done', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  // ── Sub-widgets ─────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  Widget _switchTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(title,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87)),
      subtitle: Text(subtitle,
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade500)),
      value: value,
      activeThumbColor: Theme.of(context).primaryColor,
      activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.25),
      onChanged: onChanged,
    );
  }

  Widget _bellSoundCard(BuildContext context, bool isDark, Color primary) {
    // Derive a human-readable filename from both file paths and content:// URIs
    String soundName = 'Default (Enything Bell)';
    if (_customBellPath != null) {
      final raw = Uri.decodeFull(_customBellPath!).split('/').last;
      soundName = raw.contains(':') ? raw.split(':').last : raw;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252540) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.music_note_rounded, color: primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bell Sound',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87)),
                    Text(
                      soundName,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: Colors.grey.shade500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action row
          Row(
            children: [
              // Preview
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text('Preview', style: GoogleFonts.outfit(fontSize: 13)),
                  onPressed: () => BellAlertService.instance.previewBell(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Change
              Expanded(
                child: OutlinedButton.icon(
                  icon: _isPickingFile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text('Change', style: GoogleFonts.outfit(fontSize: 13)),
                  onPressed: _isPickingFile ? null : _pickBellSound,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              // Reset (only when custom sound is active)
              if (_customBellPath != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _resetBellSound,
                  icon: const Icon(Icons.replay_rounded),
                  tooltip: 'Reset to default',
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_isSellerOrRider) ...[
            const SizedBox(height: 6),
            Text(
              '\u24D8  This sound plays when a new order needs your attention.',
              style: GoogleFonts.outfit(
                  fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

