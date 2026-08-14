-- =============================================================================
-- Migration: 20290000000062_100x_rider_stats_and_insights_sync.sql
-- Description: 100x Fortification for get_rider_stats RPC.
--   1. Calculates days_ago from completion timestamp (updated_at) in IST timezone
--      to guarantee midnight-shift crossing orders are credited to today's earnings.
--   2. Includes compensated cancelled orders (status = 'cancelled' AND rider_earnings > 0)
--      for 100% mathematical reconciliation with get_rider_balance.
--   3. Uses IS DISTINCT FROM IDOR protection.
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
  v_week_map           NUMERIC[] := ARRAY[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  IF (auth.uid() IS DISTINCT FROM p_rider_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: You can only view your own delivery stats.';
  END IF;

  -- Get IST midnight (UTC + 5:30)
  v_today_date := (NOW() AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date;

  WITH delivered AS (
    SELECT
      v_today_date
        - ((COALESCE(updated_at, created_at) AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date) AS days_ago,
      COALESCE(rider_earnings, COALESCE(delivery_charges, 0))
        + COALESCE(wait_time_penalty, 0)                                          AS charge
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
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

  -- KMS driven: max distance per cart-group (type-safe UUID COALESCE)
  SELECT COALESCE(SUM(max_dist), 0) INTO v_total_kms
  FROM (
    SELECT MAX(COALESCE(estimated_distance_km, 0)) AS max_dist
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id
      AND (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
    GROUP BY COALESCE(cart_group_id, id)
  ) sub;

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
