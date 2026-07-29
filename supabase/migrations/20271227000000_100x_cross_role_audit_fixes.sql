-- =============================================================================
-- Migration: 20271227000000_100x_cross_role_audit_fixes.sql
-- Description:
--   Four additive fixes discovered by full-codebase cross-role audit.
--   STRICTLY ADDITIVE: Only CREATE OR REPLACE FUNCTION used.
--   Zero DROP, DELETE, TRUNCATE, or ALTER TABLE statements.
--
-- Fixes:
--   1. update_rider_location — add 'awaiting_payment' to GPS cascade so
--      customer's live map updates during the 10-min payment window even when
--      the rider app is backgrounded (foreground timer handles it separately
--      via update_rider_order_location, but background isolate only calls
--      update_rider_location, so awaiting_payment orders were silently skipped).
--
--   2. update_rider_location_bg — same gap: add 'awaiting_payment' to the
--      background-service cascade (consistent with fix #1).
--
--   3. get_rider_stats — IDOR fix: any authenticated user could call
--      get_rider_stats(any_rider_uuid) and read that rider's complete earnings
--      history. Now enforces auth.uid() = p_rider_id (or admin override).
--      Also replaces the slow PL/pgSQL row-by-row loop with a single
--      set-based aggregation — same output, O(n) vs O(n*k).
--
--   4. get_seller_daily_stats — IDOR fix: any authenticated user could call
--      get_seller_daily_stats(any_shop_uuid) and read that seller's
--      todays_earning. Now enforces auth.uid() = seller_id (or admin).
-- =============================================================================


-- =============================================================================
-- FIX 1: update_rider_location — add 'awaiting_payment' to cascade
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_rider_location(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Update the rider's primary profile tracking
  UPDATE public.delivery_partners
  SET
    current_lat         = p_lat,
    current_lng         = p_lng,
    location_updated_at = NOW(),
    is_online           = true
  WHERE id = auth.uid();

  -- 2. Atomically cascade the GPS coordinates to all currently active orders.
  -- 100x FIX: Added 'awaiting_payment' so the rider's location does NOT freeze
  -- on the customer's live map during the 10-minute payment window.
  -- Previously the foreground timer handled awaiting_payment via the separate
  -- update_rider_order_location RPC, but the background isolate only calls
  -- update_rider_location, leaving awaiting_payment orders with stale GPS.
  UPDATE public.orders
  SET
    rider_lat = p_lat,
    rider_lng = p_lng
  WHERE delivery_partner_id = auth.uid()
    AND status IN (
      'awaiting_payment',
      'confirmed',
      'preparing',
      'ready_for_pickup',
      'picked_up',
      'out_for_delivery'
    );

EXCEPTION WHEN OTHERS THEN
  -- Never throw exception; background isolate timer must keep running
  RAISE WARNING 'update_rider_location: failed for uid=%: %', auth.uid(), SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;


-- =============================================================================
-- FIX 2: update_rider_location_bg — add 'awaiting_payment' to cascade
-- (Mirrors Fix 1 for the secret-authenticated background-service variant)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_rider_location_bg(
  p_rider_id UUID,
  p_lat      NUMERIC,
  p_lng      NUMERIC,
  p_secret   UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret UUID;
BEGIN
  -- Strict validation of background tracking secret
  SELECT bg_tracking_secret INTO v_secret
  FROM public.delivery_partners
  WHERE id = p_rider_id;

  IF v_secret IS NULL OR v_secret != p_secret THEN
    RAISE EXCEPTION 'Unauthorized tracking request: Secret mismatch';
  END IF;

  -- 1. Update the rider's own tracking record
  UPDATE public.delivery_partners
  SET
    location          = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326),
    last_location_lat = p_lat,
    last_location_lng = p_lng
  WHERE id = p_rider_id;

  -- 2. Cascade GPS to all active orders.
  -- 100x FIX: Added 'awaiting_payment' (consistent with update_rider_location fix).
  UPDATE public.orders
  SET
    rider_lat                 = p_lat,
    rider_lng                 = p_lng,
    rider_location_updated_at = NOW()
  WHERE delivery_partner_id = p_rider_id
    AND status IN (
      'awaiting_payment',
      'accepted',
      'confirmed',
      'preparing',
      'ready_for_pickup',
      'picked_up',
      'out_for_delivery',
      'delivering'
    );

END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;


-- =============================================================================
-- FIX 3: get_rider_stats — IDOR guard + set-based aggregation
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_rider_stats(p_rider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_date         DATE;
  v_total_earnings     NUMERIC  := 0;
  v_today_earnings     NUMERIC  := 0;
  v_total_deliveries   INTEGER  := 0;
  v_total_kms          NUMERIC  := 0;
  -- 1-indexed Postgres array; to_jsonb converts to 0-indexed JSON:
  --   array[1] → JSON[0] = 6 days ago … array[7] → JSON[6] = today
  v_week_map           NUMERIC[] := ARRAY[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
BEGIN
  -- ── 100x SECURITY FIX: IDOR Guard ────────────────────────────────────────
  -- Previously any authenticated user could call get_rider_stats(any_rider_id)
  -- and read complete earnings history. Enforce identity or admin bypass.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  IF auth.uid() != p_rider_id AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: You can only view your own delivery stats.';
  END IF;

  -- Get IST midnight (UTC + 5:30)
  v_today_date := (NOW() AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date;

  -- ── Set-based aggregation (replaces slow PL/pgSQL row-by-row LOOP) ────────
  -- Single table scan; FILTER aggregation builds today, weekly, and total
  -- earnings in one pass. Produces identical output to the original loop.
  -- weekly_earnings array layout (0-indexed in JSON):
  --   [0]=6daysago  [1]=5daysago  …  [6]=today
  WITH delivered AS (
    SELECT
      v_today_date
        - ((created_at AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date) AS days_ago,
      COALESCE(rider_earnings, COALESCE(delivery_charges, 0))
        + COALESCE(wait_time_penalty, 0)                                          AS charge
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND status = 'delivered'
  )
  SELECT
    COALESCE(SUM(charge),                                               0),
    COALESCE(SUM(charge) FILTER (WHERE days_ago = 0),                   0),
    COUNT(*)::int,
    ARRAY[
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 6), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 5), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 4), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 3), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 2), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 1), 0),
      COALESCE(SUM(charge) FILTER (WHERE days_ago = 0), 0)
    ]
  INTO v_total_earnings, v_today_earnings, v_total_deliveries, v_week_map
  FROM delivered;

  -- KMS driven: max distance per cart-group (unchanged logic from original)
  SELECT COALESCE(SUM(max_dist), 0) INTO v_total_kms
  FROM (
    SELECT MAX(COALESCE(estimated_distance_km, 0)) AS max_dist
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND status = 'delivered'
    GROUP BY COALESCE(cart_group_id, id::text)
  ) sub;

  -- Return JSON with identical key names as original (Dart client depends on these)
  RETURN jsonb_build_object(
    'total_earnings',  v_total_earnings,
    'today_earnings',  v_today_earnings,
    'total_deliveries',v_total_deliveries,
    'total_kms',       v_total_kms,
    'weekly_earnings', to_jsonb(v_week_map)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_stats(UUID) TO authenticated;


-- =============================================================================
-- FIX 4: get_seller_daily_stats — IDOR guard
-- Preserves ALL existing query logic — only adds the auth check at the top.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_seller_id    uuid;
    v_total_orders  integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products       integer := 0;
BEGIN
  -- ── 100x SECURITY FIX: IDOR Guard ────────────────────────────────────────
  -- Previously any authenticated user could call get_seller_daily_stats(shop_id)
  -- and read a seller's daily earnings. Now enforces seller identity.
  SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = p_shop_id;

  IF v_seller_id IS NULL THEN
    RAISE EXCEPTION 'Shop not found.';
  END IF;

  IF auth.uid() != v_seller_id AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: You can only view stats for your own shop.';
  END IF;

  -- ── Original query logic preserved byte-for-byte below ───────────────────

    SELECT count(*) INTO v_total_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status NOT IN ('cancelled', 'seller_rejected');

    SELECT count(*) INTO v_pending_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status IN ('pending', 'awaiting_acceptance');

    -- FIX: Persist wait_time_penalty deduction even if the order was refunded
    SELECT COALESCE(SUM(
      CASE
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0
        ELSE COALESCE(seller_payout, 0)
      END
      - COALESCE(wait_time_penalty, 0)
    ), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
      AND DATE(updated_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    SELECT count(*) INTO v_products
    FROM products
    WHERE shop_id = p_shop_id AND is_deleted = false;

    RETURN json_build_object(
        'total_orders',   v_total_orders,
        'pending_orders', v_pending_orders,
        'todays_earning', v_todays_earning,
        'products',       v_products
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_daily_stats(uuid) TO authenticated;


-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
