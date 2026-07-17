DO $$
DECLARE
    v_customer_id uuid := gen_random_uuid();
BEGIN
    RAISE NOTICE '--- Starting Support & Operations Pixel Overloading Verification ---';

    -- 2. Test string bloat on support_tickets
    BEGIN
        INSERT INTO support_tickets (id, user_id, subject, body, user_name) 
        VALUES (gen_random_uuid(), v_customer_id, 'Subject', repeat('X', 5000), 'John');
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded body in support_tickets!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded body in support_tickets table.';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 3. Test string bloat on delivery_partners
    BEGIN
        INSERT INTO delivery_partners (id, vehicle_type, vehicle_number) 
        VALUES (gen_random_uuid(), 'Bike', repeat('X', 1000));
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded vehicle_number in delivery_partners!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded vehicle_number in delivery_partners table.';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

END;
$$;
