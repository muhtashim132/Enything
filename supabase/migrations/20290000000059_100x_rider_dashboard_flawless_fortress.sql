-- =============================================================================
-- Migration: 20290000000059_100x_rider_dashboard_flawless_fortress.sql
-- Description: 100x Comprehensive Fortress for Rider Dashboard & Delivery Operations:
--   1. Atomic Multi-Shop Cart Acceptance in accept_order_rider (both 4-arg and 1-arg overloads)
--      Guarantees sibling orders in a cart group are locked and assigned simultaneously to the rider.
--   2. Authorizes assigned rider in set_shop_dispute to report issues at the shop.
--   3. Adds 'confirmed' status support to set_arrived_at_shop for early rider arrivals.
--   4. Fixes Postgres MAX(coupon_id::text)::uuid in reallocate_cancelled_delivery_fees.
--   5. Fortifies get_rider_stats type safety and IDOR guards.
-- =============================================================================

-- =============================================================================
-- 1. accept_order_rider(UUID, text, numeric, numeric) & accept_order_rider(UUID)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_status text;
  v_payment_deadline timestamptz;
  v_order_ready_time timestamptz;
  v_delivery_partner_id UUID;
  v_new_status text;
  v_cart_group_id UUID;
  v_active_cart_groups_count INT;
  v_order_record RECORD;
  v_return_seller_accepted boolean := false;
  v_resolved_shop_lat numeric;
  v_resolved_shop_lng numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 100x ARCHITECTURE FIX: Transaction-level Advisory Lock on Rider ID
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || auth.uid()::text));

  -- 1. Initial lookup & lock target order
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id, delivery_partner_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  -- Graceful cancellation check
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  -- Fast-path Idempotency Check (if rider already assigned, e.g. frontend retry)
  IF v_delivery_partner_id = auth.uid() THEN
    UPDATE orders 
    SET 
      shop_lat = CASE WHEN p_shop_lat IS NOT NULL AND p_shop_lat != 0 THEN p_shop_lat ELSE shop_lat END,
      shop_lng = CASE WHEN p_shop_lng IS NOT NULL AND p_shop_lng != 0 THEN p_shop_lng ELSE shop_lng END,
      rider_phone = CASE WHEN p_rider_phone IS NOT NULL AND p_rider_phone != '' THEN p_rider_phone ELSE rider_phone END
    WHERE id = p_order_id;
    
    RETURN v_seller_accepted;
  ELSIF v_delivery_partner_id IS NOT NULL THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- 2. Lock Cart Group Scope
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- 3. Enforce Max 3 Active Cart Groups Hoarding Limit
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 
      'cancelled', 
      'seller_rejected', 
      'partner_rejected', 
      'returned', 
      'refunded', 
      'failed',
      'payment_failed',
      'timeout',
      'verification_failed',
      'no_rider',
      'shop_dispute_cancel'
    )
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- 4. Atomic Cart Group Assignment Loop
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.delivery_partner_id, o.shop_id, o.shop_lat, o.shop_lng, o.rider_phone
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    -- Double-check assignment under lock
    IF v_order_record.delivery_partner_id IS NOT NULL AND v_order_record.delivery_partner_id != auth.uid() THEN
      RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
    END IF;

    -- Compute state transition for this sibling order
    IF v_order_record.seller_accepted = true THEN
      IF v_order_record.payment_status = 'captured' THEN
        IF v_order_record.order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
    ELSE
      v_new_status := v_order_record.status;
    END IF;

    -- Resolve shop coordinates
    IF v_order_record.id = p_order_id AND p_shop_lat IS NOT NULL AND p_shop_lat != 0 THEN
      v_resolved_shop_lat := p_shop_lat;
      v_resolved_shop_lng := p_shop_lng;
    ELSIF v_order_record.shop_lat IS NOT NULL AND v_order_record.shop_lat != 0 THEN
      v_resolved_shop_lat := v_order_record.shop_lat;
      v_resolved_shop_lng := v_order_record.shop_lng;
    ELSE
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_resolved_shop_lat, v_resolved_shop_lng
      FROM shops WHERE id = v_order_record.shop_id;
    END IF;

    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = v_new_status,
      payment_deadline = CASE WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_order_record.payment_deadline END,
      rider_phone = COALESCE(NULLIF(p_rider_phone, ''), v_order_record.rider_phone),
      shop_lat = COALESCE(v_resolved_shop_lat, v_order_record.shop_lat),
      shop_lng = COALESCE(v_resolved_shop_lng, v_order_record.shop_lng),
      updated_at = NOW()
    WHERE id = v_order_record.id;

    IF v_order_record.id = p_order_id THEN
      v_return_seller_accepted := COALESCE(v_order_record.seller_accepted, false);
    END IF;
  END LOOP;

  RETURN v_return_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO authenticated;

