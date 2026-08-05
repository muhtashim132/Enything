-- Migration: 100x Multishop Surcharge Fix
-- Description: Updates reallocate_cancelled_delivery_fees to NOT reallocate the multi-shop 
-- surcharge when an order is cancelled. This ensures the rider loses the surcharge 
-- for the cancelled shop and the customer can be fully refunded for it.

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
        v_trapped_coupon := COALESCE(rec.coupon_discount, 0) - (rec.total_amount + rec.gst_item_total + rec.platform_fee );
        IF v_trapped_coupon > 0 THEN
            v_missing_coupon := v_missing_coupon + v_trapped_coupon;
            UPDATE orders
            SET coupon_discount = (rec.total_amount + rec.gst_item_total + rec.platform_fee )
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
                grand_total_collected = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee  - COALESCE(coupon_discount, 0))
            WHERE id = rec.id;
        END LOOP;
    END IF;

    IF v_active_count = 0 OR v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    v_split_delivery := v_missing_delivery / v_active_count;
    
    -- 100x FIX: DO NOT REALLOCATE MULTI-SHOP SURCHARGE. Rider loses it, customer is refunded.
    v_split_surcharge := 0; 
    
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;
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
            rider_earnings = GREATEST(0, ((rec.delivery_charges + v_split_delivery) - v_new_gst_delivery - (rec.small_cart_fee + v_split_small) + (rec.multi_shop_surcharge + v_split_surcharge) + (rec.heavy_order_fee + v_split_heavy)) * 0.80),
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            coupon_discount = rec.coupon_discount + v_split_coupon,
            gst_delivery = v_new_gst_delivery,
            grand_total_collected = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee  + (rec.delivery_charges + v_split_delivery) - (rec.coupon_discount + v_split_coupon))
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;
