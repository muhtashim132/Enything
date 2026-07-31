-- =============================================================================
-- Migration: 20271238000000_rollback_auto_sync_hours.sql
-- Description: Rolls back the auto-syncing of is_accepting_orders and restores shops
-- =============================================================================

-- 1. Remove the trigger
DROP TRIGGER IF EXISTS trg_sync_shop_hours_update ON public.shops;
DROP FUNCTION IF EXISTS public.trg_sync_shop_hours();

-- 2. Remove the cron job
DO $$
BEGIN
    PERFORM cron.unschedule('sync-shop-hours');
EXCEPTION WHEN OTHERS THEN
    -- Ignore if job doesn't exist
END;
$$;

-- 3. Remove the sync function
DROP FUNCTION IF EXISTS public.sync_shop_accepting_orders_by_hours();
DROP FUNCTION IF EXISTS public.safe_cast_time(text);

-- 4. EMERGENCY RESTORE: Set all active shops back to accepting orders
-- Since the previous migration shut them down, we must bring them back online.
UPDATE public.shops
SET is_accepting_orders = true
WHERE is_active = true;
