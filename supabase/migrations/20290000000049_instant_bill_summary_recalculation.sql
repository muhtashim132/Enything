-- =============================================================================
-- Migration: 20290000000049_instant_bill_summary_recalculation.sql
-- =============================================================================
-- Description:
--   Recalculates Bill Summary (Multi-shop surcharge, Total GST, Item Subtotal,
--   Handling Fee, Delivery Fee, Small Cart Fee, Heavy Order Fee, Wait Time Penalty)
--   dynamically and instantly whenever shop rejections/cancellations occur or when
--   new products/shops are added after partial order rejection.
--
-- Key Business Logic Enforced:
--   1. Multi-shop surcharge is ONLY applicable when active_shops > 1:
--      - 3 active shops = 2 surcharges.
--      - 1 shop declines (2 active) = 1 surcharge.
--      - 2 shops decline (1 active) = 0 surcharge.
--   2. Handling Fee (Platform Fee): Calculated ONCE per cart group (admin rate, e.g. ₹20),
--      split equally among active shops (v_admin_platform_fee / active_shops).
--   3. Small Cart Fee: Dynamically re-evaluated on aggregate food subtotal across active
--      shops against `small_cart_threshold`. Applied if subtotal < threshold, 0 otherwise.
--   4. Heavy Order Fee: Dynamically re-evaluated on total active item weight across active
--      shops against `heavy_order_threshold_kg`. Applied if weight > threshold, 0 otherwise.
--   5. Base Delivery Charges: Maintained for the cart group, split across active shops.
--   6. Total GST: Item GST + Delivery GST + Platform GST.
--   7. Rider Earnings & Grand Total: Recalculated atomically and updated with `updated_at = NOW()`
--      so Supabase Realtime notifies Customer & Rider instantly.
-- =============================================================================

-- 1. Update `reallocate_cancelled_delivery_fees`
CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_cart_delivery NUMERIC;
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
  v_admin_platform_fee NUMERIC;
  v_small_cart_threshold NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_threshold_kg NUMERIC;
  v_heavy_order_fee NUMERIC;
  
  rec RECORD;
  pay_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_first_cancelled_id UUID;
BEGIN
    -- JSONB-safe config reads
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

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

        -- Sum weight of remaining active items (Rule:Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          JOIN products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(multi_shop_surcharge),  0),
            COALESCE(SUM(coupon_discount),       0)
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_original_surcharge,
            v_total_cart_coupon
          FROM orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR delivery_charges > 0);

        -- MULTI-SHOP SURCHARGE RECALCULATION:
        -- Only applicable when active count > 1.
        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;

        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);
        v_cancelled_surcharge := GREATEST(0, v_original_surcharge - v_allowed_surcharge);
        
        v_total_cart_delivery := GREATEST(0, v_total_cart_delivery - (v_cancelled_surcharge * (1.0 + v_delivery_gst_rate)));

        -- SMALL CART FEE DYNAMIC RE-EVALUATION:
        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_new_small := v_small_cart_fee / v_active_count;
        ELSE
            v_new_small := 0;
        END IF;

        -- HEAVY ORDER FEE DYNAMIC RE-EVALUATION:
        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_new_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_new_heavy := 0;
        END IF;

        -- HANDLING FEE (PLATFORM FEE):
        -- Calculated ONCE for the order group, split equally across active shops
        v_new_plat := v_admin_platform_fee / v_active_count;

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
            v_new_surcharge := v_allowed_surcharge     * v_prop;
            v_new_coupon    := v_total_cart_coupon    * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del  := v_new_del  - (v_new_del  / (1.0 + v_delivery_gst_rate));

            v_new_rider := GREATEST(0,
                (v_new_del - v_new_gst_del - v_new_small)
                * (v_rider_commission_percent / 100.0)
            );
            
            v_new_grand := GREATEST(0,
                rec.total_amount
                + rec.gst_item_total
                + v_new_plat
                + v_new_del
                + v_new_small
                + v_new_heavy
                + v_new_surcharge
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
                   grand_total_collected = v_new_grand,
                   updated_at            = NOW()
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
               rider_earnings        = 0,
               updated_at            = NOW()
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel');

    END LOOP;

    RETURN TRUE;
END;
$function$;


-- 2. Update `rebalance_active_delivery_fees`
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_split_plat NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_new_plat NUMERIC;
  v_new_gst_plat NUMERIC;
  rec RECORD;
  pay_rec RECORD;
  
  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
  v_admin_platform_fee numeric;
  v_admin_surcharge_rate numeric;
  v_small_cart_threshold numeric;
  v_small_cart_fee numeric;
  v_heavy_order_threshold_kg numeric;
  v_heavy_order_fee numeric;
BEGIN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

    -- Lock rows to prevent concurrency race
    PERFORM id FROM orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM orders 
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- Active weight total (Rule:Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          JOIN products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        SELECT 
            COALESCE(SUM(delivery_charges),     0),
            COALESCE(SUM(multi_shop_surcharge), 0)
          INTO 
            v_total_delivery, v_total_surcharge
          FROM orders 
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_split_delivery := v_total_delivery / v_active_count;

        IF v_active_count > 1 THEN
            v_split_surcharge := (v_admin_surcharge_rate * (v_active_count - 1)) / v_active_count;
        ELSE
            v_split_surcharge := 0;
        END IF;

        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_split_small := v_small_cart_fee / v_active_count;
        ELSE
            v_split_small := 0;
        END IF;

        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_split_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_split_heavy := 0;
        END IF;

        v_split_plat := v_admin_platform_fee / v_active_count;

        FOR rec IN 
            SELECT id, total_amount, gst_item_total, platform_fee, gst_platform,
                   COALESCE(coupon_discount, 0) AS coupon_discount, payment_status,
                   delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee
              FROM orders 
             WHERE cart_group_id = p_cart_group_id 
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
             ORDER BY id
        LOOP
            v_net_delivery := v_split_delivery;
            v_new_gst_delivery := v_split_delivery - (v_split_delivery / (1.0 + v_delivery_gst_rate));
            v_new_plat := v_split_plat;
            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            
            UPDATE orders
               SET delivery_charges      = v_split_delivery,
                   rider_earnings        = GREATEST(0,
                       (v_split_delivery - v_new_gst_delivery - v_split_small)
                       * (v_rider_commission_percent / 100.0)
                   ),
                   multi_shop_surcharge  = v_split_surcharge,
                   small_cart_fee        = v_split_small,
                   heavy_order_fee       = v_split_heavy,
                   platform_fee          = v_new_plat,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_delivery,
                   grand_total_collected = GREATEST(0,
                       rec.total_amount
                       + rec.gst_item_total
                       + v_new_plat
                       + v_net_delivery
                       + v_split_small
                       + v_split_heavy
                       + v_split_surcharge
                       - rec.coupon_discount
                   ),
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;
