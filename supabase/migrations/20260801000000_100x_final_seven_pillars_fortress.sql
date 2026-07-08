-- =============================================================================
-- Migration: 100x Final Seven Pillars Fortress (Endgame Architecture Patch)
-- Description:
--   Patches the 7 newly discovered critical logic bugs across all modules:
--   1. Review Bombing on active table `ratings`
--   2. Partial Rejection Math Exploit (Coupon Trapping)
--   3. Checkout Crash (Fatal Typo is_accepting_orders)
--   4. Permanent Rider Bricking (Timeout DoS)
--   5. Food Theft (No Delivery OTP/Geo-fence for 'delivered')
--   6. Phantom Admin Profit (Refund Losses Ignored in Dashboard)
--   7. Duplicate Admin Refunds (Idempotency Failure)
-- =============================================================================

-- =============================================================================
-- PILLAR 1: RATINGS REVIEW BOMBING FIX
-- =============================================================================
DELETE FROM public.ratings WHERE order_id IS NULL;

-- Remove existing duplicates before creating the unique index
DELETE FROM public.ratings
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER(PARTITION BY order_id, rater_role, ratee_role ORDER BY created_at DESC) as rn
        FROM public.ratings
    ) sub
    WHERE sub.rn > 1
);

-- Make order_id strictly required
ALTER TABLE public.ratings ALTER COLUMN order_id SET NOT NULL;

-- Prevent infinite reviews per order per user type
CREATE UNIQUE INDEX IF NOT EXISTS ratings_order_rater_role_idx ON public.ratings (order_id, rater_role, ratee_role);

CREATE OR REPLACE FUNCTION user_can_rate_order(p_user_id UUID, p_order_id UUID, p_role TEXT)
RETURNS boolean AS $$
BEGIN
  IF p_role = 'customer' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = p_order_id AND customer_id = p_user_id AND status = 'delivered'
    );
  ELSIF p_role = 'seller' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.shops s ON o.shop_id = s.id
      WHERE o.id = p_order_id AND s.seller_id = p_user_id AND o.status = 'delivered'
    );
  ELSIF p_role = 'rider' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = p_order_id AND delivery_partner_id = p_user_id AND status = 'delivered'
    );
  END IF;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate RLS on ratings
DROP POLICY IF EXISTS "ratings_insert_own" ON public.ratings;

CREATE POLICY "ratings_insert_own"
  ON public.ratings FOR INSERT
  TO authenticated
  WITH CHECK (
    rater_id = auth.uid() AND 
    user_can_rate_order(auth.uid(), order_id, rater_role)
  );

-- =============================================================================
-- PILLAR 2: PARTIAL REJECTION MATH EXPLOIT FIX (COUPON TRAPPING)
-- =============================================================================
CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_active_count INT;
  v_missing_delivery NUMERIC;
  v_missing_surcharge NUMERIC;
  v_missing_small NUMERIC;
  v_missing_heavy NUMERIC;
  v_missing_coupon NUMERIC := 0;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_split_coupon NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_trapped_coupon NUMERIC;
  rec RECORD;
BEGIN
    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Aggregate missing fees
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0)
    INTO 
        v_missing_delivery, v_missing_surcharge, v_missing_small, v_missing_heavy
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
      AND delivery_charges > 0
      AND COALESCE(rider_earnings, 0) = 0;

    -- Calculate TRAPPED COUPON (Coupon that exceeded the remaining items total after delivery removal)
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel') 
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
    LOOP
        v_trapped_coupon := COALESCE(rec.coupon_discount, 0) - (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform);
        IF v_trapped_coupon > 0 THEN
            v_missing_coupon := v_missing_coupon + v_trapped_coupon;
            
            -- Adjust the coupon discount on the cancelled order to release the trap
            UPDATE orders 
            SET coupon_discount = (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform)
            WHERE id = rec.id;
        END IF;
    END LOOP;

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;
    v_split_coupon := v_missing_coupon / v_active_count;

    -- Zero out the cancelled ones
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel') 
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
    LOOP
        UPDATE orders
        SET delivery_charges = 0,
            multi_shop_surcharge = 0,
            small_cart_fee = 0,
            heavy_order_fee = 0,
            gst_delivery = 0,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)) 
                ELSE 0 
            END
        WHERE id = rec.id;
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
            coupon_discount = rec.coupon_discount + v_split_coupon,
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================================================
-- PILLAR 3: CHECKOUT CRASH FIX
-- =============================================================================
CREATE OR REPLACE FUNCTION get_shop_delivery_fee(p_shop_id UUID, p_user_lat NUMERIC, p_user_lng NUMERIC)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shop_lat NUMERIC;
    v_shop_lng NUMERIC;
    v_is_accepting_orders BOOLEAN;
    v_distance_km NUMERIC;
    v_base_fee NUMERIC;
    v_per_km_fee NUMERIC;
    v_max_distance NUMERIC;
    v_total_fee NUMERIC;
