import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/rbac_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../models/rbac/admin_user_model.dart';
import '../../../models/rbac/role_model.dart';
import '../../../widgets/rbac/rbac_widgets.dart';
import '../../../widgets/rbac/invite_admin_dialog.dart';

class TeamMembersPage extends StatefulWidget {
  const TeamMembersPage({super.key});

  @override
  State<TeamMembersPage> createState() => _TeamMembersPageState();
}

class _TeamMembersPageState extends State<TeamMembersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamProvider>().loadTeam();
    });
    _searchCtrl.addListener(() {
      context.read<TeamProvider>().search(_searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();
    final team = context.watch<TeamProvider>();
    final pendingCount =
        team.invitations.where((i) => i.status.name == 'pending').length;

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Team Members',
            style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          if (rbac.isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: () => InviteAdminDialog.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B2FC9),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.person_add_rounded,
                    size: 16, color: Colors.white),
                label: Text('Invite',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF8B2FC9),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
          tabs: [
            Tab(text: 'Members (${team.members.length})'),
            Tab(text: 'Invitations ($pendingCount)'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, email or role...',
                hintStyle:
                    GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Colors.white30, size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B2FC9)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── Members Tab ────────────────────────────────
                team.loading
                    ? _skeletons()
                    : team.members.isEmpty
                        ? _empty('No team members yet')
                        : RefreshIndicator(
                            onRefresh: () => team.loadTeam(),
                            color: const Color(0xFF8B2FC9),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: team.members.length,
                              itemBuilder: (_, i) => _MemberCard(
                                member: team.members[i],
                                isSuperAdmin: rbac.isSuperAdmin,
                                allRoles: rbac.allRoles,
                                actorId: rbac.currentAdmin?.id ?? '',
                                actorRole: rbac.currentAdmin?.role?.slug ?? '',
                              ),
                            ),
                          ),

                // ── Invitations Tab ────────────────────────────
                team.loading
                    ? _skeletons()
                    : team.invitations.isEmpty
                        ? _empty('No invitations sent yet')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: team.invitations.length,
                            itemBuilder: (_, i) {
                              final inv = team.invitations[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.07)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.mail_outline_rounded,
                                      color: Colors.white38, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(inv.email,
                                            style: GoogleFonts.outfit(
                                                color: const Color(0xDEFFFFFF),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                        if (inv.roleName != null)
                                          Text(inv.roleName!,
                                              style: GoogleFonts.outfit(
                                                  color: Colors.white38,
                                                  fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  _statusBadge(inv.status.name),
                                  if (inv.status.name == 'pending' &&
                                      rbac.isSuperAdmin) ...[
                                    IconButton(
                                      icon: const Icon(Icons.copy_rounded,
                                          color: Colors.white70, size: 18),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: inv.token));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Invite code copied!')),
                                        );
                                      },
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel_outlined,
                                          color: Colors.white24, size: 18),
                                      onPressed: () =>
                                          team.revokeInvitation(inv.id),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ]),
                              );
                            },
                          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'accepted' => ('Accepted', const Color(0xFF4CAF50)),
      'expired' => ('Expired', const Color(0xFF9E9E9E)),
      'revoked' => ('Revoked', const Color(0xFFFF5722)),
      _ => ('Pending', const Color(0xFFFF9800)),
    };
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: GoogleFonts.outfit(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _skeletons() => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(children: [
            SkeletonBox(width: 44, height: 44, radius: 22),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 13),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 11),
                  ]),
            ),
            SkeletonBox(width: 60, height: 22, radius: 10),
          ]),
        ),
      );

  Widget _empty(String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.people_outline_rounded,
              color: Colors.white12, size: 56),
          const SizedBox(height: 16),
          Text(msg,
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 15)),
        ]),
      );
}

