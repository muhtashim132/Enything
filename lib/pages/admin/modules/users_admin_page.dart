import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../theme/admin_theme.dart';
import '../../../providers/rbac_provider.dart';
import '../../../models/rbac/role_model.dart';
import '../../../widgets/admin/kyc_verification_dialog.dart';

void _showKycDialog(BuildContext context, Map<String, dynamic> data, String title, String tableName, String idColumn, VoidCallback onRefresh) {
  showDialog(
    context: context,
    builder: (_) => KycVerificationDialog(
      title: title,
      data: data,
      tableName: tableName,
      idColumn: idColumn,
      onRefresh: onRefresh,
    ),
  );
}

// ── Unified Users Hub (Customers / Sellers / Riders) ─────────────
class UsersAdminPage extends StatefulWidget {
  const UsersAdminPage({super.key});

  @override
  State<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends State<UsersAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: AdminColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColors.cardBorder),
          ),
          child: TabBar(
            controller: _tabs,
            indicator: BoxDecoration(
              gradient: AdminGradients.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AdminColors.textMuted,
            labelStyle: AdminStyles.body(size: 13, color: Colors.white),
            unselectedLabelStyle: AdminStyles.body(size: 13),
            tabs: const [
              Tab(text: 'Customers'),
              Tab(text: 'Sellers'),
              Tab(text: 'Riders'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _CustomersTab(),
              _SellersTab(),
              _RidersTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  CUSTOMERS TAB
// ══════════════════════════════════════════════════════════════════
class _CustomersTab extends StatefulWidget {
  const _CustomersTab();

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await _db.from('profiles').select().order('created_at', ascending: false).limit(100);
      _users = List<Map<String, dynamic>>.from(res);
      _filtered = _users;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _users.where((u) {
        final name = (u['full_name'] ?? '').toString().toLowerCase();
        final phone = (u['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q);
      }).toList();
    });
  }

  Future<void> _promoteToAdmin(Map<String, dynamic> user) async {
    final rbac = context.read<RbacProvider>();
    final roles = rbac.allRoles.where((r) => r.slug != 'super_admin').toList();
    if (roles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No roles available.')));
      return;
    }
    RoleModel? selectedRole = roles.first;
    final passCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Promote to Admin', style: AdminStyles.title()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Make ${user['full_name'] ?? 'User'} an admin.',
                  style: AdminStyles.body(size: 13, color: AdminColors.textSecondary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<RoleModel>(
                initialValue: selectedRole,
                dropdownColor: AdminColors.surface,
                style: AdminStyles.body(),
                decoration: InputDecoration(
                  filled: true, fillColor: AdminColors.cardBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                onChanged: (v) => setS(() => selectedRole = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: AdminStyles.body(),
                decoration: InputDecoration(
                  hintText: 'Set admin password',
                  hintStyle: AdminStyles.body(color: AdminColors.textMuted),
                  filled: true, fillColor: AdminColors.cardBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: AdminStyles.body(size: 13))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Promote', style: AdminStyles.body(size: 13, color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (ok == true && selectedRole != null && passCtrl.text.isNotEmpty) {
      try {
        await _db.from('admin_users').insert({
          'id': user['id'],
          'full_name': user['full_name'] ?? 'Admin',
          'role_id': selectedRole!.id,
          'admin_level': 'admin',
          'admin_password': passCtrl.text.trim(),
          'is_active': true,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Promoted to Admin!'), backgroundColor: AdminColors.success));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Already an admin or error occurred.'), backgroundColor: AdminColors.danger));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    return Column(
      children: [
        _SearchBar(_searchCtrl, 'Search customers...'),
        Expanded(
          child: _loading
              ? _skelList()
              : _filtered.isEmpty
                  ? const AdminEmptyState(icon: Icons.people_outline, message: 'No customers found')
                  : RefreshIndicator(
                      onRefresh: () async { setState(() => _loading = true); await _fetch(); },
                      color: AdminColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final u = _filtered[i];
                          final joined = u['created_at'] != null
                              ? DateFormat('dd MMM yy').format(DateTime.parse(u['created_at'].toString()))
                              : '';
                          return _UserCard(
                            name: u['full_name'] ?? 'Unknown',
                            sub: u['phone'] ?? u['email'] ?? '',
                            badge: (u['role'] ?? 'customer').toString(),
                            badgeColor: AdminColors.info,
                            joined: joined,
                            avatarUrl: u['avatar_url'],
                            action: rbac.isSuperAdmin
                                ? IconButton(
                                    icon: const Icon(Icons.admin_panel_settings_rounded, color: AdminColors.primary, size: 20),
                                    tooltip: 'Promote to Admin',
                                    onPressed: () => _promoteToAdmin(u),
                                  )
                                : null,
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 40)).slideY(begin: 0.08);
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SELLERS TAB
// ══════════════════════════════════════════════════════════════════
class _SellersTab extends StatefulWidget {
  const _SellersTab();

  @override
  State<_SellersTab> createState() => _SellersTabState();
}

class _SellersTabState extends State<_SellersTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _sellers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await _db
          .from('shops')
          .select('*, profiles:seller_id(full_name, email, phone)')
          .order('created_at', ascending: false);
      _sellers = List<Map<String, dynamic>>.from(res);
      _filtered = _sellers;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _sellers.where((s) {
        final name = (s['shop_name'] ?? '').toString().toLowerCase();
        final owner = ((s['profiles'] as Map?)?['full_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || owner.contains(q);
      }).toList();
    });
  }

  Future<void> _toggle(String id, bool cur) async {
    try {
      await _db.from('shops').update({'is_active': !cur}).eq('id', id);
      _fetch();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(_searchCtrl, 'Search sellers...'),
        Expanded(
          child: _loading
              ? _skelList()
              : _filtered.isEmpty
                  ? const AdminEmptyState(icon: Icons.store_outlined, message: 'No sellers yet')
                  : RefreshIndicator(
                      onRefresh: () async { setState(() => _loading = true); await _fetch(); },
                      color: AdminColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final s = _filtered[i];
                          final profile = s['profiles'] as Map?;
                          final kycStatus = (s['kyc_status'] ?? 'pending') as String;
                          final isActive = s['is_active'] == true;
                          final (kycColor, kycLabel) = _kycBadge(kycStatus);
                          return _UserCard(
                            name: s['shop_name'] ?? 'Unknown Shop',
                            sub: profile?['full_name'] ?? profile?['phone'] ?? '',
                            badge: kycLabel,
                            badgeColor: kycColor,
                            joined: '',
                            avatarUrl: s['logo_url'],
                            action: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.verified_user_rounded, size: 20),
                                  color: AdminColors.info,
                                  tooltip: 'Verify KYC',
                                  onPressed: () => _showKycDialog(
                                    context,
                                    s,
                                    s['shop_name'] ?? 'Seller',
                                    'shops',
                                    'id',
                                    _fetch,
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeThumbColor: AdminColors.success,
                                  onChanged: (_) => _toggle(s['id'].toString(), isActive),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 40)).slideY(begin: 0.08);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  (Color, String) _kycBadge(String status) => switch (status) {
    'approved' || 'verified' => (AdminColors.success, 'Verified'),
    'rejected' => (AdminColors.danger, 'Rejected'),
    _ => (AdminColors.warning, 'Pending KYC'),
  };
}

// ══════════════════════════════════════════════════════════════════
//  RIDERS TAB
// ══════════════════════════════════════════════════════════════════
class _RidersTab extends StatefulWidget {
  const _RidersTab();

  @override
  State<_RidersTab> createState() => _RidersTabState();
}

class _RidersTabState extends State<_RidersTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _riders = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await _db
          .from('delivery_partners')
          .select('*, profiles:id(full_name, phone, avatar_url)')
          .order('created_at', ascending: false)
          .limit(100);
      _riders = List<Map<String, dynamic>>.from(res);
      _filtered = _riders;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _riders.where((r) {
        final profile = r['profiles'] as Map?;
        final name = (profile?['full_name'] ?? '').toString().toLowerCase();
        final phone = (profile?['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q);
      }).toList();
    });
  }

  Future<void> _toggle(String id, bool cur) async {
    try {
      await _db.from('delivery_partners').update({'is_active': !cur}).eq('id', id);
      _fetch();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(_searchCtrl, 'Search riders...'),
        Expanded(
          child: _loading
              ? _skelList()
              : _filtered.isEmpty
                  ? const AdminEmptyState(icon: Icons.delivery_dining_outlined, message: 'No riders yet')
                  : RefreshIndicator(
                      onRefresh: () async { setState(() => _loading = true); await _fetch(); },
                      color: AdminColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final r = _filtered[i];
                          final profile = r['profiles'] as Map?;
                          final isActive = r['is_active'] == true;
                          final isVerified = r['kyc_verified'] == true;
                          return _UserCard(
                            name: profile?['full_name'] ?? 'Unknown Rider',
                            sub: profile?['phone'] ?? '',
                            badge: isVerified ? 'Verified' : 'Pending KYC',
                            badgeColor: isVerified ? AdminColors.success : AdminColors.warning,
                            joined: '',
                            avatarUrl: profile?['avatar_url'],
                            action: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.verified_user_rounded, size: 20),
                                  color: AdminColors.info,
                                  tooltip: 'Verify KYC',
                                  onPressed: () => _showKycDialog(
                                    context,
                                    r,
                                    profile?['full_name'] ?? 'Rider',
                                    'delivery_partners',
                                    'id',
                                    _fetch,
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeThumbColor: AdminColors.success,
                                  onChanged: (_) => _toggle(r['id'].toString(), isActive),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 40)).slideY(begin: 0.08);
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  const _SearchBar(this.ctrl, this.hint);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: ctrl,
        style: AdminStyles.body(),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AdminStyles.body(color: AdminColors.textMuted),
          prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.textMuted, size: 20),
          filled: true,
          fillColor: AdminColors.cardBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AdminColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AdminColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AdminColors.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String name;
  final String sub;
  final String badge;
  final Color badgeColor;
  final String joined;
  final String? avatarUrl;
  final Widget? action;

  const _UserCard({
    required this.name,
    required this.sub,
    required this.badge,
    required this.badgeColor,
    required this.joined,
    this.avatarUrl,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: AdminDecorations.glassCard(),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AdminColors.primary.withOpacity(0.2),
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AdminStyles.title(size: 16, color: AdminColors.primary))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AdminStyles.body(size: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty) Text(sub, style: AdminStyles.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            AdminBadge(label: badge, color: badgeColor),
          ]),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

Widget _skelList() => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 7,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AdminDecorations.glassCard(),
        child: const Row(children: [
          SkeletonBox(width: 44, height: 44, radius: 22),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 120, height: 13),
            SizedBox(height: 6),
            SkeletonBox(width: 80, height: 11),
          ])),
        ]),
      ).animate().shimmer(duration: 1500.ms),
    );
