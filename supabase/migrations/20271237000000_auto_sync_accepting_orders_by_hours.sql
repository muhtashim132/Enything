-- =============================================================================
-- Migration: 20271237000000_auto_sync_accepting_orders_by_hours.sql
-- Description: Auto-syncs is_accepting_orders based on clock hours, properly handling night shifts.
-- =============================================================================

-- Enable pg_cron if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION public.safe_cast_time(t text)
RETURNS time AS $$
BEGIN
    IF t IS NULL OR trim(t) = '' THEN
        RETURN NULL;
    END IF;
    RETURN t::time;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.sync_shop_accepting_orders_by_hours()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now time;
BEGIN
    -- Get current time in Asia/Kolkata
    v_now := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;

    UPDATE public.shops
    SET is_accepting_orders = CASE
        -- If shop is inactive overall, it cannot accept orders
        WHEN is_active = false THEN false

        -- If hours are not set or invalid, keep existing value (seller controlled)
        WHEN public.safe_cast_time(open_time::text) IS NULL OR public.safe_cast_time(close_time::text) IS NULL THEN is_accepting_orders

        -- Normal Shift (e.g., 09:00 to 22:00)
        WHEN public.safe_cast_time(open_time::text) <= public.safe_cast_time(close_time::text) THEN
            (v_now >= public.safe_cast_time(open_time::text) AND v_now <= public.safe_cast_time(close_time::text))

        -- Night Shift (e.g., 09:00 to 04:30, where open_time > close_time)
        ELSE
            (v_now >= public.safe_cast_time(open_time::text) OR v_now <= public.safe_cast_time(close_time::text))
    END
    WHERE is_active = false OR (public.safe_cast_time(open_time::text) IS NOT NULL AND public.safe_cast_time(close_time::text) IS NOT NULL);
END;
$$;

-- First, try to remove the cron if it exists to avoid duplicate job names
DO $$
BEGIN
    PERFORM cron.unschedule('sync-shop-hours');
EXCEPTION WHEN OTHERS THEN
    -- Ignore if pg_cron is not properly accessible or job doesn't exist
END;
$$;

-- Schedule to run every 5 minutes
SELECT cron.schedule(
    'sync-shop-hours', 
    '*/5 * * * *',     
    'SELECT public.sync_shop_accepting_orders_by_hours();'
);

-- Also add a trigger so it updates immediately when seller changes times
CREATE OR REPLACE FUNCTION public.trg_sync_shop_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now time;
    v_open time;
    v_close time;
BEGIN
    v_now := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;
    v_open := public.safe_cast_time(NEW.open_time::text);
    v_close := public.safe_cast_time(NEW.close_time::text);
    
    IF NEW.is_active = false THEN
        NEW.is_accepting_orders := false;
    ELSIF v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF v_open <= v_close THEN
            NEW.is_accepting_orders := (v_now >= v_open AND v_now <= v_close);
        ELSE
            NEW.is_accepting_orders := (v_now >= v_open OR v_now <= v_close);
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_shop_hours_update ON public.shops;
CREATE TRIGGER trg_sync_shop_hours_update
    BEFORE INSERT OR UPDATE OF open_time, close_time, is_active
    ON public.shops
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sync_shop_hours();

-- Run it once right now to fix the current state immediately
SELECT public.sync_shop_accepting_orders_by_hours();
