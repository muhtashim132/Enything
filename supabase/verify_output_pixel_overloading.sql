DO $$
DECLARE
    v_profile_id uuid := gen_random_uuid();
    v_order_id uuid := gen_random_uuid();
BEGIN
    RAISE NOTICE '--- Starting Traceability & Output Storage Fortress Verification ---';

    -- Insert dummy profile for references
    INSERT INTO profiles (id, full_name, role) VALUES (v_profile_id, 'Dummy', 'customer');

    -- 1. Test Pixel Overload on Withdrawals
    BEGIN
        INSERT INTO withdrawals (id, user_id, user_role, amount, upi_id, status)
        VALUES (gen_random_uuid(), v_profile_id, 'seller', 100, repeat('X', 5000), 'pending');
        
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded upi_id in withdrawals!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded upi_id in withdrawals (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 2. Test Pixel Overload on Notifications
    BEGIN
        INSERT INTO notifications (user_id, notif_key, title, body, order_id)
        VALUES (v_profile_id, 'order_placed', 'Title', repeat('X', 5000), v_order_id);
        
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded body in notifications!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded body in notifications (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 3. Test Pixel Overload on App Logs
    BEGIN
        INSERT INTO app_logs (message)
        VALUES (repeat('X', 10000));
        
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded message in app_logs!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded message in app_logs (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- Cleanup
    DELETE FROM profiles WHERE id = v_profile_id;
    
    RAISE NOTICE '--- Verification Complete ---';
END;
$$;
