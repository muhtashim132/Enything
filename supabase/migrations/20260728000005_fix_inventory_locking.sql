-- =============================================================================
-- Migration: Fix Inventory Locking Deadlocks in place_orders_transaction
-- Description: Groups and orders by product_id before acquiring FOR UPDATE 
-- locks to completely prevent deadlocks under high concurrency.
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
      COALESCE(v_order.gst_item_total, 0) +
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.platform_fee, 0) -
      COALESCE(v_order.coupon_discount, 0);

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
    SET used_count = used_count + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID) TO authenticated;

-- =============================================================================
-- Fix client_confirm_payment Idempotency
-- Prevents marking successful payments for refund on duplicate webhook/client calls
-- =============================================================================
CREATE OR REPLACE FUNCTION client_confirm_payment(
  p_order_id UUID DEFAULT NULL,
  p_cart_group_id UUID DEFAULT NULL,
  p_razorpay_payment_id text DEFAULT NULL,
  p_razorpay_order_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_existing_payment_id text;
  v_order_id uuid;
  v_rec record;
BEGIN
  IF p_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status, razorpay_payment_id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_rec.status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = v_rec.id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_rec.payment_status = 'captured' AND v_rec.razorpay_payment_id = p_razorpay_payment_id THEN
           CONTINUE;
        END IF;
        
        -- State changed during payment (e.g. cancelled/timeout) and this is a NEW payment. Capture and refund.
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    SELECT status, payment_status, razorpay_payment_id INTO v_status, v_payment_status, v_existing_payment_id FROM orders WHERE id = p_order_id FOR UPDATE;
    IF FOUND THEN
      IF v_status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = p_order_id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_payment_status = 'captured' AND v_existing_payment_id = p_razorpay_payment_id THEN
           RETURN;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = p_order_id;
      END IF;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION client_confirm_payment(UUID, UUID, text, text) TO authenticated;