-- Overload: 1-parameter version
CREATE OR REPLACE FUNCTION public.accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.accept_order_rider(p_order_id, NULL, NULL, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID) TO authenticated;


-- =============================================================================
-- 2. set_arrived_at_shop(UUID, numeric, numeric)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_arrived_at_shop(
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
  v_arrived_at_shop_time timestamptz;
BEGIN
  v_auth_uid := auth.uid();
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status, delivery_partner_id, shop_lat, shop_lng, arrived_at_shop_time 
  INTO v_status, v_delivery_partner_id, v_shop_lat, v_shop_lng, v_arrived_at_shop_time
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != v_auth_uid THEN
    RAISE EXCEPTION 'Unauthorized: Only the assigned rider can mark arrival';
  END IF;

  -- 100x FIX: Include 'confirmed' so riders arriving early at shop don't crash
  IF v_status NOT IN ('confirmed', 'preparing', 'ready_for_pickup', 'accepted') THEN
    RAISE EXCEPTION 'Invalid status for arrival: %', v_status;
  END IF;

  IF v_arrived_at_shop_time IS NOT NULL THEN
    RETURN;
  END IF;

  IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
    v_distance := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(GREATEST(0.0::double precision, 
        POWER(SIN((p_rider_lat - v_shop_lat) * pi()/180 / 2), 2) +
        COS(v_shop_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
        POWER(SIN((p_rider_lng - v_shop_lng) * pi()/180 / 2), 2)
    ))));
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

GRANT EXECUTE ON FUNCTION public.set_arrived_at_shop(UUID, numeric, numeric) TO authenticated;


