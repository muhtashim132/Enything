-- =============================================================================
-- Migration: Fix Checkout Spoofing and Coupon Exhaustion
-- Description: Enforces fee validation bounds in place_orders_transaction and 
-- restores coupon usage upon order cancellation.
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
      -- Find variant price from jsonb array. Using a subquery for safe extraction
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
    
    -- Sum of item base prices
    SELECT COALESCE(SUM(quantity * price), 0) INTO v_expected_total_amount
    FROM jsonb_to_recordset(p_items) AS y(order_id uuid, quantity int, price numeric)
    WHERE y.order_id = v_order.id;

    IF ABS(v_expected_total_amount - COALESCE(v_order.total_amount, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order base total mismatch. Expected: %, Got: %', v_expected_total_amount, v_order.total_amount;
    END IF;

    -- Security Bounds Validation: Enforce non-negative fees
    IF COALESCE(v_order.delivery_charges, 0) < 0 THEN
      RAISE EXCEPTION 'delivery_charges cannot be negative';
    END IF;
    IF COALESCE(v_order.multi_shop_surcharge, 0) < 0 THEN
      RAISE EXCEPTION 'multi_shop_surcharge cannot be negative';
    END IF;
    IF COALESCE(v_order.platform_fee, 0) < 0 THEN
      RAISE EXCEPTION 'platform_fee cannot be negative';
    END IF;
    IF COALESCE(v_order.small_cart_fee, 0) < 0 THEN
      RAISE EXCEPTION 'small_cart_fee cannot be negative';
    END IF;
    IF COALESCE(v_order.heavy_order_fee, 0) < 0 THEN
      RAISE EXCEPTION 'heavy_order_fee cannot be negative';
    END IF;
    IF COALESCE(v_order.delivery_discount, 0) < 0 THEN
      RAISE EXCEPTION 'delivery_discount cannot be negative';
    END IF;
    IF COALESCE(v_order.coupon_discount, 0) < 0 THEN
      RAISE EXCEPTION 'coupon_discount cannot be negative';
    END IF;

    -- Grand Total math validation
    v_expected_grand_total := 
      v_expected_total_amount +
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.multi_shop_surcharge, 0) +
      COALESCE(v_order.platform_fee, 0) +
      COALESCE(v_order.small_cart_fee, 0) +
      COALESCE(v_order.heavy_order_fee, 0) -
      COALESCE(v_order.delivery_discount, 0) -
      COALESCE(v_order.coupon_discount, 0) +
      COALESCE(v_order.gst_item_total, 0) +
      COALESCE(v_order.gst_delivery, 0) +
      COALESCE(v_order.gst_platform, 0);

    -- Ensure calculated total is not negative
    IF v_expected_grand_total < 0 THEN
      v_expected_grand_total := 0;
    END IF;

    IF ABS(v_expected_grand_total - COALESCE(v_order.grand_total_collected, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order grand total mismatch. Expected: %, Got: %', v_expected_grand_total, v_order.grand_total_collected;
    END IF;
  END LOOP;

  -- 3. Insert Orders
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(null::orders, p_orders);

  -- 4. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 5. Decrement stock safely (and throw if insufficient)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int) LOOP
    SELECT total_quantity INTO v_total_qty FROM products WHERE id = v_item.product_id FOR UPDATE;
    IF v_total_qty IS NOT NULL THEN
      IF v_total_qty < v_item.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for product % (Requested: %, Available: %)', v_item.product_id, v_item.quantity, v_total_qty;
      END IF;

      UPDATE products
      SET total_quantity = total_quantity - v_item.quantity
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  -- 6. Increment coupon usage if provided
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET used_count = used_count + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID) TO authenticated;

-- =============================================================================
-- Coupon Restoration Trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION restore_coupon_usage_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only restore coupon when transitioning INTO a cancelled state
  IF NEW.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider') THEN

    IF NEW.coupon_id IS NOT NULL THEN
      UPDATE coupons
      SET used_count = GREATEST(used_count - 1, 0)
      WHERE id = NEW.coupon_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restore_coupon_on_cancel ON orders;
CREATE TRIGGER trg_restore_coupon_on_cancel
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION restore_coupon_usage_on_cancel();
