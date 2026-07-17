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
    v_huge_string text := repeat('A', 2000);
BEGIN
    RAISE NOTICE '--- Starting Pixel Overloading String Bloat Verification ---';

    SELECT id INTO v_customer_id FROM profiles WHERE role = 'customer' LIMIT 1;
    SELECT p.id, p.shop_id, p.price INTO v_product_id, v_shop_id, v_price 
    FROM products p JOIN shops s ON s.id = p.shop_id WHERE s.is_active = true LIMIT 1;

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
            'grand_total', v_price + (v_price * 0.18) + 2.5 + 60.0,
            'delivery_notes', v_huge_string
        )
    );
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', v_product_id, 'order_id', v_order_id, 'shop_id', v_shop_id, 'quantity', 1, 'price', v_price)
    );
    
    BEGIN
        PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, NULL::text, NULL::uuid);
        RAISE EXCEPTION 'VULNERABLE: Allowed 2000-character delivery notes!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Delivery notes string too long%' THEN
            RAISE NOTICE 'SUCCESS: Successfully blocked string bloat pixel overloading!';
        ELSE
            RAISE EXCEPTION 'Failed with unexpected error: %', SQLERRM;
        END IF;
    END;
END;
$$;
