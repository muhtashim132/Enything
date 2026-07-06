-- =============================================================================
-- Migration: Fix Orders Insert Defaults
-- Description: Ensures seller_accepted and partner_accepted default to false
-- during jsonb_populate_recordset in place_orders_transaction, preventing
-- NOT NULL constraint violations from older frontend payloads.
-- =============================================================================

CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB,
  p_coupon_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_order RECORD;
  v_db_price NUMERIC;
  v_total_qty INT;
  v_expected_total_amount NUMERIC;
  v_expected_grand_total NUMERIC;
BEGIN
  -- 1. Validate Base Prices
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric) LOOP
    IF v_item.variant_name IS NULL THEN
      SELECT price INTO v_db_price FROM products WHERE id = v_item.product_id;
    ELSE
      SELECT (elem->>'price')::numeric INTO v_db_price
      FROM products, jsonb_array_elements(variants) elem
      WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
    END IF;

    IF v_db_price IS NULL THEN
      RAISE EXCEPTION 'Product or variant not found: % / %', v_item.product_id, COALESCE(v_item.variant_name, 'None');
    END IF;

    IF ABS(v_db_price - v_item.price) > 0.01 THEN
      RAISE EXCEPTION 'Price spoofing detected for product %. Expected: %, Got: %', v_item.product_id, v_db_price, v_item.price;
    END IF;
  END LOOP;

  -- 2. Validate Order Totals & Grand Total Math
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(
    id uuid, 
    total_amount numeric,
    delivery_charges numeric,
    multi_shop_surcharge numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    delivery_discount numeric,
    platform_fee numeric,
    coupon_discount numeric,
    gst_item_total numeric,
    grand_total_collected numeric
  ) LOOP
    IF COALESCE(v_order.delivery_charges, 0) < 0 THEN
      RAISE EXCEPTION 'delivery_charges cannot be negative';
    END IF;
    IF COALESCE(v_order.platform_fee, 0) < 0 THEN
      RAISE EXCEPTION 'platform_fee cannot be negative';
    END IF;
    IF COALESCE(v_order.coupon_discount, 0) < 0 THEN
      RAISE EXCEPTION 'coupon_discount cannot be negative';
    END IF;

    -- Grand Total math validation
    v_expected_grand_total := 
      COALESCE(v_order.total_amount, 0) +
      COALESCE(v_order.gst_item_total, 0) +
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.platform_fee, 0) -
      COALESCE(v_order.coupon_discount, 0);

    IF v_expected_grand_total < 0 THEN
      v_expected_grand_total := 0;
    END IF;

    IF ABS(v_expected_grand_total - COALESCE(v_order.grand_total_collected, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order grand total mismatch. Expected: %, Got: %', v_expected_grand_total, v_order.grand_total_collected;
    END IF;
  END LOOP;

  -- 3. Insert Orders (inject default false for acceptance flags)
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(
    null::orders, 
    (
      SELECT jsonb_agg(
        elem || '{"seller_accepted": false, "partner_accepted": false}'::jsonb
      )
      FROM jsonb_array_elements(p_orders) elem
    )
  );

  -- 4. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 5. Decrement stock safely (and throw if insufficient) WITH DEADLOCK PREVENTION
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

      UPDATE products
      SET total_quantity = total_quantity - v_item.total_qty_req
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  -- 6. Increment coupon usage if provided
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET current_uses = current_uses + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID) TO authenticated;
