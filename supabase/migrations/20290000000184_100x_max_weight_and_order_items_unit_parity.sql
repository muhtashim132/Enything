-- ==============================================================================
-- 100X FORENSIC FORTRESS: MAXIMUM WEIGHT CEILING & ORDER ITEMS UNIT WEIGHT PARITY
-- Migration: 20290000000184_100x_max_weight_and_order_items_unit_parity.sql
--
-- Objective:
-- 1. Enforce strict 15.0 kg maximum physical delivery weight limit for two-wheelers
--    inside `place_orders_transaction` and `customer_swap_order_item`.
-- 2. Treat `v_item.weight_kg` as unit weight (weight per 1 quantity) across both
--    client checkout and backend PostgreSQL calculations to eliminate quantity-squaring bugs.
-- 3. Maintain 100% prepaid zero-COD model, soft delete compliance, row-level locking,
--    and idempotency.
-- ==============================================================================

-- ── 1. Fortify customer_swap_order_item RPC ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_swap_order_item(
  p_order_id UUID,
  p_declined_item_id UUID,
  p_replacement_product_id UUID,
  p_replacement_variant_name TEXT DEFAULT NULL,
  p_quantity INT DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order record;
  v_declined_item record;
  v_prod record;
  v_variant_price numeric;
  v_replacement_price numeric;
  v_price_delta numeric;
  v_new_item_id uuid := gen_random_uuid();
  v_old_item_subtotal numeric;
  v_new_item_subtotal numeric;
  v_new_active_subtotal numeric;
  v_clean_unit text;
  v_replacement_unit_weight_kg numeric;
  v_order_total_weight_kg numeric;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  -- Strict customer authorization
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() IS NULL OR (v_order.customer_id != auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_order.status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be modified at status %', v_order.status;
  END IF;

  -- Verify declined item exists and belongs to this order
  SELECT * INTO v_declined_item FROM order_items WHERE id = p_declined_item_id AND order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Declined item not found';
  END IF;

  -- 100x REPLAY PREVENTION: Only declined items can be swapped
  IF v_declined_item.status != 'declined' THEN
    RAISE EXCEPTION 'Item % is not in declined status (current status: %)', p_declined_item_id, v_declined_item.status;
  END IF;

  -- Lock replacement product from same shop
  SELECT * INTO v_prod FROM products 
  WHERE id = p_replacement_product_id 
    AND shop_id = v_order.shop_id 
    AND is_deleted = false 
    AND is_available = true 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Replacement product not available at this shop';
  END IF;

  -- Check inventory
  IF v_prod.total_quantity IS NOT NULL THEN
    IF v_prod.total_quantity < p_quantity THEN
      RAISE EXCEPTION 'Replacement product stock insufficient (Available: %, Requested: %)', v_prod.total_quantity, p_quantity;
    END IF;
    UPDATE products SET total_quantity = total_quantity - p_quantity WHERE id = p_replacement_product_id;
  END IF;

  -- Resolve variant price if applicable
  v_replacement_price := v_prod.price;
  IF p_replacement_variant_name IS NOT NULL AND p_replacement_variant_name != '' THEN
    SELECT (v->>'price')::numeric INTO v_variant_price
    FROM jsonb_array_elements(v_prod.variants) AS v
    WHERE v->>'name' = p_replacement_variant_name;
    
    IF v_variant_price IS NOT NULL THEN
      v_replacement_price := v_variant_price;
    END IF;
  END IF;

  -- 100x UNIT WEIGHT NORMALIZATION
  IF v_prod.weight_per_unit IS NOT NULL AND v_prod.weight_per_unit > 0 THEN
    v_clean_unit := lower(trim(COALESCE(v_prod.unit_type, 'kg')));
    IF v_clean_unit IN ('g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres') THEN
      v_replacement_unit_weight_kg := v_prod.weight_per_unit / 1000.0;
    ELSIF v_clean_unit IN ('mg', 'milligram', 'milligrams') THEN
      v_replacement_unit_weight_kg := v_prod.weight_per_unit / 1000000.0;
    ELSIF v_clean_unit IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres') THEN
      v_replacement_unit_weight_kg := v_prod.weight_per_unit;
    ELSE
      IF v_prod.weight_per_unit > 20.0 THEN
        v_replacement_unit_weight_kg := v_prod.weight_per_unit / 1000.0;
      ELSE
        v_replacement_unit_weight_kg := v_prod.weight_per_unit;
      END IF;
    END IF;
  ELSE
    v_replacement_unit_weight_kg := 0.5;
  END IF;

  v_old_item_subtotal := v_declined_item.price * v_declined_item.quantity;
  v_new_item_subtotal := v_replacement_price * p_quantity;
  v_price_delta := v_new_item_subtotal - v_old_item_subtotal;

  -- 100x FINANCIAL INTEGRITY: If order is already captured and replacement is more expensive,
  -- block direct swap and instruct customer to checkout to pay the price delta.
  IF v_order.payment_status = 'captured' AND v_price_delta > 0.01 THEN
    RAISE EXCEPTION 'REPLACEMENT_PRICE_EXCEEDS_ORIGINAL: Replacement item costs ₹% more than original item. Please select an item of equal or lower price.', v_price_delta;
  END IF;

  -- Insert new replacement order item with complete unit_price & total_price
  INSERT INTO order_items (
    id, order_id, product_id, product_name, variant_name,
    quantity, price, unit_price, total_price, status, weight_kg, created_at
  ) VALUES (
    v_new_item_id, p_order_id, p_replacement_product_id, v_prod.name, p_replacement_variant_name,
    p_quantity, v_replacement_price, v_replacement_price, v_new_item_subtotal, 'active', v_replacement_unit_weight_kg, NOW()
  );

  -- Mark old item as swapped
  UPDATE order_items 
  SET status = 'swapped', declined_reason = 'customer_replaced'
  WHERE id = p_declined_item_id;

  -- 100x PHYSICAL TWO-WHEELER PAYLOAD LIMIT GUARD (15.0 KG)
  SELECT COALESCE(SUM(quantity * COALESCE(weight_kg, 0.5)), 0)
  INTO v_order_total_weight_kg
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  IF v_order_total_weight_kg > 15.0 THEN
    RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Swapping this item brings order weight to % kg, exceeding the 15.0 kg two-wheeler limit.', round(v_order_total_weight_kg::numeric, 2);
  END IF;

  -- Recalculate true active subtotal
  SELECT COALESCE(SUM(price * quantity), 0)
  INTO v_new_active_subtotal
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- Update order totals
  UPDATE orders
  SET total_amount = v_new_active_subtotal,
      updated_at = NOW()
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_item_id', v_new_item_id,
    'price_delta', v_price_delta,
    'new_subtotal', v_new_active_subtotal,
    'total_weight_kg', v_order_total_weight_kg
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO service_role;

-- ── 2. Fortify place_orders_transaction (15.0 kg Max Weight Ceiling & Unit Weight Parity) ──
CREATE OR REPLACE FUNCTION public.place_orders_transaction(
  p_orders jsonb,
  p_items jsonb,
  p_cart_group_id uuid,
  p_coupon_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text,
  p_order_id_to_cancel uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order jsonb;
  v_item record;
  v_expected_total_amount numeric;
  v_expected_grand_total numeric;
  v_s9_5_gst numeric;
  v_non_food_gst numeric;
  v_tcs_amount numeric;
  v_tds_amount numeric;
  v_pure_commission numeric;
  v_default_comm numeric := 5.0;
  v_shop_comm numeric;
  v_cat_comm numeric;
  v_category text;
  v_shop_category text;
  v_item_cat text;
  v_db_product_name text;
  v_gst_rate numeric;
  v_gst_override numeric;
  v_is_deemed boolean;
  v_tcs_rate numeric;
  v_line_gst numeric;
  v_slab_threshold numeric;
  v_slab_high_rate numeric;
  
  v_platform_gst_rate numeric := 0.18;
  v_delivery_gst_rate numeric := 0.18;
  v_rider_commission_percent numeric := 80.0;
  v_gateway_gst_rate CONSTANT numeric := 0.18;
  
  v_server_gst_platform numeric;
  v_server_gst_delivery numeric;
  v_server_enything_commission numeric;
  v_server_seller_payout numeric;
  v_seller_gw_share numeric;
  v_server_rider_earnings numeric;
  v_gw_deduct numeric;
  
  v_inserted_ids uuid[] := '{}';
  v_inserted_item_ids uuid[] := '{}';
  v_secure_order jsonb;
  v_inventory_record record;
  v_db_stock int;
  v_order_seq int := 0;
  v_acceptance_deadline timestamptz;
  
  v_coupon_record record;
  v_user_usage_count int;
  v_total_usage_count int;
  v_customer_id uuid;
  v_expected_discount numeric := 0;
  v_coupon_discount_sum numeric := 0;
  v_calculated_discount numeric := 0;
  v_client_claimed_discount numeric := 0;
  v_sum_expected_total_amount numeric := 0;
  v_sum_verified_shop_totals numeric := 0;

  v_shop_count int := 0;
  v_sum_client_multi_shop_surcharge numeric := 0;
  v_expected_surcharge numeric := 0;
  
  v_global_delivery_base numeric := 20.0;
  v_delivery_rate_per_km numeric := 20.0;
  v_calculated_delivery_base numeric := 20.0;
  v_first_shop_dist_km double precision := 0.0;
  v_sum_client_delivery_charges numeric := 0;
  v_expected_delivery_fee numeric := 0;

  v_total_weight_kg numeric := 0;
  v_sum_client_heavy_order_fee numeric := 0;
  v_global_heavy_order_fee numeric := 25.0;
  v_global_heavy_order_threshold numeric := 10.0;
  v_expected_heavy_order_fee numeric := 0.0;

  v_sum_client_small_cart_fee numeric := 0;
  v_global_small_cart_fee numeric := 15.0;
  v_global_small_cart_threshold numeric := 99.0;

  v_sum_client_platform_fee numeric := 0;
  v_global_platform_fee numeric := 20.0;
  v_expected_platform_fee numeric := 20.0;
  v_is_replacement boolean := false;

  v_shop_lat numeric;
  v_shop_lng numeric;
  v_shop_is_active boolean;
  v_shop_is_accepting boolean;
  v_shop_is_open boolean;
  v_shop_is_available boolean;
  v_product_shop_id uuid;
  v_dist_km double precision;
  v_max_radius_km double precision := 15.0;
  v_unit_weight numeric;
  v_unit_type text;
  v_item_category text;
  v_clean_unit text;
  v_resolved_unit_weight_kg numeric;
  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;

  v_shop_lats double precision[] := '{}';
  v_shop_lngs double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharge numeric;
  i int;
BEGIN
  IF jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Transaction must contain at least one order.';
  END IF;

  -- 100x STEP 0: STRICT SESSION AUTHENTICATION & ZERO COD ENFORCEMENT
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Active session required to place orders.';
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    IF auth.uid() != (v_order->>'customer_id')::uuid AND NOT public.is_active_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Unauthorized: customer_id mismatch (% vs %)', auth.uid(), v_order->>'customer_id';
    END IF;

    -- Strict Whitelist: Only prepaid online payments allowed
    IF lower(trim(COALESCE(v_order->>'payment_method', ''))) NOT IN ('upi', 'online', 'card', 'razorpay') THEN
      RAISE EXCEPTION 'COD_NOT_SUPPORTED: Cash on delivery is not supported. All orders must be prepaid online.';
    END IF;
  END LOOP;

  -- Verify orphan item injection: all items must belong to declared orders
  FOR v_item IN SELECT order_id FROM jsonb_to_recordset(p_items) AS x(order_id uuid) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_orders) AS o 
      WHERE (o->>'id')::uuid = v_item.order_id
    ) THEN
      RAISE EXCEPTION 'Security violation: Item declared for unknown order %', v_item.order_id;
    END IF;
  END LOOP;

  -- 100x IDEMPOTENCY SAFETY GUARD
  IF p_idempotency_key IS NOT NULL AND trim(p_idempotency_key) != '' THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN (
        SELECT jsonb_agg(to_jsonb(o))
        FROM orders o
        WHERE o.idempotency_key = p_idempotency_key
      );
    END IF;
  END IF;

  -- REPLACEMENT ORDER & PREVIOUS RIDER INHERITANCE
  IF p_cart_group_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = p_cart_group_id
        AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded')
    ) INTO v_is_replacement;

    SELECT delivery_partner_id, rider_phone, partner_accepted
    INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded')
    LIMIT 1;
  END IF;

  -- Dynamic Platform Configurations
  BEGIN SELECT (value#>>'{}')::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := NULL; END;
  IF v_default_comm IS NULL THEN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_default_comm FROM platform_config WHERE key = 'commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  END IF;
  v_default_comm := LEAST(GREATEST(COALESCE(v_default_comm, 5.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := LEAST(GREATEST(COALESCE(v_platform_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := LEAST(GREATEST(COALESCE(v_delivery_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := LEAST(GREATEST(COALESCE(v_rider_commission_percent, 80.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}')::double precision INTO v_max_radius_km FROM platform_config WHERE key = 'max_delivery_radius_km'; EXCEPTION WHEN OTHERS THEN v_max_radius_km := 15.0; END;
  v_max_radius_km := GREATEST(COALESCE(v_max_radius_km, 15.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_global_delivery_base := 20.0; END;
  v_global_delivery_base := GREATEST(COALESCE(v_global_delivery_base, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 20.0; END;
  v_delivery_rate_per_km := GREATEST(COALESCE(v_delivery_rate_per_km, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 20.0; END;
  v_global_platform_fee := GREATEST(COALESCE(v_global_platform_fee, 20.0), 0.0);

  IF jsonb_array_length(p_orders) > 50 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 50 sub-orders per cart transaction.';
  END IF;

  IF jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 500 items per cart transaction.';
  END IF;

  -- 1. Geospatial & Sequential Chain Shop Processing
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_shop_count := v_shop_count + 1;
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE((v_order->>'heavy_order_fee')::numeric, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE((v_order->>'small_cart_fee')::numeric, 0);
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE((v_order->>'platform_fee')::numeric, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE((v_order->>'delivery_charges')::numeric, 0);
    
    v_dist_km := COALESCE((v_order->>'estimated_distance_km')::double precision, 0.0);

    -- SHOP STATUS & POSTGIS RESOLUTION
    SELECT 
      ST_Y(location::geometry), ST_X(location::geometry),
      is_active, is_accepting_orders, is_open
    INTO 
      v_shop_lat, v_shop_lng,
      v_shop_is_active, v_shop_is_accepting, v_shop_is_open
    FROM shops 
    WHERE id = (v_order->>'shop_id')::uuid;

    IF v_shop_is_active = false THEN
      RAISE EXCEPTION 'Shop is suspended or inactive and cannot accept orders.';
    END IF;

    IF COALESCE(v_shop_is_accepting, true) = false OR COALESCE(v_shop_is_open, true) = false THEN
      RAISE EXCEPTION 'Shop % is currently closed or not accepting orders.', v_order->>'shop_id';
    END IF;

    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      v_shop_lats := array_append(v_shop_lats, v_shop_lat::double precision);
      v_shop_lngs := array_append(v_shop_lngs, v_shop_lng::double precision);

      IF (v_order->>'delivery_lat') IS NOT NULL AND (v_order->>'delivery_lng') IS NOT NULL THEN
        DECLARE
          v_server_calc_dist double precision;
          v_client_dist double precision := COALESCE((v_order->>'estimated_distance_km')::double precision, 0.0);
        BEGIN
          v_server_calc_dist := 6371.0 * acos(
            LEAST(1.0, GREATEST(-1.0, 
              cos(radians(v_shop_lat)) * cos(radians((v_order->>'delivery_lat')::double precision)) *
              cos(radians((v_order->>'delivery_lng')::double precision) - radians(v_shop_lng)) +
              sin(radians(v_shop_lat)) * sin(radians((v_order->>'delivery_lat')::double precision))
            ))
          );
          IF v_server_calc_dist > (v_max_radius_km + 0.5) THEN
            RAISE EXCEPTION 'Geospatial validation failed: Shop % is % km away, exceeding max delivery radius of % km.', v_order->>'shop_id', round(v_server_calc_dist::numeric, 2), v_max_radius_km;
          END IF;

          IF v_client_dist > 0 AND ABS(v_server_calc_dist - v_client_dist) <= 0.3 THEN
            v_dist_km := v_client_dist;
          ELSE
            v_dist_km := v_server_calc_dist;
          END IF;
        END;
      END IF;
    END IF;

    IF v_shop_count = 1 THEN
      v_first_shop_dist_km := COALESCE(v_dist_km, 0.0);
    END IF;
  END LOOP;

  -- Calculate Distance-Based Multi-Shop Surcharges
  IF v_shop_count > 1 AND NOT v_is_replacement THEN
    FOR i IN 1..(v_shop_count - 1) LOOP
      IF array_length(v_shop_lats, 1) >= (i + 1) THEN
        v_inter_dist := 6371.0 * acos(
          LEAST(1.0, GREATEST(-1.0, 
            cos(radians(v_shop_lats[i])) * cos(radians(v_shop_lats[i+1])) *
            cos(radians(v_shop_lngs[i+1]) - radians(v_shop_lngs[i])) +
            sin(radians(v_shop_lats[i])) * sin(radians(v_shop_lats[i+1]))
          ))
        );
        v_leg_surcharge := GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km;
        v_expected_surcharge := v_expected_surcharge + v_leg_surcharge;
      END IF;
    END LOOP;
  ELSIF v_is_replacement THEN
    v_expected_surcharge := v_sum_client_multi_shop_surcharge;
  END IF;

  -- 2. Items & Weight Validation (WITH 100X UNIT WEIGHT PARITY)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    product_id uuid, 
    variant_name text, 
    price numeric, 
    quantity int, 
    order_id uuid,
    weight_kg numeric
  ) LOOP
    IF v_item.price < 0 OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Negative financial smuggling detected: Invalid price (%) or quantity (%).', v_item.price, v_item.quantity;
    END IF;
    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_item.price);
    
    SELECT weight_per_unit, unit_type, category 
    INTO v_unit_weight, v_unit_type, v_item_category 
    FROM products 
    WHERE id = v_item.product_id;

    -- 100x UNIT WEIGHT RESOLUTION & QUANTITY INTEGRITY:
    -- If client passed a refined unit weight (from WeightEngine / variant override), prioritize it.
    -- Otherwise, convert product weight_per_unit into kg or use category baseline 0.5 kg.
    IF v_item.weight_kg IS NOT NULL AND v_item.weight_kg > 0 AND v_item.weight_kg <= 15.0 THEN
      v_resolved_unit_weight_kg := v_item.weight_kg;
    ELSIF v_unit_weight IS NOT NULL AND v_unit_weight > 0 THEN
      v_clean_unit := lower(trim(COALESCE(v_unit_type, 'kg')));
      IF v_clean_unit IN ('g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres') THEN
        v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
      ELSIF v_clean_unit IN ('mg', 'milligram', 'milligrams') THEN
        v_resolved_unit_weight_kg := v_unit_weight / 1000000.0;
      ELSIF v_clean_unit IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres') THEN
        v_resolved_unit_weight_kg := v_unit_weight;
      ELSIF v_clean_unit IN ('pieces', 'piece', 'pcs', 'pc') THEN
        IF v_unit_weight > 25.0 THEN
          v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
        ELSE
          v_resolved_unit_weight_kg := v_unit_weight;
        END IF;
      ELSE
        IF v_unit_weight > 20.0 THEN
          v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
        ELSE
          v_resolved_unit_weight_kg := v_unit_weight;
        END IF;
      END IF;

      IF v_item_category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') AND v_resolved_unit_weight_kg > 20.0 THEN
        v_resolved_unit_weight_kg := v_resolved_unit_weight_kg / 1000.0;
      END IF;
    ELSE
      v_resolved_unit_weight_kg := 0.5;
    END IF;

    -- Strict unit weight multiplication by quantity
    v_total_weight_kg := v_total_weight_kg + (v_item.quantity * v_resolved_unit_weight_kg);
  END LOOP;

  -- 100x PHYSICAL TWO-WHEELER PAYLOAD LIMIT GUARD (15.0 KG HARD STOP)
  IF v_total_weight_kg > 15.0 THEN
    RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Total order weight of % kg exceeds the maximum physical delivery capacity of 15.0 kg for two-wheeler delivery.', round(v_total_weight_kg::numeric, 2);
  END IF;

  -- 3. Small Cart & Heavy Order Fees
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 99.0);
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);

  IF v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF NOT v_is_replacement AND ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee spoofing detected. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 0.01 THEN
      RAISE EXCEPTION 'Small cart fee applied incorrectly. Cart subtotal % meets threshold %.', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := NULL; END;
  IF v_global_heavy_order_fee IS NULL THEN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee_per_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 20.0; END;
  END IF;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 20.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 10.0; END;
  v_global_heavy_order_threshold := COALESCE(v_global_heavy_order_threshold, 10.0);

  IF v_total_weight_kg > v_global_heavy_order_threshold THEN
    v_expected_heavy_order_fee := v_global_heavy_order_fee * CEIL(v_total_weight_kg - v_global_heavy_order_threshold);
    IF NOT v_is_replacement AND ABS(v_sum_client_heavy_order_fee - v_expected_heavy_order_fee) > 1.5 THEN
       IF ABS(v_sum_client_heavy_order_fee - v_global_heavy_order_fee) > 1.5 THEN
          RAISE EXCEPTION 'Heavy order fee spoofing detected. Expected: %, Got: %', v_expected_heavy_order_fee, v_sum_client_heavy_order_fee;
       END IF;
    END IF;
  ELSE
    IF v_sum_client_heavy_order_fee > 0.01 THEN
       RAISE EXCEPTION 'Heavy order fee applied incorrectly. Weight % is below threshold %.', v_total_weight_kg, v_global_heavy_order_threshold;
    END IF;
  END IF;

  -- 4. Multi-Shop Surcharge Validation
  IF NOT v_is_replacement AND ABS(v_sum_client_multi_shop_surcharge - v_expected_surcharge) > 1.0 THEN
    RAISE EXCEPTION 'Multi-shop surcharge spoofing detected. Expected: %, Got: %', v_expected_surcharge, v_sum_client_multi_shop_surcharge;
  END IF;

  -- 5. Delivery Fee Validation
  IF v_first_shop_dist_km > 0 THEN
    v_calculated_delivery_base := GREATEST(v_global_delivery_base, v_global_delivery_base + (GREATEST(0.0, v_first_shop_dist_km - 1.0) * v_delivery_rate_per_km));
  ELSE
    v_calculated_delivery_base := v_global_delivery_base;
  END IF;

  IF NOT v_is_replacement THEN
    v_expected_delivery_fee := v_calculated_delivery_base;
    IF ABS(v_sum_client_delivery_charges - v_expected_delivery_fee) > 1.5 THEN
      RAISE EXCEPTION 'Delivery charges spoofing detected. Expected: %, Got: %', v_expected_delivery_fee, v_sum_client_delivery_charges;
    END IF;
  END IF;

  -- 6. Platform Fee Validation
  IF NOT v_is_replacement THEN
    IF ABS(v_sum_client_platform_fee - v_expected_platform_fee) > 0.05 THEN
      RAISE EXCEPTION 'Platform fee spoofing detected: Sum across orders (%) != expected (%).', v_sum_client_platform_fee, v_expected_platform_fee;
    END IF;
  END IF;

  -- 7. Secure Coupon Processing
  IF p_coupon_id IS NOT NULL THEN
    SELECT * INTO v_coupon_record 
    FROM coupons 
    WHERE id = p_coupon_id AND is_active = true 
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive coupon applied.';
    END IF;

    IF v_coupon_record.valid_until < NOW() OR v_coupon_record.valid_from > NOW() THEN
      RAISE EXCEPTION 'Coupon has expired or is not yet active.';
    END IF;

    IF v_coupon_record.min_order_amount IS NOT NULL AND v_sum_expected_total_amount < v_coupon_record.min_order_amount THEN
      RAISE EXCEPTION 'Minimum order amount of % not met for coupon %.', v_coupon_record.min_order_amount, v_coupon_record.code;
    END IF;

    v_customer_id := ((p_orders->0)->>'customer_id')::uuid;

    IF v_coupon_record.usage_limit_per_user IS NOT NULL THEN
      SELECT COUNT(*) INTO v_user_usage_count 
      FROM user_coupon_usage 
      WHERE user_id = v_customer_id AND coupon_id = p_coupon_id;

      IF v_user_usage_count >= v_coupon_record.usage_limit_per_user THEN
        RAISE EXCEPTION 'You have already reached the maximum usage limit for coupon %.', v_coupon_record.code;
      END IF;
    END IF;

    IF v_coupon_record.total_usage_limit IS NOT NULL THEN
      SELECT COUNT(*) INTO v_total_usage_count 
      FROM user_coupon_usage 
      WHERE coupon_id = p_coupon_id;

      IF v_total_usage_count >= v_coupon_record.total_usage_limit THEN
        RAISE EXCEPTION 'Coupon % total redemption limit reached.', v_coupon_record.code;
      END IF;
    END IF;

    IF v_coupon_record.discount_type = 'percentage' THEN
      v_calculated_discount := (v_sum_expected_total_amount * v_coupon_record.discount_value / 100.0);
      IF v_coupon_record.max_discount_amount IS NOT NULL THEN
        v_calculated_discount := LEAST(v_calculated_discount, v_coupon_record.max_discount_amount);
      END IF;
    ELSIF v_coupon_record.discount_type = 'flat' THEN
      v_calculated_discount := LEAST(v_coupon_record.discount_value, v_sum_expected_total_amount);
    ELSE
      v_calculated_discount := 0;
    END IF;

    v_expected_discount := v_calculated_discount;

    FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
      v_client_claimed_discount := v_client_claimed_discount + COALESCE((v_order->>'coupon_discount')::numeric, 0);
    END LOOP;

    IF ABS(v_client_claimed_discount - v_expected_discount) > 0.05 THEN
      RAISE EXCEPTION 'Coupon discount spoofing detected: Claimed %, Validated %', v_client_claimed_discount, v_expected_discount;
    END IF;
  END IF;

  -- 8. Process Each Sub-Order with Commission, Tax & Financial Balancing
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order_seq := v_order_seq + 1;
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    SELECT category INTO v_shop_category
    FROM shops
    WHERE id = (v_order->>'shop_id')::uuid;

    v_shop_comm := NULL;
    IF v_shop_category IS NOT NULL AND v_shop_category != '' THEN
      BEGIN
        SELECT (value#>>'{}')::numeric INTO v_shop_comm
        FROM platform_config WHERE key = 'commission_percent_' || v_shop_category;
      EXCEPTION WHEN OTHERS THEN v_shop_comm := NULL;
      END;
    END IF;
    IF v_shop_comm IS NOT NULL THEN
      v_shop_comm := LEAST(GREATEST(v_shop_comm, 0.0), 100.0);
    ELSE
      v_shop_comm := v_default_comm;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
      product_id uuid, 
      variant_name text, 
      price numeric, 
      quantity int, 
      order_id uuid
    ) LOOP
      IF v_item.order_id != (v_order->>'id')::uuid THEN
        CONTINUE;
      END IF;

      -- Check Soft Deletes and Shop Ownership
      SELECT p.price, p.category, p.name, p.gst_rate_override, p.shop_id
      INTO v_expected_grand_total, v_category, v_db_product_name, v_gst_override, v_product_shop_id
      FROM products p
      WHERE p.id = v_item.product_id AND p.is_deleted = false;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % is no longer available.', v_item.product_id;
      END IF;

      IF v_product_shop_id != (v_order->>'shop_id')::uuid THEN
        RAISE EXCEPTION 'Security violation: Product % does not belong to shop %.', v_item.product_id, v_order->>'shop_id';
      END IF;

      IF v_item.variant_name IS NOT NULL AND v_item.variant_name != '' THEN
        DECLARE
          v_variant_price numeric;
        BEGIN
          SELECT (v->>'price')::numeric INTO v_variant_price
          FROM products p, jsonb_array_elements(p.variants) AS v
          WHERE p.id = v_item.product_id AND v->>'name' = v_item.variant_name AND p.is_deleted = false;
          
          IF v_variant_price IS NOT NULL THEN
            v_expected_grand_total := v_variant_price;
          END IF;
        END;
      END IF;

      IF ABS(v_item.price - v_expected_grand_total) > 0.01 THEN
        RAISE EXCEPTION 'Price tampering detected for %: Expected %, Got %', v_db_product_name, v_expected_grand_total, v_item.price;
      END IF;

      v_item_cat := TRIM(COALESCE(v_category, v_shop_category, 'Other'));
      v_cat_comm := NULL;
      IF v_category IS NOT NULL AND TRIM(v_category) != '' THEN
        BEGIN
          SELECT (value#>>'{}')::numeric INTO v_cat_comm
          FROM platform_config WHERE key = 'commission_percent_' || TRIM(v_category);
        EXCEPTION WHEN OTHERS THEN v_cat_comm := NULL;
        END;
      END IF;

      IF v_cat_comm IS NOT NULL THEN
        v_cat_comm := LEAST(GREATEST(v_cat_comm, 0.0), 100.0);
      ELSIF v_shop_comm IS NOT NULL THEN
        v_cat_comm := v_shop_comm;
      ELSE
        v_cat_comm := v_default_comm;
      END IF;

      v_pure_commission := v_pure_commission + (v_item.price * v_item.quantity * (v_cat_comm / 100.0));

      BEGIN
        SELECT gst_rate::numeric, is_deemed_supplier, slab_threshold, slab_high_rate
        INTO v_gst_rate, v_is_deemed, v_slab_threshold, v_slab_high_rate
        FROM tax_config WHERE category = v_item_cat;
      EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;

      IF v_gst_rate IS NULL AND v_shop_category IS NOT NULL THEN
        BEGIN
          SELECT gst_rate::numeric, is_deemed_supplier, slab_threshold, slab_high_rate
          INTO v_gst_rate, v_is_deemed, v_slab_threshold, v_slab_high_rate
          FROM tax_config WHERE category = v_shop_category;
        EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
      END IF;
        
      IF v_item_cat IN ('Clothing', 'Footwear') THEN
        v_slab_threshold := COALESCE(v_slab_threshold, 2500.0);
        v_slab_high_rate := COALESCE(v_slab_high_rate, 0.18);
        IF v_item.price > v_slab_threshold THEN
          v_gst_rate := v_slab_high_rate;
        ELSE
          v_gst_rate := COALESCE(v_gst_rate, 0.05);
        END IF;
      END IF;

      IF v_gst_rate IS NULL THEN
        v_gst_rate := 0.18;
        v_is_deemed := false;
        IF v_item_cat IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN
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
      
      v_tcs_rate := CASE WHEN v_item_cat IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Fruits & Vegs', 'Butcher', 'Fish & Seafood') THEN 0.0 ELSE 0.005 END;
      v_tcs_amount := v_tcs_amount + (v_item.price * v_item.quantity * v_tcs_rate);
      v_tds_amount := v_tds_amount + (v_item.price * v_item.quantity * 0.001);

      v_expected_total_amount := v_expected_total_amount + (v_item.quantity * v_item.price);
    END LOOP;
    
    IF v_expected_total_amount <= 0 THEN
      RAISE EXCEPTION 'Shop order % must contain at least one valid item.', v_order->>'id';
    END IF;

    v_expected_grand_total := GREATEST(0, v_expected_total_amount 
      + v_s9_5_gst + v_non_food_gst 
      + COALESCE((v_order->>'platform_fee')::numeric, 0) 
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
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

    IF ABS((v_order->>'grand_total')::numeric - v_expected_grand_total) > 1.5 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total';
    END IF;

    -- Financial Split Calculations
    v_server_gst_platform := ROUND(COALESCE((v_order->>'platform_fee')::numeric, 0) * v_platform_gst_rate / (1.0 + v_platform_gst_rate), 2);
    v_server_gst_delivery := ROUND(COALESCE((v_order->>'delivery_charges')::numeric, 0) * v_delivery_gst_rate / (1.0 + v_delivery_gst_rate), 2);
    v_server_rider_earnings := ROUND(COALESCE((v_order->>'delivery_charges')::numeric, 0) * (v_rider_commission_percent / 100.0), 2);
    v_server_enything_commission := ROUND(v_pure_commission, 2);

    v_gw_deduct := COALESCE((v_order->>'gateway_deduction')::numeric, 0);
    IF v_expected_grand_total > 0 THEN
      v_seller_gw_share := ROUND(v_gw_deduct * (v_expected_total_amount / v_expected_grand_total), 2);
    ELSE
      v_seller_gw_share := 0;
    END IF;

    v_server_seller_payout := GREATEST(0, v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount - v_seller_gw_share);

    IF v_order_seq = 1 THEN
      v_acceptance_deadline := NOW() + INTERVAL '3 minutes';
    ELSE
      v_acceptance_deadline := NOW() + ((v_order_seq * 3) || ' minutes')::interval;
    END IF;

    v_secure_order := v_order || jsonb_build_object(
      'total_amount', v_expected_total_amount,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', v_s9_5_gst + v_non_food_gst,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'acceptance_deadline', v_acceptance_deadline,
      'delivery_partner_id', COALESCE(v_existing_rider_id, (v_order->>'delivery_partner_id')::uuid),
      'rider_phone', COALESCE(v_existing_rider_phone, v_order->>'rider_phone'),
      'partner_accepted', COALESCE(v_existing_partner_accepted, (v_order->>'partner_accepted')::boolean, false)
    );

    INSERT INTO orders (
      id, customer_id, shop_id, payment_method, payment_status, status,
      seller_accepted, partner_accepted, delivery_partner_id, rider_phone,
      address, address_label, delivery_lat, delivery_lng, delivery_notes,
      estimated_distance_km, acceptance_deadline, cart_group_id, idempotency_key,
      created_at, updated_at, total_amount, s9_5_gst_amount, non_food_gst_amount,
      gst_item_total, tcs_amount, tds_amount, platform_fee, delivery_charges,
      multi_shop_surcharge, small_cart_fee, heavy_order_fee, grand_total,
      grand_total_collected, gst_platform, gst_delivery,
      gateway_deduction, seller_payout, enything_commission, rider_earnings,
      coupon_id, coupon_discount, gst_rate_snapshot, prescription_urls,
      shop_prep_time_snapshot
    ) VALUES (
      (v_secure_order->>'id')::uuid, (v_secure_order->>'customer_id')::uuid, (v_secure_order->>'shop_id')::uuid,
      v_secure_order->>'payment_method', v_secure_order->>'payment_status', v_secure_order->>'status',
      (v_secure_order->>'seller_accepted')::boolean, (v_secure_order->>'partner_accepted')::boolean,
      (v_secure_order->>'delivery_partner_id')::uuid, v_secure_order->>'rider_phone',
      v_secure_order->>'address', v_secure_order->>'address_label',
      (v_secure_order->>'delivery_lat')::numeric, (v_secure_order->>'delivery_lng')::numeric,
      v_secure_order->>'delivery_notes', (v_secure_order->>'estimated_distance_km')::numeric,
      (v_secure_order->>'acceptance_deadline')::timestamptz, (v_secure_order->>'cart_group_id')::uuid,
      v_secure_order->>'idempotency_key', (v_secure_order->>'created_at')::timestamptz,
      (v_secure_order->>'updated_at')::timestamptz, (v_secure_order->>'total_amount')::numeric,
      (v_secure_order->>'s9_5_gst_amount')::numeric, (v_secure_order->>'non_food_gst_amount')::numeric,
      (v_secure_order->>'gst_item_total')::numeric, (v_secure_order->>'tcs_amount')::numeric,
      (v_secure_order->>'tds_amount')::numeric, (v_secure_order->>'platform_fee')::numeric,
      (v_secure_order->>'delivery_charges')::numeric, (v_secure_order->>'multi_shop_surcharge')::numeric,
      (v_secure_order->>'small_cart_fee')::numeric, (v_secure_order->>'heavy_order_fee')::numeric,
      (v_secure_order->>'grand_total')::numeric, (v_secure_order->>'grand_total_collected')::numeric,
      (v_secure_order->>'gst_platform')::numeric, (v_secure_order->>'gst_delivery')::numeric,
      (v_secure_order->>'gateway_deduction')::numeric, (v_secure_order->>'seller_payout')::numeric,
      (v_secure_order->>'enything_commission')::numeric, (v_secure_order->>'rider_earnings')::numeric,
      (v_secure_order->>'coupon_id')::uuid, (v_secure_order->>'coupon_discount')::numeric,
      v_secure_order->'gst_rate_snapshot', v_secure_order->'prescription_urls',
      (v_secure_order->>'shop_prep_time_snapshot')::int
    );

    v_inserted_ids := array_append(v_inserted_ids, (v_secure_order->>'id')::uuid);
  END LOOP;

  -- 9. Inventory Verification & Reservation WITH DETERMINISTIC FOR UPDATE ROW LOCKING
  FOR v_item IN SELECT product_id, SUM(quantity)::int AS total_qty_req
                FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int)
                GROUP BY product_id 
                ORDER BY product_id ASC LOOP
    SELECT total_quantity, name, is_available INTO v_db_stock, v_db_product_name, v_shop_is_available
    FROM products
    WHERE id = v_item.product_id AND is_deleted = false
    FOR UPDATE;

    IF v_shop_is_available = false THEN
      RAISE EXCEPTION 'Product % is currently marked unavailable.', COALESCE(v_db_product_name, v_item.product_id::text);
    END IF;

    IF v_db_stock IS NOT NULL THEN
      IF v_db_stock < v_item.total_qty_req THEN
        RAISE EXCEPTION 'Product % is out of stock (Available: %, Requested: %)',
          COALESCE(v_db_product_name, v_item.product_id::text), v_db_stock, v_item.total_qty_req;
      END IF;

      UPDATE products
      SET total_quantity = total_quantity - v_item.total_qty_req
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  -- Insert order items (WITH UNIT WEIGHT INTEGRITY)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    id uuid,
    order_id uuid,
    product_id uuid,
    product_name text,
    variant_name text,
    quantity int,
    price numeric,
    weight_kg numeric,
    requires_prescription boolean,
    special_instructions text,
    created_at timestamptz
  ) LOOP
    SELECT name INTO v_db_product_name FROM products WHERE id = v_item.product_id;

    INSERT INTO order_items (
      id, order_id, product_id, product_name, variant_name, quantity, price,
      unit_price, total_price, weight_kg, requires_prescription, special_instructions, created_at
    ) VALUES (
      COALESCE(v_item.id, gen_random_uuid()),
      v_item.order_id,
      v_item.product_id,
      COALESCE(v_item.product_name, v_db_product_name, 'Product'),
      v_item.variant_name,
      COALESCE(v_item.quantity, 1),
      v_item.price,
      COALESCE(v_item.price, 0),
      COALESCE(v_item.price * COALESCE(v_item.quantity, 1), 0),
      COALESCE(v_item.weight_kg, 0.5),
      COALESCE(v_item.requires_prescription, false),
      v_item.special_instructions,
      COALESCE(v_item.created_at, now())
    );
    v_inserted_item_ids := array_append(v_inserted_item_ids, COALESCE(v_item.id, gen_random_uuid()));
  END LOOP;

  -- 10. Record Coupon Usage
  IF p_coupon_id IS NOT NULL THEN
    INSERT INTO user_coupon_usage (user_id, coupon_id, order_id, discount_applied)
    VALUES (v_customer_id, p_coupon_id, v_inserted_ids[1], v_expected_discount);
  END IF;

  -- 11. Replacement Order Cleanup & Delivery Fee Rebalancing
  IF p_order_id_to_cancel IS NOT NULL OR v_is_replacement THEN
    IF p_order_id_to_cancel IS NOT NULL THEN
      UPDATE orders
      SET status = CASE 
            WHEN status IN ('delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded') THEN status
            ELSE 'cancelled'
          END,
          cancelled_reason = 'customer_replaced',
          updated_at = NOW()
      WHERE id = p_order_id_to_cancel;
    END IF;

    UPDATE orders
    SET cancelled_reason = 'customer_replaced',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel')
      AND (cancelled_reason IS NULL OR cancelled_reason != 'customer_replaced');

    UPDATE orders
    SET acceptance_deadline = NOW() + INTERVAL '3 minutes',
        payment_deadline = NOW() + INTERVAL '10 minutes',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');

    BEGIN
      PERFORM acknowledge_partial_rejection(p_cart_group_id, 'replaced');
    EXCEPTION WHEN OTHERS THEN
    END;

    BEGIN
      PERFORM rebalance_active_delivery_fees(p_cart_group_id);
    EXCEPTION WHEN OTHERS THEN
    END;
  END IF;

  RETURN (
    SELECT jsonb_agg(to_jsonb(o))
    FROM orders o
    WHERE o.id = ANY(v_inserted_ids)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO service_role;
