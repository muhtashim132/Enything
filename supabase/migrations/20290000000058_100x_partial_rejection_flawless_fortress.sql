-- =============================================================================
-- Migration: 20290000000058_100x_partial_rejection_flawless_fortress.sql
-- =============================================================================
-- Description:
--   1. Fixes `reallocate_cancelled_delivery_fees` to include 'verification_failed',
--      'partner_rejected', and 'rider_rejected' in all cancelled/rejected lists.
--   2. Dynamically re-evaluates coupon discounts against remaining active items
--      so surviving items do not receive invalid over-discounting.
--   3. Synchronizes `rebalance_active_delivery_fees` with the unified terminal status set.
--   4. Introduces `acknowledge_partial_rejection(p_cart_group_id, p_action)` RPC
--      which permanently tags unhandled rejections as customer-resolved.
--   5. Enhances `restart_payment_timer` to automatically invoke partial rejection
--      acknowledgment, disarming false 5-minute decision timeouts.
--   6. Upgrades `cancel_order` with `p_cancel_entire_group BOOLEAN DEFAULT true` parameter
--      to allow cancelling a single pending shop without destroying accepted sibling shops.
--   7. Fortifies `safe_auto_cancel_expired_orders()` to respect customer resolution tags.
-- =============================================================================

-- ── 1. Function: acknowledge_partial_rejection ───────────────────────────────
CREATE OR REPLACE FUNCTION public.acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_cart_group_id IS NULL THEN
    RETURN;
  END IF;

  -- Lock orders in group to prevent concurrent race
  PERFORM id FROM public.orders 
  WHERE cart_group_id = p_cart_group_id 
  ORDER BY id FOR UPDATE;

  -- Tag unhandled rejected / cancelled orders as customer-acknowledged
  UPDATE public.orders
  SET 
    cancelled_reason = COALESCE(cancelled_reason, 'customer_' || p_action),
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_partial_rejection(UUID, TEXT) TO authenticated, service_role;


