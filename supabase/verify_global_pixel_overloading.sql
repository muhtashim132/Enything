DO $$
DECLARE
    v_seller_id uuid := gen_random_uuid();
    v_shop_id uuid := gen_random_uuid();
    v_product_id uuid := gen_random_uuid();
BEGIN
    RAISE NOTICE '--- Starting Global Pixel Overloading Verification ---';

    -- 1. Test string bloat on shops table
    BEGIN
        INSERT INTO shops (id, seller_id, name) VALUES (v_shop_id, v_seller_id, repeat('X', 500));
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded name in shops table!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN -- check_violation
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded name in shops table (Check violation).';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 2. Test string bloat on products table
    BEGIN
        INSERT INTO products (id, shop_id, name, price, total_quantity) VALUES (v_product_id, v_shop_id, repeat('X', 2000), 10.0, 10);
        RAISE EXCEPTION 'VULNERABLE: Allowed pixel overloaded name in products table!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked pixel overloaded name in products table.';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- 3. Test JSON bomb on products table
    BEGIN
        INSERT INTO products (id, shop_id, name, price, total_quantity, variants) VALUES (
            gen_random_uuid(), 
            v_shop_id, 
            'Normal Name',
            10.0,
            10,
            (SELECT jsonb_object_agg(x::text, repeat('X', 1000)) FROM generate_series(1, 100) x)
        );
        RAISE EXCEPTION 'VULNERABLE: Allowed JSON bomb in products table!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'SUCCESS: Blocked JSON bomb in products table.';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: % (State %)', SQLERRM, SQLSTATE;
        END IF;
    END;

END;
$$;
