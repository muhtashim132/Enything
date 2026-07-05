-- =============================================================================
-- Migration: Atomic Checkout Transaction RPC
-- Description: Places orders and order_items atomically. Decrements stock
-- safely and raises an exception if out of stock, automatically rolling back.
-- =============================================================================

CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_total_qty INT;
BEGIN
  -- 1. Insert Orders
  -- Uses jsonb_populate_recordset. The caller (Dart) MUST provide fields like
  -- 'id' and 'created_at' if it wants them populated, because missing keys
  -- will become NULL and bypass column defaults.
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(null::orders, p_orders);

  -- 2. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 3. Decrement stock safely (and throw if insufficient)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int) LOOP
    
    -- Check if product tracks inventory
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
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB) TO authenticated;
