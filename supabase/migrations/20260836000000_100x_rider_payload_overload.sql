-- =============================================================================
-- Migration: 100x Rider Payload Overload Fix
-- Description:
--   Resolves a catastrophic client-side memory leak and DDOS vector where the 
--   Rider Dashboard and Earnings Page fetched the entire historical delivered 
--   orders payload to compute aggregates. This pushes the aggregation to the DB.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_rider_stats(p_rider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_start TIMESTAMPTZ;
  v_total_earnings NUMERIC := 0;
  v_today_earnings NUMERIC := 0;
  v_total_deliveries INTEGER := 0;
  v_total_kms NUMERIC := 0;
  
  -- Variables for the loop
  v_row RECORD;
  v_days_ago INTEGER;
  v_charge NUMERIC;
  v_week_map NUMERIC[] := ARRAY[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  
BEGIN
  -- Get IST midnight (UTC + 5:30)
  v_today_start := (NOW() AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes')::date;
  
  -- Calculate KMS driven (max distance per cart group)
  SELECT COALESCE(SUM(max_dist), 0) INTO v_total_kms
  FROM (
    SELECT MAX(COALESCE(estimated_distance_km, 0)) as max_dist
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id AND status = 'delivered'
    GROUP BY COALESCE(cart_group_id, id::text)
  ) sub;

  -- Calculate earnings and deliveries
  FOR v_row IN 
    SELECT 
      created_at AT TIME ZONE 'UTC' + INTERVAL '5 hours 30 minutes' as ist_time,
      COALESCE(rider_earnings, COALESCE(delivery_charges, 0)) + COALESCE(wait_time_penalty, 0) as charge
    FROM public.orders
    WHERE delivery_partner_id = p_rider_id AND status = 'delivered'
  LOOP
    v_total_deliveries := v_total_deliveries + 1;
    v_charge := v_row.charge;
    v_total_earnings := v_total_earnings + v_charge;
    
    -- Today earnings check
    IF v_row.ist_time >= v_today_start THEN
      v_today_earnings := v_today_earnings + v_charge;
    END IF;
    
    -- Weekly earnings check
    v_days_ago := DATE_PART('day', v_today_start - v_row.ist_time::date);
    IF v_days_ago >= 0 AND v_days_ago < 7 THEN
      v_week_map[7 - v_days_ago] := v_week_map[7 - v_days_ago] + v_charge;
    END IF;
  END LOOP;

  -- Build final JSON
  RETURN jsonb_build_object(
    'total_earnings', v_total_earnings,
    'today_earnings', v_today_earnings,
    'total_deliveries', v_total_deliveries,
    'total_kms', v_total_kms,
    'weekly_earnings', to_jsonb(v_week_map)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_rider_stats(UUID) TO authenticated;

-- Notify PostgREST cache reload
NOTIFY pgrst, 'reload schema';
