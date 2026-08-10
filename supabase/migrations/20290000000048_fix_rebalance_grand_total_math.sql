-- =============================================================================
-- Migration: 20290000000048_fix_rebalance_grand_total_math.sql
-- =============================================================================
-- BUG FIX: The `rebalance_active_delivery_fees` function was computing
-- `grand_total_collected` WITHOUT including `small_cart_fee`, `heavy_order_fee`,
-- and `multi_shop_surcharge`. The sister function `reallocate_cancelled_delivery_fees`
-- was fixed in migration 47 but `rebalance` was not.
--
-- Also fixes:
--   1. JSONB extraction: Uses (value#>>'{}'  )::numeric (migration 42 used
--      the old value::numeric which fails on JSONB columns).
--   2. Platform fee reversal: Reads admin platform_fee rate to dynamically
--      recalculate handling fee when shops change.
--   3. GST platform recalculation: Updates gst_platform based on the new
--      platform_fee after reversal.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_active_count INT;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_total_small NUMERIC;
  v_total_heavy NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
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
BEGIN
    -- JSONB-safe config reads (consistent with reallocate function)
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);

    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);

    -- Row-level lock to avoid concurrent races
    PERFORM id FROM orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    -- Isolate rebalancing strictly to Razorpay payment boundaries
    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id) INTO v_active_count 
          FROM orders 
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- Only sum active orders
        SELECT 
            COALESCE(SUM(delivery_charges),     0),
            COALESCE(SUM(multi_shop_surcharge), 0),
            COALESCE(SUM(small_cart_fee),       0),
            COALESCE(SUM(heavy_order_fee),      0)
          INTO 
            v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
          FROM orders 
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_split_delivery  := v_total_delivery  / v_active_count;
        v_split_surcharge := v_total_surcharge / v_active_count;
        v_split_small     := v_total_small     / v_active_count;
        v_split_heavy     := v_total_heavy     / v_active_count;

        FOR rec IN 
            SELECT id, total_amount, gst_item_total, platform_fee, gst_platform,
                   COALESCE(coupon_discount, 0) AS coupon_discount, payment_status,
                   delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee
              FROM orders 
             WHERE cart_group_id = p_cart_group_id 
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
             ORDER BY id
        LOOP
            v_net_delivery := v_split_delivery;
            
            v_new_gst_delivery := v_split_delivery - (v_split_delivery / (1.0 + v_delivery_gst_rate));

            -- Platform fee: use the admin rate per shop (consistent with reallocate)
            v_new_plat := v_admin_platform_fee;
            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            
            -- ───────────────────────────────────────────────────────────────
            -- rider_earnings: v_split_delivery already contains surcharge
            -- (since surcharge was bundled into delivery_charges at checkout).
            -- So (delivery - gst - small) = base + surcharge + heavy.
            -- Consistent with checkout and reallocate logic.
            -- ───────────────────────────────────────────────────────────────
            UPDATE orders
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
                   -- FIX: Include small_cart_fee, heavy_order_fee, multi_shop_surcharge
                   -- in grand_total_collected (was missing, causing incorrect totals).
                   -- Matches the formula in reallocate_cancelled_delivery_fees (migration 47).
                   grand_total_collected = GREATEST(0,
                       rec.total_amount
                       + rec.gst_item_total
                       + v_new_plat
                       + v_net_delivery
                       + v_split_small
                       + v_split_heavy
                       + v_split_surcharge
                       - rec.coupon_discount
                   )
             WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;
