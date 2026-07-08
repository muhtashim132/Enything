-- =============================================================================
-- Migration: 100x Delivery Partner Fortress
-- Description:
--   1. Patches the "Unbounded Wealth Creation Money Glitch" in reject_order_rider
--      where riders could drop orders with a fake 1M penalty that transferred to 
--      the next rider and deducted from the seller.
--   2. Patches the "Wait Penalty Geo-Spoofing Extortion" in set_arrived_at_shop
--      by enforcing a strict 300-meter geo-fence on the server via Haversine distance.
--   3. Patches "Rider Wage Theft" via Admin Cancellations by ensuring rider_earnings
--      are preserved if the order was already picked up, out for delivery, or delivered.
-- =============================================================================

-- 1. Patch set_arrived_at_shop (Geo-Spoofing Extortion)
CREATE OR REPLACE FUNCTION set_arrived_at_shop(p_order_id UUID, p_rider_lat numeric DEFAULT NULL, p_rider_lng numeric DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_partner_id uuid;
  v_status text;
  v_shop_lat numeric;
  v_shop_lng numeric;
  v_distance numeric;
BEGIN
  -- Strict row locking
  SELECT delivery_partner_id, status, shop_lat, shop_lng INTO v_delivery_partner_id, v_status, v_shop_lat, v_shop_lng
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment', 'pending') THEN
    RAISE EXCEPTION 'Cannot mark arrived at shop during status: %', v_status;
  END IF;

  -- 100x FIX: Enforce 300-meter geo-fence on the server
  IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
    -- Haversine formula for distance in meters
    v_distance := 6371000 * 2 * ASIN(SQRT(
        POWER(SIN((p_rider_lat - v_shop_lat) * pi()/180 / 2), 2) +
        COS(v_shop_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
        POWER(SIN((p_rider_lng - v_shop_lng) * pi()/180 / 2), 2)
    ));
    IF v_distance > 300 THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the shop. Max allowed is 300m.', v_distance::int;
    END IF;
  ELSE
    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark arrival.';
    END IF;
  END IF;

  UPDATE orders
  SET arrived_at_shop_time = now() AT TIME ZONE 'utc'
  WHERE id = p_order_id AND arrived_at_shop_time IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION set_arrived_at_shop(UUID, numeric, numeric) TO authenticated;


-- 2. Patch reject_order_rider (Money Glitch)
CREATE OR REPLACE FUNCTION reject_order_rider(p_order_id UUID, p_reason text DEFAULT NULL, p_penalty numeric DEFAULT 0, p_disputed boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_arrived_at_shop_time timestamptz;
  v_shop_prep_time_snapshot int;
  v_seller_payout numeric;
  v_shop_category text;
  v_wait_penalty_rate numeric;
  v_wait_mins int;
  v_calculated_wait_penalty numeric := 0;
  v_shop_id uuid;
BEGIN
  -- Strict row locking
  SELECT status, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout, shop_id 
  INTO v_status, v_delivery_partner_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout, v_shop_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Security Check: Ensure caller is the assigned rider
  IF v_delivery_partner_id IS NOT NULL AND v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only assigned rider can drop this order';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- 100x FIX: Prevent Unbounded Money Glitch
  -- Do not blindly accept p_penalty from client. Also, DO NOT leave wait_time_penalty on the order
  -- for the next rider to steal. 

  UPDATE orders
  SET 
    status = 'awaiting_acceptance',
    partner_accepted = false,
    delivery_partner_id = null,
    arrived_at_shop_time = null, -- Wipe arrival time to prevent exploits by the next rider
    wait_time_penalty = 0,       -- ZERO out penalty so the NEXT rider doesn't get free money
    wait_time_disputed = COALESCE(p_disputed, false)
  WHERE id = p_order_id;
  
  -- Rider 1 effectively forfeits their wait penalty by abandoning the order.
END;
$$;

GRANT EXECUTE ON FUNCTION reject_order_rider(UUID, text, numeric, boolean) TO authenticated;


-- 3. Patch reallocate_cancelled_delivery_fees (Wage Theft Prevention)
DROP FUNCTION IF EXISTS reallocate_cancelled_delivery_fees();
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

    -- Aggregate missing fees from rejected/cancelled orders
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0)
    INTO 
        v_missing_delivery, v_missing_surcharge, v_missing_small, v_missing_heavy
    FROM orders
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected')
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
          AND status IN ('cancelled', 'seller_rejected') 
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


-- 4. Patch admin_cancel_order (Wage Theft Prevention)
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

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'Order is already cancelled';
  END IF;

  -- 100x FIX: Do not zero out rider_earnings if they actually picked it up
  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
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


-- 5. Patch request_rider_withdrawal (Wage Theft Prevention)
CREATE OR REPLACE FUNCTION request_rider_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_user_id UUID;
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- 100x FIX: Include cancelled orders where rider_earnings were preserved
  SELECT COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
  AND delivery_partner_id = v_user_id;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'delivery_partner'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %', v_available_balance;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  INSERT INTO withdrawals (
    user_id, user_role, amount, upi_id, bank_account_number, bank_ifsc, bank_account_holder, status
  ) VALUES (
    v_user_id, 'delivery_partner', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_rider_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
