-- =============================================================================
-- Migration: Fix Customer Coupons & Offline Shop Exploits
-- Description:
--   1. Blocks customers from checking out with offline shops (Checkout Exploit)
--   2. Replaces flawed FOR EACH ROW coupon trigger with a mathematically safe
--      STATEMENT level transition table trigger to perfectly restore coupons.
-- =============================================================================

-- 1. Fix place_orders_transaction to enforce shop availability
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
  v_coupon_max_uses INT;
  v_coupon_current_uses INT;
  v_shop_active BOOLEAN;
  v_shop_accepting BOOLEAN;
BEGIN
  -- 0. Validate Shops are Active and Accepting Orders
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(shop_id uuid) LOOP
    IF v_order.shop_id IS NOT NULL THEN
      SELECT is_active, is_accepting_orders INTO v_shop_active, v_shop_accepting FROM shops WHERE id = v_order.shop_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop not found for id %', v_order.shop_id;
      END IF;
      
      IF v_shop_active = false OR v_shop_accepting = false THEN
        RAISE EXCEPTION 'One or more shops in your cart are currently offline and not accepting orders.';
      END IF;
    END IF;
  END LOOP;

  -- 1. Validate Base Prices (variant-aware)
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
    platform_fee numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    delivery_discount numeric,
    coupon_discount numeric,
    gst_item_total numeric,
    gst_delivery numeric,
    gst_platform numeric,
    grand_total_collected numeric
  ) LOOP

    SELECT COALESCE(SUM(quantity * price), 0) INTO v_expected_total_amount
    FROM jsonb_to_recordset(p_items) AS y(order_id uuid, quantity int, price numeric)
    WHERE y.order_id = v_order.id;

    IF ABS(v_expected_total_amount - COALESCE(v_order.total_amount, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order base total mismatch. Expected: %, Got: %', v_expected_total_amount, v_order.total_amount;
    END IF;

    IF COALESCE(v_order.delivery_charges, 0) < 0 THEN RAISE EXCEPTION 'delivery_charges cannot be negative'; END IF;
    IF COALESCE(v_order.multi_shop_surcharge, 0) < 0 THEN RAISE EXCEPTION 'multi_shop_surcharge cannot be negative'; END IF;
    IF COALESCE(v_order.platform_fee, 0) < 0 THEN RAISE EXCEPTION 'platform_fee cannot be negative'; END IF;
    IF COALESCE(v_order.small_cart_fee, 0) < 0 THEN RAISE EXCEPTION 'small_cart_fee cannot be negative'; END IF;
    IF COALESCE(v_order.heavy_order_fee, 0) < 0 THEN RAISE EXCEPTION 'heavy_order_fee cannot be negative'; END IF;
    IF COALESCE(v_order.delivery_discount, 0) < 0 THEN RAISE EXCEPTION 'delivery_discount cannot be negative'; END IF;
    IF COALESCE(v_order.coupon_discount, 0) < 0 THEN RAISE EXCEPTION 'coupon_discount cannot be negative'; END IF;

    v_expected_grand_total :=
      v_expected_total_amount +
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

  -- 3. Validate coupon usage limit
  IF p_coupon_id IS NOT NULL THEN
    SELECT usage_limit, current_uses INTO v_coupon_max_uses, v_coupon_current_uses
    FROM coupons
    WHERE id = p_coupon_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon does not exist.';
    END IF;

    IF v_coupon_max_uses IS NOT NULL AND v_coupon_current_uses >= v_coupon_max_uses THEN
      RAISE EXCEPTION 'Coupon has reached its maximum usage limit.';
    END IF;
  END IF;

  -- 4. Insert Orders
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(
    null::orders,
    (
      SELECT jsonb_agg(
        CASE WHEN elem ? 'seller_accepted' THEN elem ELSE elem || '{"seller_accepted": false}'::jsonb END
        ||
        CASE WHEN elem ? 'partner_accepted' THEN '{}'::jsonb ELSE '{"partner_accepted": false}'::jsonb END
      )
      FROM jsonb_array_elements(p_orders) elem
    )
  );

  -- 5. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 6. Decrement stock safely WITH DEADLOCK PREVENTION
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

  -- 7. Increment coupon usage
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET current_uses = current_uses + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

-- 2. Clean up old trigger
DROP TRIGGER IF EXISTS trg_restore_coupon_on_cancel ON orders;
DROP FUNCTION IF EXISTS restore_coupon_usage_on_cancel();

-- 3. Create Statement-Level Transition Table Trigger for Mathematically Perfect Coupon Restoration
CREATE OR REPLACE FUNCTION restore_coupon_usage_stmt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Find the counts of coupons to decrement. We only decrement if a group is FULLY cancelled.
  WITH cancelled_orders AS (
      SELECT n.coupon_id, n.cart_group_id, n.id
      FROM new_orders n
      JOIN old_orders o ON n.id = o.id
      WHERE n.coupon_id IS NOT NULL
        AND n.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed')
        AND o.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed')
  ),
  decrements AS (
      SELECT coupon_id, COUNT(DISTINCT COALESCE(cart_group_id::text, id::text)) as dec_count
      FROM cancelled_orders c
      WHERE NOT EXISTS (
          SELECT 1 FROM orders o2
          WHERE o2.cart_group_id = c.cart_group_id
            AND o2.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed')
      )
      GROUP BY coupon_id
  )
  UPDATE coupons c
  SET current_uses = GREATEST(c.current_uses - d.dec_count, 0)
  FROM decrements d
  WHERE c.id = d.coupon_id;

  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_restore_coupon_stmt
AFTER UPDATE ON orders
REFERENCING OLD TABLE AS old_orders NEW TABLE AS new_orders
FOR EACH STATEMENT
EXECUTE FUNCTION restore_coupon_usage_stmt();
