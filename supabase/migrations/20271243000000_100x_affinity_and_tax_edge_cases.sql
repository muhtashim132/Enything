-- =============================================================================
-- Migration: 20271243000000_100x_affinity_and_tax_edge_cases.sql
-- Description: ADDITIVE ONLY - CREATE OR REPLACE FUNCTION only.
--              Fixes the "Ghost Lock" rider affinity bug by adding rider_rejected
--              Fixes the double-charging of gst_platform in grand_total_collected
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_nearby_unassigned_orders(
    p_rider_lat double precision DEFAULT NULL, 
    p_rider_lng double precision DEFAULT NULL, 
    p_radius_km double precision DEFAULT 15.0
)
 RETURNS SETOF public.orders
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_admin_max_radius double precision;
BEGIN
    BEGIN
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
    p_radius_km := LEAST(GREATEST(p_radius_km, 1.0), 50.0);

    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
            -- EXCLUSIVE RIDER AFFINITY:
            AND NOT EXISTS (
                SELECT 1 FROM public.orders siblings
                WHERE COALESCE(siblings.cart_group_id, siblings.id) = COALESCE(o.cart_group_id, o.id)
                  AND siblings.delivery_partner_id IS NOT NULL
                  AND siblings.delivery_partner_id != auth.uid()
                  AND siblings.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel')
            )
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) DESC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        WHERE o.status IN ('awaiting_acceptance', 'pending')
        ORDER BY o.created_at DESC;
    ELSE
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          JOIN public.shops s ON o.shop_id = s.id
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
            AND s.location IS NOT NULL
            AND ST_DWithin(
                s.location::geography, 
                ST_SetSRID(ST_MakePoint(p_rider_lng, p_rider_lat), 4326)::geography, 
                p_radius_km * 1000
            )
            -- EXCLUSIVE RIDER AFFINITY:
            AND NOT EXISTS (
                SELECT 1 FROM public.orders siblings
                WHERE COALESCE(siblings.cart_group_id, siblings.id) = COALESCE(o.cart_group_id, o.id)
                  AND siblings.delivery_partner_id IS NOT NULL
                  AND siblings.delivery_partner_id != auth.uid()
                  AND siblings.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel')
            )
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) ASC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        WHERE o.status IN ('awaiting_acceptance', 'pending')
        ORDER BY o.created_at ASC;
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;

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
    v_split_surcharge := v_missing_surcharge / v_active_count;
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
  SELECT COUNT(id) INTO v_active_count
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                   'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

  IF v_active_count = 0 THEN RETURN; END IF;

  SELECT
    COALESCE(SUM(delivery_charges), 0),
    COALESCE(SUM(multi_shop_surcharge), 0),
    COALESCE(SUM(small_cart_fee), 0),
    COALESCE(SUM(heavy_order_fee), 0)
  INTO v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                   'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

  v_split_delivery := v_total_delivery / v_active_count;
  v_split_surcharge := v_total_surcharge / v_active_count;
  v_split_small := v_total_small / v_active_count;
  v_split_heavy := v_total_heavy / v_active_count;

  v_new_gst_delivery := v_split_delivery - (v_split_delivery / 1.18);

  FOR rec IN
    SELECT id, total_amount, gst_item_total, platform_fee, gst_platform,
           COALESCE(coupon_discount, 0) AS coupon_discount, payment_status
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                     'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
  LOOP
    UPDATE orders
    SET delivery_charges = v_split_delivery,
        multi_shop_surcharge = v_split_surcharge,
        small_cart_fee = v_split_small,
        heavy_order_fee = v_split_heavy,
        rider_earnings = GREATEST(0, (v_split_delivery - v_new_gst_delivery - v_split_small + v_split_surcharge + v_split_heavy) * 0.80),
        gst_delivery = v_new_gst_delivery,
        grand_total_collected = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee  + v_split_delivery - rec.coupon_discount)
    WHERE id = rec.id;
  END LOOP;
END;
$$;
