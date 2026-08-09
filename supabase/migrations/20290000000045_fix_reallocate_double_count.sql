-- 100x FIX: Remove double-counting of bundled delivery fees from v_new_grand
-- The delivery_charges column (and thus v_new_del) ALREADY includes the multi_shop_surcharge,
-- small_cart_fee, and heavy_order_fee. Adding them again inflates grand_total_collected.

CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_total_cart_delivery NUMERIC;
  v_total_cart_platform NUMERIC;
  v_total_cart_small NUMERIC;
  v_total_cart_heavy NUMERIC;
  v_total_cart_coupon NUMERIC;
  v_original_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  v_allowed_surcharge NUMERIC;
  v_cancelled_surcharge NUMERIC;
  v_available_pool NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  v_new_coupon NUMERIC;
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_platform_gst_rate NUMERIC;
  v_delivery_gst_rate NUMERIC;
  v_rider_commission_percent NUMERIC;
  
  rec RECORD;
  pay_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_first_cancelled_id UUID;
BEGIN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    
    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE; 
        END IF;

        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(platform_fee),          0),
            COALESCE(SUM(small_cart_fee),        0),
            COALESCE(SUM(heavy_order_fee),       0),
            COALESCE(SUM(multi_shop_surcharge),  0),
            COALESCE(SUM(coupon_discount),       0)
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_cart_platform,
            v_total_cart_small,
            v_total_cart_heavy,
            v_original_surcharge,
            v_total_cart_coupon
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR delivery_charges > 0);

        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;

        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);
        v_cancelled_surcharge := GREATEST(0, v_original_surcharge - v_allowed_surcharge);
        
        v_total_cart_delivery := GREATEST(0, v_total_cart_delivery - (v_cancelled_surcharge * (1.0 + v_delivery_gst_rate)));

        FOR rec IN
            SELECT id, total_amount, gst_item_total, coupon_discount
              FROM orders
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
        LOOP
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_del       := v_total_cart_delivery  * v_prop;
            v_new_plat      := v_total_cart_platform  * v_prop;
            v_new_small     := v_total_cart_small     * v_prop;
            v_new_heavy     := v_total_cart_heavy     * v_prop;
            v_new_surcharge := v_allowed_surcharge     * v_prop;
            v_new_coupon    := v_total_cart_coupon    * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del  := v_new_del  - (v_new_del  / (1.0 + v_delivery_gst_rate));

            v_new_rider := GREATEST(0,
                (v_new_del - v_new_gst_del - v_new_small)
                * (v_rider_commission_percent / 100.0)
            );
            
            -- BUG FIX: v_new_del ALREADY contains v_new_small, v_new_heavy, and v_new_surcharge.
            -- Adding them again mathematically double-counts them, inflating grand_total_collected.
            v_new_grand := GREATEST(0,
                rec.total_amount
                + rec.gst_item_total
                + v_new_plat
                + v_new_del
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
        END LOOP;

        SELECT COALESCE(SUM(grand_total_collected), 0)
          INTO v_sum_active_grand
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        SELECT id INTO v_first_cancelled_id
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND delivery_charges > 0
         ORDER BY created_at ASC
         LIMIT 1;

        UPDATE orders
           SET grand_total_collected = CASE WHEN id = v_first_cancelled_id THEN v_refund_amount ELSE 0 END,
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
           AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

    END LOOP;

    RETURN TRUE;
END;
$function$;
