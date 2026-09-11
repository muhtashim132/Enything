// ============================================================================
// tax_export_service.dart — Enything CA Compliance Package & CSV Export Service
// ============================================================================
// Authority: CGST Act 2017 (§52, §9(5), GSTR-8, GSTR-1, GSTR-3B) & IT Act (§194-O)
// ============================================================================

import 'package:intl/intl.dart';
import '../models/admin_tax_package_model.dart';

class TaxExportService {
  TaxExportService._();
  static final TaxExportService instance = TaxExportService._();

  static final NumberFormat _currencyFmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final NumberFormat _rawNumFmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 2);

  static String _f(double val) => _currencyFmt.format(val);
  static String _raw(double val) => _rawNumFmt.format(val).trim();

  // ── 1. GSTR-8 Table 3 CSV Export (Government of India GST Portal Format) ─────
  static String generateGstr8Csv(AdminTaxPackage pkg) {
    final sb = StringBuffer();
    // Headers matching GST Portal Offline Utility for GSTR-8 Table 3
    sb.writeln(
        'GSTIN of Supplier,Trade Name,Category,Gross Taxable Supplies (INR),Returns / Cancellations (INR),Net Value of Taxable Supplies (INR),Central Tax CGST 0.25% (INR),State Tax SGST 0.25% (INR),Integrated Tax IGST (INR),Total TCS Collected (INR),Compliance Note');

    for (final row in pkg.vendorSchedule) {
      // Exclude deemed food supplier from TCS Table 3 (or mark as exempt)
      final isFood = row.isDeemedSupplier;
      final gstin = row.gstNumber;
      final netVal = row.grossSales;
      final cgst = isFood ? 0.0 : (row.tcsAmount / 2.0);
      final sgst = isFood ? 0.0 : (row.tcsAmount / 2.0);
      final totalTcs = isFood ? 0.0 : row.tcsAmount;
      final note = isFood
          ? 'EXEMPT: Section 9(5) Deemed Food Supplier'
          : (row.hasValidGstin
              ? 'ACTIVE GST REGISTERED'
              : 'EXEMPT UNREGISTERED (Notif 34/2023-CT)');

      sb.writeln(
          '"$gstin","${_escape(row.shopName)}","${_escape(row.category)}",${_raw(row.grossSales)},0.00,${_raw(netVal)},${_raw(cgst)},${_raw(sgst)},0.00,${_raw(totalTcs)},"$note"');
    }

    return sb.toString();
  }

  // ── 2. Income Tax Section 194-O TDS CSV Export (Form 26Q Annexure) ──────────
  static String generateSection194OTdsCsv(AdminTaxPackage pkg) {
    final sb = StringBuffer();
    sb.writeln(
        'PAN of Seller,Legal Trade Name,Owner Name,Contact Phone,Category,Gross Consideration Paid (INR),TDS Rate,TDS Amount Deducted (INR),Net Payout Transferred (INR),Compliance Status');

    for (final row in pkg.vendorSchedule) {
      final tdsRate = row.hasValidPan ? '0.1%' : '5% (§206AA Penalty)';
      sb.writeln(
          '"${row.panNumber}","${_escape(row.shopName)}","${_escape(row.ownerName)}","${row.ownerPhone}","${_escape(row.category)}",${_raw(row.grossSales)},"$tdsRate",${_raw(row.tdsAmount)},${_raw(row.sellerPayout)},"${row.complianceStatus}"');
    }

    return sb.toString();
  }

  // ── 3. GSTR-1 Table 4 B2B Commission Tax Invoices Register ─────────────────
  static String generateCommissionInvoicesCsv(AdminTaxPackage pkg) {
    final sb = StringBuffer();
    final lastDay = DateTime(pkg.year, pkg.month + 1, 0).day;
    final invoiceDate =
        '$lastDay/${pkg.month.toString().padLeft(2, '0')}/${pkg.year}';

    sb.writeln(
        'Invoice Number,Invoice Date,Recipient GSTIN,Recipient Trade Name,State Code / POS,SAC Code,Taxable Commission Base (INR),GST Rate,CGST 9% (INR),SGST 9% (INR),Total Invoice Value (INR)');

    for (final row in pkg.vendorSchedule) {
      final base = row.commission;
      final cgst = row.commissionGst / 2.0;
      final sgst = row.commissionGst / 2.0;
      final total = base + row.commissionGst;

      sb.writeln(
          '"${row.invoiceNumber}","$invoiceDate","${row.gstNumber}","${_escape(row.shopName)}","Jammu & Kashmir (01)","9985",${_raw(base)},18%,${_raw(cgst)},${_raw(sgst)},${_raw(total)}');
    }

    return sb.toString();
  }

  // ── 4. Comprehensive CA God Mode Report (WhatsApp & Email Ready) ────────────
  static String generateFullCaTextReport(AdminTaxPackage pkg) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final monthName = months[pkg.month - 1];

    final sb = StringBuffer();
    sb.writeln('════════════════════════════════════════════════════════════════');
    sb.writeln('ENYTHING — CHARTERED ACCOUNTANT MONTHLY COMPLIANCE DOSSIER');
    sb.writeln('Period   : $monthName ${pkg.year}');
    sb.writeln('Platform : Enything Hyperlocal Marketplace');
    sb.writeln('Orders   : ${pkg.deliveredOrders} delivered orders');
    sb.writeln('Generated: ${DateTime.now().toString().substring(0, 16)}');
    sb.writeln('════════════════════════════════════════════════════════════════');
    sb.writeln();

    // ── SECTION 1: GSTR-3B CASH TAX RECONCILIATION ──
    sb.writeln('┌──────────────────────────────────────────────────────────────┐');
    sb.writeln('│ SECTION 1: GSTR-3B TAX LIABILITY & CASH RECONCILIATION       │');
    sb.writeln('└──────────────────────────────────────────────────────────────┘');
    sb.writeln('Gross GMV (Base Sales Facilitated)  : ${_f(pkg.grossGmv)}');
    sb.writeln('1. S.9(5) Food GST (Deemed Supplier): ${_f(pkg.s9_5Gst)}  (Table 3.1.1(i))');
    sb.writeln('2. Delivery Service GST (SAC 9965)  : ${_f(pkg.deliveryGst)}');
    sb.writeln('3. Platform Convenience Fee GST     : ${_f(pkg.platformGst)}');
    sb.writeln('4. Commission GST (18% on fees)     : ${_f(pkg.commissionGst)}');
    sb.writeln('────────────────────────────────────────────────────────────────');
    sb.writeln('TOTAL OUTPUT GST PAYABLE            : ${_f(pkg.enythingTotalPayable)}');
    sb.writeln('LESS: Razorpay Gateway Input Credit : -${_f(pkg.gatewayClaimableItc)} (Claimable ITC via GSTR-2B)');
    sb.writeln('════════════════════════════════════════════════════════════════');
    sb.writeln('★ NET CASH TAX PAYABLE TO GOVT      : ${_f(pkg.netCashPayableGovt)}');
    sb.writeln('  (Deposit via PMT-06 challan by 20th of the month)');
    sb.writeln();

    // ── SECTION 2: GSTR-8 TCS SUMMARY ──
    sb.writeln('┌──────────────────────────────────────────────────────────────┐');
    sb.writeln('│ SECTION 2: GST TCS STATEMENT (§52 CGST ACT — FORM GSTR-8)     │');
    sb.writeln('└──────────────────────────────────────────────────────────────┘');
    sb.writeln('Total Non-Food Taxable Base Sales   : ${_f(pkg.grossGmv)}');
    sb.writeln('GST TCS Withheld at Source (0.5%)   : ${_f(pkg.tcsCollected)}');
    sb.writeln('  • CGST (0.25%)                    : ${_f(pkg.tcsCollected / 2)}');
    sb.writeln('  • SGST (0.25%)                    : ${_f(pkg.tcsCollected / 2)}');
    sb.writeln('Legal Basis: CGST Act §52 & Notification 15/2024-CT');
    sb.writeln('• S.9(5) Food & 0% GST categories are strictly exempt from TCS.');
    sb.writeln('• File Form GSTR-8 by 10th. TCS credits to vendor electronic cash ledger.');
    sb.writeln();

    // ── SECTION 3: SECTION 194-O INCOME TAX TDS ──
    sb.writeln('┌──────────────────────────────────────────────────────────────┐');
    sb.writeln('│ SECTION 3: INCOME TAX TDS STATEMENT (§194-O — FORM 26Q)      │');
    sb.writeln('└──────────────────────────────────────────────────────────────┘');
    sb.writeln('Total Consideration Facilitated     : ${_f(pkg.grossGmv)}');
    sb.writeln('TDS Withheld (0.1% Finance Act 2024): ${_f(pkg.tdsCollected)}');
    sb.writeln('• Deposit via Challan ITNS 281 by 7th of next month.');
    sb.writeln('• File quarterly Form 26Q. Vendors view credit in Form 26AS/AIS.');
    sb.writeln();

    // ── SECTION 4: VENDOR-WISE TAX BREAKDOWN ──
    sb.writeln('┌──────────────────────────────────────────────────────────────┐');
    sb.writeln('│ SECTION 4: VENDOR-WISE TAX & COMPLIANCE BREAKDOWN            │');
    sb.writeln('└──────────────────────────────────────────────────────────────┘');

    for (int i = 0; i < pkg.vendorSchedule.length; i++) {
      final v = pkg.vendorSchedule[i];
      sb.writeln('${i + 1}. ${v.shopName.toUpperCase()} [${v.category}]');
      sb.writeln('   GSTIN: ${v.gstNumber} | PAN: ${v.panNumber}');
      sb.writeln('   Owner: ${v.ownerName} (${v.ownerPhone})');
      sb.writeln('   Orders: ${v.orderCount} delivered | Base Sales: ${_f(v.grossSales)}');
      if (v.isDeemedSupplier) {
        sb.writeln('   Deemed Food GST (S.9(5)): ${_f(v.s9_5Gst)} (Enything deposits directly)');
      } else {
        sb.writeln('   Non-Food Product GST: ${_f(v.nonFoodGst)} (Transferred to vendor for filing)');
        sb.writeln('   GST TCS Withheld (§52, 0.5%): ${_f(v.tcsAmount)} (Reported in GSTR-8)');
      }
      sb.writeln('   IT TDS Withheld (§194-O, 0.1%): ${_f(v.tdsAmount)}');
      sb.writeln('   Commission Base: ${_f(v.commission)} | GST 18%: ${_f(v.commissionGst)}');
      sb.writeln('   Commission Invoice: ${v.invoiceNumber}');
      sb.writeln('   Compliance Status: ${v.complianceStatus}');
      sb.writeln('   ─────────────────────────────────────────────────────────');
    }

    // ── SECTION 5: COMPLIANCE MONITOR ──
    final stats = pkg.complianceStats;
    sb.writeln();
    sb.writeln('┌──────────────────────────────────────────────────────────────┐');
    sb.writeln('│ SECTION 5: COMPLIANCE AUDIT & RED-FLAGS                      │');
    sb.writeln('└──────────────────────────────────────────────────────────────┘');
    sb.writeln('Total Active Vendors in Period     : ${stats.totalActiveShops}');
    sb.writeln('• 🟢 GST Registered Vendors        : ${stats.compliantGstCount}');
    sb.writeln('• 🔵 Food / Section 9(5) Vendors   : ${stats.foodDeemedCount}');
    sb.writeln('• 🟡 Exempt / Enrolled (<₹40L)     : ${stats.exemptUnregisteredCount}');
    sb.writeln('• 🔴 Action Required (Missing Docs): ${stats.actionRequiredCount}');

    if (stats.actionRequiredCount > 0) {
      sb.writeln();
      sb.writeln('⚠️ URGENT: The following vendors are missing GSTIN/PAN:');
      for (final v in pkg.vendorSchedule.where((r) => r.isActionRequired)) {
        sb.writeln('   - ${v.shopName} (${v.category}): GSTIN=${v.gstNumber}, PAN=${v.panNumber}, Phone=${v.ownerPhone}');
      }
      sb.writeln('   Contact these vendors before filing GSTR-8 on the 10th.');
    } else {
      sb.writeln('✓ All vendors have verified identity and tax numbers on file.');
    }

    sb.writeln('════════════════════════════════════════════════════════════════');
    return sb.toString();
  }

  static String _escape(String text) => text.replaceAll('"', '""');
}
