-- =============================================================================
-- Migration: 100x Reallocation Dynamic Rates Fix
-- Description:
--   The reallocate_cancelled_delivery_fees function used HARDCODED values:
--     - 0.80  (80%) for rider commission
--     - 1.18  (18% GST) for delivery GST
--   But place_orders_transaction and rebalance_active_delivery_fees both read
--   these dynamically from platform_config. If an admin changes either rate,
--   the initial checkout uses the new rate, but any subsequent reallocation
--   (after a seller rejection or customer cancellation) silently reverted to
--   the hardcoded values, causing financial mismatches.
--
--   This fix is 100% ADDITIVE:
--     - Only the SOURCE of rate values changes (hardcoded → dynamic)
--     - All math formulas remain byte-identical
--     - Zero schema/RLS/trigger changes
--     - Instantly undoable by re-deploying the previous migration
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
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
  v_new_gst_delivery NUMERIC;
  v_trapped_coupon NUMERIC;
  v_refunded_delivery_portion NUMERIC;
  rec RECORD;
  pay_rec RECORD;

  -- 100x FIX: Dynamic admin rates (matching rebalance_active_delivery_fees pattern)
  v_delivery_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    -- Read dynamic rates from platform_config with safe fallback defaults
    BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);

    BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);

    PERFORM id FROM orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    -- 100x FIX: Isolate reallocation strictly to Razorpay payment boundaries.
    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
    LOOP
        SELECT COUNT(id) INTO v_active_count
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                         'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

        -- 100x FIX: Prevent single-shop cancellation delivery fee theft
        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        v_missing_coupon := 0;

        SELECT
            COALESCE(SUM(delivery_charges), 0),
            COALESCE(SUM(multi_shop_surcharge), 0),
            COALESCE(SUM(small_cart_fee), 0),
            COALESCE(SUM(heavy_order_fee), 0)
        INTO
            v_missing_delivery, v_missing_surcharge, v_missing_small, v_missing_heavy
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0;

        FOR rec IN
            SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
            FROM orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
              AND delivery_charges > 0
              AND COALESCE(rider_earnings, 0) = 0
            ORDER BY id
        LOOP
            v_trapped_coupon := COALESCE(rec.coupon_discount, 0) - (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform);
            IF v_trapped_coupon > 0 THEN
                v_missing_coupon := v_missing_coupon + v_trapped_coupon;
                UPDATE orders
                SET coupon_discount = (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform)
                WHERE id = rec.id;
            END IF;
        END LOOP;

        IF v_missing_delivery > 0 THEN
            FOR rec IN
                SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status
                FROM orders
                WHERE cart_group_id = p_cart_group_id
                  AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
                  AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                  AND delivery_charges > 0
                  AND COALESCE(rider_earnings, 0) = 0
                ORDER BY id
            LOOP
                UPDATE orders
                SET delivery_charges = 0,
                    multi_shop_surcharge = 0,
                    small_cart_fee = 0,
                    heavy_order_fee = 0,
                    gst_delivery = 0,
                    grand_total_collected = CASE 
                        WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)) 
                        ELSE 0 
                    END
                WHERE id = rec.id;
            END LOOP;
        END IF;

        IF v_missing_delivery = 0 THEN
            CONTINUE;
        END IF;

        -- 100x FIX: Use dynamic GST rate instead of hardcoded 1.18
        v_refunded_delivery_portion := (v_missing_surcharge + v_missing_heavy) * (1.0 + v_delivery_gst_rate);
        v_missing_delivery := GREATEST(0, v_missing_delivery - v_refunded_delivery_portion);

        v_split_delivery := v_missing_delivery / v_active_count;
        v_split_surcharge := 0; 
        v_split_heavy := 0;
        v_split_small := v_missing_small / v_active_count;
        v_split_coupon := v_missing_coupon / v_active_count;

        FOR rec IN
            SELECT id, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
                   total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
                   COALESCE(coupon_discount, 0) AS coupon_discount
            FROM orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                             'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
            ORDER BY id
        LOOP
            -- 100x FIX: Use dynamic GST rate instead of hardcoded 1.18
            v_new_gst_delivery := (rec.delivery_charges + v_split_delivery) - ((rec.delivery_charges + v_split_delivery) / (1.0 + v_delivery_gst_rate));

            UPDATE orders
            SET delivery_charges = rec.delivery_charges + v_split_delivery,
                -- 100x FIX: Use dynamic rider commission instead of hardcoded 0.80
                rider_earnings = GREATEST(0, ((rec.delivery_charges + v_split_delivery) - v_new_gst_delivery - (rec.small_cart_fee + v_split_small)) * (v_rider_commission_percent / 100.0)),
                multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
                small_cart_fee = rec.small_cart_fee + v_split_small,
                heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
                coupon_discount = rec.coupon_discount + v_split_coupon,
                gst_delivery = v_new_gst_delivery,
                grand_total_collected = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + (rec.delivery_charges + v_split_delivery) - (rec.coupon_discount + v_split_coupon))
            WHERE id = rec.id;
        END LOOP;
    END LOOP;

    RETURN TRUE;
END;
$$;
