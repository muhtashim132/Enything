// ============================================================================
// bulk_order_event_page.dart — Date, Slot & Venue Configuration
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/bulk_order_provider.dart';
import '../../../providers/location_provider.dart';

class BulkOrderEventPage extends StatefulWidget {
  const BulkOrderEventPage({super.key});

  @override
  State<BulkOrderEventPage> createState() => _BulkOrderEventPageState();
}

class _BulkOrderEventPageState extends State<BulkOrderEventPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _eventNameController;
  late TextEditingController _venueAddressController;
  late TextEditingController _venueNotesController;
  late TextEditingController _contactNameController;
  late TextEditingController _contactPhoneController;
  late TextEditingController _secondaryPhoneController;
  late TextEditingController _gatePassController;

  DateTime? _selectedDate;
  Map<String, dynamic>? _selectedSlot;
  List<DateTime> _selectableDates = [];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<BulkOrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    _eventNameController = TextEditingController(text: provider.eventName);
    _venueAddressController = TextEditingController(text: provider.venueAddress);
    _venueNotesController = TextEditingController(text: provider.venueDeliveryNotes);
    _contactNameController = TextEditingController(
      text: provider.contactPersonName.isNotEmpty
          ? provider.contactPersonName
          : (user?.fullName ?? ''),
    );
    _contactPhoneController = TextEditingController(
      text: provider.contactPersonPhone.isNotEmpty
          ? provider.contactPersonPhone
          : (user?.phone ?? ''),
    );
    _secondaryPhoneController = TextEditingController(text: provider.secondaryContactPhone);
    _gatePassController = TextEditingController(text: provider.gatePassInstructions);

    _generateSelectableDates(provider);
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _venueAddressController.dispose();
    _venueNotesController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _secondaryPhoneController.dispose();
    _gatePassController.dispose();
    super.dispose();
  }

  void _generateSelectableDates(BulkOrderProvider provider) {
    final shop = provider.selectedShop;
    final minLeadHours = shop?.minBulkLeadTimeHours ?? 6;
    final maxLeadHours = shop?.maxBulkLeadTimeHours ?? 72;

    final earliest = DateTime.now().add(Duration(hours: minLeadHours));
    final latest = DateTime.now().add(Duration(hours: maxLeadHours));

    final dates = <DateTime>[];
    var cursor = DateTime(earliest.year, earliest.month, earliest.day);
    final endDay = DateTime(latest.year, latest.month, latest.day);

    while (!cursor.isAfter(endDay)) {
      dates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    _selectableDates = dates;
    _selectedDate = provider.eventDate != null && dates.any((d) => d.day == provider.eventDate!.day)
        ? provider.eventDate
        : dates.first;

    _fetchSlots();
  }

  Future<void> _fetchSlots() async {
    if (_selectedDate == null) return;
    final provider = Provider.of<BulkOrderProvider>(context, listen: false);
    final shop = provider.selectedShop;
    if (shop != null) {
      await provider.fetchSlotAvailability(shop.id, _selectedDate!);
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;
    final bulkProvider = Provider.of<BulkOrderProvider>(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Event & Delivery Details 📅',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Step Header
            _buildStepIndicator(isDark, primary),
            const SizedBox(height: 16),

            // Event Name Field
            _buildSectionCard(
              isDark: isDark,
              title: 'Occasion & Event',
              icon: Icons.celebration_rounded,
              primary: primary,
              child: TextFormField(
                controller: _eventNameController,
                decoration: InputDecoration(
                  labelText: 'Event Name / Occasion',
                  hintText: 'e.g. Birthday Party, Corporate Meet, Family Gathering',
                  prefixIcon: const Icon(Icons.stars_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter the occasion name';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),

            // Date Picker Carousel
            _buildSectionCard(
              isDark: isDark,
              title: 'Select Delivery Date',
              icon: Icons.calendar_month_rounded,
              primary: primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Advance notice allows kitchen to prepare fresh batches.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectableDates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final date = _selectableDates[index];
                        final isSelected = _selectedDate?.day == date.day &&
                            _selectedDate?.month == date.month;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDate = date;
                              _selectedSlot = null;
                            });
                            _fetchSlots();
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 68,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primary
                                  : (isDark ? const Color(0xFF242424) : Colors.grey[100]),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? primary
                                    : (isDark ? Colors.white12 : Colors.grey.shade300),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE').format(date).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white70
                                        : (isDark ? Colors.white60 : Colors.grey[600]),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  date.day.toString(),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                Text(
                                  DateFormat('MMM').format(date),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white70
                                        : (isDark ? Colors.white60 : Colors.grey[600]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Time Slot Selector
            _buildSectionCard(
              isDark: isDark,
              title: 'Kitchen Delivery Slot',
              icon: Icons.schedule_rounded,
              primary: primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slots show kitchen capacity and prevent overbooking.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  if (bulkProvider.isLoadingSlots)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ))
                  else if (bulkProvider.availableSlots.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'No time slots available for this date. Please pick another date.',
                        style: TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                    )
                  else
                    Column(
                      children: bulkProvider.availableSlots.map((slot) {
                        final start = slot['slot_start']?.toString().substring(0, 5) ?? '';
                        final end = slot['slot_end']?.toString().substring(0, 5) ?? '';
                        final available = slot['available_capacity'] as int? ?? 0;
                        final isAvail = slot['is_available'] == true && available >= bulkProvider.totalItems;
                        final isSelected = _selectedSlot?['slot_start'] == slot['slot_start'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: isAvail
                                ? () {
                                    setState(() => _selectedSlot = slot);
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.15)
                                    : (isDark ? const Color(0xFF242424) : Colors.white),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? primary
                                      : (isAvail
                                          ? (isDark ? Colors.white12 : Colors.grey.shade300)
                                          : Colors.red.withValues(alpha: 0.3)),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: isSelected
                                        ? primary
                                        : (isAvail ? Colors.grey : Colors.grey.shade400),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '$start – $end',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isAvail
                                          ? (isDark ? Colors.white : Colors.black87)
                                          : Colors.grey,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isAvail
                                          ? Colors.green.withValues(alpha: 0.12)
                                          : Colors.red.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isAvail ? '$available left' : 'FULL / INSUFFICIENT',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: isAvail ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Venue Location & Notes
            _buildSectionCard(
              isDark: isDark,
              title: 'Venue & Delivery Point',
              icon: Icons.location_on_rounded,
              primary: primary,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _venueAddressController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Full Venue Address',
                            hintText: 'Hall name, floor, landmark, street...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter the delivery venue address';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.my_location_rounded),
                        tooltip: 'Use current location',
                        onPressed: () {
                          final loc =
                              Provider.of<LocationProvider>(context, listen: false);
                          if (loc.currentAddress.isNotEmpty) {
                            setState(() {
                              _venueAddressController.text = loc.currentAddress;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _venueNotesController,
                    decoration: InputDecoration(
                      labelText: 'Venue Notes / Delivery Instructions',
                      hintText: 'e.g. Park near back gate, call before entering...',
                      prefixIcon: const Icon(Icons.directions_bus_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _gatePassController,
                    decoration: InputDecoration(
                      labelText: 'Gate Pass / Security Instructions',
                      hintText: 'e.g. Host name on visitor registry is Mr. Sharma',
                      prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Contact Persons (Primary + Secondary Fallback)
            _buildSectionCard(
              isDark: isDark,
              title: 'Event Coordinators',
              icon: Icons.contact_phone_rounded,
              primary: primary,
              child: Column(
                children: [
                  TextFormField(
                    controller: _contactNameController,
                    decoration: InputDecoration(
                      labelText: 'Primary Contact Person',
                      hintText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contactPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Primary Contact Phone',
                      hintText: '10-digit mobile number',
                      prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (val) => val == null || val.trim().length < 10 ? 'Enter valid phone' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secondaryPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Secondary Fallback Phone (Recommended)',
                      hintText: 'Alternative phone if primary is unreachable',
                      prefixIcon: const Icon(Icons.phone_forwarded_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Next Button
            ElevatedButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                if (_selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select an event date')),
                  );
                  return;
                }
                if (_selectedSlot == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a kitchen delivery slot')),
                  );
                  return;
                }

                final start = _parseTimeOfDay(_selectedSlot!['slot_start']);
                final end = _parseTimeOfDay(_selectedSlot!['slot_end']);

                final locProvider =
                    Provider.of<LocationProvider>(context, listen: false);

                bulkProvider.setEventDetails(
                  name: _eventNameController.text.trim(),
                  date: _selectedDate,
                  start: start,
                  end: end,
                  venue: _venueAddressController.text.trim(),
                  lat: locProvider.currentLocation?.latitude,
                  lng: locProvider.currentLocation?.longitude,
                  notes: _venueNotesController.text.trim(),
                  contactName: _contactNameController.text.trim(),
                  contactPhone: _contactPhoneController.text.trim(),
                  secondaryPhone: _secondaryPhoneController.text.trim(),
                  gatePass: _gatePassController.text.trim(),
                );

                Navigator.pushNamed(context, AppRoutes.bulkOrderCheckout);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Review & Finalize Order',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark, Color primary) {
    return Row(
      children: [
        _buildStepBadge(1, 'Menu', true, primary),
        Expanded(child: Container(height: 2, color: primary)),
        _buildStepBadge(2, 'Event & Slot', true, primary),
        Expanded(child: Container(height: 2, color: Colors.grey.shade400)),
        _buildStepBadge(3, 'Review', false, primary),
      ],
    );
  }

  Widget _buildStepBadge(int number, String label, bool active, Color primary) {
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active ? primary : Colors.grey.shade400,
          foregroundColor: Colors.white,
          child: Text('$number', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? primary : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color primary,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
