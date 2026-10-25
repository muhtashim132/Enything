// ============================================================================
// manual_quote_request_page.dart — Custom Event Catering Free-Text Quote Request
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/quote_request_provider.dart';

class ManualQuoteRequestPage extends StatefulWidget {
  const ManualQuoteRequestPage({super.key});

  @override
  State<ManualQuoteRequestPage> createState() => _ManualQuoteRequestPageState();
}

class _ManualQuoteRequestPageState extends State<ManualQuoteRequestPage> {
  final _formKey = GlobalKey<FormState>();

  // Admin Helpline
  static const String _adminPhone = '+917006464241';
  static const String _adminPhoneDisplay = '+91 7006464241 (Muhtashim)';

  // Form Controllers
  final _customerPhoneController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _eventNameController = TextEditingController();
  final _guestsController = TextEditingController(text: '50');
  final _requirementsController = TextEditingController();
  final _venueAddressController = TextEditingController();
  final _venueNotesController = TextEditingController();
  final _preferredTimeController = TextEditingController(text: '1:00 PM - 3:00 PM');
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();
  final _gatePassController = TextEditingController();

  // Selection states
  String _selectedEventType = 'birthday';
  DateTime? _selectedEventDate;
  String _selectedDietary = 'All Welcome';
  double? _venueLat;
  double? _venueLng;

  bool _isSubmitting = false;

  static const List<Map<String, String>> _eventTypes = [
    {'type': 'birthday', 'label': 'Birthday 🎂'},
    {'type': 'wedding', 'label': 'Wedding 💍'},
    {'type': 'corporate', 'label': 'Corporate 💼'},
    {'type': 'house_party', 'label': 'House Party 🎉'},
    {'type': 'religious', 'label': 'Religious 🕊️'},
    {'type': 'school_event', 'label': 'School/College 🎓'},
    {'type': 'custom', 'label': 'Custom ✨'},
  ];

  static const List<String> _dietaryOptions = [
    'All Welcome',
    'Pure Veg 🌱',
    'Non-Veg 🍗',
    'Jain Food ✨',
    'Halal 🌙',
  ];

