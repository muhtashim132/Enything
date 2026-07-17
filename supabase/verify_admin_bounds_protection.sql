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
    v_expected_rider_earnings numeric;
BEGIN
    RAISE NOTICE '--- Starting Admin Config Sanity Bounds Verification ---';
    ALTER TABLE orders DISABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders DISABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders DISABLE TRIGGER tr_rider_new_order_push;

    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id WHERE s.is_active = true LIMIT 1;

    -- Sabotage admin config with malicious/typo bounds
    UPDATE platform_config SET value = '500.0' WHERE key = 'rider_commission_percent'; -- 500%
    UPDATE products SET category = 'Electronics' WHERE id = v_product_id;
    UPDATE tax_config SET gst_rate = 0.18, is_deemed_supplier = false WHERE category = 'Electronics';
    
    -- Real-world logic dictates the DB should clamp 500.0 to 100.0
    v_expected_rider_earnings := 60.0 * 1.0; -- 100% of base delivery (assuming no GST and small cart fee)

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
            'delivery_charges', 60.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'multi_shop_surcharge', 0.0,
            'coupon_discount', 0.0,
            'grand_total', v_price + (v_price * 0.18) + 2.5 + 60.0
        )
    );
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)
    );
    
    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
    
    SELECT rider_earnings INTO v_rider_earnings FROM orders WHERE id = v_order_id;
    
    IF v_rider_earnings > 60.0 THEN
        RAISE EXCEPTION 'VULNERABLE: Rider earnings allowed to exceed 100%% of delivery charges! Paid: %', v_rider_earnings;
    END IF;

    RAISE NOTICE 'SUCCESS: Successfully clamped admin config typo! Rider paid: %', v_rider_earnings;
    
    ALTER TABLE orders ENABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders ENABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders ENABLE TRIGGER tr_rider_new_order_push;
END;
$$;
