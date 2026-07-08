-- =============================================================================
-- Migration: 100x Octonary Logic Fortress (Post-Pickup Reallocation Omission)
-- Description:
--   1. Patches reallocate_cancelled_delivery_fees to include the complete
--      lifecycle of active and successfully completed states ('picked_up', 
--      'out_for_delivery', 'delivered', 'pending', 'confirmed'). This 
--      prevents the platform from stealing delivery fees from riders who 
--      have already picked up or delivered the food before a cancellation.
-- =============================================================================

CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_active_count INT;
  v_missing_delivery NUMERIC;
  v_missing_surcharge NUMERIC;
  v_missing_small NUMERIC;
  v_missing_heavy NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  rec RECORD;
BEGIN
    -- 100x FIX: Encompass the ENTIRE lifecycle of active and successful states
    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('pending', 'awaiting_acceptance', 'awaiting_payment', 'confirmed', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Aggregate missing fees from rejected/cancelled/timed out orders
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
      AND rider_earnings = 0; -- Only reallocate if rider was NOT PAID.

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;

    -- Zero out the cancelled ones (only if rider earnings is 0)
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status, rider_earnings
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel') 
          AND delivery_charges > 0
    LOOP
        IF COALESCE(rec.rider_earnings, 0) = 0 THEN
          UPDATE orders
          SET delivery_charges = 0,
              multi_shop_surcharge = 0,
              small_cart_fee = 0,
              heavy_order_fee = 0,
              gst_delivery = 0,
              grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)),
              grand_total_collected = CASE 
                  WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)) 
                  ELSE 0 
              END
          WHERE id = rec.id;
        END IF;
    END LOOP;

    -- Add to active orders
    -- 100x FIX: Encompass the ENTIRE lifecycle of active and successful states
    FOR rec IN 
        SELECT id, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('pending', 'awaiting_acceptance', 'awaiting_payment', 'confirmed', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
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
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
