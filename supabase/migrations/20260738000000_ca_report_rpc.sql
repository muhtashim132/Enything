-- =============================================================================
-- Migration: CA Report RPC
-- Description: 
-- Moves the CA Report aggregations to the backend to prevent OOM errors
-- and bypass the 1000 row PostgREST limit for high-volume sellers.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_seller_ca_report(p_shop_id uuid, p_start_date timestamptz, p_end_date timestamptz)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller_id uuid;
  v_result record;
BEGIN
  -- Verify ownership
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = p_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT 
    COALESCE(SUM(total_amount), 0) as total_base_sales,
    COALESCE(SUM(non_food_gst_amount), 0) as non_food_gst,
    COALESCE(SUM(s9_5_gst_amount), 0) as s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) as delivery_gst,
    COALESCE(SUM(gst_platform), 0) as platform_gst,
    COALESCE(SUM(tcs_amount), 0) as tcs_deducted,
    COALESCE(SUM(tds_amount), 0) as tds_deducted,
    COALESCE(SUM(enything_commission), 0) as commission,
    COALESCE(SUM(seller_payout), 0) as seller_payout,
    COALESCE(SUM(grand_total_collected), 0) as grand_collected,
    COALESCE(SUM(gateway_deduction), 0) as gateway_fees,
    COUNT(*) as delivered_orders
  INTO v_result
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
    AND created_at >= p_start_date
    AND created_at < p_end_date;

  RETURN json_build_object(
    'total_base_sales', v_result.total_base_sales,
    'non_food_gst', v_result.non_food_gst,
    's9_5_gst', v_result.s9_5_gst,
    'delivery_gst', v_result.delivery_gst,
    'platform_gst', v_result.platform_gst,
    'tcs_deducted', v_result.tcs_deducted,
    'tds_deducted', v_result.tds_deducted,
    'commission', v_result.commission,
    'seller_payout', v_result.seller_payout,
    'grand_collected', v_result.grand_collected,
    'gateway_fees', v_result.gateway_fees,
    'delivered_orders', v_result.delivered_orders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_seller_ca_report(uuid, timestamptz, timestamptz) TO authenticated;
