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
BEGIN
    RAISE NOTICE '--- Starting Ghost Shop Bypass Verification ---';

    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    
    -- Pick a shop and DEACTIVATE it
    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id LIMIT 1;
    
    UPDATE shops SET is_active = false WHERE id = v_shop_id;

    v_orders := jsonb_build_array(
        jsonb_build_object(
            'id', v_order_id,
            'customer_id', v_customer_id,
            'shop_id', v_shop_id,
            'payment_method', 'cod',
            'payment_status', 'pending',
            'status', 'awaiting_acceptance',
            'estimated_distance_km', 2.0,
            'total_amount', v_price,
            's9_5_gst_amount', 0.0,
            'non_food_gst_amount', v_price * 0.18,
            'platform_fee', 2.5,
            'delivery_charges', 40.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', v_price + (v_price * 0.18) + 2.5 + 40.0
        )
    );
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)
    );
    
    BEGIN
        PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
        RAISE EXCEPTION 'VULNERABLE: Allowed order placement at an INACTIVE ghost shop!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%inactive or closed%' THEN
            RAISE NOTICE 'SUCCESS: Successfully blocked Ghost Order Bypass Exploit!';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: %', SQLERRM;
        END IF;
    END;
    
    -- Restore shop
    UPDATE shops SET is_active = true WHERE id = v_shop_id;
END;
$$;
