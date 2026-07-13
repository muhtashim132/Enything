import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_categories.dart';

/// Renders extra form fields that vary per [CategoryGroup].
/// Call [collectData()] to get a Map ready to merge into `shops` additionalData.
class CategoryExtraFields extends StatefulWidget {
  final CategoryGroup group;
  final String category;

  const CategoryExtraFields({
    super.key,
    required this.group,
    required this.category,
  });

  @override
  State<CategoryExtraFields> createState() => CategoryExtraFieldsState();
}

class CategoryExtraFieldsState extends State<CategoryExtraFields>
    with SingleTickerProviderStateMixin {
  // ── Food fields ──────────────────────────────────────────────────────────
  final _fssaiCtrl = TextEditingController();
  String _foodType = 'Both'; // Pure Veg | Non-Veg | Both
  final _prepTimeCtrl = TextEditingController();
  final _packagingChargeCtrl = TextEditingController();

  // ── Pharmacy fields ──────────────────────────────────────────────────────
  final _drugLicCtrl = TextEditingController();
  final _pharmacistCtrl = TextEditingController();
  bool _acceptsReturns = false;

  // ── Perishable fields ────────────────────────────────────────────────────
  final _perishFssaiCtrl = TextEditingController();
  String _cutoffTime = '6:00 PM';

  // ── Retail fields ────────────────────────────────────────────────────────
  String _returnPolicy = '7 Days';

  late AnimationController _anim;
  late Animation<double> _fade;

  static const _cutoffOptions = [
    '12:00 PM',
    '1:00 PM',
    '2:00 PM',
    '3:00 PM',
    '4:00 PM',
    '5:00 PM',
    '6:00 PM',
    '7:00 PM',
    '8:00 PM',
  ];

  static const _returnOptions = [
    'Non-Returnable',
    '3 Days',
    '7 Days',
    '14 Days',
    '30 Days',
  ];

  static const _foodTypeOptions = ['Pure Veg', 'Non-Veg', 'Both'];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        duration: const Duration(milliseconds: 350), vsync: this)
      ..forward();
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(CategoryExtraFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fssaiCtrl,
      _prepTimeCtrl,
      _packagingChargeCtrl,
      _drugLicCtrl,
      _pharmacistCtrl,
      _perishFssaiCtrl,
    ]) {
      c.dispose();
    }
    _anim.dispose();
    super.dispose();
  }

  // ── Public: collect data into a flat map ───────────────────────────────────
  Map<String, dynamic> collectData() {
    switch (widget.group) {
      case CategoryGroup.food:
        return {
          'fssai_number': _fssaiCtrl.text.trim(),
          'food_type': _foodType,
          'avg_prep_time_mins': int.tryParse(_prepTimeCtrl.text.trim()) ?? 30,
          'packaging_charge':
              double.tryParse(_packagingChargeCtrl.text.trim()) ?? 0,
        };
      case CategoryGroup.pharmacy:
        return {
          'drug_license_number': _drugLicCtrl.text.trim(),
          'pharmacist_name': _pharmacistCtrl.text.trim(),
          'accepts_returns': _acceptsReturns,
        };
      case CategoryGroup.perishable:
        return {
          'fssai_number': _perishFssaiCtrl.text.trim(),
          'order_cutoff': _cutoffTime,
        };
      case CategoryGroup.retail:
        return {
          'return_policy': _returnPolicy,
        };
    }
  }

  /// Returns a validation error string, or null if all required fields are ok.
  String? validate() {
    switch (widget.group) {
      case CategoryGroup.food:
        if (_fssaiCtrl.text.trim().isEmpty) {
          return 'FSSAI Licence Number is required for food businesses';
        }
        return null;
      case CategoryGroup.pharmacy:
        if (_drugLicCtrl.text.trim().isEmpty) {
          return 'Drug Licence Number is required for pharmacy / medical stores';
        }
        if (_pharmacistCtrl.text.trim().isEmpty) {
          return 'Registered Pharmacist name is required';
        }
        return null;
      case CategoryGroup.perishable:
        if (_perishFssaiCtrl.text.trim().isEmpty) {
          return 'FSSAI Licence Number is required';
        }
        return null;
      case CategoryGroup.retail:
        return null; // GST is optional for retail
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final info = AppCategories.groupInfo(widget.group);
    return FadeTransition(
      opacity: _fade,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group banner ───────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _groupAccent(widget.group).withValues(alpha: 0.18),
                  _groupAccent(widget.group).withValues(alpha: 0.05),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _groupAccent(widget.group).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Text(info['emoji']!, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info['label']!,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info['hint']!,
                        style: GoogleFonts.outfit(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Group-specific fields ──────────────────────────────────────────
          ..._buildGroupFields(),
        ],
      ),
    );
  }

  List<Widget> _buildGroupFields() {
    switch (widget.group) {
      case CategoryGroup.food:
        return _foodFields();
      case CategoryGroup.pharmacy:
        return _pharmacyFields();
      case CategoryGroup.perishable:
        return _perishableFields();
      case CategoryGroup.retail:
        return _retailFields();
    }
  }

  // ── Food ───────────────────────────────────────────────────────────────────
  List<Widget> _foodFields() => [
        _DarkField(
          label: 'FSSAI Licence Number *',
          controller: _fssaiCtrl,
          hint: '12345678901234',
          caps: true,
          icon: Icons.verified_outlined,
        ),
        const SizedBox(height: 16),
        _DropdownField<String>(
          label: 'Food Type *',
          value: _foodType,
          icon: Icons.eco_outlined,
          items: _foodTypeOptions,
          itemLabel: (v) => v,
          onChanged: (v) => setState(() => _foodType = v!),
        ),
        const SizedBox(height: 16),
        _DarkField(
          label: 'Average Prep Time (mins)',
          controller: _prepTimeCtrl,
          hint: 'e.g. 30',
          number: true,
          icon: Icons.timer_outlined,
        ),
        const SizedBox(height: 16),
        _DarkField(
          label: 'Packaging Charge (₹)',
          controller: _packagingChargeCtrl,
          hint: 'e.g. 10',
          number: true,
          icon: Icons.shopping_bag_outlined,
        ),
      ];

  // ── Pharmacy ───────────────────────────────────────────────────────────────
  List<Widget> _pharmacyFields() => [
        _DarkField(
          label: 'Drug Licence Number *',
          controller: _drugLicCtrl,
          hint: 'MH-MUM-12345',
          caps: true,
          icon: Icons.medical_services_outlined,
        ),
        const SizedBox(height: 16),
        _DarkField(
          label: 'Registered Pharmacist Name *',
          controller: _pharmacistCtrl,
          hint: 'Dr. Sharma',
          icon: Icons.person_pin_outlined,
        ),
        const SizedBox(height: 16),
        _ToggleField(
          label: 'Accepts Medicine Returns?',
          subtitle: 'Most medicines are non-returnable by law',
          value: _acceptsReturns,
          onChanged: (v) => setState(() => _acceptsReturns = v),
          icon: Icons.assignment_return_outlined,
        ),
      ];

  // ── Perishable ─────────────────────────────────────────────────────────────
  List<Widget> _perishableFields() => [
        _DarkField(
          label: 'FSSAI Licence Number *',
          controller: _perishFssaiCtrl,
          hint: '12345678901234',
          caps: true,
          icon: Icons.verified_outlined,
        ),
        const SizedBox(height: 16),
        _DropdownField<String>(
          label: 'Daily Order Cut-off Time',
          value: _cutoffTime,
          icon: Icons.schedule_outlined,
          items: _cutoffOptions,
          itemLabel: (v) => v,
          onChanged: (v) => setState(() => _cutoffTime = v!),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Orders placed after this time will be for the next day',
            style: GoogleFonts.outfit(color: Colors.white30, fontSize: 11),
          ),
        ),
      ];

  // ── Retail ─────────────────────────────────────────────────────────────────
  List<Widget> _retailFields() => [
        _DropdownField<String>(
          label: 'Return Policy',
          value: _returnPolicy,
          icon: Icons.assignment_return_outlined,
          items: _returnOptions,
          itemLabel: (v) => v,
          onChanged: (v) => setState(() => _returnPolicy = v!),
        ),
      ];

  Color _groupAccent(CategoryGroup g) {
    switch (g) {
      case CategoryGroup.food:
        return const Color(0xFFFF6B35);
      case CategoryGroup.pharmacy:
        return const Color(0xFF2F9E44);
      case CategoryGroup.perishable:
        return const Color(0xFF1C7ED6);
      case CategoryGroup.retail:
        return const Color(0xFF9C36B5);
    }
  }
}

// ── Private helper widgets ─────────────────────────────────────────────────────

class _DarkField extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final bool number, caps;
  final IconData? icon;

  const _DarkField({
    required this.label,
    required this.controller,
    required this.hint,
    this.number = false,
    this.caps = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: TextField(
            controller: controller,
            maxLength: 500,
            buildCounter: (BuildContext context, { int? currentLength, int? maxLength, bool? isFocused }) => null,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            textCapitalization:
                caps ? TextCapitalization.characters : TextCapitalization.words,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
              prefixIcon: icon != null
                  ? Icon(icon, color: Colors.white38, size: 20)
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              border: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF0D1440),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              icon:
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              items: items
                  .map((item) => DropdownMenuItem<T>(
                        value: item,
                        child: Row(
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white38, size: 18),
                              const SizedBox(width: 10),
                            ],
                            Text(itemLabel(item),
                                style: GoogleFonts.outfit(
                                    color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleField extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const _ToggleField({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white38, size: 22),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.outfit(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF2F9E44),
            activeTrackColor: const Color(0xFF2F9E44).withAlpha(120),
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}
