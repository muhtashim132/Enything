-- =============================================================================
-- Migration: 100x Remove v_platform_gst_rate Typo
-- Description:
--   Removes an accidental line of PL/pgSQL left over from a thought process
--   that referenced an undeclared variable `v_platform_gst_rate`, causing
--   the rejection endpoint to crash.
-- =============================================================================

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
  v_total_small_cart NUMERIC;
  v_total_heavy_order NUMERIC;
  v_original_surcharge NUMERIC;
  v_pure_base_delivery NUMERIC;
  
  v_allowed_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_surcharge NUMERIC;
  
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC;
  
  rec RECORD;
  pay_rec RECORD;

  v_delivery_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);

    BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    
    BEGIN SELECT value::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);

    PERFORM id FROM orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0) INTO v_active_count, v_active_items_total
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                         'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- Extract all bundled fees so we can calculate the TRUE base delivery pool
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges), 0),
            COALESCE(SUM(small_cart_fee), 0),
            COALESCE(SUM(heavy_order_fee), 0),
            COALESCE(SUM(multi_shop_surcharge), 0)
        INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_small_cart,
            v_total_heavy_order,
            v_original_surcharge
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND (status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
               OR delivery_charges > 0);
               
        v_pure_base_delivery := GREATEST(0, v_total_cart_delivery - v_original_surcharge - v_total_small_cart - v_total_heavy_order);

        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;
        
        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);

        v_sum_active_grand := 0;

        FOR rec IN
            SELECT id, total_amount, gst_item_total, coupon_discount, platform_fee, small_cart_fee, heavy_order_fee
            FROM orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                             'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
            ORDER BY id
        LOOP
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_surcharge := v_allowed_surcharge * v_prop;
            v_new_del := (v_pure_base_delivery * v_prop) + v_new_surcharge + COALESCE(rec.small_cart_fee, 0) + COALESCE(rec.heavy_order_fee, 0);

            v_new_gst_del := v_new_del - (v_new_del / (1.0 + v_delivery_gst_rate));
            
            v_new_rider := GREATEST(0, (v_new_del - v_new_gst_del - COALESCE(rec.small_cart_fee, 0)) * (v_rider_commission_percent / 100.0));
            
            -- FIX: Safely calculate grand total using only existing columns.
            -- bundled delivery_charges contains EVERYTHING else (base+surcharge+small+heavy).
            v_new_grand := GREATEST(0, rec.total_amount + rec.gst_item_total + COALESCE(rec.platform_fee, 0) + v_new_del - COALESCE(rec.coupon_discount, 0));

            UPDATE orders
            SET delivery_charges = v_new_del,
                multi_shop_surcharge = v_new_surcharge,
                gst_delivery = v_new_gst_del,
                rider_earnings = v_new_rider,
                grand_total_collected = v_new_grand
            WHERE id = rec.id;
            
            v_sum_active_grand := v_sum_active_grand + v_new_grand;
        END LOOP;

        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        UPDATE orders
        SET grand_total_collected = v_refund_amount,
            delivery_charges = 0, platform_fee = 0, small_cart_fee = 0, heavy_order_fee = 0, multi_shop_surcharge = 0, gst_platform = 0, gst_delivery = 0, rider_earnings = 0
        WHERE id = (
            SELECT id FROM orders 
            WHERE cart_group_id = p_cart_group_id 
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
              AND delivery_charges > 0 
            ORDER BY id LIMIT 1
        );

        UPDATE orders
        SET grand_total_collected = 0,
            delivery_charges = 0, platform_fee = 0, small_cart_fee = 0, heavy_order_fee = 0, multi_shop_surcharge = 0, gst_platform = 0, gst_delivery = 0, rider_earnings = 0
        WHERE cart_group_id = p_cart_group_id 
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0;

    END LOOP;

    RETURN TRUE;
END;
$$;
