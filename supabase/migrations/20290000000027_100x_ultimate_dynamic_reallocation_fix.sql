-- =============================================================================
-- Migration: 100x Ultimate Dynamic Reallocation Fix
-- Description:
--   1. Fixes checkout missing fees (`multi_shop_surcharge`, `small_cart_fee`, `heavy_order_fee`)
--      from `v_expected_grand_total`. This perfectly aligns with the Dart fix to `grand_total_collected`.
--   2. Updates `reallocate_cancelled_delivery_fees` to dynamically recalculate cart surcharges based 
--      on `v_active_count`, distribute the total cart fees proportionally across active orders, 
--      and accurately record the refund remainder on the cancelled order for 0% revenue leakage.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.place_orders_transaction(
    p_customer_id uuid,
    p_cart_group_id uuid,
    p_payment_method text,
    p_address text,
    p_address_label text,
    p_delivery_lat double precision,
    p_delivery_lng double precision,
    p_delivery_notes text,
    p_customer_phone text,
    p_items jsonb,
    p_orders jsonb,
    p_idempotency_key uuid,
    p_coupon_id uuid DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_cart_group_id uuid;
  v_inserted_ids uuid[] := '{}';
  v_order jsonb;
  v_item record;
  v_expected_total_amount numeric;
  v_expected_grand_total numeric;
  v_sum_expected_total_amount numeric := 0;
  v_sum_verified_shop_totals numeric := 0;
  v_db_price numeric;
  v_total_qty int;
  v_category text;
  v_gst_rate numeric;
  v_is_deemed boolean;
  v_line_gst numeric;
  v_s9_5_gst numeric;
  v_non_food_gst numeric;
  v_tcs_rate numeric;
  v_tcs_amount numeric;
  v_tds_amount numeric;
  v_gw_deduct numeric;
  v_secure_order jsonb;
  v_default_comm numeric := 5.0;
  v_cat_comm numeric;
  v_pure_commission numeric;
  v_server_gst_platform numeric;
  v_server_gst_delivery numeric;
  v_server_enything_commission numeric;
  v_server_seller_payout numeric;
  v_server_rider_earnings numeric;
  v_acceptance_deadline timestamptz;
  v_gst_override numeric;
  v_platform_gst_rate numeric;
  v_delivery_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
  BEGIN SELECT value::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);

  BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
  
  BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);

  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN jsonb_build_object('success', true, 'message', 'Idempotent request ignored (already processed)');
    END IF;
  END IF;

  v_cart_group_id := p_cart_group_id;

  SELECT COALESCE(SUM((x.quantity * x.price)), 0)
  INTO v_sum_expected_total_amount
  FROM jsonb_to_recordset(p_items) AS x(quantity int, price numeric);

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    
    IF length(v_order->>'address') > 1000 THEN RAISE EXCEPTION 'Address string too long (Max 1000 chars)'; END IF;
    IF length(v_order->>'address_label') > 100 THEN RAISE EXCEPTION 'Address label string too long (Max 100 chars)'; END IF;
    IF length(v_order->>'delivery_notes') > 500 THEN RAISE EXCEPTION 'Delivery notes string too long (Max 500 chars)'; END IF;
    IF length(v_order->>'cancelled_reason') > 500 THEN RAISE EXCEPTION 'Cancelled reason string too long (Max 500 chars)'; END IF;
    IF length(v_order->>'customer_phone') > 20 THEN RAISE EXCEPTION 'Customer phone string too long (Max 20 chars)'; END IF;
    IF length(v_order->>'shop_phone') > 20 THEN RAISE EXCEPTION 'Shop phone string too long (Max 20 chars)'; END IF;
    IF length(v_order->>'razorpay_payment_id') > 255 THEN RAISE EXCEPTION 'Payment ID string too long (Max 255 chars)'; END IF;
    IF length(v_order->>'razorpay_order_id') > 255 THEN RAISE EXCEPTION 'Order ID string too long (Max 255 chars)'; END IF;
    
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int, order_id uuid) WHERE order_id = (v_order->>'id')::uuid LOOP
      SELECT category, gst_rate_override INTO v_category, v_gst_override FROM products WHERE id = v_item.product_id;
      
      BEGIN
        SELECT value::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := v_default_comm; END;
      v_cat_comm := LEAST(GREATEST(COALESCE(v_cat_comm, v_default_comm), 0.0), 100.0);
      
      v_pure_commission := v_pure_commission + ((v_item.price * v_item.quantity * v_cat_comm) / 100.0);

      BEGIN
          SELECT gst_rate::numeric, is_deemed_supplier INTO v_gst_rate, v_is_deemed FROM tax_config WHERE category = v_category;
        EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
        
        IF v_category IN ('Clothing', 'Footwear') THEN
          IF v_item.price > 2500 THEN
            v_gst_rate := 0.18;
          ELSE
            v_gst_rate := 0.05;
          END IF;
        END IF;

        IF v_gst_rate IS NULL THEN
          v_gst_rate := 0.18;
          v_is_deemed := false;
          IF v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN
            v_gst_rate := 0.05;
            v_is_deemed := true;
          END IF;
        END IF;

        IF v_gst_override IS NOT NULL THEN
          v_gst_rate := v_gst_override;
        END IF;

        v_gst_rate := LEAST(GREATEST(v_gst_rate, 0.0), 1.0);
      
      v_line_gst := v_item.price * v_item.quantity * v_gst_rate;
      
      IF v_is_deemed THEN
        v_s9_5_gst := v_s9_5_gst + v_line_gst;
      ELSE
        v_non_food_gst := v_non_food_gst + v_line_gst;
      END IF;
      
      v_tcs_rate := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Fruits & Vegs', 'Butcher', 'Fish & Seafood') THEN 0.0 ELSE 0.01 END;
      v_tcs_amount := v_tcs_amount + (v_item.price * v_item.quantity * v_tcs_rate);
      v_tds_amount := v_tds_amount + (v_item.price * v_item.quantity * 0.001);

      v_expected_total_amount := v_expected_total_amount + (v_item.quantity * v_item.price);
    END LOOP;
    
    IF v_expected_total_amount <= 0 THEN
      RAISE EXCEPTION 'Shop order % must contain at least one valid item.', v_order->>'id';
    END IF;

    -- 100x FIX: Include all fees in grand_total_collected!
    v_expected_grand_total := GREATEST(0, v_expected_total_amount 
      + v_s9_5_gst + v_non_food_gst 
      + COALESCE((v_order->>'platform_fee')::numeric, 0) 
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
      + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
      + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
      + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0));

    IF ABS((v_order->>'total_amount')::numeric - v_expected_total_amount) > 1.0 THEN
      RAISE EXCEPTION 'Total amount mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_total_amount, v_order->>'total_amount';
    END IF;

    IF ABS((v_order->>'s9_5_gst_amount')::numeric - v_s9_5_gst) > 1.0 THEN
      RAISE EXCEPTION 'S9.5 GST mismatch for order %. Expected: %, Got: %', v_order->>'id', v_s9_5_gst, v_order->>'s9_5_gst_amount';
    END IF;
    
    IF ABS((v_order->>'non_food_gst_amount')::numeric - v_non_food_gst) > 1.0 THEN
      RAISE EXCEPTION 'Non-food GST mismatch for order %. Expected: %, Got: %', v_order->>'id', v_non_food_gst, v_order->>'non_food_gst_amount';
    END IF;

    IF ABS((v_order->>'grand_total_collected')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, (v_order->>'grand_total_collected');
    END IF;
    
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));

    v_gw_deduct := GREATEST(0, (v_expected_grand_total * 0.02) * (1.0 + v_platform_gst_rate));

    v_server_enything_commission := v_pure_commission + v_server_gst_platform;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount - v_gw_deduct;
    
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));

    IF auth.uid() IS NOT NULL AND auth.uid() != (v_order->>'customer_id')::uuid THEN
      RAISE EXCEPTION 'Unauthorized: customer_id mismatch';
    END IF;
    
    v_acceptance_deadline := (v_order->>'acceptance_deadline')::timestamptz;

    v_secure_order := jsonb_build_object(
      'id', COALESCE(v_order->>'id', gen_random_uuid()::text),
      'customer_id', auth.uid(),
      'shop_id', v_order->>'shop_id',
      'payment_method', v_order->>'payment_method',
      'payment_status', CASE WHEN (v_order->>'payment_method') = 'cod' THEN 'pending' ELSE 'awaiting_payment' END,
      'status', CASE WHEN (v_order->>'payment_method') = 'cod' THEN 'pending' ELSE 'awaiting_payment' END,
      'seller_accepted', false,
      'partner_accepted', false,
      'address', v_order->>'address',
      'address_label', v_order->>'address_label',
      'delivery_lat', (v_order->>'delivery_lat')::double precision,
      'delivery_lng', (v_order->>'delivery_lng')::double precision,
      'delivery_notes', v_order->>'delivery_notes',
      'estimated_distance_km', v_order->>'estimated_distance_km',
      'cancelled_reason', v_order->>'cancellation_reason',
      'customer_phone', v_order->>'customer_phone',
      'shop_phone', v_order->>'shop_phone',
      'shop_prep_time_snapshot', v_order->>'shop_prep_time_snapshot',
      'prescription_urls', v_order->'prescription_urls',
      'gst_rate_snapshot', v_gst_rate,
      'razorpay_payment_id', v_order->>'razorpay_payment_id',
      'razorpay_order_id', v_order->>'razorpay_order_id',
      'total_amount', v_expected_total_amount,
      'gst_item_total', v_s9_5_gst + v_non_food_gst,
      'platform_fee', COALESCE((v_order->>'platform_fee')::numeric, 0),
      'delivery_charges', COALESCE((v_order->>'delivery_charges')::numeric, 0),
      'multi_shop_surcharge', COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0),
      'small_cart_fee', COALESCE((v_order->>'small_cart_fee')::numeric, 0),
      'heavy_order_fee', COALESCE((v_order->>'heavy_order_fee')::numeric, 0),
      'coupon_discount', COALESCE((v_order->>'coupon_discount')::numeric, 0),
      'grand_total_collected', v_expected_grand_total,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'coupon_id', p_coupon_id
    );

    INSERT INTO orders (
      id, customer_id, shop_id, delivery_partner_id, cart_group_id,
      payment_method, payment_status, status,
      seller_accepted, partner_accepted, address, address_label,
      delivery_lat, delivery_lng, delivery_notes,
      estimated_distance_km, cancelled_reason,
      customer_phone, shop_phone, shop_prep_time_snapshot, prescription_urls,
      gst_rate_snapshot, razorpay_payment_id, razorpay_order_id,
      total_amount, s9_5_gst_amount, non_food_gst_amount, gst_item_total,
      platform_fee, gst_platform,
      delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee, gst_delivery,
      coupon_discount, grand_total_collected,
      tcs_amount, tds_amount,
      gateway_deduction, seller_payout, enything_commission, rider_earnings,
      idempotency_key, coupon_id, acceptance_deadline
    )
    SELECT
      (v_secure_order->>'id')::uuid,
      (v_secure_order->>'customer_id')::uuid,
      (v_secure_order->>'shop_id')::uuid,
      NULL,
      p_cart_group_id,
      v_secure_order->>'payment_method',
      v_secure_order->>'payment_status',
      v_secure_order->>'status',
      (v_secure_order->>'seller_accepted')::boolean,
      (v_secure_order->>'partner_accepted')::boolean,
      v_secure_order->>'address',
      v_secure_order->>'address_label',
      (v_secure_order->>'delivery_lat')::double precision,
      (v_secure_order->>'delivery_lng')::double precision,
      v_secure_order->>'delivery_notes',
      (v_secure_order->>'estimated_distance_km')::numeric,
      v_secure_order->>'cancelled_reason',
      v_secure_order->>'customer_phone',
      v_secure_order->>'shop_phone',
      (v_secure_order->>'shop_prep_time_snapshot')::int,
      v_secure_order->'prescription_urls',
      v_secure_order->'gst_rate_snapshot', v_secure_order->>'razorpay_payment_id', v_secure_order->>'razorpay_order_id',
      (v_secure_order->>'total_amount')::numeric,
      (v_secure_order->>'s9_5_gst_amount')::numeric,
      (v_secure_order->>'non_food_gst_amount')::numeric,
      (v_secure_order->>'gst_item_total')::numeric,
      (v_secure_order->>'platform_fee')::numeric,
      (v_secure_order->>'gst_platform')::numeric,
      (v_secure_order->>'delivery_charges')::numeric,
      (v_secure_order->>'multi_shop_surcharge')::numeric,
      (v_secure_order->>'small_cart_fee')::numeric,
      (v_secure_order->>'heavy_order_fee')::numeric,
      (v_secure_order->>'gst_delivery')::numeric,
      (v_secure_order->>'coupon_discount')::numeric,
      (v_secure_order->>'grand_total_collected')::numeric,
      (v_secure_order->>'tcs_amount')::numeric,
      (v_secure_order->>'tds_amount')::numeric,
      (v_secure_order->>'gateway_deduction')::numeric, (v_secure_order->>'seller_payout')::numeric, (v_secure_order->>'enything_commission')::numeric, (v_secure_order->>'rider_earnings')::numeric,
      p_idempotency_key::uuid,
      p_coupon_id,
      v_acceptance_deadline
    ;

    v_inserted_ids := array_append(v_inserted_ids, (v_order->>'id')::uuid);
    v_sum_verified_shop_totals := v_sum_verified_shop_totals + v_expected_total_amount;
  END LOOP;
  
  IF v_sum_verified_shop_totals != v_sum_expected_total_amount THEN
    RAISE EXCEPTION 'Phantom item smuggling detected: Some items bypassed shop validation loops.';
  END IF;
  
  FOR v_item IN
    SELECT product_id, SUM(quantity) as total_qty_req
    FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int)
    GROUP BY product_id
    ORDER BY product_id
  LOOP
    SELECT total_quantity INTO v_total_qty FROM products WHERE id = v_item.product_id FOR UPDATE;
    IF v_total_qty IS NOT NULL THEN
      IF v_total_qty < v_item.total_qty_req THEN
        RAISE EXCEPTION 'Insufficient stock for product % (Requested: %, Available: %)', v_item.product_id, v_item.total_qty_req, v_total_qty;
      END IF;
      UPDATE products SET total_quantity = total_quantity - v_item.total_qty_req WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    id uuid,
    order_id uuid,
    product_id uuid,
    variant_name text,
    quantity int,
    special_instructions text
  ) LOOP
    IF v_item.order_id = ANY(v_inserted_ids) THEN
      IF v_item.variant_name IS NULL THEN
        SELECT price INTO v_db_price FROM products WHERE id = v_item.product_id;
      ELSE
        SELECT (elem->>'price')::numeric INTO v_db_price
        FROM products, jsonb_array_elements(variants) elem
        WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
      END IF;

      INSERT INTO order_items (
        id, order_id, product_id, variant_name, price, quantity, special_instructions
      ) VALUES (
        COALESCE(v_item.id, gen_random_uuid()),
        v_item.order_id,
        v_item.product_id,
        v_item.variant_name,
        v_db_price,
        v_item.quantity,
      v_item.special_instructions
      );
    END IF;
  END LOOP;
  
  IF p_coupon_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM orders 
      WHERE cart_group_id = v_cart_group_id 
        AND coupon_id = p_coupon_id
        AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    ) THEN
      UPDATE coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Orders placed successfully');
