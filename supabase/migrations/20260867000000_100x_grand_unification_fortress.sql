-- =============================================================================
-- Migration: 100x Grand Unification Fortress (Phase 14)
-- Description:
--   1. Fixes the Admin Wage Theft exploit where `admin_issue_refund` forcefully
--      zeroed out rider earnings for orders already physically in transit.
--   2. Fixes the Blind Assignment Pixel Overload bug where `get_nearby_unassigned_orders`
--      used a naive row limit, slicing multi-shop cart groups in half and blinding 
--      the rider UI to orders they were about to accept.
-- =============================================================================

-- =============================================================================
-- 1. Patch admin_issue_refund to preserve Rider Wage Theft (14A)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_issue_refund(p_order_id UUID)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_payment_status text;
  v_refund_status text;
  v_cart_group_id uuid;
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status, refund_status INTO v_status, v_payment_status, v_refund_status
  FROM orders WHERE id = p_order_id;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  IF v_refund_status IN ('processing', 'completed') THEN
    RAISE EXCEPTION 'Refund is already processing or completed. Cannot trigger duplicate refund.';
  END IF;

  IF v_status IN ('cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute', 'shop_dispute_cancel', 'payment_failed', 'timeout') THEN
    IF v_payment_status != 'captured' THEN
      RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
    END IF;
    UPDATE orders
    SET refund_status = 'processing'
    WHERE id = p_order_id;
  ELSE
    -- 100x STRESS TEST FIX (Phase 14A): Prevent Admin Rider Wage Theft
    IF v_status IN ('picked_up', 'out_for_delivery') THEN
      UPDATE orders
      SET
        status = 'cancelled',
        cancelled_reason = 'admin',
        -- Rider already drove to the shop, keep their earnings intact!
        refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
      WHERE id = p_order_id;
    ELSE
      UPDATE orders
      SET
        status = 'cancelled',
        cancelled_reason = 'admin',
        rider_earnings = 0,
        wait_time_penalty = 0,
        refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
      WHERE id = p_order_id;
    END IF;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$function$;

-- =============================================================================
-- 2. Patch get_nearby_unassigned_orders to prevent Blind Cart Slicing (14B)
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
BEGIN
    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        -- 100x FIX: Fetch by Cartesian Group LIMIT, not row LIMIT!
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) DESC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        ORDER BY o.created_at DESC;
    ELSE
        -- Geographic Proximity Search with Cartesian Group LIMIT
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
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) ASC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        ORDER BY o.created_at ASC;
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;
