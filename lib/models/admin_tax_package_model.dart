// ============================================================================
// admin_tax_package_model.dart — Enything Admin God Mode CA & Tax Package Model
// ============================================================================
// Authority: CGST Act 2017 (§52, §9(5), GSTR-8, GSTR-1, GSTR-3B) & IT Act (§194-O)
// ============================================================================

class AdminTaxPackage {
  final int month;
  final int year;
  final double grossGmv;
  final double s9_5Gst;
  final double deliveryGst;
  final double platformGst;
  final double commissionGst;
  final double enythingCommissionBase;
  final double enythingTotalPayable;
  final double nonFoodGst;
  final double tcsCollected;
  final double tdsCollected;
  final double sellerPayouts;
  final double riderEarnings;
  final double gatewayFees;
  final double gatewayClaimableItc;
  final double netCashPayableGovt;
  final int deliveredOrders;
  final List<VendorTaxScheduleRow> vendorSchedule;
  final TaxComplianceStats complianceStats;

  const AdminTaxPackage({
    required this.month,
    required this.year,
    required this.grossGmv,
    required this.s9_5Gst,
    required this.deliveryGst,
    required this.platformGst,
    required this.commissionGst,
    required this.enythingCommissionBase,
    required this.enythingTotalPayable,
    required this.nonFoodGst,
    required this.tcsCollected,
    required this.tdsCollected,
    required this.sellerPayouts,
    required this.riderEarnings,
    required this.gatewayFees,
    required this.gatewayClaimableItc,
    required this.netCashPayableGovt,
    required this.deliveredOrders,
    required this.vendorSchedule,
    required this.complianceStats,
  });

  factory AdminTaxPackage.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final stats = json['compliance_stats'] as Map<String, dynamic>? ?? {};
    final vendorsRaw = json['vendor_schedule'] as List<dynamic>? ?? [];

    return AdminTaxPackage(
      month: (period['month'] as num?)?.toInt() ?? DateTime.now().month,
      year: (period['year'] as num?)?.toInt() ?? DateTime.now().year,
      grossGmv: (summary['gross_gmv'] as num?)?.toDouble() ?? 0.0,
      s9_5Gst: (summary['s9_5_gst'] as num?)?.toDouble() ?? 0.0,
      deliveryGst: (summary['delivery_gst'] as num?)?.toDouble() ?? 0.0,
      platformGst: (summary['platform_gst'] as num?)?.toDouble() ?? 0.0,
      commissionGst: (summary['commission_gst'] as num?)?.toDouble() ?? 0.0,
      enythingCommissionBase:
          (summary['enything_commission_base'] as num?)?.toDouble() ?? 0.0,
      enythingTotalPayable:
          (summary['enything_total_payable'] as num?)?.toDouble() ?? 0.0,
      nonFoodGst: (summary['non_food_gst'] as num?)?.toDouble() ?? 0.0,
      tcsCollected: (summary['tcs_collected'] as num?)?.toDouble() ?? 0.0,
      tdsCollected: (summary['tds_collected'] as num?)?.toDouble() ?? 0.0,
      sellerPayouts: (summary['seller_payouts'] as num?)?.toDouble() ?? 0.0,
      riderEarnings: (summary['rider_earnings'] as num?)?.toDouble() ?? 0.0,
      gatewayFees: (summary['gateway_fees'] as num?)?.toDouble() ?? 0.0,
      gatewayClaimableItc:
          (summary['gateway_claimable_itc'] as num?)?.toDouble() ?? 0.0,
      netCashPayableGovt:
          (summary['net_cash_payable_govt'] as num?)?.toDouble() ?? 0.0,
      deliveredOrders: (summary['delivered_orders'] as num?)?.toInt() ?? 0,
      vendorSchedule: vendorsRaw
          .map((v) =>
              VendorTaxScheduleRow.fromJson(v as Map<String, dynamic>))
          .toList(),
      complianceStats: TaxComplianceStats.fromJson(stats),
    );
  }
}

