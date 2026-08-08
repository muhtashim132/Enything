-- =============================================================================
-- Migration: 20290000000042_fix_rebalance_unpaid_grand_total.sql
-- Description:
--   BUGFIX: Fixes a logical flaw in `rebalance_active_delivery_fees` where
--   the `grand_total_collected` of active unpaid (pending) replacement orders
--   was incorrectly zeroed out by the `ELSE 0` clause, causing the
--   Razorpay payment gateway to fail with "Minimum 100 paise" because
--   the calculated `dbAmount` evaluated to 0.
--   
--   This is identical to the fix applied to `reallocate_cancelled_delivery_fees`
--   in `20290000000001_fix_reallocate_unpaid_grand_total.sql`.
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
  rec RECORD;
  pay_rec RECORD;
  
  v_delivery_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    
    BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);

    PERFORM id FROM orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    -- 100x FIX: Isolate rebalancing strictly to Razorpay payment boundaries.
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

        -- 100x FIX: Only sum active orders. Old code summed all orders indiscriminately.
        SELECT 
            COALESCE(SUM(delivery_charges), 0),
            COALESCE(SUM(multi_shop_surcharge), 0),
            COALESCE(SUM(small_cart_fee), 0),
            COALESCE(SUM(heavy_order_fee), 0)
        INTO 
            v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
        FROM orders 
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_split_delivery := v_total_delivery / v_active_count;
        v_split_surcharge := v_total_surcharge / v_active_count;
        v_split_small := v_total_small / v_active_count;
        v_split_heavy := v_total_heavy / v_active_count;

        FOR rec IN 
            SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, COALESCE(coupon_discount, 0) AS coupon_discount, payment_status,
                   delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee
            FROM orders 
            WHERE cart_group_id = p_cart_group_id 
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
            ORDER BY id
        LOOP
            v_net_delivery := v_split_delivery;
            
            v_new_gst_delivery := v_split_delivery - (v_split_delivery / (1.0 + v_delivery_gst_rate));
            
            UPDATE orders
            SET delivery_charges = v_split_delivery,
                rider_earnings = GREATEST(0, (v_split_delivery - v_new_gst_delivery - v_split_small) * (v_rider_commission_percent / 100.0)),
                multi_shop_surcharge = v_split_surcharge,
                small_cart_fee = v_split_small,
                heavy_order_fee = v_split_heavy,
                gst_delivery = v_new_gst_delivery,
                grand_total_collected = CASE 
                    WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount) 
                    ELSE GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount)
                END
            WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;
