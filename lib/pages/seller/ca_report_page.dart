import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive_layout.dart';

// ============================================================================
// CA Report Page — Monthly GST, TCS & TDS Report for Chartered Accountant
// ============================================================================
// Produces the 5 documents required by your CA every month:
//   Doc 1 — Sales Register       → GSTR-1 & GSTR-3B filing
//   Doc 2 — Commission Invoice   → Input Tax Credit (ITC) claim
//   Doc 3 — Section 9(5) Statement → Proves Enything paid food GST
//   Doc 4 — TDS Statement (§194-O) → Income Tax credit via Form 26AS
//   Doc 5 — GST TCS Statement (§52) → Only if non-food orders exist; GSTR-8 credit
// ============================================================================

class CaReportPage extends StatefulWidget {
  const CaReportPage({super.key});
  @override
  State<CaReportPage> createState() => _CaReportPageState();
}

class _CaReportPageState extends State<CaReportPage> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _isLoading = true;

  // Month selector
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Aggregated values from DB
  double _totalBaseSales = 0;
  double _nonFoodGst = 0;      // Seller remits (GSTR-1 liability)
  double _s9_5Gst = 0;         // Enything remits (exempt for seller)
  double _deliveryGst = 0;
  double _platformGst = 0;
  double _tcsDeducted = 0;     // GST TCS §52 — GSTR-8 credit in GSTR-2B (only on taxable non-food)
  double _tdsDeducted = 0;     // Income Tax TDS §194-O — Form 26AS credit (all categories, 0.1%)
  double _commission = 0;
  double _sellerPayout = 0;
  double _grandCollected = 0;
  double _gatewayFees = 0;
  int _deliveredOrders = 0;
  String _shopName = '';
  List<Map<String, dynamic>> _monthlyOrders = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      final shops = await _supabase
          .from('shops')
          .select('id, name')
          .eq('seller_id', auth.currentUserId ?? '');

      if ((shops as List).isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final shopId = shops.first['id'] as String;
      _shopName = shops.first['name'] ?? 'Your Shop';

      final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

      final orders = await _supabase
          .from('orders')
          .select()
          .eq('shop_id', shopId)
          .eq('status', 'delivered')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      double baseSales = 0, nonFood = 0, s9_5 = 0, delGst = 0, platGst = 0,
          tcs = 0, comm = 0, payout = 0, grand = 0, gw = 0, tds = 0;

      for (final o in (orders as List)) {
        baseSales += (o['total_amount'] ?? 0.0).toDouble();
        nonFood   += (o['non_food_gst_amount'] ?? 0.0).toDouble();
        s9_5      += (o['s9_5_gst_amount'] ?? 0.0).toDouble();
        delGst    += (o['gst_delivery'] ?? 0.0).toDouble();
        platGst   += (o['gst_platform'] ?? 0.0).toDouble();
        tcs       += (o['tcs_amount'] ?? 0.0).toDouble();
        comm      += (o['enything_commission'] ?? 0.0).toDouble();
        payout    += (o['seller_payout'] ?? 0.0).toDouble();
        grand     += (o['grand_total_collected'] ?? 0.0).toDouble();
        gw        += (o['gateway_deduction'] ?? 0.0).toDouble();
        tds       += (o['tds_amount'] ?? 0.0).toDouble();
      }

      setState(() {
        _totalBaseSales = baseSales;
        _nonFoodGst     = nonFood;
        _s9_5Gst        = s9_5;
        _deliveryGst    = delGst;
        _platformGst    = platGst;
        _tcsDeducted    = tcs;
        _tdsDeducted    = tds;
        _commission     = comm;
        _sellerPayout   = payout;
        _grandCollected = grand;
        _gatewayFees    = gw;
        _deliveredOrders = orders.length;
        _monthlyOrders  = List<Map<String, dynamic>>.from(orders);
        _isLoading      = false;
      });
    } catch (e) {
      debugPrint('CaReport error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── Month navigation ─────────────────────────────────────────────────────

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadReport();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return;
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadReport();
  }

  String get _monthLabel {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  // ── Clipboard helpers ────────────────────────────────────────────────────

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard ✓', style: GoogleFonts.outfit()),
        backgroundColor: const Color(0xFF2F9E44),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _buildFullReport() {
    final commGst = _commission * 0.18;
    final tcsBlock = _tcsDeducted > 0
        ? '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\n'
            'DOC 5 \u2014 GST TCS STATEMENT (\u00a752 CGST \u2014 Non-food only)\n'
            '\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\n'
            'GST TCS Deducted by Enything (1%): \u20b9${_f(_tcsDeducted)}\n'
            'Legal basis: CGST Act \u00a752 (taxable non-food supplies only)\n'
            '\u00a79(5) food and 0% GST categories are exempt from TCS.\n'
            '\u2192 Enything files GSTR-8 by 10th of next month.\n'
            '\u2192 Claim \u20b9${_f(_tcsDeducted)} as credit in your GSTR-2B after Enything files GSTR-8.\n'
        : '(No GST TCS \u2014 all your orders are food/\u00a79(5) or 0% GST categories)';
    
    return '''
ENYTHING \u2014 CA MONTHLY TAX REPORT
Period : $_monthLabel
Shop   : $_shopName
Orders : $_deliveredOrders delivered
Generated: ${DateTime.now().toString().substring(0, 16)}

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
DOC 1 \u2014 SALES REGISTER (for GSTR-1 / 3B)
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
Taxable Base Sales (excl. GST) : \u20b9${_f(_totalBaseSales)}
GST Seller Must Remit (non-food): \u20b9${_f(_nonFoodGst)}
GST Paid by Enything \u2014 S.9(5) Food : \u20b9${_f(_s9_5Gst)}  \u2190 YOU OWE NOTHING ON THIS
Total GST in Orders             : \u20b9${_f(_nonFoodGst + _s9_5Gst)}

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
DOC 2 \u2014 COMMISSION INVOICE (for ITC)
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
Enything Commission                : \u20b9${_f(_commission)}
GST on Commission (18%)         : \u20b9${_f(commGst)}
Total Commission + GST          : \u20b9${_f(_commission + commGst)}
\u2192 Claim \u20b9${_f(commGst)} as Input Tax Credit in GSTR-3B

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
DOC 3 \u2014 SECTION 9(5) STATEMENT
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
Food/Restaurant GST paid by Enything: \u20b9${_f(_s9_5Gst)}
Legal basis: CGST Notification 17/2021-CT(R) \u00a79(5)
You are NOT the deemed supplier for these orders.
Do NOT include this in your GSTR-1.

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
DOC 4 \u2014 INCOME TAX TDS (\u00a7194-O \u2014 Finance Act 2024)
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
TDS Deducted by Enything (0.1%)    : \u20b9${_f(_tdsDeducted)}
Legal basis: IT Act \u00a7194-O (rate 0.1% eff. Oct 1 2024)
\u2192 Enything files Form 26QE by 7th of next month.
\u2192 Claim this as credit in your Form 26AS / AIS after Enything files.

$tcsBlock
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
PAYOUT RECONCILIATION
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
Gross Collected from Customers  : \u20b9${_f(_grandCollected)}
Seller Net Payout (incl. GST)   : \u20b9${_f(_sellerPayout)}
Enything Commission                : \u20b9${_f(_commission)}
IT TDS Withheld (\u00a7194-O, 0.1%)  : \u20b9${_f(_tdsDeducted)}
GST TCS Withheld (\u00a752, 1%)      : \u20b9${_f(_tcsDeducted)}
Delivery GST (Enything remits)     : \u20b9${_f(_deliveryGst)}
Platform GST (Enything remits)     : \u20b9${_f(_platformGst)}
Gateway Fees                    : \u20b9${_f(_gatewayFees)}
''';
  }

  String _f(double v) => v.toStringAsFixed(2);

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        foregroundColor: Colors.white,
        title: Text('CA Tax Report',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, color: Colors.white70),
            tooltip: 'Copy Full Report',
            onPressed: _isLoading ? null : () => _copyText(_buildFullReport()),
          ),
        ],
      ),
      body: MaxWidthContainer(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4C6EF5)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: [
                // ── Month Selector ────────────────────────────────────────
                _monthSelector(),
                const SizedBox(height: 8),
                // Summary pill
                _summaryPill(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _monthlyOrders.isEmpty ? null : _showTransactionsBottomSheet,
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: Text('View Detailed Transactions',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Document 1 — Sales Register ───────────────────────────
                _docCard(
                  docNumber: '01',
                  title: 'Sales Register',
                  subtitle: 'File in GSTR-1 & GSTR-3B by 11th / 20th',
                  accentColor: const Color(0xFF4C6EF5),
                  rows: [
                    _row('Taxable Base Sales (excl. GST)', _totalBaseSales),
                    _row('GST You Must Remit (non-food)', _nonFoodGst,
                        color: const Color(0xFFFF6B6B)),
                    _row('GST Paid by Enything — S.9(5) Food', _s9_5Gst,
                        color: const Color(0xFF51CF66), tag: 'NOT YOUR LIABILITY'),
                    _divider(),
                    _row('Total Orders (Delivered)', _deliveredOrders.toDouble(),
                        isCount: true),
                  ],
                  copyText: '''Sales Register — $_monthLabel
Taxable Base Sales : ₹${_f(_totalBaseSales)}
GST Seller Remits  : ₹${_f(_nonFoodGst)}
GST Enything S.9(5)   : ₹${_f(_s9_5Gst)}  (not your liability)
Orders Delivered   : $_deliveredOrders''',
                ),
                // ── Document 2 — Commission Invoice ──────────────────────
                _docCard(
                  docNumber: '02',
                  title: 'Commission Invoice',
                  subtitle: 'Claim GST on commission as ITC in GSTR-3B',
                  accentColor: const Color(0xFFCC5DE8),
                  rows: [
                    _row('Enything Commission', _commission),
                    _row('GST on Commission (18%)', _commission * 0.18,
                        color: const Color(0xFF51CF66), tag: 'CLAIM AS ITC'),
                    _divider(),
                    _row('Total Invoice Amount', _commission * 1.18, isBold: true),
                  ],
                  copyText: '''Commission Invoice — $_monthLabel
Enything Commission   : ₹${_f(_commission)}
GST on Commission  : ₹${_f(_commission * 0.18)}  ← claim as ITC
Total              : ₹${_f(_commission * 1.18)}''',
                ),
                // ── Document 3 — Section 9(5) ─────────────────────────────
                _docCard(
                  docNumber: '03',
                  title: 'Section 9(5) Statement',
                  subtitle: 'Proves Enything paid food GST — exclude from your GSTR-1',
                  accentColor: const Color(0xFF51CF66),
                  rows: [
                    _row('Food/Restaurant GST — Enything Remitted', _s9_5Gst,
                        color: const Color(0xFF51CF66)),
                    _row('Delivery GST — Enything Remitted', _deliveryGst,
                        color: const Color(0xFF51CF66)),
                    _row('Platform GST — Enything Remitted', _platformGst,
                        color: const Color(0xFF51CF66)),
                    _divider(),
                    _row('Total GST Enything Pays to Govt',
                        _s9_5Gst + _deliveryGst + _platformGst,
                        isBold: true, color: const Color(0xFF51CF66)),
                  ],
                  copyText: '''S.9(5) Statement — $_monthLabel
Legal basis: CGST Notification 17/2021-CT(R)
Food GST Enything remits  : ₹${_f(_s9_5Gst)}
Delivery GST           : ₹${_f(_deliveryGst)}
Platform GST           : ₹${_f(_platformGst)}
Total Enything Pays       : ₹${_f(_s9_5Gst + _deliveryGst + _platformGst)}
Do NOT include food GST in your GSTR-1.''',
                ),
                // ── Document 4 — Income Tax TDS Statement (§194-O) ──────────────────
                _docCard(
                  docNumber: '04',
                  title: 'TDS Statement (Income Tax §194-O)',
                  subtitle: 'Claim this as credit in Form 26AS after Enything files 26QE',
                  accentColor: const Color(0xFF4DABF7),
                  rows: [
                    _row('IT TDS Withheld by Enything (0.1%)', _tdsDeducted,
                        color: const Color(0xFF4DABF7), tag: 'FORM 26AS CREDIT'),
                    _row('Gross Sales Basis (all categories)', _totalBaseSales),
                    _divider(),
                    _infoRow(
                      'Finance Act 2024: Rate 0.1% (was 1%) effective Oct 1 2024.\n'
                      'Applies to ALL categories — food, retail, pharmacy. No exceptions.\n'
                      'Enything files Form 26QE by 7th of next month. Claim in Form 26AS / AIS.',
                    ),
                  ],
                  copyText: '''TDS Statement (§194-O) — $_monthLabel
Legal basis: IT Act §194-O (Finance Act 2024, rate 0.1% eff. Oct 1 2024)
TDS Deducted (0.1%) : ₹${_f(_tdsDeducted)}
Gross Sales Basis   : ₹${_f(_totalBaseSales)}
→ Enything files Form 26QE by 7th of next month.
→ Claim ₹${_f(_tdsDeducted)} as credit in your Form 26AS / AIS.''',
                ),
                // ── Document 5 — GST TCS Statement (§52) — conditional ──────────────
                // Only shown when TCS > 0 (i.e., seller has taxable non-food orders).
                // Pure restaurant/food sellers will never see this card.
                if (_tcsDeducted > 0)
                  _docCard(
                    docNumber: '05',
                    title: 'GST TCS Statement (§52 CGST)',
                    subtitle: 'Only on taxable non-food orders — claim in GSTR-2B',
                    accentColor: const Color(0xFFF4C542),
                    rows: [
                      _row('GST TCS Withheld by Enything (1%)', _tcsDeducted,
                          color: const Color(0xFFF4C542), tag: 'GSTR-2B CREDIT'),
                      _row('Net Taxable Supply Basis (non-food)', _totalBaseSales - (_s9_5Gst / 0.05).clamp(0.0, _totalBaseSales)),
                      _divider(),
                      _infoRow(
                        'CGST §52: TCS = 1% on taxable non-food supplies only.\n'
                        '§9(5) food & 0% GST categories (Fruits, Butcher, Fish) are exempt from TCS.\n'
                        'Enything files GSTR-8 by 10th of next month. Claim credit in GSTR-2B after that.',
                      ),
                    ],
                    copyText: '''GST TCS Statement (§52) — $_monthLabel
Legal basis: CGST Act §52 (taxable non-food supplies only)
GST TCS Deducted (1%)     : ₹${_f(_tcsDeducted)}
Taxable Supply Basis      : ₹${_f(_totalBaseSales - (_s9_5Gst / 0.05).clamp(0.0, _totalBaseSales))}
→ §9(5) food orders and 0% GST categories are excluded from TCS.
→ Enything files GSTR-8 by 10th. Claim ₹${_f(_tcsDeducted)} in your GSTR-2B.''',
                  ),
                // ── Payout Reconciliation ─────────────────────────────────
                _docCard(
                  docNumber: '✓',
                  title: 'Payout Reconciliation',
                  subtitle: 'Match this with your bank statement',
                  accentColor: const Color(0xFFFF8C42),
                  rows: [
                    _row('Gross Collected from Customers', _grandCollected),
                    _row('Seller Net Payout (incl. GST)', _sellerPayout,
                        color: const Color(0xFF51CF66), isBold: true),
                    _row('Enything Commission', _commission),
                    _row('IT TDS Withheld (§194-O, 0.1%)', _tdsDeducted),
                    if (_tcsDeducted > 0)
                      _row('GST TCS Withheld (§52, 1%)', _tcsDeducted),
                    _row('Gateway Fees (Razorpay)', _gatewayFees),
                  ],
                  copyText: 'Payout Reconciliation — $_monthLabel\n'
                      'Gross Collected    : ₹${_f(_grandCollected)}\n'
                      'Seller Payout      : ₹${_f(_sellerPayout)}\n'
                      'Enything Commission   : ₹${_f(_commission)}\n'
                      'IT TDS (§194-O)    : ₹${_f(_tdsDeducted)}\n'
                      '${_tcsDeducted > 0 ? "GST TCS (§52)      : ₹${_f(_tcsDeducted)}\n" : ""}'
                      'Gateway Fees       : ₹${_f(_gatewayFees)}',
                ),

                // ── Copy Full Report Button ───────────────────────────────
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _copyText(_buildFullReport()),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: Text('Copy Full Report for CA',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C6EF5),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '📌  Share this text report with your CA on WhatsApp or email.\n'
                  '    Enything files Form 26QE (TDS) by the 7th & GSTR-8 (GST TCS) by the 10th.\n'
                  '    Check Form 26AS for TDS credit; check GSTR-2B for GST TCS credit.',
                  style: GoogleFonts.outfit(
                      color: Colors.white38, fontSize: 11, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
        ),
    );
  }

  void _showTransactionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141425),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Detailed Transactions',
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _monthlyOrders.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final order = _monthlyOrders[index];
                      final orderId = order['id'].toString().substring(0, 8);
                      final baseAmount =
                          (order['total_amount'] ?? 0.0).toDouble();
                      final nonFoodGst =
                          (order['non_food_gst_amount'] ?? 0.0).toDouble();
                      final s9_5Gst =
                          (order['s9_5_gst_amount'] ?? 0.0).toDouble();
                      final totalGst = nonFoodGst + s9_5Gst;
                      final total = baseAmount + totalGst;

                      String gstLabel = '';
                      if (s9_5Gst > 0 && nonFoodGst == 0) {
                        gstLabel = '(Food - Enything pays)';
                      } else if (nonFoodGst > 0 && s9_5Gst == 0) {
                        gstLabel = '(Retail - You pay)';
                      } else if (s9_5Gst > 0 && nonFoodGst > 0) {
                        gstLabel = '(Mixed)';
                      } else {
                        gstLabel = '(0%)';
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #$orderId',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              'Base: ₹${_f(baseAmount)} + GST: ₹${_f(totalGst)} $gstLabel = Total: ₹${_f(total)}',
                              style: GoogleFonts.outfit(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _monthSelector() => Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF141425),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
              onPressed: _prevMonth,
            ),
            Expanded(
              child: Text(
                _monthLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right_rounded,
                  color: _selectedMonth.month == DateTime.now().month &&
                          _selectedMonth.year == DateTime.now().year
                      ? Colors.white24
                      : Colors.white70),
              onPressed: _nextMonth,
            ),
          ],
        ),
      );

  Widget _summaryPill() {
    final isCurrentMonth = _selectedMonth.month == DateTime.now().month &&
        _selectedMonth.year == DateTime.now().year;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF4C6EF5), Color(0xFF364FC7)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_shopName,
                style: GoogleFonts.outfit(
                    color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            Text('$_deliveredOrders orders · ₹${_f(_grandCollected)} collected',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          if (isCurrentMonth)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('LIVE',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ),
        ],
      ),
    );
  }

  Widget _docCard({
    required String docNumber,
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<Widget> rows,
    required String copyText,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF141425),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Text(docNumber,
                        style: GoogleFonts.outfit(
                            color: accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        Text(subtitle,
                            style: GoogleFonts.outfit(
                                color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 18, color: accentColor),
                    tooltip: 'Copy this section',
                    onPressed: () => _copyText(copyText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Rows
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(children: rows),
            ),
          ],
        ),
      );

  Widget _row(String label, double value,
      {Color? color, bool isBold = false, String? tag, bool isCount = false}) {
    final displayValue =
        isCount ? value.toInt().toString() : '₹${_f(value)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.outfit(
                    color: isBold ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight:
                        isBold ? FontWeight.w700 : FontWeight.w400)),
          ),
          if (tag != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (color ?? Colors.white).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tag,
                  style: GoogleFonts.outfit(
                      color: color ?? Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(width: 8),
          ],
          Text(displayValue,
              style: GoogleFonts.outfit(
                  color: color ?? Colors.white,
                  fontSize: isBold ? 15 : 13,
                  fontWeight:
                      isBold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(color: Colors.white12, height: 1),
      );

  Widget _infoRow(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 14, color: Color(0xFFF4C542)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.outfit(
                      color: Colors.white54, fontSize: 11, height: 1.5)),
            ),
          ],
        ),
      );
}
