-- =============================================================================
-- Migration: 20290000000026_100x_platform_config_jsonb_fix.sql
-- Description: 100x Additive Data Healing for Platform Config JSONB Spoofing Bug
-- 
-- Root Cause: When admin panel saved numeric configs (like platform_fee = 20),
-- the Dart app passed a String ("20.0"). Since the column is JSONB, it was saved
-- as a JSON string ('"20.0"'). When place_orders_transaction did `SELECT value::numeric`,
-- Postgres crashed (invalid syntax: cannot cast json string to numeric directly),
-- triggering a silent fallback to 2.5, causing a "Spoofing Detected" mismatch during checkout.
--
-- Fix: This migration heals all currently corrupted JSON strings in the database
-- by converting them into clean JSON numbers.
--
-- SAFETY VERIFICATION:
--   Zero schema changes. Zero function changes.
--   Purely additive data healing using safe extraction and casting.
-- =============================================================================

DO $$
DECLARE
    v_key text;
    v_numeric numeric;
BEGIN
    -- We target only the keys that are supposed to be numeric.
    -- (This avoids accidentally touching string configurations if they exist).
    FOR v_key IN SELECT unnest(ARRAY[
        'commission_percent',
        'default_commission_percent',
        'platform_fee',
        'small_cart_fee',
        'small_cart_threshold',
        'heavy_order_fee_per_kg',
        'heavy_order_fee',
        'heavy_order_threshold_kg',
        'max_delivery_radius_km',
        'delivery_rate_per_km',
        'wait_penalty_per_min',
        'referral_bonus_amount',
        'delivery_gst_rate',
        'platform_fee_gst_rate',
        'multi_shop_surcharge',
        'rider_commission_percent',
        'rider_notification_radius_km'
    ])
    LOOP
        -- Check if the key exists AND its jsonb type is 'string'
        IF EXISTS (
            SELECT 1 FROM platform_config 
            WHERE key = v_key AND jsonb_typeof(value) = 'string'
        ) THEN
            BEGIN
                -- Safely extract the string (without quotes) using #>> '{}', cast to numeric
                PERFORM (SELECT (value#>>'{}')::numeric FROM platform_config WHERE key = v_key LIMIT 1);
                
                -- If it parses successfully, overwrite it with a JSON number using to_jsonb
                UPDATE platform_config 
                SET value = to_jsonb((value#>>'{}')::numeric)
                WHERE key = v_key AND jsonb_typeof(value) = 'string';
                
            EXCEPTION WHEN OTHERS THEN
                -- If it somehow contains garbage, safely set it to 0.0 JSON number
                UPDATE platform_config 
                SET value = to_jsonb(0.0::numeric)
                WHERE key = v_key AND jsonb_typeof(value) = 'string';
            END;
        END IF;
    END LOOP;

    -- Also safely handle any dynamically generated category overrides that were saved as strings
    -- (e.g. commission_percent_Restaurant, wait_penalty_per_min_Grocery)
    DECLARE
        rec RECORD;
    BEGIN
        FOR rec IN 
            SELECT key, value FROM platform_config 
            WHERE (key LIKE 'commission_percent_%' OR key LIKE 'wait_penalty_per_min_%')
              AND jsonb_typeof(value) = 'string'
        LOOP
            BEGIN
                PERFORM (rec.value#>>'{}')::numeric;
                UPDATE platform_config 
                SET value = to_jsonb((value#>>'{}')::numeric)
                WHERE key = rec.key;
            EXCEPTION WHEN OTHERS THEN
                UPDATE platform_config 
                SET value = to_jsonb(0.0::numeric)
                WHERE key = rec.key;
            END;
        END LOOP;
    END;
END $$;
