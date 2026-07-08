-- =============================================================================
-- Migration: 100x Seller Final Audit (State Machine & Reallocation Shield)
-- Description:
--   1. Fixes the "Refund Blackhole" vulnerability where fee reallocation aborted
--      if active siblings were already marked as 'delivered', causing riders to 
--      lose delivery pay for completed trips when a sibling order was cancelled.
--   2. Secures the State Machine by strictly forbidding riders from bypassing 
--      the seller's 'ready_for_pickup' state. A rider can no longer mark an 
--      order 'picked_up' directly from 'preparing' to spoof wait penalties.
-- =============================================================================

-- 1. Fix Fee Reallocation Bug (Include 'delivered' orders)
CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_missing_delivery NUMERIC := 0;
    v_missing_rider NUMERIC := 0;
    v_missing_surcharge NUMERIC := 0;
    v_missing_small NUMERIC := 0;
    v_missing_heavy NUMERIC := 0;
    v_missing_discount NUMERIC := 0;
    v_active_count INT := 0;
    v_split_delivery NUMERIC;
    v_split_rider NUMERIC;
    v_split_surcharge NUMERIC;
    v_split_small NUMERIC;
    v_split_heavy NUMERIC;
    v_split_discount NUMERIC;
    rec RECORD;
    v_net_delivery NUMERIC;
    v_new_gst_delivery NUMERIC;
BEGIN
    -- Explicitly lock ALL orders for this cart_group_id ordered by id to prevent deadlocks
    PERFORM id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE;

    -- Only run if there's an active order
    -- 100x BUG FIX: 'delivered' orders must be included. If an order was already delivered, 
    -- it MUST absorb the delivery fee of a newly cancelled sibling so the rider still gets paid.
    SELECT COUNT(*) INTO v_active_count
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_payment', 'awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Sum up delivery fees from cancelled orders that haven't been zeroed yet
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(rider_earnings), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0),
        COALESCE(SUM(delivery_discount), 0)
    INTO 
        v_missing_delivery, v_missing_rider, v_missing_surcharge, v_missing_small, v_missing_heavy, v_missing_discount
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel')
      AND delivery_charges > 0;

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    -- Split evenly among active orders
    v_split_delivery  := v_missing_delivery  / v_active_count;
    v_split_rider     := v_missing_rider     / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small     := v_missing_small     / v_active_count;
    v_split_heavy     := v_missing_heavy     / v_active_count;
    v_split_discount  := v_missing_discount  / v_active_count;

    -- Zero out delivery on cancelled/rejected orders
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount 
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
    LOOP
        UPDATE orders
        SET delivery_charges       = 0,
            rider_earnings         = 0,
            multi_shop_surcharge   = 0,
            small_cart_fee         = 0,
            heavy_order_fee        = 0,
            delivery_discount      = 0,
            gst_delivery           = 0,
            grand_total            = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)),
            grand_total_collected  = CASE 
                                       WHEN refund_status = 'completed' THEN 0 
                                       ELSE GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)) 
                                     END
        WHERE id = rec.id;
    END LOOP;

    -- Add absorbed fees to active orders
    FOR rec IN 
        SELECT id, delivery_charges, rider_earnings, multi_shop_surcharge, small_cart_fee, 
               heavy_order_fee, delivery_discount, 
               total_amount, gst_item_total, platform_fee, gst_platform, 
               COALESCE(coupon_discount, 0) AS coupon_discount,
               status
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('awaiting_payment', 'awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy)
                        - (rec.delivery_discount + v_split_discount);
                        
        -- Extract 18% embedded GST: net - (net / 1.18)
        v_new_gst_delivery := v_net_delivery - (v_net_delivery / 1.18);
        
        UPDATE orders
        SET delivery_charges      = rec.delivery_charges + v_split_delivery,
            rider_earnings        = rec.rider_earnings + v_split_rider,
            multi_shop_surcharge  = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee        = rec.small_cart_fee + v_split_small,
            heavy_order_fee       = rec.heavy_order_fee + v_split_heavy,
            delivery_discount     = rec.delivery_discount + v_split_discount,
            gst_delivery          = v_new_gst_delivery,
            grand_total           = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount),
            grand_total_collected  = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount)
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;


-- 2. Fix State Machine Bypass (Wait Penalty Spoofing)
CREATE OR REPLACE FUNCTION update_order_status(p_order_id UUID, p_new_status text, p_ready_time timestamptz DEFAULT NULL, p_wait_penalty numeric DEFAULT 0)
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
  v_wait_mins int;
  v_shop_category text;
  v_wait_penalty_rate numeric;
BEGIN
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout 
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF p_new_status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Invalid status for this RPC: %', p_new_status;
  END IF;

  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF v_seller_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only seller can update to %', p_new_status;
    END IF;
  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
    END IF;
    
    -- 100x BUG FIX: Prevent Rider from bypassing Seller's 'ready_for_pickup'
    IF p_new_status = 'picked_up' AND v_current_status != 'ready_for_pickup' THEN
      RAISE EXCEPTION 'Cannot mark picked_up from %. Seller must mark ready_for_pickup first.', v_current_status;
    END IF;
    
    IF p_new_status = 'out_for_delivery' AND v_current_status != 'picked_up' THEN
      RAISE EXCEPTION 'Cannot mark out_for_delivery from %', v_current_status;
    END IF;
    
    IF p_new_status = 'delivered' AND v_current_status NOT IN ('out_for_delivery', 'picked_up') THEN
      RAISE EXCEPTION 'Cannot mark delivered from %', v_current_status;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := COALESCE(p_ready_time, now());
    
    IF v_arrived_at_shop_time IS NOT NULL THEN
      v_wait_mins := EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60;
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

        v_calculated_wait_penalty := (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)) * v_wait_penalty_rate;
        
        IF v_calculated_wait_penalty > COALESCE(v_seller_payout, 0) THEN
          v_calculated_wait_penalty := COALESCE(v_seller_payout, 0);
        END IF;

      END IF;
    END IF;

    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = v_actual_ready_time,
      wait_time_penalty = v_calculated_wait_penalty
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = p_new_status
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION update_order_status(UUID, text, timestamptz, numeric) TO authenticated;