-- ── 2. Function: restart_payment_timer ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.restart_payment_timer(p_cart_group_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_cart_group_id IS NULL THEN
    RETURN;
  END IF;

  -- Bump the payment deadline and acceptance deadline for active orders
  UPDATE public.orders
  SET 
    payment_deadline = NOW() + INTERVAL '10 minutes',
    acceptance_deadline = NOW() + INTERVAL '3 minutes',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND customer_id = auth.uid()
    AND status IN ('awaiting_payment', 'awaiting_acceptance');

  -- Disarm partial rejection decision timeout
  PERFORM public.acknowledge_partial_rejection(p_cart_group_id, 'proceeded');
END;
$$;

GRANT EXECUTE ON FUNCTION public.restart_payment_timer(UUID) TO authenticated, service_role;


-- ── 3. Function: cancel_order (Selective Single Shop / Full Group) ────────────
-- Drop previous signature to prevent overload conflicts
DROP FUNCTION IF EXISTS public.cancel_order(UUID, TEXT);
DROP FUNCTION IF EXISTS public.cancel_order(UUID, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_reason TEXT,
  p_cancel_entire_group BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- Authorization check
  IF auth.uid() IS NULL OR (NOT COALESCE(v_is_customer, false) AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL AND p_cancel_entire_group THEN
    -- Cancel ALL active/pending orders in the cart group
    FOR v_rec IN 
      SELECT id, status, payment_status, refund_status 
      FROM public.orders 
      WHERE cart_group_id = v_cart_group_id 
      ORDER BY id FOR UPDATE 
    LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE public.orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
    
    PERFORM public.reallocate_cancelled_delivery_fees(v_cart_group_id);
    PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
    
  ELSE
    -- Selective single order cancellation (e.g. "Cancel Pending Shops" without cancelling accepted siblings)
    FOR v_rec IN 
      SELECT id, status, payment_status, refund_status 
      FROM public.orders 
      WHERE id = p_order_id 
      FOR UPDATE 
    LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE public.orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;

    -- Rebalance remaining active orders in the cart group
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM public.reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT, BOOLEAN) TO authenticated, service_role;


-- ── 4. Function: reallocate_cancelled_delivery_fees ──────────────────────────
CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(multi_shop_surcharge),  0),
            COALESCE(SUM(coupon_discount),       0),
            MAX(coupon_id)
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
        -- Split equally across active shops
        v_new_plat := v_admin_platform_fee / v_active_count;

        -- DYNAMIC COUPON RE-EVALUATION:
        -- Recompute discount on active food total to prevent over-discounting
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
                    -- Subtotal no longer meets minimum order value requirement
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


-- ── 5. Function: rebalance_active_delivery_fees ──────────────────────────────
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_split_plat NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_new_plat NUMERIC;
  v_new_gst_plat NUMERIC;
  rec RECORD;
  pay_rec RECORD;
  
  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
  v_admin_platform_fee numeric;
  v_admin_surcharge_rate numeric;
  v_small_cart_threshold numeric;
  v_small_cart_fee numeric;
  v_heavy_order_threshold_kg numeric;
  v_heavy_order_fee numeric;
BEGIN
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

    -- Lock rows to prevent concurrency race
    PERFORM id FROM public.orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
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

        -- Active weight total (Rule: Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        SELECT 
            COALESCE(SUM(delivery_charges),     0),
            COALESCE(SUM(multi_shop_surcharge), 0)
          INTO 
            v_total_delivery, v_total_surcharge
          FROM public.orders 
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_split_delivery := v_total_delivery / v_active_count;

        IF v_active_count > 1 THEN
            v_split_surcharge := (v_admin_surcharge_rate * (v_active_count - 1)) / v_active_count;
        ELSE
            v_split_surcharge := 0;
        END IF;

        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_split_small := v_small_cart_fee / v_active_count;
        ELSE
            v_split_small := 0;
        END IF;

        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_split_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_split_heavy := 0;
        END IF;

        v_split_plat := v_admin_platform_fee / v_active_count;

        FOR rec IN 
            SELECT id, total_amount, gst_item_total,
                   COALESCE(coupon_discount, 0) AS coupon_discount
              FROM public.orders 
             WHERE cart_group_id = p_cart_group_id 
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
             ORDER BY id
        LOOP
            v_net_delivery := v_split_delivery;
            v_new_gst_delivery := v_split_delivery - (v_split_delivery / (1.0 + v_delivery_gst_rate));
            v_new_plat := v_split_plat;
            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            
            UPDATE public.orders
               SET delivery_charges      = v_split_delivery,
                   rider_earnings        = GREATEST(0,
                       (v_split_delivery - v_new_gst_delivery - v_split_small)
                       * (v_rider_commission_percent / 100.0)
                   ),
                   multi_shop_surcharge  = v_split_surcharge,
                   small_cart_fee        = v_split_small,
                   heavy_order_fee       = v_split_heavy,
                   platform_fee          = v_new_plat,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_delivery,
                   grand_total_collected = GREATEST(0,
                       rec.total_amount
                       + rec.gst_item_total
                       + v_new_plat
                       + v_net_delivery
                       + v_split_small
                       + v_split_heavy
                       + v_split_surcharge
                       - rec.coupon_discount
                   ),
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(UUID) TO authenticated, service_role;


-- ── 6. Function: safe_auto_cancel_expired_orders ─────────────────────────────
CREATE OR REPLACE FUNCTION public.safe_auto_cancel_expired_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_group RECORD;
BEGIN
  -- 1. Awaiting Acceptance Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM public.orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM public.orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM public.orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM public.reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM public.rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 2. Awaiting Payment Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM public.orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM public.orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM public.orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_reason = 'payment_failed',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM public.reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM public.rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 3. Ghosted Prep Orders Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM public.orders 
    WHERE status IN ('confirmed', 'preparing') 
      AND payment_deadline IS NOT NULL 
      AND payment_deadline < (NOW() - INTERVAL '1.5 hours')
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM public.orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM public.orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_reason = 'Auto-cancelled: Seller ghosted preparation',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM public.reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM public.rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 4. 100x Partial Rejection Decision Timeout (5 minutes)
  -- ONLY targets UNRESOLVED rejections where the customer has NOT acknowledged / proceeded / replaced.
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM public.orders
    WHERE cart_group_id IS NOT NULL
    GROUP BY cart_group_id
    HAVING 
      COUNT(CASE WHEN status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN 1 END) > 0
      AND 
      COUNT(CASE WHEN status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled') THEN 1 END) > 0
      AND
      -- Exclude groups where the rejection was already acknowledged, replaced, or handled by customer
      COUNT(CASE WHEN COALESCE(cancelled_reason, '') LIKE 'customer%' THEN 1 END) = 0
      AND
      -- Calculate deadline from MAX(updated_at) of unhandled rejections
      MAX(CASE WHEN status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled') 
                    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%' 
               THEN COALESCE(updated_at, created_at) END) + INTERVAL '5 minutes' < NOW()
    LIMIT 100
  LOOP
    PERFORM id FROM public.orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;

    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE cart_group_id = v_group.cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
      
    PERFORM public.reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    PERFORM public.rebalance_active_delivery_fees(v_group.cart_group_id);
  END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.safe_auto_cancel_expired_orders() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