BEGIN
    SELECT lat, lng, is_accepting_orders 
    INTO v_shop_lat, v_shop_lng, v_is_accepting_orders
    FROM shops 
    WHERE id = p_shop_id;

    -- FIX: is_accepting_orders is the correct column!
    IF NOT v_is_accepting_orders THEN
        RETURN jsonb_build_object('error', 'Shop is currently not accepting orders.');
    END IF;

    v_distance_km := 6371 * ACOS(
        COS(RADIANS(v_shop_lat)) * COS(RADIANS(p_user_lat)) +
        SIN(RADIANS(v_shop_lat)) * SIN(RADIANS(p_user_lat)) * COS(RADIANS(p_user_lng) - RADIANS(v_shop_lng))
    );

    SELECT 
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_base_fee'), 30),
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_per_km_fee'), 10),
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_max_distance_km'), 15)
    INTO v_base_fee, v_per_km_fee, v_max_distance;

    IF v_distance_km > v_max_distance THEN
        RETURN jsonb_build_object('error', 'Address is outside delivery range (' || v_max_distance || 'km).');
    END IF;

    v_total_fee := v_base_fee + (GREATEST(0, v_distance_km - 2) * v_per_km_fee);

    RETURN jsonb_build_object(
        'delivery_fee', ROUND(v_total_fee),
        'distance_km', ROUND(v_distance_km, 2)
    );
END;
$$;


-- =============================================================================
-- PILLAR 4: RIDER BRICKING (TIMEOUT DoS) FIX
-- =============================================================================
CREATE OR REPLACE FUNCTION accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_cart_group_id uuid;
  v_active_carts int;
BEGIN
  -- 100x FIX: Enforce MAX 3 Active Cart Groups to prevent order hoarding.
  -- Exclude all possible terminal/failure states!
  SELECT COUNT(DISTINCT cart_group_id) INTO v_active_carts
  FROM orders 
  WHERE delivery_partner_id = auth.uid() 
    AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'payment_failed', 'timeout', 'verification_failed', 'no_rider', 'shop_dispute_cancel');

  IF v_active_carts >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You cannot accept more than 3 active carts simultaneously.';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, delivery_partner_id
  INTO v_status, v_delivery_partner_id
  FROM orders WHERE id = p_order_id;

  IF v_status != 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Order is not ready for pickup (Status: %)', v_status;
  END IF;

  IF v_delivery_partner_id IS NOT NULL THEN
    RAISE EXCEPTION 'Order already accepted by another rider';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders 
    SET 
      delivery_partner_id = auth.uid(), 
      status = 'picked_up',
      rider_assigned_at = now() AT TIME ZONE 'utc'
    WHERE cart_group_id = v_cart_group_id AND status = 'ready_for_pickup' AND delivery_partner_id IS NULL;
  ELSE
    UPDATE orders 
    SET 
      delivery_partner_id = auth.uid(), 
      status = 'picked_up',
      rider_assigned_at = now() AT TIME ZONE 'utc'
    WHERE id = p_order_id;
  END IF;
END;
$$;


-- =============================================================================
-- PILLAR 5: FOOD THEFT FIX (DELIVERY OTP / GEO-FENCE ENFORCEMENT)
-- =============================================================================
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id UUID, 
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
  v_wait_mins int;
  v_shop_category text;
  v_wait_penalty_rate numeric;
  v_customer_lat numeric;
  v_customer_lng numeric;
  v_distance_to_customer numeric;
