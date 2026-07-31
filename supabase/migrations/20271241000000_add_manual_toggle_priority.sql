-- =============================================================================
-- Migration: 20271241000000_add_manual_toggle_priority.sql
-- Description: ADDITIVE-ONLY — Adds a manual override flag so sellers can
--              close their shops early without the cron job reopening them.
--
--              SAFETY GUARANTEES:
--              • Schema is purely additive (adds one column).
--              • Existing Dart/Flutter code requires ZERO changes.
--              • Replaces the two sync functions from 20271239000000 with
--                identical logic + the is_manually_closed checks.
--              • Automatically resets the manual override at the end of the shift
--                so sellers are not permanently locked out if they forget.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1 ─ Add Column (Additive Schema Change)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.shops 
ADD COLUMN IF NOT EXISTS is_manually_closed BOOLEAN DEFAULT false;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2 ─ Trigger to intercept manual toggles from the App UI
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_capture_manual_toggle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only act if the value is actually changing
    IF NEW.is_accepting_orders IS DISTINCT FROM OLD.is_accepting_orders THEN
        -- Only act if the request comes from an authenticated user (the seller via App API).
        -- Background jobs (like cron) do NOT have JWT claims, so this isolates UI actions.
        IF current_setting('request.jwt.claims', true) IS NOT NULL THEN
            IF NEW.is_accepting_orders = false THEN
                -- Seller tapped "Close Shop"
                NEW.is_manually_closed := true;
            ELSE
                -- Seller tapped "Open Shop"
                NEW.is_manually_closed := false;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_capture_manual_toggle_update ON public.shops;
CREATE TRIGGER trg_capture_manual_toggle_update
    BEFORE UPDATE OF is_accepting_orders
    ON public.shops
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_capture_manual_toggle();


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3 ─ Update Cron Function to respect the manual override & Smart Reset
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
    v_now := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;

    -- SMART RESET: If a shop is manually closed, but the current time is now
    -- OUTSIDE its operating hours (i.e. the shift has ended), reset the flag.
    -- This ensures they open normally the next day.
    UPDATE public.shops
    SET is_manually_closed = false
    WHERE is_manually_closed = true
      AND public.safe_cast_time(open_time::text) IS NOT NULL
      AND public.safe_cast_time(close_time::text) IS NOT NULL
      AND (
          -- Normal shift: out of bounds if before open OR after close
          (public.safe_cast_time(open_time::text) <= public.safe_cast_time(close_time::text)
           AND (v_now < public.safe_cast_time(open_time::text) OR v_now > public.safe_cast_time(close_time::text)))
          OR
          -- Night shift: out of bounds if before open AND after close
          (public.safe_cast_time(open_time::text) > public.safe_cast_time(close_time::text)
           AND (v_now < public.safe_cast_time(open_time::text) AND v_now > public.safe_cast_time(close_time::text)))
      );

    -- EVALUATE is_accepting_orders (respecting is_manually_closed)
    UPDATE public.shops
    SET is_accepting_orders = CASE
        WHEN is_active = false THEN false
        WHEN public.safe_cast_time(open_time::text) IS NULL OR public.safe_cast_time(close_time::text) IS NULL THEN is_accepting_orders
        
        -- RESPECT MANUAL OVERRIDE
        WHEN is_manually_closed = true THEN false

        WHEN public.safe_cast_time(open_time::text) <= public.safe_cast_time(close_time::text) THEN
            (v_now >= public.safe_cast_time(open_time::text) AND v_now <= public.safe_cast_time(close_time::text))
        ELSE
            (v_now >= public.safe_cast_time(open_time::text) OR v_now <= public.safe_cast_time(close_time::text))
    END
    WHERE is_active = false
       OR is_manually_closed = true
       OR (public.safe_cast_time(open_time::text) IS NOT NULL AND public.safe_cast_time(close_time::text) IS NOT NULL);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4 ─ Update Hours Trigger to respect the manual override & Smart Reset
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

    -- If seller changes their operating hours entirely, reset the manual override
    IF NEW.open_time IS DISTINCT FROM OLD.open_time OR NEW.close_time IS DISTINCT FROM OLD.close_time THEN
        NEW.is_manually_closed := false;
    END IF;

    -- Smart Reset inline: If time is outside the new hours, reset override
    IF NEW.is_manually_closed = true AND v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF v_open <= v_close THEN
            IF v_now < v_open OR v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        ELSE
            IF v_now < v_open AND v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        END IF;
    END IF;

    -- Evaluate is_accepting_orders
    IF NEW.is_active = false THEN
        NEW.is_accepting_orders := false;
    ELSIF v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF NEW.is_manually_closed = true THEN
            NEW.is_accepting_orders := false;
        ELSE
            IF v_open <= v_close THEN
                NEW.is_accepting_orders := ( v_now >= v_open AND v_now <= v_close );
            ELSE
                NEW.is_accepting_orders := ( v_now >= v_open OR  v_now <= v_close );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
-- Trigger is already attached from previous migration, just replacing the function body.
