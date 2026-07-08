-- =============================================================================
-- Migration: 100x Dual Blackhole Refund & Rider Underpayment Fix
-- Description:
--   1. Fixes the "Customer Refund Blackhole" in `reallocate_cancelled_delivery_fees`
--      by preserving the `grand_total_collected` amount minus delivery fees, rather
--      than blindly setting it to 0. This ensures the refund worker correctly
--      refunds the food portion of a partially rejected multi-shop cart.
--   2. Fixes the "Rider Underpayment Blackhole" by correctly targeting active
--      orders across ALL active states ('awaiting_acceptance', 'awaiting_payment',
--      'pending_pickup', 'accepted') rather than just 'awaiting_payment'.
-- =============================================================================

CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_active_count int;
    
    v_missing_delivery numeric;
    v_missing_rider numeric;
    v_missing_surcharge numeric;
    v_missing_small numeric;
    v_missing_heavy numeric;
    v_missing_discount numeric;

    v_split_delivery numeric;
    v_split_rider numeric;
    v_split_surcharge numeric;
    v_split_small numeric;
    v_split_heavy numeric;
    v_split_discount numeric;
    
    v_net_delivery numeric;
    v_new_gst_delivery numeric;
    rec RECORD;
BEGIN
    -- Count active orders in the cart (expanded to ensure NO active order is skipped)
    SELECT COUNT(*) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Aggregate missing fees from rejected/cancelled orders
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

    -- Zero out the cancelled ones, while PRESERVING the customer's right to a refund
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status
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
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)),
            -- 100x FIX 1: Preserve grand_total_collected so the edge function actually refunds the customer's food!
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    -- Add to active orders (Prevent Rider Underpayment Blackhole)
    FOR rec IN 
        SELECT id, delivery_charges, rider_earnings, multi_shop_surcharge, small_cart_fee, heavy_order_fee, delivery_discount,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          -- 100x FIX 2: Added 'pending_pickup' and 'accepted' to ensure already-paid carts don't blackhole the delivery fees.
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted')
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
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount),
            -- 100x FIX 3: Accurately reflect that the delivery fee collection moved to this active order.
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;