class VendorTaxScheduleRow {
  final String shopId;
  final String shopName;
  final String category;
  final bool isDeemedSupplier;
  final String gstNumber;
  final String panNumber;
  final String ownerName;
  final String ownerPhone;
  final int orderCount;
  final double grossSales;
  final double nonFoodGst;
  final double s9_5Gst;
  final double tcsAmount;
  final double tdsAmount;
  final double commission;
  final double commissionGst;
  final double sellerPayout;
  final String invoiceNumber;
  final String complianceStatus;

  const VendorTaxScheduleRow({
    required this.shopId,
    required this.shopName,
    required this.category,
    required this.isDeemedSupplier,
    required this.gstNumber,
    required this.panNumber,
    required this.ownerName,
    required this.ownerPhone,
    required this.orderCount,
    required this.grossSales,
    required this.nonFoodGst,
    required this.s9_5Gst,
    required this.tcsAmount,
    required this.tdsAmount,
    required this.commission,
    required this.commissionGst,
    required this.sellerPayout,
    required this.invoiceNumber,
    required this.complianceStatus,
  });

  bool get hasValidGstin =>
      gstNumber.isNotEmpty && gstNumber != 'NOT_PROVIDED' && gstNumber.length == 15;

  bool get hasValidPan =>
      panNumber.isNotEmpty && panNumber != 'NOT_PROVIDED' && panNumber.length == 10;

  bool get isActionRequired => complianceStatus == 'ACTION_REQUIRED';

  factory VendorTaxScheduleRow.fromJson(Map<String, dynamic> json) {
    return VendorTaxScheduleRow(
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? 'Shop',
      category: json['category']?.toString() ?? 'Retail',
      isDeemedSupplier: json['is_deemed_supplier'] as bool? ?? false,
      gstNumber: json['gst_number']?.toString() ?? 'NOT_PROVIDED',
      panNumber: json['pan_number']?.toString() ?? 'NOT_PROVIDED',
      ownerName: json['owner_name']?.toString() ?? 'Unknown',
      ownerPhone: json['owner_phone']?.toString() ?? 'N/A',
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
      grossSales: (json['gross_sales'] as num?)?.toDouble() ?? 0.0,
      nonFoodGst: (json['non_food_gst'] as num?)?.toDouble() ?? 0.0,
      s9_5Gst: (json['s9_5_gst'] as num?)?.toDouble() ?? 0.0,
      tcsAmount: (json['tcs_amount'] as num?)?.toDouble() ?? 0.0,
      tdsAmount: (json['tds_amount'] as num?)?.toDouble() ?? 0.0,
      commission: (json['commission'] as num?)?.toDouble() ?? 0.0,
      commissionGst: (json['commission_gst'] as num?)?.toDouble() ?? 0.0,
      sellerPayout: (json['seller_payout'] as num?)?.toDouble() ?? 0.0,
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      complianceStatus: json['compliance_status']?.toString() ?? 'ACTION_REQUIRED',
    );
  }
}

class TaxComplianceStats {
  final int totalActiveShops;
  final int foodDeemedCount;
  final int compliantGstCount;
  final int exemptUnregisteredCount;
  final int actionRequiredCount;

  const TaxComplianceStats({
    required this.totalActiveShops,
    required this.foodDeemedCount,
    required this.compliantGstCount,
    required this.exemptUnregisteredCount,
    required this.actionRequiredCount,
  });

  factory TaxComplianceStats.fromJson(Map<String, dynamic> json) {
    return TaxComplianceStats(
      totalActiveShops: (json['total_active_shops'] as num?)?.toInt() ?? 0,
      foodDeemedCount: (json['food_deemed_count'] as num?)?.toInt() ?? 0,
      compliantGstCount: (json['compliant_gst_count'] as num?)?.toInt() ?? 0,
      exemptUnregisteredCount:
          (json['exempt_unregistered_count'] as num?)?.toInt() ?? 0,
      actionRequiredCount: (json['action_required_count'] as num?)?.toInt() ?? 0,
    );
  }
}
