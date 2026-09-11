-- =============================================================================
-- Migration: 20290000000123_100x_fix_weight_resolution_in_reallocation.sql
-- Description:
--   100x Intelligent Weight Resolution in Delivery Fee Reallocation & Rebalance.
--   Root Cause Fix: Previously, reallocate_cancelled_delivery_fees bypassed
--   order_items.weight_kg and directly summed oi.quantity * p.weight_per_unit
--   without unit normalization. For products where sellers entered weight in
--   grams (e.g. 500 grams for jeans), it treated 500 as 500 Kilograms, creating
--   a phantom 491kg excess weight and inflating Heavy Order Fee by +₹12,275.
--
--   This migration upgrades reallocate_cancelled_delivery_fees and
--   rebalance_active_delivery_fees with canonical multi-tier weight resolution:
--     1. Prioritize order_items.weight_kg (stored accurately in KG during checkout).
--     2. Parse order_items.weight_in_grams / 1000.0.
--     3. Canonical unit_type and category normalization (grams, ml, pieces > 25, etc.).
--     4. Safety clamp bounds.
--   Zero logic changes to any other backend/frontend rules. Strictly additive.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_newly_cancelled_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_cart_delivery NUMERIC;
  v_total_cart_coupon NUMERIC;
  v_available_pool NUMERIC;
  
  v_admin_delivery_base NUMERIC := 20.0;
  v_delivery_rate_per_km NUMERIC := 20.0;
  v_new_base_delivery NUMERIC := 20.0;
  v_new_active_delivery_total NUMERIC := 0.0;
  
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
  
  -- Coupon re-evaluation variables
  v_group_coupon_id UUID;
  v_coupon_type TEXT;
  v_coupon_val NUMERIC;
  v_coupon_cap NUMERIC;
  v_coupon_min NUMERIC;
  v_recalculated_total_discount NUMERIC := 0;
  
  rec RECORD;
  pay_rec RECORD;
  c_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_total_refund_amount NUMERIC := 0;
  v_allocated_refund_sum NUMERIC := 0;
  v_order_refund NUMERIC := 0;
  v_sum_cancelled_weights NUMERIC := 0;
  v_cancelled_idx INT := 0;

  -- Active shop coordinates for sequential distance chaining
  v_act_shop_lats double precision[] := '{}';
  v_act_shop_lngs double precision[] := '{}';
  v_act_dist_to_c double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharges numeric[] := '{}';
  v_total_act_surcharge numeric := 0.0;
  v_active_idx int := 0;
