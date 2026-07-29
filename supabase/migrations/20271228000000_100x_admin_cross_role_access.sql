-- =============================================================================
-- Migration: 100x Admin Cross-Role Access Fortress
-- Description:
--   1. Restores Admin Dashboard visibility for Seller and Rider balances by 
--      adding an admin bypass to strict IDOR guards.
--   2. Restores Admin ability to pull CA Reports for any seller.
--   3. Restores Admin ability to force-update order statuses and bypass geofences.
--   4. Creates the missing 'get_customer_dashboard_stats' for customer overviews
--      with strict IDOR protection (but admin bypass).
-- =============================================================================

-- 1. Restore Admin Access to Seller Balance
CREATE OR REPLACE FUNCTION get_seller_balance(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  -- 100x FIX: Block IDOR scraping attacks, but allow Admin bypass
  IF (auth.uid() IS NULL OR auth.uid() != p_seller_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access financial data for another user.';
  END IF;

  -- FIX: Persist wait_time_penalty deduction even if the order was refunded
  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = p_seller_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Restore Admin Access to Rider Balance
CREATE OR REPLACE FUNCTION get_rider_balance(p_rider_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  -- 100x FIX: Block IDOR scraping attacks, but allow Admin bypass
  IF (auth.uid() IS NULL OR auth.uid() != p_rider_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access financial data for another user.';
  END IF;

  -- Sum all positive earnings from delivered and valid cancelled orders
  SELECT COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
  AND delivery_partner_id = p_rider_id;

  -- Sum all valid withdrawals
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_rider_id
  AND user_role = 'delivery_partner'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Restore Admin Access to CA Report
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
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = p_shop_id;
  
  -- 100x FIX: Allow Admin bypass for CA Report
  IF (auth.uid() IS NULL OR v_seller_id != auth.uid()) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT 
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE total_amount END), 0) as total_base_sales,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE non_food_gst_amount END), 0) as non_food_gst,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE s9_5_gst_amount END), 0) as s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) as delivery_gst,
    COALESCE(SUM(gst_platform), 0) as platform_gst,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE tcs_amount END), 0) as tcs_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE tds_amount END), 0) as tds_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE enything_commission END), 0) as commission,
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0) as seller_payout,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') = 'completed' THEN 0 ELSE grand_total_collected END), 0) as grand_collected,
    COALESCE(SUM(gateway_deduction), 0) as gateway_fees,
    COUNT(*) as delivered_orders
  INTO v_result
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
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


-- 4. Restore Admin Force-Update Capability in Order Status
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id uuid, 
    p_new_status text, 
    p_ready_time timestamptz DEFAULT NULL, 
    p_wait_penalty numeric DEFAULT 0,
    p_rider_lat numeric DEFAULT NULL,
    p_rider_lng numeric DEFAULT NULL,
    p_delivery_otp text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_rider_id uuid;
  v_arrived_at_shop_time timestamptz;
  v_shop_prep_time_snapshot int;
  v_seller_payout numeric;
  v_calculated_wait_penalty numeric := 0;
  v_actual_ready_time timestamptz;
  v_wait_mins numeric;
  v_shop_category text;
  v_wait_penalty_rate numeric;
  v_customer_lat numeric;
  v_customer_lng numeric;
  v_distance_to_customer numeric;
  v_delivery_otp text;
