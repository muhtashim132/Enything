DO $$
DECLARE
    v_order_id uuid := '6958b49d-bb18-4f11-88a1-b63e11209aee';
    v_shop_id uuid := 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce';
    v_product_id uuid := '1aaba223-98c2-4092-a217-04712a6c0dcf';
    v_user_id uuid := 'd40b97d4-1e09-4967-9fe6-f8c425b97171';
BEGIN
    RAISE NOTICE '--- Starting Core Ledger Items Fortress Verification ---';

    -- 1. Test Pixel Overload on Order Items (special_instructions)
    BEGIN
        INSERT INTO order_items (id, order_id, product_id, product_name, price, quantity, special_instructions)
        VALUES (gen_random_uuid(), v_order_id, v_product_id, 'Name', 10, 1, repeat('X', 5000));
        
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded special_instructions in order_items!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded special_instructions in order_items (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 2. Test Pixel Overload on Ratings (review)
    BEGIN
        INSERT INTO ratings (id, order_id, rater_id, ratee_id, shop_id, rating, review, rater_role, ratee_role)
        VALUES (gen_random_uuid(), v_order_id, v_user_id, v_user_id, v_shop_id, 5, repeat('X', 5000), 'customer', 'seller');
        
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded review in ratings!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded review in ratings (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;
    
    RAISE NOTICE '--- Verification Complete ---';
END;
$$;
