-- =============================================================================
-- Migration: 20290000000043_fix_partial_rejection_recalculation.sql
-- =============================================================================
-- Re-creates reallocate_cancelled_delivery_fees and rebalance_active_delivery_fees
-- with the following fixes:
--
--  1. platform_config JSONB extraction: Uses (value#>>'{}'  )::numeric consistently
--     for ALL config reads (the old rebalance used value::numeric which silently
--     falls back to defaults on JSONB columns).
--
--  2. Config key fix: reallocate now reads 'platform_fee_gst_rate' (the canonical
--     key name used by all other functions) instead of the old typo 'platform_gst_rate'.
--
--  3. Documentation: Clarified that rider_earnings correctly includes surcharge
--     because surcharge is embedded in the delivery_charges pool. No formula change.
--
-- NOTE: All financial logic (proportional splits, ghost-surcharge removal, platform
--   fee reversal, grand_total calculation, rider_earnings) is preserved exactly.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1.  reallocate_cancelled_delivery_fees
--     Only change: rider_earnings now includes v_new_surcharge in its base.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_available_pool NUMERIC;
  
  v_total_cart_delivery NUMERIC;
  v_total_cart_platform NUMERIC;
  v_total_cart_small NUMERIC;
  v_total_cart_heavy NUMERIC;
  v_original_surcharge NUMERIC;
  
  v_allowed_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  v_cancelled_surcharge NUMERIC;
  
  v_allowed_platform_fee NUMERIC;
  v_admin_platform_fee NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC;
  
  rec RECORD;
  pay_rec RECORD;

  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_delivery_gst_rate    FROM platform_config WHERE key = 'delivery_gst_rate';    EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_platform_gst_rate    FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);

    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_admin_surcharge_rate  FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_admin_platform_fee    FROM platform_config WHERE key = 'platform_fee';          EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);

    -- Row-level lock to avoid concurrent races
    PERFORM id FROM orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    -- Iterate once per distinct Razorpay payment boundary
    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
    LOOP
        -- How many active (non-cancelled) orders share this payment?
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- Original pool: active + newly cancelled (with delivery_charges > 0)
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(platform_fee),          0),
            COALESCE(SUM(small_cart_fee),        0),
            COALESCE(SUM(heavy_order_fee),       0),
            COALESCE(SUM(multi_shop_surcharge),  0)
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_cart_platform,
            v_total_cart_small,
            v_total_cart_heavy,
            v_original_surcharge
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR delivery_charges > 0);

        -- Surcharge allowed for the remaining active shops
        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;
        -- Never inflate beyond what was originally charged
        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);
        
        -- Cancelled ghost surcharge = difference
        v_cancelled_surcharge := GREATEST(0, v_original_surcharge - v_allowed_surcharge);
        
        -- Remove ghost surcharge (+ its delivery GST) from the master delivery pool
        v_total_cart_delivery := GREATEST(0, v_total_cart_delivery - (v_cancelled_surcharge * (1.0 + v_delivery_gst_rate)));
        
        -- Handling fee reversal: recalculate platform fee based on remaining shops
        v_allowed_platform_fee := v_admin_platform_fee * v_active_count;
        v_allowed_platform_fee := LEAST(v_allowed_platform_fee, v_total_cart_platform);

        v_sum_active_grand := 0;

        FOR rec IN
            SELECT id, total_amount, gst_item_total, coupon_discount
              FROM orders
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
             ORDER BY id
        LOOP
            -- Proportional weight by item subtotal
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_del       := v_total_cart_delivery  * v_prop;
            v_new_plat      := v_allowed_platform_fee * v_prop;
            v_new_small     := v_total_cart_small      * v_prop;
            v_new_heavy     := v_total_cart_heavy      * v_prop;
            v_new_surcharge := v_allowed_surcharge     * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del  := v_new_del  - (v_new_del  / (1.0 + v_delivery_gst_rate));

            -- ───────────────────────────────────────────────────────────────
            -- rider_earnings: v_new_del already contains the ALLOWED surcharge
            -- (only the ghost/cancelled surcharge was removed from the pool at
            -- line 151). So (v_new_del - gst - small) = base + surcharge + heavy,
            -- which matches checkout: riderBase = base + surcharge + heavy.
            -- DO NOT add v_new_surcharge again — that would double-count.
            -- ───────────────────────────────────────────────────────────────
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
                - COALESCE(rec.coupon_discount, 0)
            );

            UPDATE orders
               SET delivery_charges      = v_new_del,
                   platform_fee          = v_new_plat,
                   small_cart_fee        = v_new_small,
                   heavy_order_fee       = v_new_heavy,
                   multi_shop_surcharge  = v_new_surcharge,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_del,
                   rider_earnings        = v_new_rider,
                   grand_total_collected = v_new_grand
             WHERE id = rec.id;
            
            v_sum_active_grand := v_sum_active_grand + v_new_grand;
        END LOOP;

        -- Refund delta goes on the first cancelled order (audit trail)
        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        UPDATE orders
           SET grand_total_collected = v_refund_amount,
               delivery_charges      = 0,
               platform_fee          = 0,
               small_cart_fee        = 0,
               heavy_order_fee       = 0,
               multi_shop_surcharge  = 0,
               gst_platform          = 0,
               gst_delivery          = 0,
               rider_earnings        = 0
         WHERE id = (
             SELECT id FROM orders 
              WHERE cart_group_id = p_cart_group_id 
                AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
                AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                AND delivery_charges > 0 
              ORDER BY id LIMIT 1
         );

        -- Zero out all other cancelled orders in this payment group
        UPDATE orders
           SET grand_total_collected = 0,
               delivery_charges      = 0,
               platform_fee          = 0,
               small_cart_fee        = 0,
               heavy_order_fee       = 0,
               multi_shop_surcharge  = 0,
               gst_platform          = 0,
               gst_delivery          = 0,
               rider_earnings        = 0
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND delivery_charges > 0;

    END LOOP;

    RETURN TRUE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2.  rebalance_active_delivery_fees
--     Only change: rider_earnings now includes multi_shop_surcharge in its base.
-- ─────────────────────────────────────────────────────────────────────────────
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
  rec RECORD;
  pay_rec RECORD;
  
  v_delivery_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);

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
                   gst_delivery          = v_new_gst_delivery,
                   grand_total_collected = GREATEST(0,
                       rec.total_amount
                       + rec.gst_item_total
                       + rec.platform_fee
                       + rec.gst_platform
                       + v_net_delivery
                       - rec.coupon_discount
                   )
             WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;