BEGIN
  -- Strict row locking
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout, delivery_otp 
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout, v_delivery_otp
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF p_new_status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Invalid status for this RPC: %', p_new_status;
  END IF;

  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    -- 100x FIX: Allow Admin Bypass
    IF (v_seller_id != auth.uid() OR auth.uid() IS NULL) AND NOT public.is_active_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Unauthorized: Only seller or admin can update to %', p_new_status;
    END IF;
    
    IF p_new_status = 'preparing' AND v_current_status NOT IN ('awaiting_acceptance', 'pending', 'preparing', 'confirmed') THEN
      RAISE EXCEPTION 'Cannot mark preparing from terminal or downstream state: %', v_current_status;
    END IF;

    IF p_new_status = 'ready_for_pickup' AND v_current_status != 'preparing' THEN
      RAISE EXCEPTION 'Cannot mark ready_for_pickup from state: %', v_current_status;
    END IF;

  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    -- 100x FIX: Allow Admin Bypass
    IF (v_rider_id != auth.uid() OR auth.uid() IS NULL) AND NOT public.is_active_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider or admin can update to %', p_new_status;
    END IF;
    
    IF p_new_status = 'picked_up' AND v_current_status NOT IN ('preparing', 'ready_for_pickup') THEN
      RAISE EXCEPTION 'Cannot mark picked_up from %', v_current_status;
    END IF;
    
    IF p_new_status = 'out_for_delivery' AND v_current_status != 'picked_up' THEN
      RAISE EXCEPTION 'Cannot mark out_for_delivery from %', v_current_status;
    END IF;
    
    IF p_new_status = 'delivered' THEN
        IF v_current_status NOT IN ('out_for_delivery', 'picked_up') THEN
            RAISE EXCEPTION 'Cannot mark delivered from %', v_current_status;
        END IF;

        -- Legacy Address Deadlock Bypass
        SELECT delivery_lat, delivery_lng INTO v_customer_lat, v_customer_lng
        FROM orders
        WHERE id = p_order_id;

        IF v_customer_lat IS NOT NULL AND v_customer_lng IS NOT NULL THEN
            IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL THEN
                v_distance_to_customer := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(GREATEST(0.0::double precision, 
                    POWER(SIN((p_rider_lat - v_customer_lat) * pi()/180 / 2), 2) +
                    COS(v_customer_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
                    POWER(SIN((p_rider_lng - v_customer_lng) * pi()/180 / 2), 2)
                ))));
                -- 100x FIX: Allow admin bypass for Geo-Fence
                IF v_distance_to_customer > 300 AND NOT public.is_active_admin(auth.uid()) THEN
                    RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the customer. Max allowed is 300m.', v_distance_to_customer::int;
                END IF;
            ELSIF NOT public.is_active_admin(auth.uid()) THEN
                -- 100x FIX: Allow admin bypass for missing coordinates
                RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark delivered.';
            END IF;
        END IF;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := now() AT TIME ZONE 'utc';
    
    IF v_arrived_at_shop_time IS NOT NULL THEN
      v_wait_mins := (EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60.0)::numeric;
      IF v_wait_mins > COALESCE(v_shop_prep_time_snapshot, 0) THEN
        
        SELECT category INTO v_shop_category FROM shops WHERE id = v_shop_id;
        BEGIN
          SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min_' || v_shop_category;
        EXCEPTION WHEN OTHERS THEN 
          v_wait_penalty_rate := NULL; 
        END;

        IF v_wait_penalty_rate IS NULL THEN
          BEGIN
            SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min';
          EXCEPTION WHEN OTHERS THEN 
            v_wait_penalty_rate := 2.0; 
          END;
        END IF;

        IF v_wait_penalty_rate IS NULL THEN
          v_wait_penalty_rate := 2.0;
        END IF;

        v_calculated_wait_penalty := ROUND(GREATEST(0::numeric, (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)::numeric)) * v_wait_penalty_rate, 2);
        
        IF v_calculated_wait_penalty > COALESCE(v_seller_payout, 0) THEN
          v_calculated_wait_penalty := COALESCE(v_seller_payout, 0);
        END IF;

      END IF;
    END IF;

    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = v_actual_ready_time,
      wait_time_penalty = v_calculated_wait_penalty,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET 
      status = p_new_status,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;
END;
$$;


-- 5. Create Missing Customer Dashboard Stats RPC
CREATE OR REPLACE FUNCTION get_customer_dashboard_stats(p_customer_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_orders int := 0;
  v_total_spent numeric := 0;
  v_active_orders int := 0;
  v_cancelled_orders int := 0;
BEGIN
  -- 100x FIX: Strict IDOR Guard with Admin Bypass
  IF (auth.uid() IS NULL OR auth.uid() != p_customer_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access data for another user.';
  END IF;

  SELECT count(*) INTO v_total_orders
  FROM orders
  WHERE customer_id = p_customer_id AND status = 'delivered';

  SELECT COALESCE(SUM(grand_total_collected), 0) INTO v_total_spent
  FROM orders
  WHERE customer_id = p_customer_id AND status = 'delivered';

  SELECT count(*) INTO v_active_orders
  FROM orders
  WHERE customer_id = p_customer_id AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'rider_rejected', 'timeout', 'payment_failed', 'verification_failed', 'shop_dispute_cancel', 'refunded', 'returned', 'failed');

  SELECT count(*) INTO v_cancelled_orders
  FROM orders
  WHERE customer_id = p_customer_id AND status IN ('cancelled', 'seller_rejected', 'rider_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

  RETURN json_build_object(
    'total_orders', v_total_orders,
    'total_spent', v_total_spent,
    'active_orders', v_active_orders,
    'cancelled_orders', v_cancelled_orders
  );
END;
$$;
