import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../pages/settings/profile_settings_dialogs.dart';

/// Swiggy/Zomato-style address picker bottom sheet.
/// Shows saved addresses, current GPS option, and lets users add new addresses.
void showAddressPickerSheet(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final userId = auth.currentUserId;
  if (userId == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddressPickerContent(userId: userId),
  );
}

class _AddressPickerContent extends StatefulWidget {
  final String userId;
  const _AddressPickerContent({required this.userId});

  @override
  State<_AddressPickerContent> createState() => _AddressPickerContentState();
}

class _AddressPickerContentState extends State<_AddressPickerContent> {
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    // Ensure saved addresses are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().loadSavedAddresses(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locProv = context.watch<LocationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final savedAddresses = locProv.savedAddresses;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Text(
                  'Choose delivery location',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      color: isDark ? Colors.white54 : Colors.grey),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Use current location
          _buildUseCurrentLocation(isDark, locProv),

          if (savedAddresses.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SAVED ADDRESSES',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                  ),
                ),
              ),
            ),
          ],

          // Saved addresses list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: savedAddresses.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 56,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final addr = savedAddresses[index];
                final isActive = locProv.selectedAddress?.id == addr.id ||
                    (locProv.selectedAddress == null &&
                        locProv.matchedAddress?.id == addr.id);

                return Dismissible(
                  key: Key(addr.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 22),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete ${addr.displayLabel} address?',
                            style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700)),
                        content: Text('This cannot be undone.',
                            style: GoogleFonts.outfit()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) {
                    locProv.deleteSavedAddress(addr.id, widget.userId);
                  },
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.12)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(addr.icon,
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          addr.displayLabel,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (addr.isDefault) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('DEFAULT',
                                style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).primaryColor)),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              size: 16,
                              color: Theme.of(context).primaryColor),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      addr.fullAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color:
                            isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: () {
                        // Close picker first, then open 2-step edit flow
                        Navigator.pop(context);
                        showAddEditAddressDialog(
                          context,
                          existingAddress: addr,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.edit_location_alt_outlined,
                            size: 18,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade600),
                      ),
                    ),
                    onTap: () {
                      locProv.selectSavedAddress(addr);
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),

          // Add new address button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showAddEditAddressDialog(context);
                  },
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: Text('Add new address',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(
                      color: isDark
                          ? Colors.white24
                          : Theme.of(context).primaryColor.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUseCurrentLocation(bool isDark, LocationProvider locProv) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _isLocating
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.my_location_rounded,
                color: Theme.of(context).primaryColor, size: 20),
      ),
      title: Text(
        'Use current location',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Theme.of(context).primaryColor,
        ),
      ),
      subtitle: Text(
        locProv.hasLocation ? locProv.rawAddress : 'Using GPS',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          fontSize: 12,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
        ),
      ),
      onTap: () async {
        setState(() => _isLocating = true);
        locProv.clearSelectedAddress();
        await locProv.requestLocation();
        if (mounted) {
          setState(() => _isLocating = false);
          Navigator.pop(context);
        }
      },
    );
  }
}
