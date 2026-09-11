-- ============================================================================
-- Migration: 20290000000120_admin_ca_compliance_god_mode_rpc.sql
-- Description: Creates God Mode CA & Tax Compliance Package RPC for Enything Platform Owner
-- Authority: CGST Act 2017 (§52, §9(5), GSTR-8, GSTR-1, GSTR-3B) & Income Tax Act (§194-O)
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_ca_monthly_package(INT, INT);

CREATE OR REPLACE FUNCTION public.admin_get_ca_monthly_package(p_month INT, p_year INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
  v_summary RECORD;
  v_vendor_rows JSONB;
  v_compliance_stats RECORD;
BEGIN
  -- 1. Strict Admin Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- 2. Input Boundary Validation
  IF p_month < 1 OR p_month > 12 THEN
    RAISE EXCEPTION 'Invalid month: %', p_month;
  END IF;
  IF p_year < 2020 OR p_year > 2099 THEN
    RAISE EXCEPTION 'Invalid year: %', p_year;
  END IF;

  -- 3. Monthly date boundaries (Asia/Kolkata standard timezone for Indian GST)
  v_start_date := (make_date(p_year, p_month, 1)::timestamp AT TIME ZONE 'Asia/Kolkata');
  v_end_date := ((make_date(p_year, p_month, 1) + INTERVAL '1 month')::timestamp AT TIME ZONE 'Asia/Kolkata');

  -- 4. High-level Summary for GSTR-3B & Cash Reconciliation
  WITH delivered_orders AS (
    SELECT o.* 
    FROM orders o
    WHERE o.status = 'delivered'
      AND o.created_at >= v_start_date
      AND o.created_at < v_end_date
  )
  SELECT
    COALESCE(SUM(total_amount), 0) AS gross_gmv,
    COALESCE(SUM(s9_5_gst_amount), 0) AS s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) AS delivery_gst,
    COALESCE(SUM(gst_platform), 0) AS platform_gst,
    COALESCE(SUM(enything_commission * 0.18), 0) AS commission_gst,
    COALESCE(SUM(enything_commission), 0) AS enything_commission_base,
    COALESCE(SUM(non_food_gst_amount), 0) AS non_food_gst,
    COALESCE(SUM(tcs_amount), 0) AS tcs_collected,
    COALESCE(SUM(tds_amount), 0) AS tds_collected,
    COALESCE(SUM(seller_payout), 0) AS seller_payouts,
    COALESCE(SUM(rider_earnings), 0) AS rider_earnings,
    COALESCE(SUM(gateway_deduction), 0) AS gateway_fees,
    COUNT(*) AS delivered_orders
  INTO v_summary
  FROM delivered_orders;

  -- 5. Vendor-wise GSTR-8 (Table 3) & Section 194-O TDS Schedule
  WITH delivered_orders AS (
    SELECT o.* 
    FROM orders o
    WHERE o.status = 'delivered'
      AND o.created_at >= v_start_date
      AND o.created_at < v_end_date
  ),
  vendor_agg AS (
    SELECT
      s.id AS shop_id,
      s.name AS shop_name,
      s.category AS category,
      s.gst_number,
      s.pan_number,
      p.full_name AS owner_name,
      p.phone AS owner_phone,
      CASE WHEN LOWER(TRIM(COALESCE(s.category, ''))) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'sweets and mithai', 'tea & coffee', 'ice cream', 'paan shop', 'cafe')
        THEN true ELSE false END AS is_deemed_supplier,
      COUNT(o.id) AS order_count,
      COALESCE(SUM(o.total_amount), 0) AS gross_sales,
      COALESCE(SUM(o.non_food_gst_amount), 0) AS non_food_gst,
      COALESCE(SUM(o.s9_5_gst_amount), 0) AS s9_5_gst,
      COALESCE(SUM(o.tcs_amount), 0) AS tcs_amount,
      COALESCE(SUM(o.tds_amount), 0) AS tds_amount,
      COALESCE(SUM(o.enything_commission), 0) AS commission,
      COALESCE(SUM(o.enything_commission * 0.18), 0) AS commission_gst,
      COALESCE(SUM(o.seller_payout), 0) AS seller_payout
    FROM delivered_orders o
    JOIN shops s ON s.id = o.shop_id
    LEFT JOIN profiles p ON p.id = s.seller_id
    GROUP BY s.id, s.name, s.category, s.gst_number, s.pan_number, p.full_name, p.phone
    ORDER BY s.name ASC
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'shop_id', va.shop_id,
      'shop_name', va.shop_name,
      'category', va.category,
      'is_deemed_supplier', va.is_deemed_supplier,
      'gst_number', COALESCE(NULLIF(trim(va.gst_number), ''), 'NOT_PROVIDED'),
      'pan_number', COALESCE(NULLIF(trim(va.pan_number), ''), 'NOT_PROVIDED'),
      'owner_name', COALESCE(va.owner_name, 'Unknown Owner'),
      'owner_phone', COALESCE(va.owner_phone, 'N/A'),
      'order_count', va.order_count,
      'gross_sales', ROUND(va.gross_sales, 2),
      'non_food_gst', ROUND(va.non_food_gst, 2),
      's9_5_gst', ROUND(va.s9_5_gst, 2),
      'tcs_amount', ROUND(va.tcs_amount, 2),
      'tds_amount', ROUND(va.tds_amount, 2),
      'commission', ROUND(va.commission, 2),
      'commission_gst', ROUND(va.commission_gst, 2),
      'seller_payout', ROUND(va.seller_payout, 2),
      'invoice_number', 'ENY/' || p_year || '-' || LPAD(p_month::text, 2, '0') || '/' || UPPER(SUBSTRING(REPLACE(va.shop_id::text, '-', '') FROM 1 FOR 6)),
      'compliance_status', CASE
        WHEN va.is_deemed_supplier THEN 'FOOD_DEEMED'
        WHEN va.gst_number IS NOT NULL AND length(trim(va.gst_number)) = 15 THEN 'COMPLIANT'
        WHEN va.pan_number IS NOT NULL AND length(trim(va.pan_number)) = 10 THEN 'EXEMPT_UNREGISTERED'
        ELSE 'ACTION_REQUIRED'
      END
    )
  )
  INTO v_vendor_rows
  FROM vendor_agg va;

  -- 6. Real-time Compliance Statistics
  WITH delivered_orders AS (
    SELECT o.shop_id 
    FROM orders o
    WHERE o.status = 'delivered'
      AND o.created_at >= v_start_date
      AND o.created_at < v_end_date
    GROUP BY o.shop_id
  ),
  active_shops AS (
    SELECT 
      s.id,
      s.category,
      s.gst_number,
      s.pan_number,
      CASE WHEN LOWER(TRIM(COALESCE(s.category, ''))) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'sweets and mithai', 'tea & coffee', 'ice cream', 'paan shop', 'cafe')
        THEN true ELSE false END AS is_deemed
    FROM delivered_orders d
    JOIN shops s ON s.id = d.shop_id
  )
  SELECT
    COUNT(*) AS total_active_shops,
    COUNT(CASE WHEN is_deemed THEN 1 END) AS food_deemed_count,
    COUNT(CASE WHEN NOT is_deemed AND gst_number IS NOT NULL AND length(trim(gst_number)) = 15 THEN 1 END) AS compliant_gst_count,
    COUNT(CASE WHEN NOT is_deemed AND (gst_number IS NULL OR length(trim(gst_number)) != 15) AND pan_number IS NOT NULL AND length(trim(pan_number)) = 10 THEN 1 END) AS exempt_unregistered_count,
    COUNT(CASE WHEN NOT is_deemed AND (gst_number IS NULL OR length(trim(gst_number)) != 15) AND (pan_number IS NULL OR length(trim(pan_number)) != 10) THEN 1 END) AS action_required_count
  INTO v_compliance_stats
  FROM active_shops;

  -- 7. Build Output JSON
  v_result := jsonb_build_object(
    'period', jsonb_build_object(
      'month', p_month,
      'year', p_year,
      'start_date', v_start_date,
      'end_date', v_end_date
    ),
    'summary', jsonb_build_object(
      'gross_gmv', ROUND(v_summary.gross_gmv, 2),
      's9_5_gst', ROUND(v_summary.s9_5_gst, 2),
      'delivery_gst', ROUND(v_summary.delivery_gst, 2),
      'platform_gst', ROUND(v_summary.platform_gst, 2),
      'commission_gst', ROUND(v_summary.commission_gst, 2),
      'enything_commission_base', ROUND(v_summary.enything_commission_base, 2),
      'enything_total_payable', ROUND(v_summary.s9_5_gst + v_summary.delivery_gst + v_summary.platform_gst + v_summary.commission_gst, 2),
      'non_food_gst', ROUND(v_summary.non_food_gst, 2),
      'tcs_collected', ROUND(v_summary.tcs_collected, 2),
      'tds_collected', ROUND(v_summary.tds_collected, 2),
      'seller_payouts', ROUND(v_summary.seller_payouts, 2),
      'rider_earnings', ROUND(v_summary.rider_earnings, 2),
      'gateway_fees', ROUND(v_summary.gateway_fees, 2),
      'gateway_claimable_itc', ROUND(v_summary.gateway_fees * 0.18 / 1.18, 2),
      'net_cash_payable_govt', ROUND(
        GREATEST(0, (v_summary.s9_5_gst + v_summary.delivery_gst + v_summary.platform_gst + v_summary.commission_gst) - (v_summary.gateway_fees * 0.18 / 1.18)), 
        2
      ),
      'delivered_orders', v_summary.delivered_orders
    ),
    'vendor_schedule', COALESCE(v_vendor_rows, '[]'::jsonb),
    'compliance_stats', jsonb_build_object(
      'total_active_shops', COALESCE(v_compliance_stats.total_active_shops, 0),
      'food_deemed_count', COALESCE(v_compliance_stats.food_deemed_count, 0),
      'compliant_gst_count', COALESCE(v_compliance_stats.compliant_gst_count, 0),
      'exempt_unregistered_count', COALESCE(v_compliance_stats.exempt_unregistered_count, 0),
      'action_required_count', COALESCE(v_compliance_stats.action_required_count, 0)
    )
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_ca_monthly_package(INT, INT) TO authenticated;