// ── Member Card ────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final AdminUserModel member;
  final bool isSuperAdmin;
  final List<RoleModel> allRoles;
  final String actorId;
  final String actorRole;

  const _MemberCard({
    required this.member,
    required this.isSuperAdmin,
    required this.allRoles,
    required this.actorId,
    required this.actorRole,
  });

  Future<void> _changeRole(BuildContext context) async {
    RoleModel? picked;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF12091F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change Role',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 16),
              ...allRoles
                  .where((r) => r.slug != 'super_admin')
                  .map((r) => ListTile(
                        dense: true,
                        title: Text(r.name,
                            style: GoogleFonts.outfit(
                                color: const Color(0xDEFFFFFF))),
                        trailing: member.role?.id == r.id
                            ? const Icon(Icons.check_rounded,
                                color: Color(0xFF8B2FC9), size: 18)
                            : null,
                        onTap: () {
                          picked = r;
                          Navigator.pop(context);
                        },
                      )),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;
    if (!context.mounted) return;
    await context.read<TeamProvider>().assignRole(
          userId: member.id,
          roleId: picked!.id,
          actorId: actorId,
          actorRole: actorRole,
        );
  }

  Future<void> _resetPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12091F),
        title: Text('Reset Password',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter new password for ${member.fullName}:',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'New Password',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B2FC9)),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok == true && ctrl.text.isNotEmpty) {
      if (!context.mounted) return;
      await context.read<TeamProvider>().resetPassword(
            userId: member.id,
            newPassword: ctrl.text.trim(),
            actorId: actorId,
            actorRole: actorRole,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset successfully')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = context.read<TeamProvider>();
    final lastLogin = member.lastLoginAt != null
        ? DateFormat('dd MMM yy').format(member.lastLoginAt!)
        : 'Never';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF8B2FC9).withValues(alpha: 0.2),
            backgroundImage: member.avatarUrl != null
                ? NetworkImage(member.avatarUrl!)
                : null,
            child: member.avatarUrl == null
                ? Text(member.initials,
                    style: GoogleFonts.outfit(
                        color: const Color(0xFF8B2FC9),
                        fontWeight: FontWeight.w800,
                        fontSize: 14))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member.fullName,
                  style: GoogleFonts.outfit(
                      color: const Color(0xDEFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(member.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 4),
              Row(children: [
                if (member.role != null)
                  RoleBadge(
                      name: member.role!.name,
                      color: member.role!.badgeColor,
                      small: true),
                const SizedBox(width: 6),
                UserStatusBadge(
                    isActive: member.isActive,
                    isSuspended: member.isSuspended,
                    small: true),
              ]),
              Text('Last login: $lastLogin',
                  style:
                      GoogleFonts.outfit(color: Colors.white24, fontSize: 10)),
            ]),
          ),
          if (isSuperAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white38, size: 18),
              color: const Color(0xFF1A1030),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) async {
                HapticFeedback.lightImpact();
                if (v == 'role') {
                  await _changeRole(context);
                } else if (v == 'password') {
                  await _resetPassword(context);
                } else if (v == 'suspend') {
                  final ok = await ConfirmActionDialog.show(
                    context,
                    title: 'Suspend Member',
                    message:
                        'Suspend ${member.fullName}? They will lose access immediately.',
                    confirmLabel: 'Suspend',
                    confirmColor: const Color(0xFFFF5722),
                  );
                  if (ok) {
                    await team.suspendMember(
                        userId: member.id,
                        actorId: actorId,
                        actorRole: actorRole);
                  }
                } else if (v == 'reactivate') {
                  await team.reactivateMember(
                      userId: member.id,
                      actorId: actorId,
                      actorRole: actorRole);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'role',
                    child: _item(Icons.swap_horiz_rounded, 'Change Role',
                        const Color(0xDEFFFFFF))),
                PopupMenuItem(
                    value: 'password',
                    child: _item(Icons.lock_reset_rounded, 'Reset Password',
                        const Color(0xDEFFFFFF))),
                if (!member.isSuspended)
                  PopupMenuItem(
                      value: 'suspend',
                      child: _item(Icons.block_rounded, 'Suspend',
                          const Color(0xFFFF5722)))
                else
                  PopupMenuItem(
                      value: 'reactivate',
                      child: _item(Icons.check_circle_outline_rounded,
                          'Reactivate', const Color(0xFF4CAF50))),
              ],
            ),
        ]),
      ),
    );
  }

  Widget _item(IconData icon, String label, Color color) => Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.outfit(color: color)),
      ]);
}
