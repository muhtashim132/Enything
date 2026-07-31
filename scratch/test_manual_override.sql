-- Test to verify the manual override logic works
-- 1. Insert/Update a dummy shop to be open right now (e.g., 00:00 to 23:59)
-- 2. Simulate a cron run
-- 3. Check is_accepting_orders = true
-- 4. Simulate a manual toggle (is_accepting_orders = false via authenticated user)
-- 5. Run cron again
-- 6. Check that is_accepting_orders REMAINS false (manual priority)

DO $$
DECLARE
    v_shop_id uuid;
BEGIN
    -- We will test with an existing test shop: "Test Shop 32"
    SELECT id INTO v_shop_id FROM public.shops WHERE name = 'Test Shop 32' LIMIT 1;
    
    IF v_shop_id IS NULL THEN
       RAISE NOTICE 'Test shop not found.';
       RETURN;
    END IF;

    -- Set to 24 hours so it should always be open
    UPDATE public.shops 
    SET open_time = '00:00', close_time = '23:59:59', is_active = true, is_manually_closed = false
    WHERE id = v_shop_id;

    -- 1. Cron runs -> should be open
    PERFORM public.sync_shop_accepting_orders_by_hours();
    
    IF NOT (SELECT is_accepting_orders FROM public.shops WHERE id = v_shop_id) THEN
        RAISE EXCEPTION 'Test failed: Cron did not open 24hr shop.';
    END IF;
    
    -- 2. Simulate manual toggle by a user (setting jwt claim)
    -- We cannot easily mock jwt claims in a DO block reliably without superuser in Supabase,
    -- but we can manually trigger the condition by setting is_manually_closed directly to simulate it,
    -- or we can temporarily mock current_setting if we wrap it.
    -- Actually, we can set local setting for this transaction!
    PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    
    -- Simulate seller toggling off
    UPDATE public.shops SET is_accepting_orders = false WHERE id = v_shop_id;
    
    -- Verify trigger caught it
    IF NOT (SELECT is_manually_closed FROM public.shops WHERE id = v_shop_id) THEN
        RAISE EXCEPTION 'Test failed: Trigger did not catch manual close.';
    END IF;
    
    -- 3. Cron runs again
    PERFORM public.sync_shop_accepting_orders_by_hours();
    
    -- It should REMAIN false because of manual override
    IF (SELECT is_accepting_orders FROM public.shops WHERE id = v_shop_id) THEN
        RAISE EXCEPTION 'Test failed: Cron overrode the manual close!';
    END IF;

    RAISE NOTICE 'SUCCESS: All manual override tests passed perfectly.';
END $$;
