import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Helper dialogs for Profile Settings Page

void showSavedAddressesDialog(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final user = auth.user;
  if (user == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      bool isLoading = true;
      bool fetchingLocation = false;
      int selectedIndex = 0; // 0 = Home, 1 = Work

      final Map<int, Map<String, TextEditingController>> ctrls = {
        0: {
          'flat': TextEditingController(),
          'address': TextEditingController(),
          'landmark': TextEditingController(),
          'pincode': TextEditingController(),
        },
        1: {
          'flat': TextEditingController(),
          'address': TextEditingController(),
          'landmark': TextEditingController(),
          'pincode': TextEditingController(),
        }
      };

      return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
        if (isLoading) {
          Supabase.instance.client
              .from('customers')
              .select()
              .eq('id', user.id)
              .maybeSingle()
              .then((data) {
            if (data != null && context.mounted) {
              final home = data['address_home'] ?? {};
              final work = data['address_work'] ?? {};

              ctrls[0]!['flat']!.text = home['flat'] ?? '';
              ctrls[0]!['address']!.text =
                  home['address'] ?? data['default_address'] ?? '';
              ctrls[0]!['landmark']!.text =
                  home['landmark'] ?? data['landmark'] ?? '';
              ctrls[0]!['pincode']!.text =
                  home['pincode'] ?? data['pincode'] ?? '';

              ctrls[1]!['flat']!.text = work['flat'] ?? '';
              ctrls[1]!['address']!.text = work['address'] ?? '';
              ctrls[1]!['landmark']!.text = work['landmark'] ?? '';
              ctrls[1]!['pincode']!.text = work['pincode'] ?? '';
            }
            setState(() => isLoading = false);
          });
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }

        final currentCtrls = ctrls[selectedIndex]!;

        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved Addresses',
                  style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selectedIndex = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedIndex == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: selectedIndex == 0
                                ? [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4)
                                  ]
                                : [],
                          ),
                          child: Center(
                              child: Text('🏠 Home',
                                  style: GoogleFonts.outfit(
                                      fontWeight: selectedIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w500))),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selectedIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedIndex == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: selectedIndex == 1
                                ? [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4)
                                  ]
                                : [],
                          ),
                          child: Center(
                              child: Text('💼 Work',
                                  style: GoogleFonts.outfit(
                                      fontWeight: selectedIndex == 1
                                          ? FontWeight.w700
                                          : FontWeight.w500))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: currentCtrls['flat'],
                decoration: const InputDecoration(
                    labelText: 'House / Flat Number', hintText: 'e.g. A-404'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: currentCtrls['address'],
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Delivery Address',
                          hintText: 'Type address or tap 📍'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: fetchingLocation
                        ? null
                        : () async {
                            setState(() => fetchingLocation = true);
                            try {
                              final locProv = context.read<LocationProvider>();
                              final authProv = context.read<AuthProvider>();
                              bool granted = await locProv.requestLocation();
                              if (granted && context.mounted) {
                                currentCtrls['address']!.text =
                                    locProv.currentAddress;
                                // Sync the fresh GPS coordinates to the database
                                // so distance-based filtering always uses the latest location.
                                final uid = authProv.currentUserId;
                                if (uid != null) {
                                  await locProv.syncLocationToDatabase('customer', uid);
                                }
                              }
                            } finally {
                              if (context.mounted) {
                                setState(() => fetchingLocation = false);
                              }
                            }
                          },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16)),
                      child: fetchingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.my_location_rounded,
                              color: Theme.of(context).primaryColor, size: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: currentCtrls['landmark'],
                decoration: const InputDecoration(
                    labelText: 'Landmark', hintText: 'e.g. Near City Mall'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: currentCtrls['pincode'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Pincode', hintText: 'e.g. 400001'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final homeMap = {
                    'flat': ctrls[0]!['flat']!.text.trim(),
                    'address': ctrls[0]!['address']!.text.trim(),
                    'landmark': ctrls[0]!['landmark']!.text.trim(),
                    'pincode': ctrls[0]!['pincode']!.text.trim(),
                  };
                  final workMap = {
                    'flat': ctrls[1]!['flat']!.text.trim(),
                    'address': ctrls[1]!['address']!.text.trim(),
                    'landmark': ctrls[1]!['landmark']!.text.trim(),
                    'pincode': ctrls[1]!['pincode']!.text.trim(),
                  };

                  final activeMap = selectedIndex == 0 ? homeMap : workMap;

                  await Supabase.instance.client.from('customers').update({
                    'address_home': homeMap,
                    'address_work': workMap,
                    // Sync the active toggled address to the default fields so the app logic still works seamlessly
                    'default_address': activeMap['address'],
                    'landmark': activeMap['landmark'],
                    'pincode': activeMap['pincode'],
                  }).eq('id', user.id);

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56)),
                child: Text(
                    'Save & Set as Default ${selectedIndex == 0 ? "Home" : "Work"}'),
              ),
            ],
          ),
        );
      });
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
                'opening_time': openCtrl.text.trim(),
                'closing_time': closeCtrl.text.trim()
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
              ? Supabase.instance.client.rpc('get_my_shop_kyc').maybeSingle()
              : Supabase.instance.client.rpc('get_my_rider_kyc').maybeSingle(),
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
                                fontSize: 12, color: Colors.blue.shade800),
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

  showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
  
  Supabase.instance.client.from('delivery_partners').select('aadhar_number, pan_number, driving_license').eq('id', auth.currentUserId ?? '').maybeSingle().then((res) {
    if (context.mounted) Navigator.pop(context); // close loader
    if (res != null && context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KYC Documents', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                _buildReadOnlyFieldDialog('Aadhaar Number', res['aadhar_number'] ?? 'Not provided', isDark),
                const SizedBox(height: 16),
                _buildReadOnlyFieldDialog('PAN Number', res['pan_number'] ?? 'Not provided', isDark),
                const SizedBox(height: 16),
                _buildReadOnlyFieldDialog('Driving License', res['driving_license'] ?? 'Not provided', isDark),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Close', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }).catchError((_) {
    if (context.mounted) Navigator.pop(context);
  });
}