-- =============================================================================
-- 3. set_shop_dispute(UUID, boolean)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_shop_dispute(p_order_id UUID, p_cancel BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
  v_customer_id uuid;
  v_delivery_partner_id uuid;
BEGIN
  SELECT cart_group_id, customer_id, delivery_partner_id 
  INTO v_cart_group_id, v_customer_id, v_delivery_partner_id 
  FROM orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 100x FIX: Authorize Customer, Assigned Delivery Partner, or Admin
  IF auth.uid() IS NULL OR (
    v_customer_id IS DISTINCT FROM auth.uid() 
    AND v_delivery_partner_id IS DISTINCT FROM auth.uid() 
    AND NOT public.is_active_admin(auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer, assigned rider, or an admin can open a dispute';
  END IF;

  -- Strict Deterministic Locking
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute_cancel') THEN
    RAISE EXCEPTION 'Cannot open shop dispute at this stage: %', v_status;
  END IF;

  IF p_cancel = true THEN
    UPDATE orders
    SET 
      status = 'cancelled', 
      cancelled_reason = 'shop_dispute', 
      wait_time_disputed = true,
      refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END,
      updated_at = NOW()
    WHERE id = p_order_id;
    
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    END IF;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute', updated_at = NOW()
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_shop_dispute(UUID, boolean) TO authenticated;


-- =============================================================================
-- 4. reallocate_cancelled_delivery_fees(UUID) Type-Safe Patch
-- =============================================================================
CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_cart_delivery NUMERIC;
  v_total_cart_coupon NUMERIC;
  v_original_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  v_allowed_surcharge NUMERIC;
  v_cancelled_surcharge NUMERIC;
  v_available_pool NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  v_new_coupon NUMERIC;
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_platform_gst_rate NUMERIC;
  v_delivery_gst_rate NUMERIC;
  v_rider_commission_percent NUMERIC;
  v_admin_platform_fee NUMERIC;
  v_small_cart_threshold NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_threshold_kg NUMERIC;
  v_heavy_order_fee NUMERIC;
  
  -- Coupon re-evaluation variables
  v_group_coupon_id UUID;
  v_coupon_type TEXT;
  v_coupon_val NUMERIC;
  v_coupon_cap NUMERIC;
  v_coupon_min NUMERIC;
  v_recalculated_total_discount NUMERIC := 0;
  
  rec RECORD;
  pay_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_first_cancelled_id UUID;
BEGIN
    -- JSONB-safe config reads
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

    -- Iterate per unique payment in the cart group that has cancellations/rejections
    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE; 
        END IF;

        -- Sum weight of remaining active items (Rule: Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        -- 100x FIX: Type-safe UUID MAX with MAX(coupon_id::text)::uuid
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(multi_shop_surcharge),  0),
            COALESCE(SUM(coupon_discount),       0),
            MAX(coupon_id::text)::uuid
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_original_surcharge,
            v_total_cart_coupon,
            v_group_coupon_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR delivery_charges > 0);

        -- MULTI-SHOP SURCHARGE RECALCULATION:
        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;

        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);
        v_cancelled_surcharge := GREATEST(0, v_original_surcharge - v_allowed_surcharge);
        
        v_total_cart_delivery := GREATEST(0, v_total_cart_delivery - (v_cancelled_surcharge * (1.0 + v_delivery_gst_rate)));

        -- SMALL CART FEE DYNAMIC RE-EVALUATION:
        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_new_small := v_small_cart_fee / v_active_count;
        ELSE
            v_new_small := 0;
        END IF;

        -- HEAVY ORDER FEE DYNAMIC RE-EVALUATION:
        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_new_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_new_heavy := 0;
        END IF;

        -- HANDLING FEE (PLATFORM FEE):
        v_new_plat := v_admin_platform_fee / v_active_count;

        -- DYNAMIC COUPON RE-EVALUATION:
        IF v_group_coupon_id IS NOT NULL AND v_active_items_total > 0 THEN
            SELECT type, value, max_discount, min_order_value
            INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min
            FROM public.coupons
            WHERE id = v_group_coupon_id;

            IF FOUND THEN
                IF v_active_items_total >= COALESCE(v_coupon_min, 0) THEN
                    IF v_coupon_type = 'percentage' THEN
                        v_recalculated_total_discount := v_active_items_total * (v_coupon_val / 100.0);
                        IF v_coupon_cap IS NOT NULL THEN
                            v_recalculated_total_discount := LEAST(v_recalculated_total_discount, v_coupon_cap);
                        END IF;
                    ELSIF v_coupon_type = 'flat' THEN
                        v_recalculated_total_discount := LEAST(v_coupon_val, v_active_items_total);
                    ELSE
                        v_recalculated_total_discount := v_total_cart_coupon;
                    END IF;
                ELSE
                    v_recalculated_total_discount := 0;
                END IF;
            ELSE
                v_recalculated_total_discount := v_total_cart_coupon;
            END IF;
        ELSE
            v_recalculated_total_discount := v_total_cart_coupon;
        END IF;

        FOR rec IN
            SELECT id, total_amount, gst_item_total
              FROM public.orders
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
        LOOP
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_del       := v_total_cart_delivery * v_prop;
            v_new_surcharge := v_allowed_surcharge   * v_prop;
            v_new_coupon    := v_recalculated_total_discount * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del  := v_new_del  - (v_new_del  / (1.0 + v_delivery_gst_rate));

            v_new_rider := GREATEST(0,
                (v_new_del - v_new_gst_del - v_new_small)
                * (v_rider_commission_percent / 100.0)
            );
            
            v_new_grand := GREATEST(0,
                rec.total_amount
                + rec.gst_item_total
                + v_new_plat
                + v_new_del
                + v_new_small
                + v_new_heavy
                + v_new_surcharge
                - COALESCE(v_new_coupon, 0)
            );

            UPDATE public.orders
               SET delivery_charges      = v_new_del,
                   platform_fee          = v_new_plat,
                   small_cart_fee        = v_new_small,
                   heavy_order_fee       = v_new_heavy,
                   multi_shop_surcharge  = v_new_surcharge,
                   coupon_discount       = v_new_coupon,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_del,
                   rider_earnings        = v_new_rider,
                   grand_total_collected = v_new_grand,
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;

        SELECT COALESCE(SUM(grand_total_collected), 0)
          INTO v_sum_active_grand
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        SELECT id INTO v_first_cancelled_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
         ORDER BY created_at ASC
         LIMIT 1;

        UPDATE public.orders
           SET grand_total_collected = CASE WHEN id = v_first_cancelled_id THEN v_refund_amount ELSE 0 END,
               delivery_charges      = 0,
               platform_fee          = 0,
               small_cart_fee        = 0,
               heavy_order_fee       = 0,
               multi_shop_surcharge  = 0,
               coupon_discount       = 0,
               gst_platform          = 0,
               gst_delivery          = 0,
               rider_earnings        = 0,
               updated_at            = NOW()
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

    END LOOP;

    RETURN TRUE;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reallocate_cancelled_delivery_fees(UUID) TO authenticated, service_role;


-- =============================================================================
-- 5. get_rider_stats(UUID) Type Safety & Performance Fortification
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_rider_stats(p_rider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_date         DATE;
  v_total_earnings     NUMERIC  := 0;
  v_today_earnings     NUMERIC  := 0;
  v_total_deliveries   INTEGER  := 0;
  v_total_kms          NUMERIC  := 0;
  v_week_map           NUMERIC[] := ARRAY[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  IF auth.uid() != p_rider_id AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: You can only view your own delivery stats.';
  END IF;

  -- Get IST midnight (UTC + 5:30)
  v_today_date := (NOW() AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date;

  WITH delivered AS (
    SELECT
      v_today_date
        - ((created_at AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date) AS days_ago,
      COALESCE(rider_earnings, COALESCE(delivery_charges, 0))
        + COALESCE(wait_time_penalty, 0)                                          AS charge
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND status = 'delivered'
  )
  SELECT
    COALESCE(SUM(charge),                                               0),
    COALESCE(SUM(charge) FILTER (WHERE days_ago = 0),                   0),
    COUNT(*)::int,
    ARRAY[
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 6), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 5), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 4), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 3), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 2), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 1), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 0), 0)
    ]
  INTO v_total_earnings, v_today_earnings, v_total_deliveries, v_week_map
  FROM delivered;

  -- KMS driven: max distance per cart-group (type-safe UUID COALESCE)
  SELECT COALESCE(SUM(max_dist), 0) INTO v_total_kms
  FROM (
    SELECT MAX(COALESCE(estimated_distance_km, 0)) AS max_dist
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND status = 'delivered'
    GROUP BY COALESCE(cart_group_id, id)
  ) sub;

  RETURN jsonb_build_object(
    'total_earnings',  v_total_earnings,
    'today_earnings',  v_today_earnings,
    'total_deliveries',v_total_deliveries,
    'total_kms',       v_total_kms,
    'weekly_earnings', to_jsonb(v_week_map)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_stats(UUID) TO authenticated;