END;
$$;


CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_available_pool NUMERIC;
  
  v_total_cart_delivery NUMERIC;
  v_total_cart_platform NUMERIC;
  v_total_cart_small NUMERIC;
  v_total_cart_heavy NUMERIC;
  v_original_surcharge NUMERIC;
  v_allowed_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC;
  
  rec RECORD;
  pay_rec RECORD;

  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
BEGIN
    BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    
    BEGIN SELECT value::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);

    BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    
    BEGIN SELECT value::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);

    PERFORM id FROM orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0) INTO v_active_count, v_active_items_total
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                         'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- 100x FIX: Find the total original pool size. We include active orders AND the NEWLY cancelled orders.
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges), 0),
            COALESCE(SUM(platform_fee), 0),
            COALESCE(SUM(small_cart_fee), 0),
            COALESCE(SUM(heavy_order_fee), 0),
            COALESCE(SUM(multi_shop_surcharge), 0)
        INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_cart_platform,
            v_total_cart_small,
            v_total_cart_heavy,
            v_original_surcharge
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND (status NOT IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
               OR delivery_charges > 0);

        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;
        
        -- Cap to ensure we don't increase the surcharge beyond what the user originally paid
        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);

        v_sum_active_grand := 0;

        FOR rec IN
            SELECT id, total_amount, gst_item_total, coupon_discount
            FROM orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted',
                             'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered')
            ORDER BY id
        LOOP
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_del := v_total_cart_delivery * v_prop;
            v_new_plat := v_total_cart_platform * v_prop;
            v_new_small := v_total_cart_small * v_prop;
            v_new_heavy := v_total_cart_heavy * v_prop;
            v_new_surcharge := v_allowed_surcharge * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del := v_new_del - (v_new_del / (1.0 + v_delivery_gst_rate));
            
            v_new_rider := GREATEST(0, (v_new_del - v_new_gst_del - v_new_small) * (v_rider_commission_percent / 100.0));
            
            v_new_grand := GREATEST(0, rec.total_amount + rec.gst_item_total + v_new_plat + v_new_del + v_new_small + v_new_heavy + v_new_surcharge - COALESCE(rec.coupon_discount, 0));

            UPDATE orders
            SET delivery_charges = v_new_del,
                platform_fee = v_new_plat,
                small_cart_fee = v_new_small,
                heavy_order_fee = v_new_heavy,
                multi_shop_surcharge = v_new_surcharge,
                gst_platform = v_new_gst_plat,
                gst_delivery = v_new_gst_del,
                rider_earnings = v_new_rider,
                grand_total_collected = v_new_grand
            WHERE id = rec.id;
            
            v_sum_active_grand := v_sum_active_grand + v_new_grand;
        END LOOP;

        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        -- 100x FIX: Apply the exact mathematical refund delta to the FIRST newly cancelled order.
        UPDATE orders
        SET grand_total_collected = v_refund_amount,
            delivery_charges = 0, platform_fee = 0, small_cart_fee = 0, heavy_order_fee = 0, multi_shop_surcharge = 0, gst_platform = 0, gst_delivery = 0, rider_earnings = 0
        WHERE id = (
            SELECT id FROM orders 
            WHERE cart_group_id = p_cart_group_id 
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
              AND delivery_charges > 0 
            ORDER BY id LIMIT 1
        );

        -- Zero out everything for the REST of the newly cancelled orders.
        UPDATE orders
        SET grand_total_collected = 0,
            delivery_charges = 0, platform_fee = 0, small_cart_fee = 0, heavy_order_fee = 0, multi_shop_surcharge = 0, gst_platform = 0, gst_delivery = 0, rider_earnings = 0
        WHERE cart_group_id = p_cart_group_id 
          AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
          AND delivery_charges > 0; -- Because we already updated the first one, the rest will just safely become 0 too.
          -- Wait! The first one had delivery_charges > 0 BEFORE the previous UPDATE. The previous UPDATE set it to 0!
          -- So this second UPDATE will naturally skip the first one! This is incredibly robust!

    END LOOP;

    RETURN TRUE;
END;
$$;