Widget _buildReadOnlyFieldDialog(String label, String value, bool isDark) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

void showGenericInfoDialog(BuildContext context, String title, String content) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title:
          Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
      ],
    ),
  );
}

void showNotificationSettingsDialog(BuildContext context) {
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
          SharedPreferences.getInstance().then((prefs) {
            if (context.mounted) {
              setState(() {
                orderUpdates = prefs.getBool('notif_orders') ?? true;
                promoOffers = prefs.getBool('notif_promo') ?? true;
                sysAlerts = prefs.getBool('notif_sys') ?? true;
                isLoading = false;
              });
            }
          });
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
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
              Text('Choose which alerts you want to receive on this device.',
                  style: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
              
              SwitchListTile(
                title: Text('Order Updates', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text('Status changes, rider assignments, tracking', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade500)),
                value: orderUpdates,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => orderUpdates = val);
                  final prefs = await SharedPreferences.getInstance();
                  prefs.setBool('notif_orders', val);
                },
              ),
              SwitchListTile(
                title: Text('Promotions & Offers', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text('Discounts, coupons, and marketing alerts', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade500)),
                value: promoOffers,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => promoOffers = val);
                  final prefs = await SharedPreferences.getInstance();
                  prefs.setBool('notif_promo', val);
                },
              ),
              SwitchListTile(
                title: Text('System Alerts', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text('App updates, security notices, maintenance', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade500)),
                value: sysAlerts,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (val) async {
                  setState(() => sysAlerts = val);
                  final prefs = await SharedPreferences.getInstance();
                  prefs.setBool('notif_sys', val);
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
