import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../../providers/rbac_provider.dart';
import '../../../providers/audit_provider.dart';
import '../../../models/rbac/audit_log_model.dart';
import '../../../widgets/rbac/rbac_widgets.dart';
import '../../../pages/admin/rbac/forbidden_page.dart';
import '../../../utils/time_utils.dart';

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final _actionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _entityType;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 200) {
        context.read<AuditProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _load() {
    context.read<AuditProvider>().load(
          action:
              _actionCtrl.text.trim().isEmpty ? null : _actionCtrl.text.trim(),
          entityType: _entityType,
          from: _from,
          to: _to,
        );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF8B2FC9)),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = context.watch<AuditProvider>();
    final rbac = context.watch<RbacProvider>();

    if (!rbac.can('audit.view')) return const ForbiddenPage(fullPage: false);

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Audit Logs',
            style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          if (_from != null ||
              _actionCtrl.text.isNotEmpty ||
              _entityType != null)
            TextButton(
              onPressed: () {
                _actionCtrl.clear();
                setState(() {
                  _entityType = null;
                  _from = null;
                  _to = null;
                });
                context.read<AuditProvider>().reset();
                _load();
              },
              child: Text('Clear',
                  style: GoogleFonts.outfit(
                      color: const Color(0xFFFF5722), fontSize: 12)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter Row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _actionCtrl,
                    style:
                        GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Filter by action...',
                      hintStyle: GoogleFonts.outfit(
                          color: Colors.white24, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white24, size: 17),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFF8B2FC9))),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickDateRange,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _from != null
                          ? const Color(0xFF8B2FC9).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _from != null
                              ? const Color(0xFF8B2FC9).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Icon(Icons.date_range_rounded,
                        color: _from != null
                            ? const Color(0xFF8B2FC9)
                            : Colors.white38,
                        size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                // Entity filter chip
                _entityChip(),
              ],
            ),
          ),

          if (_from != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      color: Colors.white38, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('dd MMM').format(_from!.toIST())} – ${DateFormat('dd MMM yyyy').format(_to ?? _from!.toIST())}',
                    style:
                        GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // ── Log List ────────────────────────────────────────────
          Expanded(
            child: audit.loading && audit.logs.isEmpty
                ? _buildSkeletons()
                : audit.logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history_rounded,
                                color: Colors.white12, size: 56),
                            const SizedBox(height: 16),
                            Text('No audit logs found',
                                style: GoogleFonts.outfit(
                                    color: Colors.white38, fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: audit.logs.length + (audit.hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == audit.logs.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF8B2FC9), strokeWidth: 2),
                              ),
                            );
                          }
                          return _LogCard(log: audit.logs[i]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _entityChip() {
    const types = ['role', 'admin_user', 'invitation', 'order', 'payment'];
    return PopupMenuButton<String?>(
      color: const Color(0xFF1A1030),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        setState(() => _entityType = v);
        _load();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: null,
          child: Text('All types',
              style: GoogleFonts.outfit(color: Colors.white70)),
        ),
        ...types.map((t) => PopupMenuItem(
              value: t,
              child: Row(
                children: [
                  Text(t, style: GoogleFonts.outfit(color: Colors.white70)),
                  if (_entityType == t) ...[
                    const Spacer(),
                    const Icon(Icons.check_rounded,
                        color: Color(0xFF8B2FC9), size: 14),
                  ],
                ],
              ),
            )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _entityType != null
              ? const Color(0xFF8B2FC9).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _entityType != null
                  ? const Color(0xFF8B2FC9).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(Icons.filter_list_rounded,
            color:
                _entityType != null ? const Color(0xFF8B2FC9) : Colors.white38,
            size: 18),
      ),
    );
  }

  Widget _buildSkeletons() => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 100, height: 11),
              SizedBox(height: 6),
              SkeletonBox(height: 13),
              SizedBox(height: 6),
              SkeletonBox(width: 150, height: 11),
            ],
          ),
        ),
      );
}

class _LogCard extends StatefulWidget {
  final AuditLogModel log;
  const _LogCard({required this.log});

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _expanded = false;

  Color _actionColor(String action) {
    if (action.contains('delete') ||
        action.contains('suspend') ||
        action.contains('reject')) {
      return const Color(0xFFFF5722);
    }
    if (action.contains('create') ||
        action.contains('approve') ||
        action.contains('accept')) {
      return const Color(0xFF4CAF50);
    }
    if (action.contains('update') ||
        action.contains('edit') ||
        action.contains('assign')) {
      return const Color(0xFF2196F3);
    }
    return const Color(0xFF9E9E9E);
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final color = _actionColor(log.action);
    final fmt = DateFormat('dd MMM yy, HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.actionLabel,
                          style: GoogleFonts.outfit(
                              color: const Color(0xDEFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.actorName ?? log.actorId ?? 'System',
                          style: GoogleFonts.outfit(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmt.format(log.createdAt.toIST()),
                        style: GoogleFonts.outfit(
                            color: Colors.white24, fontSize: 10),
                      ),
                      if (log.entityType != null)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(log.entityType!,
                              style: GoogleFonts.outfit(
                                  color: Colors.white30, fontSize: 9)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white24,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && log.metadata.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(log.metadata),
                  style: GoogleFonts.sourceCodePro(
                      color: Colors.green.shade300, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
