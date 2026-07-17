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
    
    v_rider_earnings numeric;
    v_grand_total numeric;
    
    -- Inputs
    v_base_delivery numeric := 40.0;
    v_small_cart_fee numeric := 15.0;
    v_heavy_fee numeric := 25.0;
    v_multi_shop numeric := 0.0;
    v_total_delivery_pre_gst numeric := v_base_delivery + v_small_cart_fee + v_heavy_fee + v_multi_shop;
    v_total_delivery_post_gst numeric := v_total_delivery_pre_gst * 1.18; -- 18% GST
    
    -- Calculated dynamically by DB expected
    v_expected_rider_earnings numeric := (v_base_delivery + v_heavy_fee + v_multi_shop) * 0.80; -- 65 * 0.8 = 52
BEGIN
    RAISE NOTICE '--- Starting Infinite Money Glitch Verification ---';
    ALTER TABLE orders DISABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders DISABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders DISABLE TRIGGER tr_rider_new_order_push;

    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id WHERE s.is_active = true LIMIT 1;

    -- Setup platform config
    UPDATE platform_config SET value = '80.0' WHERE key = 'rider_commission_percent';
    UPDATE platform_config SET value = '0.18' WHERE key = 'delivery_gst_rate';
    
    -- Force v_price to 50 to allow small cart fee, and set product weight to allow heavy fee
    v_price := 50.0;
    UPDATE products SET weight_per_unit = 15.0, price = 50.0 WHERE id = v_product_id;
    
    v_grand_total := v_price + 9.0 + 2.5 + v_total_delivery_post_gst; -- 50(item) + 9(18% gst) + 2.5(plat) + 94.4(del) = 155.9
    
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
            'non_food_gst_amount', 9.0,
            'platform_fee', 2.5,
            'delivery_charges', v_total_delivery_post_gst,
            'small_cart_fee', v_small_cart_fee,
            'heavy_order_fee', v_heavy_fee,
            'multi_shop_surcharge', v_multi_shop,
            'coupon_discount', 0.0,
            'grand_total', v_grand_total
        )
    );
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)
    );
    
    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
    
    SELECT rider_earnings INTO v_rider_earnings FROM orders WHERE id = v_order_id;
    
    IF v_rider_earnings != v_expected_rider_earnings THEN
        RAISE EXCEPTION 'INFINITE MONEY GLITCH ACTIVE! Rider paid %, Expected %', v_rider_earnings, v_expected_rider_earnings;
    END IF;

    RAISE NOTICE 'SUCCESS: Rider earnings strictly calculated as % without double-counting!', v_rider_earnings;
    
    ALTER TABLE orders ENABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders ENABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders ENABLE TRIGGER tr_rider_new_order_push;
END;
$$;
