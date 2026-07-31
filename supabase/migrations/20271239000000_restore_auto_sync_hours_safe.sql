-- =============================================================================
-- Migration: 20271239000000_restore_auto_sync_hours_safe.sql
-- Description: ADDITIVE-ONLY — Re-creates the auto-sync mechanism that was
--              dropped by 20271238000000_rollback_auto_sync_hours.sql.
--
--              Restores is_accepting_orders auto-sync based on open_time /
--              close_time with correct cross-midnight (night-shift) handling.
--
--              SAFETY GUARANTEES:
--              • No existing SQL functions, RPCs, policies, or data are changed
--              • Only the three previously-dropped objects are re-created:
--                  1. safe_cast_time()
--                  2. sync_shop_accepting_orders_by_hours()
--                  3. trg_sync_shop_hours() + trigger
--              • Cron job re-scheduled under the same name (was previously
--                unscheduled by the rollback, so this is a fresh schedule)
--              • One immediate execution to fix shops that are currently wrong
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1 ─ Helper: safe TIME cast (returns NULL instead of raising on bad data)
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2 ─ Cron-driven sync function
--
-- Logic per shop row:
--   • is_active = false              → is_accepting_orders := false
--   • open_time or close_time NULL   → leave is_accepting_orders unchanged
--                                      (seller retains full manual control)
--   • open_time <= close_time        → NORMAL SHIFT
--                                      open if: now >= open AND now <= close
--   • open_time > close_time         → NIGHT / CROSS-MIDNIGHT SHIFT
--     (e.g. 09:00 → 05:00)            open if: now >= open OR  now <= close
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_shop_accepting_orders_by_hours()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now time;
BEGIN
    -- Always use IST (UTC+5:30) so sellers set hours in local time
    v_now := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;

    UPDATE public.shops
    SET is_accepting_orders = CASE
        -- ① Inactive shop: never accepting
        WHEN is_active = false
            THEN false

        -- ② Hours not set or unparseable: preserve seller's manual value
        WHEN public.safe_cast_time(open_time::text) IS NULL
          OR public.safe_cast_time(close_time::text) IS NULL
            THEN is_accepting_orders

        -- ③ Normal shift (e.g. 09:00 → 22:00): simple range check
        WHEN public.safe_cast_time(open_time::text) <= public.safe_cast_time(close_time::text)
            THEN (   v_now >= public.safe_cast_time(open_time::text)
                 AND v_now <= public.safe_cast_time(close_time::text) )

        -- ④ Night / cross-midnight shift (e.g. 09:00 → 05:00):
        --    open_time > close_time, so open hours wrap around midnight
        ELSE
            (    v_now >= public.safe_cast_time(open_time::text)
              OR v_now <= public.safe_cast_time(close_time::text) )
    END
    -- Only touch rows where a decision can actually be made:
    --   inactive shops always need the false applied,
    --   shops with valid hours need the time-based sync applied.
    WHERE is_active = false
       OR (    public.safe_cast_time(open_time::text)  IS NOT NULL
           AND public.safe_cast_time(close_time::text) IS NOT NULL );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3 ─ Schedule cron to run every 5 minutes
--          (unschedule first to be idempotent in case of re-run)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
    PERFORM cron.unschedule('sync-shop-hours');
EXCEPTION WHEN OTHERS THEN
    -- Job didn't exist — that's fine, we're about to create it
    NULL;
END;
$$;

SELECT cron.schedule(
    'sync-shop-hours',
    '*/5 * * * *',
    'SELECT public.sync_shop_accepting_orders_by_hours();'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4 ─ Trigger: instant sync when seller saves new hours or toggles active
--
--  Fires BEFORE INSERT OR UPDATE on open_time, close_time, is_active so the
--  NEW row already has the correct is_accepting_orders before it lands in DB.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_sync_shop_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now   time;
    v_open  time;
    v_close time;
BEGIN
    v_now   := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;
    v_open  := public.safe_cast_time(NEW.open_time::text);
    v_close := public.safe_cast_time(NEW.close_time::text);

    IF NEW.is_active = false THEN
        -- ① Inactive → always closed
        NEW.is_accepting_orders := false;

    ELSIF v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF v_open <= v_close THEN
            -- ③ Normal shift
            NEW.is_accepting_orders := ( v_now >= v_open AND v_now <= v_close );
        ELSE
            -- ④ Cross-midnight shift
            NEW.is_accepting_orders := ( v_now >= v_open OR  v_now <= v_close );
        END IF;
        -- ② If hours are NULL we leave NEW.is_accepting_orders untouched
        --   (seller's last manual value is preserved)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5 ─ Immediate fix: run the sync right now so all shops reflect the
--          correct is_accepting_orders based on their current hours and
--          the current IST time without waiting up to 5 minutes for the cron.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT public.sync_shop_accepting_orders_by_hours();