BEGIN
    -- Deterministic row-level locking
    PERFORM id FROM public.orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_admin_delivery_base := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_admin_delivery_base := COALESCE(v_admin_delivery_base, 20.0);
    v_delivery_rate_per_km := COALESCE(v_delivery_rate_per_km, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        SELECT COUNT(id)
          INTO v_newly_cancelled_count
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0);

        IF v_active_count = 0 AND v_newly_cancelled_count = 0 THEN
            CONTINUE;
        END IF;

        -- CASE A: ALL SHOPS CANCELLED (v_active_count = 0)
        IF v_active_count = 0 THEN
            UPDATE public.orders
               SET delivery_charges      = 0,
                   platform_fee          = 0,
                   small_cart_fee        = 0,
                   heavy_order_fee       = 0,
                   multi_shop_surcharge  = 0,
                   coupon_discount       = 0,
                   gst_platform          = 0,
                   gst_delivery          = 0,
                   rider_earnings        = 0,
                   delivery_partner_id   = NULL,
                   updated_at            = NOW()
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
               AND (delivery_charges > 0 OR platform_fee > 0);

            CONTINUE;
        END IF;

        IF v_newly_cancelled_count = 0 THEN
            CONTINUE;
        END IF;

        -- 100x INTELLIGENT WEIGHT ENGINE FOR ACTIVE ITEMS
        -- Solves the phantom heavy order fee by prioritizing oi.weight_kg (stored in KG during checkout)
        -- and applying canonical unit normalization if falling back to product weight_per_unit.
        SELECT COALESCE(SUM(
            oi.quantity * (
                CASE 
                    -- Priority 1: Trusted oi.weight_kg (already normalized to KG during checkout)
                    WHEN oi.weight_kg IS NOT NULL AND oi.weight_kg > 0 AND oi.weight_kg <= 25.0 THEN
                        oi.weight_kg
                    -- If oi.weight_kg was entered in grams (> 25 kg for retail/apparel/food)
                    WHEN oi.weight_kg IS NOT NULL AND oi.weight_kg > 25.0 AND (p.category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') OR oi.weight_kg > 100.0) THEN
                        oi.weight_kg / 1000.0
                    -- Priority 2: Explicit weight in grams
                    WHEN oi.weight_in_grams IS NOT NULL AND oi.weight_in_grams > 0 THEN
                        oi.weight_in_grams / 1000.0
                    -- Priority 3: Product weight_per_unit with canonical unit_type normalization
                    WHEN p.weight_per_unit IS NOT NULL AND p.weight_per_unit > 0 THEN
                        CASE 
                            WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres') THEN
                                p.weight_per_unit / 1000.0
                            WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('mg', 'milligram', 'milligrams') THEN
                                p.weight_per_unit / 1000000.0
                            WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres') THEN
                                p.weight_per_unit
                            WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('pieces', 'piece', 'pcs', 'pc') THEN
                                CASE WHEN p.weight_per_unit > 25.0 THEN p.weight_per_unit / 1000.0 ELSE p.weight_per_unit END
                            WHEN p.category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') AND p.weight_per_unit > 20.0 THEN
                                p.weight_per_unit / 1000.0
                            WHEN p.weight_per_unit > 25.0 THEN
                                p.weight_per_unit / 1000.0
                            ELSE
                                p.weight_per_unit
                        END
                    ELSE 0.5
                END
            )
        ), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        -- Hard cap safety sanity
        v_active_weight_total := LEAST(COALESCE(v_active_weight_total, 0.0), 100.0);

        -- Available pool from active plus newly cancelled
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(coupon_discount),       0),
            MAX(coupon_id::text)::uuid
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_cart_coupon,
            v_group_coupon_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR grand_total > 0
                OR delivery_charges > 0
                OR platform_fee > 0);

        -- Build sequential coordinates for remaining active shops
        v_act_shop_lats := '{}';
        v_act_shop_lngs := '{}';
        v_act_dist_to_c := '{}';
        v_leg_surcharges := '{}';
        v_total_act_surcharge := 0.0;

        FOR rec IN
            SELECT o.id, o.estimated_distance_km, o.delivery_lat, o.delivery_lng, s.location
            FROM public.orders o
            JOIN public.shops s ON s.id = o.shop_id
            WHERE o.cart_group_id = p_cart_group_id
              AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
            ORDER BY o.created_at ASC, o.id ASC
        LOOP
            v_act_shop_lats := array_append(v_act_shop_lats, ST_Y(rec.location::geometry)::double precision);
            v_act_shop_lngs := array_append(v_act_shop_lngs, ST_X(rec.location::geometry)::double precision);
            v_act_dist_to_c := array_append(v_act_dist_to_c, COALESCE(rec.estimated_distance_km::double precision, 3.0));
        END LOOP;

        -- Sequential Base Delivery: first active shop is promoted to Base Shop
        v_new_base_delivery := GREATEST(v_admin_delivery_base, GREATEST(1, CEIL(v_act_dist_to_c[1])) * v_delivery_rate_per_km);

        -- Sequential Surcharges for Active Shops
        v_leg_surcharges := array_append(v_leg_surcharges, 0.0); -- Active Shop 1 surcharge = 0
        IF v_active_count > 1 THEN
            FOR i IN 1..(v_active_count - 1) LOOP
                v_inter_dist := 6371.0 * acos(
                  LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(v_act_shop_lats[i])) * cos(radians(v_act_shop_lats[i+1])) *
                    cos(radians(v_act_shop_lngs[i+1]) - radians(v_act_shop_lngs[i])) +
                    sin(radians(v_act_shop_lats[i])) * sin(radians(v_act_shop_lats[i+1]))
                  ))
                );
                v_new_surcharge := GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km;
                v_leg_surcharges := array_append(v_leg_surcharges, v_new_surcharge);
                v_total_act_surcharge := v_total_act_surcharge + v_new_surcharge;
            END LOOP;
        END IF;

        -- Small cart & Heavy order fees
        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_new_small := v_small_cart_fee;
        ELSE
            v_new_small := 0;
        END IF;

        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_new_heavy := v_heavy_order_fee * CEIL(v_active_weight_total - v_heavy_order_threshold_kg);
        ELSE
            v_new_heavy := 0;
        END IF;

        -- Total delivery fee for active orders
        v_new_active_delivery_total := (v_new_base_delivery + v_total_act_surcharge + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);

        -- Dynamic Coupon Re-evaluation
        v_recalculated_total_discount := 0;
        IF v_group_coupon_id IS NOT NULL AND v_total_cart_coupon > 0 THEN
            SELECT discount_type, discount_value, max_discount_amount, min_order_amount
              INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min
              FROM public.coupons
             WHERE id = v_group_coupon_id;

            IF FOUND THEN
                IF v_coupon_min IS NULL OR v_active_items_total >= v_coupon_min THEN
                    IF v_coupon_type = 'percentage' THEN
                        v_recalculated_total_discount := (v_active_items_total * (v_coupon_val / 100.0));
                        IF v_coupon_cap IS NOT NULL THEN
                            v_recalculated_total_discount := LEAST(v_recalculated_total_discount, v_coupon_cap);
                        END IF;
                    ELSE
                        v_recalculated_total_discount := LEAST(v_coupon_val, v_active_items_total);
                    END IF;
                ELSE
                    v_recalculated_total_discount := 0;
                END IF;
            END IF;
        END IF;

        -- Update Active Orders with Leg-Specific Attribution
        v_sum_active_grand := 0;
        v_active_idx := 0;

        FOR rec IN
            SELECT id, total_amount, s9_5_gst_amount, non_food_gst_amount
            FROM public.orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
            ORDER BY created_at ASC, id ASC
        LOOP
            v_active_idx := v_active_idx + 1;

            -- Shop 1 holds Base Delivery + Small/Heavy Fee + Platform Fee
            -- Shop 2+ hold Leg Surcharge only
            IF v_active_idx = 1 THEN
                v_new_del := (v_new_base_delivery + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);
                v_new_plat := v_admin_platform_fee;
                v_new_surcharge := 0.0;
                v_new_rider := GREATEST(0, (v_new_base_delivery + v_new_heavy) * (v_rider_commission_percent / 100.0));
            ELSE
                v_new_surcharge := COALESCE(v_leg_surcharges[v_active_idx], 0.0);
                v_new_del := v_new_surcharge * (1.0 + v_delivery_gst_rate);
                v_new_plat := 0.0;
                v_new_rider := GREATEST(0, v_new_surcharge * (v_rider_commission_percent / 100.0));
            END IF;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del := v_new_del - (v_new_del / (1.0 + v_delivery_gst_rate));

            IF v_active_items_total > 0 THEN
                v_new_coupon := v_recalculated_total_discount * (rec.total_amount / v_active_items_total);
            ELSE
                v_new_coupon := 0;
            END IF;

            v_new_grand := GREATEST(0, rec.total_amount + rec.s9_5_gst_amount + rec.non_food_gst_amount + v_new_plat + v_new_del - v_new_coupon);
            v_sum_active_grand := v_sum_active_grand + v_new_grand;

            UPDATE public.orders
               SET delivery_charges      = v_new_del,
                   platform_fee          = v_new_plat,
                   small_cart_fee        = CASE WHEN v_active_idx = 1 THEN v_new_small ELSE 0 END,
                   heavy_order_fee       = CASE WHEN v_active_idx = 1 THEN v_new_heavy ELSE 0 END,
                   multi_shop_surcharge  = v_new_surcharge,
                   coupon_discount       = v_new_coupon,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_del,
                   rider_earnings        = v_new_rider,
                   grand_total           = v_new_grand,
                   grand_total_collected = v_new_grand,
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;

        -- Distribute Refund to Newly Cancelled Orders
        v_total_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);
        v_allocated_refund_sum := 0;
        v_cancelled_idx := 0;

        SELECT COALESCE(SUM(grand_total_collected), 0)
          INTO v_sum_cancelled_weights
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0);

        FOR c_rec IN
            SELECT id, grand_total_collected
            FROM public.orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
              AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0)
            ORDER BY id ASC
        LOOP
            v_cancelled_idx := v_cancelled_idx + 1;
            
            IF v_cancelled_idx = v_newly_cancelled_count THEN
                v_order_refund := v_total_refund_amount - v_allocated_refund_sum;
            ELSE
                IF v_sum_cancelled_weights > 0 THEN
                    v_order_refund := ROUND((v_total_refund_amount * (c_rec.grand_total_collected / v_sum_cancelled_weights))::numeric, 2);
                ELSE
                    v_order_refund := ROUND((v_total_refund_amount / v_newly_cancelled_count)::numeric, 2);
                END IF;
                v_allocated_refund_sum := v_allocated_refund_sum + v_order_refund;
            END IF;

            UPDATE public.orders
               SET delivery_charges      = 0,
                   platform_fee          = 0,
                   small_cart_fee        = 0,
                   heavy_order_fee       = 0,
                   multi_shop_surcharge  = 0,
                   coupon_discount       = 0,
                   gst_platform          = 0,
                   gst_delivery          = 0,
                   rider_earnings        = 0,
                   grand_total           = 0,
                   grand_total_collected = v_order_refund,
                   updated_at            = NOW()
             WHERE id = c_rec.id;
        END LOOP;
    END LOOP;

    RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reallocate_cancelled_delivery_fees(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reallocate_cancelled_delivery_fees(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ensure rebalance_active_delivery_fees delegates to fortified reallocate function
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM public.reallocate_cancelled_delivery_fees(p_cart_group_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- Historical Data Rectification: Order #F1ACA0C9 (Safe Additive Repair)
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.orders
   SET grand_total = 213.95,
       grand_total_collected = 213.95,
       heavy_order_fee = 0.00,
       updated_at = NOW()
 WHERE id = 'f1aca0c9-041e-4539-8202-28464044c625'
   AND grand_total > 10000;
