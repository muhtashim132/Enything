-- Migration: 100x Partial Rejection Regression Fix
-- Description: Restores gst_platform and unpaid cancelled order logic 
-- (payment_status check) which were accidentally removed in migration 18, 
-- while keeping the surcharge and heavy fee refund fixes from migration 19.

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
BEGIN
    PERFORM id FROM orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    SELECT COUNT(id) INTO v_active_count
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                     'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

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

    FOR rec IN
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
        ORDER BY id
    LOOP
        -- FIX: Restore gst_platform to trapped coupon calculation
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
                -- FIX: Restore payment_status logic and gst_platform so unpaid cancelled orders get 0 grand_total_collected
                grand_total_collected = CASE 
                    WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)) 
                    ELSE 0 
                END
            WHERE id = rec.id;
        END LOOP;
    END IF;

    IF v_active_count = 0 OR v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    -- Rider loses it, customer is refunded. We must subtract these from v_missing_delivery.
    -- These fees are inside delivery_charges with 18% GST.
    v_refunded_delivery_portion := (v_missing_surcharge + v_missing_heavy) * 1.18;
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
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                         'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
        ORDER BY id
    LOOP
        v_new_gst_delivery := (rec.delivery_charges + v_split_delivery) - ((rec.delivery_charges + v_split_delivery) / 1.18);

        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            -- delivery_charges already includes multi_shop_surcharge and heavy_order_fee.
            -- Do not explicitly add them here. Only subtract gst and small_cart_fee to find the rider's base pay.
            rider_earnings = GREATEST(0, ((rec.delivery_charges + v_split_delivery) - v_new_gst_delivery - (rec.small_cart_fee + v_split_small)) * 0.80),
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            coupon_discount = rec.coupon_discount + v_split_coupon,
            gst_delivery = v_new_gst_delivery,
            -- FIX: Restore gst_platform logic for active orders
            grand_total_collected = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + (rec.delivery_charges + v_split_delivery) - (rec.coupon_discount + v_split_coupon))
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;
