-- =============================================================================
-- Migration: Comprehensive 100x Fixes
-- Description:
--   1. Fixes place_orders_transaction to include all fees in grand_total math.
--   2. Secures place_orders_transaction against coupon_discount spoofing.
--   3. Fixes monitor_rider_heartbeat to gracefully reassign riders instead of cancelling.
--   4. Secures request_seller_withdrawal to deduct refunded/disputed order amounts.
-- =============================================================================

-- 1 & 2. Fix place_orders_transaction
CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB,
  p_coupon_id UUID DEFAULT NULL,
  p_idempotency_key UUID DEFAULT NULL
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
  -- Idempotency Check: if this key already exists, simply return successfully
  -- to simulate a successful creation without duplicating the work.
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN;
    END IF;
  END IF;

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

    -- Prevent forged coupon discounts
    IF p_coupon_id IS NULL AND COALESCE(v_order.coupon_discount, 0) > 0 THEN
      RAISE EXCEPTION 'Cannot apply coupon discount without a valid coupon code.';
    END IF;

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

    -- Include ALL fees and taxes in grand total calculation
    v_expected_grand_total :=
      v_expected_total_amount +
      COALESCE(v_order.gst_item_total, 0) +
      COALESCE(v_order.gst_delivery, 0) +
      COALESCE(v_order.gst_platform, 0) +
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.platform_fee, 0) +
      COALESCE(v_order.multi_shop_surcharge, 0) +
      COALESCE(v_order.small_cart_fee, 0) +
      COALESCE(v_order.heavy_order_fee, 0) -
      COALESCE(v_order.delivery_discount, 0) -
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
    WHERE id = p_coupon_id FOR UPDATE;

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
        ||
        (CASE WHEN p_idempotency_key IS NOT NULL THEN jsonb_build_object('idempotency_key', p_idempotency_key) ELSE '{}'::jsonb END)
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


-- 3. Fix monitor_rider_heartbeat
CREATE OR REPLACE FUNCTION monitor_rider_heartbeat()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Unassign rider gracefully if they ghost before picking up the food
  -- Revert status back to awaiting_acceptance so another rider can be dispatched,
  -- preserving the customer's order and the shop's preparation effort.
  UPDATE orders
  SET 
    status = CASE 
      WHEN status IN ('preparing', 'ready_for_pickup') THEN status -- keep prep status
      ELSE 'awaiting_acceptance' -- rollback confirmed to awaiting dispatch
    END,
    delivery_partner_id = NULL,
    partner_accepted = false,
    arrived_at_shop_time = NULL -- Reset arrival if they claimed to arrive then ghosted
  WHERE 
    status IN ('confirmed', 'preparing', 'ready_for_pickup') 
    AND delivery_partner_id IS NOT NULL
    AND rider_location_updated_at IS NOT NULL
    AND rider_location_updated_at < (NOW() - INTERVAL '15 minutes');
END;
$$;


-- 4. Fix request_seller_withdrawal
CREATE OR REPLACE FUNCTION request_seller_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_user_id UUID;
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Acquire an advisory lock to serialize withdrawal requests for this user
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- Calculate total earned across all shops owned by the seller
  -- IMPORTANT FIX: Deduct orders where refund_status is processing or completed
  SELECT COALESCE(SUM(seller_payout), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = v_user_id);

  -- Calculate total paid (or pending)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %', v_available_balance;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Insert withdrawal
  INSERT INTO withdrawals (
    user_id, user_role, amount, upi_id, bank_account_number, bank_ifsc, bank_account_holder, status
  ) VALUES (
    v_user_id, 'seller', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
