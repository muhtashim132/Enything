-- =============================================================================
-- Migration: 100x Checkout Spatial Math Fortress (Phase 9)
-- Description:
--   1. Fixes a Catastrophic Checkout Crash (Mathematical Denial of Service)
--      triggered by IEEE 754 floating-point precision errors in PostgreSQL's 
--      ACOS function when a customer's coordinates perfectly match the shop's.
--   2. Injects a Strict Mathematical Guard (`LEAST(1.0, GREATEST(-1.0, ...))`)
--      to guarantee the dot product stays within the valid [-1, 1] domain.
--   3. Adds a NULL Propagation Guard to prevent silent crashes in the API.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_shop_delivery_fee(p_shop_id uuid, p_user_lat numeric, p_user_lng numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_shop_lat NUMERIC;
    v_shop_lng NUMERIC;
    v_is_accepting_orders BOOLEAN;
    v_distance_km NUMERIC;
    v_base_fee NUMERIC;
    v_per_km_fee NUMERIC;
    v_max_distance NUMERIC;
    v_total_fee NUMERIC;
BEGIN
    SELECT lat, lng, is_accepting_orders 
    INTO v_shop_lat, v_shop_lng, v_is_accepting_orders
    FROM shops 
    WHERE id = p_shop_id;

    -- FIX: is_accepting_orders is the correct column!
    IF NOT v_is_accepting_orders THEN
        RETURN jsonb_build_object('error', 'Shop is currently not accepting orders.');
    END IF;

    -- 100x STRESS TEST FIX (Phase 9): Prevent NULL Propagation Crash
    IF v_shop_lat IS NULL OR v_shop_lng IS NULL OR p_user_lat IS NULL OR p_user_lng IS NULL THEN
        RETURN jsonb_build_object('error', 'Invalid coordinates. Cannot calculate delivery fee.');
    END IF;

    -- 100x STRESS TEST FIX (Phase 9): Prevent IEEE 754 Floating-Point ACOS Crash (Mathematical DoS)
    v_distance_km := 6371 * ACOS(
        LEAST(1.0, GREATEST(-1.0, 
            COS(RADIANS(v_shop_lat)) * COS(RADIANS(p_user_lat)) +
            SIN(RADIANS(v_shop_lat)) * SIN(RADIANS(p_user_lat)) * COS(RADIANS(p_user_lng) - RADIANS(v_shop_lng))
        ))
    );

    SELECT 
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_base_fee'), 30),
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_per_km_fee'), 10),
        COALESCE((SELECT value::numeric FROM platform_config WHERE key = 'delivery_max_distance_km'), 15)
    INTO v_base_fee, v_per_km_fee, v_max_distance;

    IF v_distance_km > v_max_distance THEN
        RETURN jsonb_build_object('error', 'Address is outside delivery range (' || v_max_distance || 'km).');
    END IF;

    v_total_fee := v_base_fee + (GREATEST(0, v_distance_km - 2) * v_per_km_fee);

    RETURN jsonb_build_object(
        'delivery_fee', ROUND(v_total_fee),
        'distance_km', ROUND(v_distance_km, 2)
    );
END;
$function$;
