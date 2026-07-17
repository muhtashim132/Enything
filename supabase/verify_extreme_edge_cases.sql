DO $$
DECLARE
    v_customer_id uuid;
    v_shop_id uuid;
    v_product_id uuid;
    v_cart_group_id uuid := gen_random_uuid();
    v_order_id uuid := gen_random_uuid();
    v_price numeric;
    v_orders jsonb;
    v_items jsonb;
    
    v_error_msg text;
BEGIN
    RAISE NOTICE '--- Starting Extreme Edge Cases Testing ---';
    ALTER TABLE orders DISABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders DISABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders DISABLE TRIGGER tr_rider_new_order_push;

    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id WHERE s.is_active = true LIMIT 1;

    -- CASE 1: 0 Delivery Fee
    v_orders := jsonb_build_array(
        jsonb_build_object(
            'id', v_order_id,
            'customer_id', v_customer_id,
            'shop_id', v_shop_id,
            'payment_method', 'cod',
            'payment_status', 'pending',
            'status', 'awaiting_acceptance',
            'estimated_distance_km', 5.0,
            'total_amount', v_price,
            's9_5_gst_amount', 0.0,
            'non_food_gst_amount', 18.0,
            'platform_fee', 2.5,
            'delivery_charges', 0.0, -- HACK!
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', v_price + 18.0 + 2.5
        )
    );
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)
    );
    
    BEGIN
        PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
        RAISE EXCEPTION 'CASE 1 FAILED: Allowed 0 delivery fee!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Delivery charge floor breached%' THEN
            RAISE NOTICE 'CASE 1 PASSED: Delivery floor enforced (%).', SQLERRM;
        ELSE
            RAISE EXCEPTION 'CASE 1 FAILED WITH WRONG ERROR: %', SQLERRM;
        END IF;
    END;

    -- CASE 2: Too many items (JSON bomb)
    -- We construct a JSON array of 151 items.
    v_items := (SELECT jsonb_agg(jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)) FROM generate_series(1, 151));
    v_orders := jsonb_build_array(
        jsonb_build_object(
            'id', v_order_id,
            'customer_id', v_customer_id,
            'shop_id', v_shop_id,
            'payment_method', 'cod',
            'payment_status', 'pending',
            'status', 'awaiting_acceptance',
            'estimated_distance_km', 1.0,
            'total_amount', v_price * 151,
            's9_5_gst_amount', 0.0,
            'non_food_gst_amount', 18.0 * 151,
            'platform_fee', 2.5,
            'delivery_charges', 20.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', (v_price * 151) + (18.0 * 151) + 2.5 + 20.0
        )
    );
    
    BEGIN
        PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
        RAISE EXCEPTION 'CASE 2 FAILED: Allowed 151 items!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%too many items%' THEN
            RAISE NOTICE 'CASE 2 PASSED: JSON Bomb prevented (%).', SQLERRM;
        ELSE
            RAISE EXCEPTION 'CASE 2 FAILED WITH WRONG ERROR: %', SQLERRM;
        END IF;
    END;

    -- CASE 3: Max int quantity exploit
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 101, 'price', v_price)
    );
    BEGIN
        PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
        RAISE EXCEPTION 'CASE 3 FAILED: Allowed 101 quantity!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%cannot exceed 100%' THEN
            RAISE NOTICE 'CASE 3 PASSED: Max quantity prevented (%).', SQLERRM;
        ELSE
            RAISE EXCEPTION 'CASE 3 FAILED WITH WRONG ERROR: %', SQLERRM;
        END IF;
    END;

    RAISE NOTICE 'ALL EXTREME EDGE CASES PASSED! ABSOLUTE CHECKOUT FORTRESS SECURED!';
    ALTER TABLE orders ENABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders ENABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders ENABLE TRIGGER tr_rider_new_order_push;
END;
$$;