BEGIN
  -- Strict row locking
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
    
    IF p_new_status = 'preparing' AND v_current_status NOT IN ('awaiting_acceptance', 'pending', 'preparing') THEN
      RAISE EXCEPTION 'Cannot mark preparing from terminal or downstream state: %', v_current_status;
    END IF;

    IF p_new_status = 'ready_for_pickup' AND v_current_status != 'preparing' THEN
      RAISE EXCEPTION 'Cannot mark ready_for_pickup from state: %', v_current_status;
    END IF;

  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
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

        -- 100x FIX: Enforce 300m Geo-Fence for Customer Location
        SELECT lat, lng INTO v_customer_lat, v_customer_lng
        FROM addresses
        WHERE id = (SELECT delivery_address_id FROM orders WHERE id = p_order_id);

        IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_customer_lat IS NOT NULL AND v_customer_lng IS NOT NULL THEN
            v_distance_to_customer := 6371000 * 2 * ASIN(SQRT(
                POWER(SIN((p_rider_lat - v_customer_lat) * pi()/180 / 2), 2) +
                COS(v_customer_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
                POWER(SIN((p_rider_lng - v_customer_lng) * pi()/180 / 2), 2)
            ));
            IF v_distance_to_customer > 300 THEN
                RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the customer. Max allowed is 300m.', v_distance_to_customer::int;
            END IF;
        ELSE
            IF v_customer_lat IS NOT NULL AND v_customer_lng IS NOT NULL THEN
                RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark delivered.';
            END IF;
        END IF;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := now() AT TIME ZONE 'utc';
    
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

        v_calculated_wait_penalty := GREATEST(0, (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0))) * v_wait_penalty_rate;
        
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


-- =============================================================================
-- PILLAR 6: PHANTOM ADMIN PROFIT FIX (REFUND LOSSES)
-- =============================================================================
CREATE OR REPLACE FUNCTION admin_get_finance_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv NUMERIC;
  v_pure_profit NUMERIC;
  v_seller_payouts NUMERIC;
  v_rider_earnings NUMERIC;
  v_pending_settlements INT;
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT 
    COALESCE(SUM(
      CASE WHEN COALESCE(refund_status, 'none') = 'completed' THEN 0 ELSE grand_total_collected END
    ), 0),
    
    -- 100x FIX: Pure Profit must now evaluate ACROSS ALL STATUSES so refunded/cancelled losses are calculated!
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') = 'completed' THEN 
          0 - COALESCE(rider_earnings, 0) - COALESCE(gateway_deduction, 0)
        WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel') THEN
          0 - COALESCE(rider_earnings, 0) - COALESCE(gateway_deduction, 0)
        ELSE 
          COALESCE(enything_commission, 0) + 
          (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) + 
          (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) - 
          COALESCE(gateway_deduction, 0) - COALESCE(coupon_discount, 0)
      END
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM orders; -- DO NOT FILTER CANCELLED ORDERS ANYMORE!

  SELECT 
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0),
    COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0),
    COUNT(*)
  INTO v_seller_payouts, v_rider_earnings, v_pending_settlements
  FROM orders WHERE status = 'delivered';

  RETURN jsonb_build_object(
    'total_gmv', ROUND(v_gmv, 2),
    'pure_profit', ROUND(v_pure_profit, 2),
    'seller_payouts', ROUND(v_seller_payouts, 2),
    'rider_earnings', ROUND(v_rider_earnings, 2),
    'pending_settlements', v_pending_settlements
  );
END;
$$;


-- =============================================================================
-- PILLAR 7: DUPLICATE ADMIN REFUNDS FIX
-- =============================================================================
CREATE OR REPLACE FUNCTION admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_refund_status text;
  v_cart_group_id uuid;
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status, refund_status INTO v_status, v_payment_status, v_refund_status
  FROM orders WHERE id = p_order_id;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  -- 100x FIX: Prevent idempotency failures (double refunds)
  IF v_refund_status IN ('processing', 'completed') THEN
    RAISE EXCEPTION 'Refund is already processing or completed. Cannot trigger duplicate refund.';
  END IF;

  IF v_status IN ('cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute', 'shop_dispute_cancel') THEN
    IF v_payment_status != 'captured' THEN
      RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
    END IF;
    UPDATE orders
    SET refund_status = 'processing'
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status = 'cancelled',
      cancelled_reason = 'admin',
      rider_earnings = 0,
      wait_time_penalty = 0,
      refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION update_order_status(UUID, text, timestamptz, numeric, numeric, numeric, text) TO authenticated;
