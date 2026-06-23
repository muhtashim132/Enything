import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../models/saved_address_model.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../widgets/map_pin_picker_page.dart';

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
                              Navigator.pop(ctx);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Permission denied: Ask admin to grant SELECT on KYC columns.')));
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

void showNotificationSettingsDialog(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final userId = auth.currentUserId;
  if (userId == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      bool isLoading = true;
      bool orderUpdates = true;
      bool promoOffers = true;
      bool sysAlerts = true;

      return StatefulBuilder(builder: (context, setState) {
        if (isLoading) {
          Supabase.instance.client
              .from('profiles')
              .select('notif_orders, notif_promos, notif_system')
              .eq('id', userId)
              .maybeSingle()
              .then((res) {
            if (context.mounted) {
              setState(() {
                if (res != null) {
                  orderUpdates = res['notif_orders'] ?? true;
                  promoOffers = res['notif_promos'] ?? true;
                  sysAlerts = res['notif_system'] ?? true;
                }
                isLoading = false;
              });
            }
          }).catchError((e) {
            if (context.mounted) {
              setState(() => isLoading = false);
            }
          });
          return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()));
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Push Notification Settings',
                  style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                  'Choose which alerts you want to receive on this device.',
                  style: GoogleFonts.outfit(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
              SwitchListTile(
                title: Text('Order Updates',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Status changes, rider assignments, tracking',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: Colors.grey.shade500)),
                value: orderUpdates,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => orderUpdates = val);
                  await Supabase.instance.client
                      .from('profiles')
                      .update({'notif_orders': val}).eq('id', userId);
                },
              ),
              SwitchListTile(
                title: Text('Promotions & Offers',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text('Discounts, coupons, and marketing alerts',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: Colors.grey.shade500)),
                value: promoOffers,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => promoOffers = val);
                  await Supabase.instance.client
                      .from('profiles')
                      .update({'notif_promos': val}).eq('id', userId);
                },
              ),
              SwitchListTile(
                title: Text('System Alerts',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'App updates, security notices, maintenance',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: Colors.grey.shade500)),
                value: sysAlerts,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => sysAlerts = val);
                  await Supabase.instance.client
                      .from('profiles')
                      .update({'notif_system': val}).eq('id', userId);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      });
    },
  );
}
