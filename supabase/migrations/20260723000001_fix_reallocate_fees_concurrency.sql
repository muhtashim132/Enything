-- =============================================================================
-- Migration: Fix Concurrent Fee Reallocation
-- Description: Adds FOR UPDATE lock to reallocate_cancelled_delivery_fees to 
-- prevent duplicate reallocation if multiple sellers reject concurrently.
-- =============================================================================

CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_missing_delivery NUMERIC := 0;
    v_missing_rider NUMERIC := 0;
    v_missing_surcharge NUMERIC := 0;
    v_missing_small NUMERIC := 0;
    v_missing_heavy NUMERIC := 0;
    v_missing_discount NUMERIC := 0;
    v_active_count INT := 0;
    v_split_delivery NUMERIC;
    v_split_rider NUMERIC;
    v_split_surcharge NUMERIC;
    v_split_small NUMERIC;
    v_split_heavy NUMERIC;
    v_split_discount NUMERIC;
    rec RECORD;
    v_net_delivery NUMERIC;
    v_new_gst_delivery NUMERIC;
BEGIN
    -- Explicitly lock ALL orders for this cart_group_id to prevent concurrent reallocations
    PERFORM id FROM orders WHERE cart_group_id = p_cart_group_id FOR UPDATE;

    -- Only run if there's a mix of active and cancelled orders where delivery > 0
    SELECT COUNT(*) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status = 'awaiting_payment';

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Sum up fees from cancelled orders that haven't been absorbed yet
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(rider_earnings), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0),
        COALESCE(SUM(delivery_discount), 0)
    INTO 
        v_missing_delivery, v_missing_rider, v_missing_surcharge, v_missing_small, v_missing_heavy, v_missing_discount
    FROM orders
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected')
      AND delivery_charges > 0;

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    -- Split among active orders
    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_rider := v_missing_rider / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;
    v_split_discount := v_missing_discount / v_active_count;

    -- Zero out the cancelled ones
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform 
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected') 
          AND delivery_charges > 0
    LOOP
        UPDATE orders
        SET delivery_charges = 0,
            rider_earnings = 0,
            multi_shop_surcharge = 0,
            small_cart_fee = 0,
            heavy_order_fee = 0,
            delivery_discount = 0,
            gst_delivery = 0,
            grand_total = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform,
            grand_total_collected = 0
        WHERE id = rec.id;
    END LOOP;

    -- Add to active orders
    FOR rec IN 
        SELECT id, delivery_charges, rider_earnings, multi_shop_surcharge, small_cart_fee, heavy_order_fee, delivery_discount,
               total_amount, gst_item_total, platform_fee, gst_platform
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status = 'awaiting_payment'
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy)
                        - (rec.delivery_discount + v_split_discount);
                        
        -- Extract 18% embedded GST: net - (net / 1.18)
        v_new_gst_delivery := v_net_delivery - (v_net_delivery / 1.18);
        
        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            rider_earnings = rec.rider_earnings + v_split_rider,
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            delivery_discount = rec.delivery_discount + v_split_discount,
            gst_delivery = v_new_gst_delivery,
            -- Recalculate grand_total
            grand_total = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery,
            grand_total_collected = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;
