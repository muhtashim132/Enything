-- =============================================================================
-- Migration: 100x Stress-Test Fortress (Extreme Edge Cases & Cascading Failures)
-- Description:
--   1. Patches Haversine float overflow (ASIN out of range) DoS vulnerability.
--   2. Expands reallocate_cancelled_delivery_fees to handle timeouts/failures.
--   3. Refactors cron jobs to use row-locking loops and trigger reallocation, 
--      plugging a massive delivery fee blackhole.
--   4. Zeroes out platform/seller fees on admin-cancelled delivered orders 
--      to prevent phantom revenue accounting bleed.
-- =============================================================================

-- 1. Patch Haversine Float Overflow (DoS Prevention)
CREATE OR REPLACE FUNCTION set_arrived_at_shop(
  p_order_id UUID,
  p_rider_lat NUMERIC DEFAULT NULL,
  p_rider_lng NUMERIC DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_auth_uid uuid;
  v_shop_lat numeric;
  v_shop_lng numeric;
  v_distance numeric;
BEGIN
  v_auth_uid := auth.uid();
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status, delivery_partner_id, shop_lat, shop_lng 
  INTO v_status, v_delivery_partner_id, v_shop_lat, v_shop_lng 
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != v_auth_uid THEN
    RAISE EXCEPTION 'Not assigned to this order';
  END IF;

  IF v_status != 'pending_pickup' THEN
    RAISE EXCEPTION 'Invalid status for arrival: %', v_status;
  END IF;

  -- 100x FIX: Enforce 300-meter geo-fence securely & prevent float overflow crashes!
  IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
    v_distance := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(
        POWER(SIN((p_rider_lat - v_shop_lat) * pi()/180 / 2), 2) +
        COS(v_shop_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
        POWER(SIN((p_rider_lng - v_shop_lng) * pi()/180 / 2), 2)
    )));
    IF v_distance > 300 THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the shop. Max allowed is 300m.', v_distance::int;
    END IF;
  ELSE
    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark arrival.';
    END IF;
  END IF;

  UPDATE orders
  SET 
    arrived_at_shop_time = NOW(),
    updated_at = NOW()
  WHERE id = p_order_id;
END;
$$;


-- 2. Patch reallocate_cancelled_delivery_fees (Timeout Blackhole Fix)
CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_active_count INT;
  v_missing_delivery NUMERIC;
  v_missing_surcharge NUMERIC;
  v_missing_small NUMERIC;
  v_missing_heavy NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  rec RECORD;
BEGIN
    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Aggregate missing fees from rejected/cancelled/timed out orders
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0)
    INTO 
        v_missing_delivery, v_missing_surcharge, v_missing_small, v_missing_heavy
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute', 'shop_dispute_cancel')
      AND delivery_charges > 0
      AND rider_earnings = 0; -- Only reallocate if rider was NOT PAID.

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;

    -- Zero out the cancelled ones (only if rider earnings is 0)
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status, rider_earnings
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute', 'shop_dispute_cancel') 
          AND delivery_charges > 0
    LOOP
        IF COALESCE(rec.rider_earnings, 0) = 0 THEN
          UPDATE orders
          SET delivery_charges = 0,
              multi_shop_surcharge = 0,
              small_cart_fee = 0,
              heavy_order_fee = 0,
              gst_delivery = 0,
              grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)),
              grand_total_collected = CASE 
                  WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)) 
                  ELSE 0 
              END
          WHERE id = rec.id;
        END IF;
    END LOOP;

    -- Add to active orders
    FOR rec IN 
        SELECT id, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup')
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy);
                        
        v_new_gst_delivery := v_net_delivery - (v_net_delivery / 1.18);
        
        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            rider_earnings = (rec.delivery_charges + v_split_delivery - v_new_gst_delivery) * 0.80,
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Patch Cron Jobs to Trigger Reallocation securely (Cascading Logic Fix)
CREATE OR REPLACE FUNCTION auto_cancel_expired_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec RECORD;
BEGIN
  -- Cancel orders that are awaiting acceptance and past their acceptance deadline
  FOR v_rec IN 
    SELECT id, cart_group_id, payment_status 
    FROM orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    FOR UPDATE 
  LOOP
    UPDATE orders
    SET status = 'timeout',
        refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = v_rec.id;
    
    IF v_rec.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_rec.cart_group_id);
    END IF;
  END LOOP;

  -- Cancel orders that are awaiting payment and past their payment deadline
  FOR v_rec IN 
    SELECT id, cart_group_id, payment_status 
    FROM orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    FOR UPDATE 
  LOOP
    UPDATE orders
    SET status = 'payment_failed',
        refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = v_rec.id;
    
    IF v_rec.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_rec.cart_group_id);
    END IF;
  END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION sweep_phantom_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN 
    SELECT id, cart_group_id, payment_status 
    FROM orders 
    WHERE status IN ('pending', 'awaiting_payment', 'awaiting_acceptance')
      AND created_at < NOW() - INTERVAL '24 hours'
    FOR UPDATE 
  LOOP
    UPDATE orders
    SET status = 'cancelled',
        rejection_message = 'Automated system cleanup: Order stuck in phantom state',
        refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = v_rec.id;
    
    IF v_rec.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_rec.cart_group_id);
    END IF;
  END LOOP;
END;
$$;


-- 4. Patch admin_cancel_order (Phantom Revenue Fix)
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

  -- Lock orders dynamically (deadlock safe)
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Get current status of the target order
  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'Order is already cancelled';
  END IF;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      platform_fee     = 0,
      gst_platform     = 0,
      seller_payout    = 0,
      grand_total      = GREATEST(0, delivery_charges + gst_delivery),
      grand_total_collected = 0,
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' THEN 'processing'
                           ELSE refund_status
                         END
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      rider_earnings   = 0, -- Zero out only if rider did not physically transport it
      wait_time_penalty = 0,
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' THEN 'processing'
                           ELSE refund_status
                         END
    WHERE id = p_order_id;
  END IF;

  -- Reallocate delivery fees for admin cancellations
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$$;
