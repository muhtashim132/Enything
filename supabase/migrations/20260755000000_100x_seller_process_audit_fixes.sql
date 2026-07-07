-- =============================================================================
-- Migration: 100x Seller Process & Dashboard Audit Fixes
-- Description:
-- 1. Fixes `reject_order_seller` to explicitly call `reallocate_cancelled_delivery_fees`
--    so that the remaining active orders in a multi-shop cart correctly absorb the 
--    rider's delivery fee mathematically on the backend.
-- 2. Fixes `admin_cancel_order` to also trigger the same reallocation.
-- 3. Fixes `get_seller_daily_stats` to filter earnings by `updated_at` (delivery time) 
--    rather than `created_at` (placement time) for accurate daily accounting.
-- 4. Fixes `get_seller_ca_report` to use `updated_at` and exclude refunded orders.
-- =============================================================================

-- 1. Fix reject_order_seller
CREATE OR REPLACE FUNCTION reject_order_seller(p_order_id UUID, p_reject_reason text, p_message text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Fetch cart_group_id first without locking to prevent out-of-order lock deadlocks
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  -- Lock all orders in the group deterministically by ID if it's a multi-shop order
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  -- Now fetch the specific order and lock it (or re-lock it safely)
  SELECT status, shop_id, payment_status INTO v_status, v_shop_id, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Allow rejection even if confirmed or preparing
  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = p_message,
    -- Trigger refund if payment was already captured
    refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
  WHERE id = p_order_id;

  -- 100x BUG FIX: Reallocate the delivery fee fraction from this cancelled order to the remaining 
  -- active orders so that the customer is not refunded the delivery fee and the rider is paid in full.
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_order_seller(UUID, text, text) TO authenticated;

-- 2. Fix admin_cancel_order
CREATE OR REPLACE FUNCTION admin_cancel_order(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Fetch cart_group_id first without locking
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  -- Lock deterministically
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  -- Only block if already in a fully terminal state
  IF v_status IN ('cancelled', 'delivered') THEN
    RAISE EXCEPTION 'Order is already %', v_status;
  END IF;

  UPDATE orders
  SET
    status           = 'cancelled',
    cancelled_reason = 'admin',
    refund_status    = CASE
                         WHEN v_payment_status = 'captured' THEN 'processing'
                         ELSE refund_status
                       END
  WHERE id = p_order_id;

  -- 100x BUG FIX: Reallocate delivery fees for admin cancellations
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_cancel_order(UUID) TO authenticated;


-- 3. Fix get_seller_daily_stats Date Logic
CREATE OR REPLACE FUNCTION get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_orders integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products integer := 0;
BEGIN
    -- Get total orders
    SELECT count(*) INTO v_total_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status NOT IN ('cancelled', 'seller_rejected');

    -- Get pending orders
    SELECT count(*) INTO v_pending_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status IN ('pending', 'awaiting_acceptance');

    -- Get today's earnings
    -- 100x FIX: Use updated_at instead of created_at because an order 
    -- placed yesterday but delivered today represents today's earnings.
    SELECT COALESCE(SUM(COALESCE(seller_payout, 0)), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
      AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
      AND DATE(updated_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    -- Get products count
    SELECT count(*) INTO v_products
    FROM products
    WHERE shop_id = p_shop_id AND is_deleted = false;

    RETURN json_build_object(
        'total_orders', v_total_orders,
        'pending_orders', v_pending_orders,
        'todays_earning', v_todays_earning,
        'products', v_products
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_seller_daily_stats(uuid) TO authenticated;

-- 4. Fix get_seller_ca_report Date Logic and Refund Integrity
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

  -- 100x FIX: Use updated_at to ensure orders delivered in the time period are counted, 
  -- regardless of when they were created.
  -- Also added refund_status filter to ensure refunded orders don't falsely inflate sales.
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
    AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
    AND updated_at >= p_start_date
    AND updated_at < p_end_date;

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
