-- =============================================================================
-- Migration: 20290000000051_100x_admin_dispatch_and_disputes.sql
-- =============================================================================
-- Description:
--   1. Idempotency Uniqueness Guard: Prevents duplicate checkout submissions at DB level.
--   2. Order Disputes Portal: Table, RLS policies, and triggers for customer dispute claims.
--   3. Emergency Admin Dispatch Alert: Notifies Admin Dispatch before auto-cancelling unassigned orders.
--   4. Rider Telemetry GPS Speed Filter: Rejects location updates exceeding 120 km/h speed threshold.
-- =============================================================================

-- 1. Partial Unique Index on Idempotency Key
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_idempotency_key 
ON public.orders(idempotency_key) 
WHERE idempotency_key IS NOT NULL;

-- 2. Customer Order Disputes Table
CREATE TABLE IF NOT EXISTS public.order_disputes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES public.shops(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    description TEXT,
    photo_urls JSONB DEFAULT '[]'::jsonb,
    refund_amount_requested NUMERIC(10,2) DEFAULT 0.00,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'partially_approved')),
    admin_notes TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS on order_disputes
ALTER TABLE public.order_disputes ENABLE ROW LEVEL SECURITY;

-- RLS Policies for order_disputes
DROP POLICY IF EXISTS "Customers can view their own disputes" ON public.order_disputes;
CREATE POLICY "Customers can view their own disputes"
ON public.order_disputes FOR SELECT
USING (auth.uid() = customer_id OR public.is_active_admin(auth.uid()));

DROP POLICY IF EXISTS "Customers can insert disputes for their delivered orders" ON public.order_disputes;
CREATE POLICY "Customers can insert disputes for their delivered orders"
ON public.order_disputes FOR INSERT
WITH CHECK (
    auth.uid() = customer_id 
    AND EXISTS (
        SELECT 1 FROM public.orders 
        WHERE id = order_id AND customer_id = auth.uid() AND status = 'delivered'
    )
);

DROP POLICY IF EXISTS "Admins can update order disputes" ON public.order_disputes;
CREATE POLICY "Admins can update order disputes"
ON public.order_disputes FOR UPDATE
USING (public.is_active_admin(auth.uid()));

-- Grants
GRANT SELECT, INSERT ON public.order_disputes TO authenticated;
GRANT ALL ON public.order_disputes TO service_role;

-- 3. Emergency Admin Dispatch Alert inside safe_auto_cancel_expired_orders
CREATE OR REPLACE FUNCTION public.safe_auto_cancel_expired_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_group RECORD;
  v_order_id UUID;
  v_cust_id UUID;
BEGIN
  -- 1. Awaiting Acceptance Timeout with Admin Dispatch Emergency Alert
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(customer_id) as customer_ids
    FROM orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    -- Alert Admin Dispatch via notifications table before executing cancellation
    INSERT INTO public.notifications (
      user_id,
      title,
      body,
      type,
      data,
      is_read,
      created_at
    )
    SELECT 
      id,
      '🚨 EMERGENCY DISPATCH ALERT',
      'Order group ' || COALESCE(v_group.cart_group_id::text, v_group.order_ids[1]::text) || ' timed out with no rider. Admin action required.',
      'admin_dispatch_alert',
      jsonb_build_object('cart_group_id', v_group.cart_group_id, 'order_ids', v_group.order_ids),
      false,
      NOW()
    FROM public.profiles
    WHERE role = 'admin'
    ON CONFLICT DO NOTHING;

    -- Update order status to cancelled
    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout_no_rider_dispatch_alerted',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 2. Awaiting Payment Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'payment_failed',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 3. Ghosted Prep Orders Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM orders 
    WHERE status IN ('confirmed', 'preparing') 
      AND payment_deadline IS NOT NULL 
      AND payment_deadline < (NOW() - INTERVAL '1.5 hours')
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'Auto-cancelled: Seller ghosted preparation',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 4. 100x Partial Rejection Decision Timeout (5 minutes)
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM orders
    WHERE cart_group_id IS NOT NULL
    GROUP BY cart_group_id
    HAVING 
      COUNT(CASE WHEN status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN 1 END) > 0
      AND 
      COUNT(CASE WHEN status IN ('seller_rejected', 'cancelled') THEN 1 END) > 0
      AND
      COUNT(CASE WHEN cancelled_reason = 'customer_replaced' THEN 1 END) = 0
      AND
      MAX(CASE WHEN status IN ('seller_rejected', 'cancelled') AND COALESCE(cancelled_reason, '') != 'customer_replaced' THEN COALESCE(updated_at, created_at) END) + INTERVAL '5 minutes' < NOW()
    LIMIT 100
  LOOP
    PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE cart_group_id = v_group.cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
      
    PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
  END LOOP;
END;
$function$;

-- 4. Rider Telemetry GPS Speed & Drift Filter RPC
CREATE OR REPLACE FUNCTION public.update_rider_location_telemetry(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rider_id UUID;
  v_last_lat DOUBLE PRECISION;
  v_last_lng DOUBLE PRECISION;
  v_last_time TIMESTAMPTZ;
  v_distance_meters NUMERIC;
  v_time_seconds NUMERIC;
  v_speed_kmh NUMERIC;
BEGIN
  v_rider_id := auth.uid();
  IF v_rider_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated';
  END IF;

  -- Fetch previous location and timestamp
  SELECT rider_lat, rider_lng, updated_at
  INTO v_last_lat, v_last_lng, v_last_time
  FROM public.profiles
  WHERE id = v_rider_id;

  -- Speed Sanity Check (Max 120 km/h = 33.3 m/s)
  IF v_last_lat IS NOT NULL AND v_last_lng IS NOT NULL AND v_last_time IS NOT NULL THEN
    v_time_seconds := EXTRACT(EPOCH FROM (NOW() - v_last_time));
    IF v_time_seconds > 0 AND v_time_seconds < 300 THEN
      -- Distance in meters using PostGIS ST_DistanceSphere
      v_distance_meters := ST_DistanceSphere(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326),
        ST_SetSRID(ST_MakePoint(v_last_lng, v_last_lat), 4326)
      );
      v_speed_kmh := (v_distance_meters / v_time_seconds) * 3.6;

      IF v_speed_kmh > 120.0 THEN
        -- Reject telemetric jump (> 120 km/h GPS drift)
        RETURN FALSE;
      END IF;
    END IF;
  END IF;

  -- Update profiles table with verified position
  UPDATE public.profiles
  SET rider_lat = p_lat,
      rider_lng = p_lng,
      updated_at = NOW()
  WHERE id = v_rider_id;

  -- Update active assigned orders with rider location for live track page
  UPDATE public.orders
  SET rider_lat = p_lat,
      rider_lng = p_lng,
      updated_at = NOW()
  WHERE delivery_partner_id = v_rider_id
    AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery');

  RETURN TRUE;
END;
$function$;
