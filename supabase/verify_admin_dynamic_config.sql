DO $$
DECLARE
    v_customer_id uuid;
    v_shop_id uuid;
    v_product_id uuid;
    v_cart_group_id_1 uuid := gen_random_uuid();
    v_cart_group_id_2 uuid := gen_random_uuid();
    
    v_order_id_1 uuid := gen_random_uuid();
    v_order_id_2 uuid := gen_random_uuid();
    
    v_price numeric;
    
    v_rider_earnings_1 numeric;
    v_rider_earnings_2 numeric;
    v_gst_delivery_1 numeric;
    v_gst_delivery_2 numeric;
    
    v_orders jsonb;
    v_items jsonb;
    v_grand_total numeric;
BEGIN
    RAISE NOTICE '--- Starting Admin Dynamic Config Validation ---';
    ALTER TABLE orders DISABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders DISABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders DISABLE TRIGGER tr_rider_new_order_push;

    -- 1. Setup Test Data
    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    IF v_customer_id IS NULL THEN RAISE EXCEPTION 'No customer found'; END IF;

    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id 
    WHERE s.is_active = true LIMIT 1;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'No product found'; END IF;

    -- Update inventory for test
    UPDATE products SET total_quantity = 100 WHERE id = v_product_id;

    -- Calculate expected grand total (Item + 2.5 Platform + 0 Small Cart + 100 Delivery + 0 Surcharge + 0 Heavy)
    -- GST: 18% on 100 = 18.0 (default non-food fallback).
    v_grand_total := v_price + 0.0 + 18.0 + 2.5 + 0.0 + 100.0;

    -- Construct payloads (with delivery charge = 100, so it easily clears the 10/km * 1.5km = 15 floor)
    v_orders := jsonb_build_array(
        jsonb_build_object(
            'id', v_order_id_1,
            'customer_id', v_customer_id,
            'shop_id', v_shop_id,
            'payment_method', 'cod',
            'payment_status', 'pending',
            'status', 'awaiting_acceptance',
            'estimated_distance_km', 1.5,
            'total_amount', v_price,
            's9_5_gst_amount', 0.0,
            'non_food_gst_amount', 18.0,
            'platform_fee', 2.5,
            'delivery_charges', 100.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', v_grand_total
        )
    );

    v_items := jsonb_build_array(
        jsonb_build_object(
            'product_id', v_product_id,
            'order_id', v_order_id_1,
            'shop_id', v_shop_id,
            'quantity', 1,
            'price', v_price
        )
    );

    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id_1, NULL::uuid, NULL::text, NULL::uuid);

    SELECT rider_earnings, gst_delivery INTO v_rider_earnings_1, v_gst_delivery_1
    FROM orders WHERE id = v_order_id_1;

    RAISE NOTICE 'Order 1 (Original Config) - Rider Earnings: %, GST Delivery: %', v_rider_earnings_1, v_gst_delivery_1;

    -- 3. Modify Admin Config
    UPDATE platform_config SET value = '50.0' WHERE key = 'rider_commission_percent';
    UPDATE platform_config SET value = '0.05' WHERE key = 'delivery_gst_rate';

    -- 4. Checkout 2 (with modified config)
    v_orders := jsonb_build_array(
        jsonb_build_object(
            'id', v_order_id_2,
            'customer_id', v_customer_id,
            'shop_id', v_shop_id,
            'payment_method', 'cod',
            'payment_status', 'pending',
            'status', 'awaiting_acceptance',
            'estimated_distance_km', 1.5,
            'total_amount', v_price,
            's9_5_gst_amount', 0.0,
            'non_food_gst_amount', 18.0,
            'platform_fee', 2.5,
            'delivery_charges', 100.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', v_grand_total
        )
    );

    v_items := jsonb_build_array(
        jsonb_build_object(
            'product_id', v_product_id,
            'order_id', v_order_id_2,
            'shop_id', v_shop_id,
            'quantity', 1,
            'price', v_price
        )
    );

    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id_2, NULL::uuid, NULL::text, NULL::uuid);

    SELECT rider_earnings, gst_delivery INTO v_rider_earnings_2, v_gst_delivery_2
    FROM orders WHERE id = v_order_id_2;

    RAISE NOTICE 'Order 2 (Modified Config) - Rider Earnings: %, GST Delivery: %', v_rider_earnings_2, v_gst_delivery_2;

    -- 5. Restore Admin Config
    UPDATE platform_config SET value = '80.0' WHERE key = 'rider_commission_percent';
    UPDATE platform_config SET value = '0.18' WHERE key = 'delivery_gst_rate';

    -- 6. Validate Output
    IF v_rider_earnings_1 = v_rider_earnings_2 THEN
        RAISE EXCEPTION 'CRITICAL FAILURE: Rider Earnings did NOT change dynamically!';
    END IF;

    IF v_gst_delivery_1 = v_gst_delivery_2 THEN
        RAISE EXCEPTION 'CRITICAL FAILURE: Delivery GST did NOT change dynamically!';
    END IF;

    RAISE NOTICE 'SUCCESS: Dynamic Admin configurations are instantly parsed by the transaction!';
    
    ALTER TABLE orders ENABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders ENABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders ENABLE TRIGGER tr_rider_new_order_push;
END;
$$;
