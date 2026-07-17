-- =============================================================================
-- Phase 22: Rider Wage Theft via Post-Pickup Cancellation (Reallocation Active Status Fix)
-- Description: Expands the 'active' status array in reallocate_cancelled_delivery_fees 
-- and rebalance_active_delivery_fees to include 'picked_up', 'out_for_delivery', and 'delivered'
-- to prevent riders from losing their trip fees if a multi-shop order cancels after they pick up one of the orders.
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
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_trapped_coupon NUMERIC;
  rec RECORD;
BEGIN
    -- 100x STRESS TEST FIX (Phase 8): Deterministic Bulk Locking (Deadlock & N+1 Prevention)
    PERFORM id FROM orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    -- 100x STRESS TEST FIX (Phase 22): Include post-pickup statuses as "active" so riders don't lose fees!
    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

    -- Aggregate missing fees
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

    -- Calculate TRAPPED COUPON
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
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

    -- 100x STRESS TEST FIX (Phase 21): Even if no active orders remain, 
    -- we MUST zero out the delivery charges on the cancelled orders so they don't artificially inflate platform revenue metrics.
    IF v_missing_delivery > 0 THEN
        -- Zero out the cancelled ones FIRST
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
                grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)),
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

    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;
    v_split_coupon := v_missing_coupon / v_active_count;

    -- Add to active orders (100x STRESS TEST FIX Phase 22: Add to picked_up, out_for_delivery, delivered too!)
    FOR rec IN 
        SELECT id, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
        ORDER BY id
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy);
                        
        -- 100x STRESS TEST FIX (Phase 21): Mathematically pure GST extraction
        v_new_gst_delivery := (rec.delivery_charges + v_split_delivery) - ((rec.delivery_charges + v_split_delivery) / 1.18);
        
        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            -- 100x STRESS TEST FIX (Phase 21): Add surcharges to Rider Earnings
            rider_earnings = GREATEST(0, ((rec.delivery_charges + v_split_delivery) - v_new_gst_delivery - (rec.small_cart_fee + v_split_small) + (rec.multi_shop_surcharge + v_split_surcharge) + (rec.heavy_order_fee + v_split_heavy)) * 0.80),
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            coupon_discount = rec.coupon_discount + v_split_coupon,
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;


CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
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
  v_new_gst_delivery NUMERIC;
  
  rec RECORD;
BEGIN
  -- 1. Get active count (100x STRESS TEST FIX Phase 22: Add post-pickup statuses)
  SELECT COUNT(id) INTO v_active_count
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');
    
  IF v_active_count = 0 THEN RETURN; END IF;
  
  -- 2. Sum up all fees across ALL active orders
  SELECT 
    COALESCE(SUM(delivery_charges), 0),
    COALESCE(SUM(multi_shop_surcharge), 0),
    COALESCE(SUM(small_cart_fee), 0),
    COALESCE(SUM(heavy_order_fee), 0)
  INTO v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');
    
  v_split_delivery := v_total_delivery / v_active_count;
  v_split_surcharge := v_total_surcharge / v_active_count;
  v_split_small := v_total_small / v_active_count;
  v_split_heavy := v_total_heavy / v_active_count;
  
  -- 100x STRESS TEST FIX (Phase 21): GST is inclusive, not additive.
  v_new_gst_delivery := v_split_delivery - (v_split_delivery / 1.18);
  
  -- 3. Update all active orders with the equal split
  FOR rec IN 
    SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, COALESCE(coupon_discount, 0) as coupon_discount, payment_status
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
  LOOP
    UPDATE orders
    SET delivery_charges = v_split_delivery,
        multi_shop_surcharge = v_split_surcharge,
        small_cart_fee = v_split_small,
        heavy_order_fee = v_split_heavy,
        -- 100x STRESS TEST FIX (Phase 21): Fix rider earnings to include surcharges and exact GST logic
        rider_earnings = GREATEST(0, (v_split_delivery - v_new_gst_delivery - v_split_small + v_split_surcharge + v_split_heavy) * 0.80),
        gst_delivery = v_new_gst_delivery,
        grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount),
        grand_total_collected = CASE WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount) ELSE 0 END
    WHERE id = rec.id;
  END LOOP;
END;
$$;