  @override
  void initState() {
    super.initState();
    // Default event date is 3 days in future
    _selectedEventDate = DateTime.now().add(const Duration(days: 3));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillUserData();
      _restoreDraft();
    });
  }

  @override
  void dispose() {
    _customerPhoneController.dispose();
    _customerNameController.dispose();
    _eventNameController.dispose();
    _guestsController.dispose();
    _requirementsController.dispose();
    _venueAddressController.dispose();
    _venueNotesController.dispose();
    _preferredTimeController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _secondaryPhoneController.dispose();
    _gatePassController.dispose();
    super.dispose();
  }

  void _prefillUserData() {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user != null) {
      if (_customerPhoneController.text.isEmpty && user.phone.isNotEmpty) {
        _customerPhoneController.text = user.phone;
        _contactPhoneController.text = user.phone;
      }
      if (_customerNameController.text.isEmpty && user.fullName.isNotEmpty) {
        _customerNameController.text = user.fullName;
        _contactNameController.text = user.fullName;
      }
    }

    final loc = context.read<LocationProvider>();
    if (loc.currentAddress.isNotEmpty && _venueAddressController.text.isEmpty) {
      _venueAddressController.text = loc.currentAddress;
      _venueLat = loc.currentLocation?.latitude;
      _venueLng = loc.currentLocation?.longitude;
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString('manual_quote_draft');
      if (draft != null) {
        final data = jsonDecode(draft) as Map<String, dynamic>;
        if (_requirementsController.text.isEmpty && data['requirements'] != null) {
          setState(() {
            _requirementsController.text = data['requirements'] as String;
            if (data['event_name'] != null) _eventNameController.text = data['event_name'] as String;
            if (data['guests'] != null) _guestsController.text = data['guests'] as String;
            if (data['venue_address'] != null) _venueAddressController.text = data['venue_address'] as String;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'requirements': _requirementsController.text,
        'event_name': _eventNameController.text,
        'guests': _guestsController.text,
        'venue_address': _venueAddressController.text,
      };
      await prefs.setString('manual_quote_draft', jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('manual_quote_draft');
    } catch (_) {}
  }

  Future<void> _callAdmin() async {
    final uri = Uri.parse('tel:$_adminPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer: $_adminPhone')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstAllowed = now.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedEventDate ?? firstAllowed,
      firstDate: firstAllowed,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'SELECT EVENT DATE',
      confirmText: 'SET DATE',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedEventDate = picked);
    }
  }

  Future<void> _submitQuote() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please correct the highlighted fields'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedEventDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an event date')),
      );
      return;
    }

    final guests = int.tryParse(_guestsController.text.trim()) ?? 0;
    if (guests <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimated guests must be greater than 0')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final payload = {
      'customer_phone': _customerPhoneController.text.trim(),
      'customer_name': _customerNameController.text.trim(),
      'event_name': _eventNameController.text.trim(),
      'event_type': _selectedEventType,
      'event_date': _selectedEventDate!.toIso8601String().split('T').first,
      'estimated_guest_count': guests,
      'dietary_preferences': _selectedDietary,
      'requirements_description': _requirementsController.text.trim(),
      'venue_address': _venueAddressController.text.trim(),
      'venue_lat': _venueLat,
      'venue_lng': _venueLng,
      'venue_delivery_notes': _venueNotesController.text.trim(),
      'preferred_delivery_time': _preferredTimeController.text.trim(),
      'contact_person_name': _contactNameController.text.trim().isNotEmpty
          ? _contactNameController.text.trim()
          : _customerNameController.text.trim(),
      'contact_person_phone': _contactPhoneController.text.trim().isNotEmpty
          ? _contactPhoneController.text.trim()
          : _customerPhoneController.text.trim(),
      'secondary_contact_phone': _secondaryPhoneController.text.trim(),
      'gate_pass_instructions': _gatePassController.text.trim(),
    };

    try {
      final res = await context.read<QuoteRequestProvider>().submitQuoteRequest(payload);
      await _clearDraft();

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final quoteId = res['quote_id'] as String?;

      // Send background FCM push to all active superadmins / admins
      try {
        final notifProvider = context.read<NotificationProvider>();
        final adminRows = await Supabase.instance.client
            .from('admin_users')
            .select('id')
            .eq('is_active', true);
        final customerName = _customerNameController.text.trim().isNotEmpty
            ? _customerNameController.text.trim()
            : 'A customer';
        final eventName = _eventNameController.text.trim();
        final guests = _guestsController.text.trim();
        final phone = _customerPhoneController.text.trim();

        for (final admin in (adminRows as List)) {
          notifProvider.sendBackgroundPush(
            targetUserId: admin['id'] as String,
            title: '📋 New Catering Quote!',
            body: '$customerName requested catering for $guests guests ($eventName). 📞 $phone',
            data: {
              'type': 'catering_quote',
              'role': 'admin',
              'action': 'new_quote',
              if (quoteId != null) 'quote_id': quoteId,
            },
          );
        }
      } catch (err) {
        debugPrint('Failed to send admin push for catering quote: $err');
      }

      // Show congratulations bottom sheet or dialog
      _showSuccessSheet(quoteId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccessSheet(String? quoteId) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.greenAccent,
                  size: 46,
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 16),
              Text(
                'Quote Request Sent! 🎉',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Our catering manager (Muhtashim) has received your event requirements and will call you directly at ${_customerPhoneController.text.trim()} within 10 minutes to discuss pricing and options.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, color: Colors.amberAccent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Want to talk right now?',
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _adminPhoneDisplay,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _callAdmin,
                      child: const Text('Call Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext); // Close sheet
                    if (quoteId != null) {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.quoteResponse,
                        arguments: {'quote_id': quoteId},
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(
                    'Track My Quote 📋',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101018) : const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          'Request Custom Event Quote',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF171725) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: Form(
        key: _formKey,
        onChanged: _saveDraft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Direct Hotline Banner ──
              _buildAdminCallBanner(primary),
              const SizedBox(height: 20),

              // ── Section 1: Contact Details ──
              _buildSectionHeader('1. Your Contact Information', Icons.contact_phone_rounded, primary),
              const SizedBox(height: 12),
              _buildCard([
                _buildTextField(
                  controller: _customerPhoneController,
                  label: 'Phone Number (Required for quote discussion) *',
                  hint: '+91 98XXXXXXXX',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().length < 8) return 'Please provide a valid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _customerNameController,
                  label: 'Full Name *',
                  hint: 'e.g. Rahul Sharma',
                  icon: Icons.person_rounded,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your name';
                    return null;
                  },
                ),
              ], isDark),
              const SizedBox(height: 24),

              // ── Section 2: Event Information ──
              _buildSectionHeader('2. Event Details', Icons.celebration_rounded, primary),
              const SizedBox(height: 12),
              _buildCard([
                _buildTextField(
                  controller: _eventNameController,
                  label: 'Event Title / Occasion *',
                  hint: 'e.g. Amit\'s 30th Birthday Bash',
                  icon: Icons.event_note_rounded,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter an event title';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Event Type:',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _eventTypes.map((et) {
                    final isSelected = _selectedEventType == et['type'];
                    return ChoiceChip(
                      label: Text(et['label']!),
                      selected: isSelected,
                      showCheckmark: false,
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return primary.withValues(alpha: 0.2);
                        }
                        return isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04);
                      }),
                      selectedColor: primary.withValues(alpha: 0.2),
                      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                      labelStyle: TextStyle(
                        color: isSelected ? primary : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: isSelected ? primary : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedEventType = et['type']!);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: primary.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(12),
                            color: primary.withValues(alpha: 0.05),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Event Date *',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.calendar_month_rounded, size: 18, color: primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedEventDate != null
                                        ? DateFormat('EEE, MMM d, yyyy').format(_selectedEventDate!)
                                        : 'Tap to select',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _guestsController,
                        label: 'Guests Count *',
                        hint: '50',
                        icon: Icons.groups_rounded,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = int.tryParse(v);
                          if (n == null || n <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Quick guest chips
                Row(
                  children: [25, 50, 100, 200, 500].map((count) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ActionChip(
                        padding: EdgeInsets.zero,
                        label: Text('$count'),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        color: WidgetStateProperty.all(isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                        onPressed: () {
                          setState(() => _guestsController.text = '$count');
                        },
                      ),
                    );
                  }).toList(),
                ),
              ], isDark),
              const SizedBox(height: 24),

              // ── Section 3: Requirements (Hero) ──
              _buildSectionHeader('3. What Do You Need? (Free-Text Requirements)', Icons.restaurant_menu_rounded, primary),
              const SizedBox(height: 12),
              _buildCard([
                Text(
                  'Write down the dishes, quantities, and specifics. You can write freely — we will review and calculate the pricing for you.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _requirementsController,
                  label: 'Describe Requirements & Quantities *',
                  hint: 'Example:\n• 50 Plates Chicken Biryani\n• 100 Butter Naan & 40 Dal Makhani\n• 50 Plates Paneer Butter Masala\n• 150 Gulab Jamun\n• Disposable plates & spoons required\n• Food must be delivered hot by 1:00 PM',
                  maxLines: 7,
                  minLines: 5,
                  validator: (v) {
                    if (v == null || v.trim().length < 5) {
                      return 'Please provide at least 5 characters describing your menu';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Dietary Preferences:',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _dietaryOptions.map((opt) {
                    final isSel = _selectedDietary == opt;
                    return FilterChip(
                      label: Text(opt),
                      selected: isSel,
                      showCheckmark: false,
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return primary.withValues(alpha: 0.2);
                        }
                        return isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
                      }),
                      selectedColor: primary.withValues(alpha: 0.2),
                      backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                      labelStyle: TextStyle(
                        color: isSel ? primary : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: isSel ? primary : (isDark ? Colors.white12 : Colors.black12),
                        width: isSel ? 1.5 : 1.0,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedDietary = opt);
                      },
                    );
                  }).toList(),
                ),
              ], isDark),
              const SizedBox(height: 24),

              // ── Section 4: Venue & Delivery ──
              _buildSectionHeader('4. Venue & Logistics', Icons.location_on_rounded, primary),
              const SizedBox(height: 12),
              _buildCard([
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _venueAddressController,
                        label: 'Venue Address & Landmark *',
                        hint: 'Banquet Hall / House #, Street, City',
                        maxLines: 2,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please provide venue address';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.my_location_rounded, color: primary),
                      tooltip: 'Auto-fill current location',
                      onPressed: () {
                        final loc = context.read<LocationProvider>();
                        if (loc.currentAddress.isNotEmpty) {
                          setState(() {
                            _venueAddressController.text = loc.currentAddress;
                            _venueLat = loc.currentLocation?.latitude;
                            _venueLng = loc.currentLocation?.longitude;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Venue updated to current GPS address')),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _preferredTimeController,
                  label: 'Preferred Delivery Time Window',
                  hint: 'e.g. 12:30 PM - 2:00 PM',
                  icon: Icons.access_time_filled_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _venueNotesController,
                  label: 'Special Venue Instructions (Optional)',
                  hint: 'e.g. 3rd floor banquet hall, service elevator available',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _contactNameController,
                        label: 'Event Host / On-Site Contact',
                        hint: 'Host / Event Manager',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _contactPhoneController,
                        label: 'Host / Contact Phone',
                        hint: '+91 98XXXXXXXX',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
              ], isDark),
              const SizedBox(height: 28),

              // ── Submit Button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitQuote,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'SUBMIT QUOTE REQUEST',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'No advance payment required now. We will call you within 10 minutes to finalize details.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminCallBanner(Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2138), Color(0xFF151728)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded, color: Colors.amberAccent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Direct Catering Hotline 📞',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Call Muhtashim: $_adminPhone',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _callAdmin,
            child: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color primary) {
    return Row(
      children: [
        Icon(icon, size: 20, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B2A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    int maxLines = 1,
    int? minLines,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: GoogleFonts.outfit(
        fontSize: 14,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
          fontSize: 13,
          color: isDark ? Colors.white30 : Colors.black38,
        ),
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        prefixIcon: icon != null ? Icon(icon, size: 20, color: AppTheme.primaryColor) : null,
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppTheme.primaryColor,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
