-- =============================================================================
-- Migration: Fix All Remaining Bugs (2026-07-29)
-- Description:
--   BUG-2: place_orders_transaction forced seller_accepted/partner_accepted=false
--           overrides magic/test account orders that legitimately set them to true.
--           Fix: Only inject default=false when the field is missing from payload,
--           not when it's explicitly set.
--   BUG-5: reallocate_cancelled_delivery_fees recalculates grand_total_collected
--           without subtracting coupon_discount → customer overcharged when a
--           partial group cancellation triggers fee reallocation.
--   BUG-9: admin_cancel_order does not set refund_status='processing' for orders
--           in seller_rejected/verification_failed state with payment_status='captured'.
--   BUG-2b: place_orders_transaction coupon validation — add max_uses check so
--            retried orders cannot reuse exhausted coupons.
-- =============================================================================

-- =============================================================================
-- FIX 1 (BUG-2): place_orders_transaction — Conditional acceptance flag injection
-- =============================================================================
-- The previous version (20260728000008) unconditionally merged
--   '{"seller_accepted": false, "partner_accepted": false}'
-- onto every order row. This broke magic/test account checkout which explicitly
-- sets seller_accepted=true, partner_accepted=true, status='awaiting_payment'.
--
-- New approach: Only set the flags to false when they are absent from the payload.
-- This preserves explicit values while still protecting against missing columns.
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
  v_coupon_max_uses INT;
  v_coupon_current_uses INT;
BEGIN
  -- 1. Validate Base Prices (variant-aware)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric) LOOP
    IF v_item.variant_name IS NULL THEN
      SELECT price INTO v_db_price FROM products WHERE id = v_item.product_id;
    ELSE
      -- Find variant price from jsonb array
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

    -- Sum of item base prices from p_items for this order
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
    -- delivery_charges already includes surcharges, GST, fees minus discounts.
    -- platform_fee already includes gst_platform.
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

  -- 3. Validate coupon (if provided) — BUG-2b FIX: re-check usage limits on retry
  -- Prevents exhausted coupons from being reused on retried orders.
  -- Column names: usage_limit (nullable = unlimited), current_uses
  IF p_coupon_id IS NOT NULL THEN
    SELECT usage_limit, current_uses INTO v_coupon_max_uses, v_coupon_current_uses
    FROM coupons
    WHERE id = p_coupon_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon does not exist.';
    END IF;

    -- Only block if usage_limit is set (NULL = unlimited)
    IF v_coupon_max_uses IS NOT NULL AND v_coupon_current_uses >= v_coupon_max_uses THEN
      RAISE EXCEPTION 'Coupon has reached its maximum usage limit.';
    END IF;
  END IF;

  -- 4. Insert Orders — BUG-2 FIX: Conditionally inject acceptance defaults.
  --    Use COALESCE so explicit true values (magic/test accounts) are preserved.
  --    Only fill in false when the field is absent from the JSON payload.
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(
    null::orders,
    (
      SELECT jsonb_agg(
        -- Inject seller_accepted=false only if the key is missing
        CASE
          WHEN elem ? 'seller_accepted' THEN elem
          ELSE elem || '{"seller_accepted": false}'::jsonb
        END
        ||
        -- Inject partner_accepted=false only if the key is missing
        CASE
          WHEN elem ? 'partner_accepted' THEN '{}'::jsonb
          ELSE '{"partner_accepted": false}'::jsonb
        END
      )
      FROM jsonb_array_elements(p_orders) elem
    )
  );

  -- 5. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 6. Decrement stock safely WITH DEADLOCK PREVENTION
  --    Groups by product_id and orders by UUID to prevent deadlocks under concurrency.
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

  -- 7. Increment coupon usage if provided
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET current_uses = current_uses + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID) TO authenticated;


-- =============================================================================
-- FIX 2 (BUG-5): reallocate_cancelled_delivery_fees — Missing coupon deduction
-- =============================================================================
-- When reallocation adds cancelled shop delivery fees to active orders, it
-- recalculated grand_total_collected WITHOUT subtracting coupon_discount.
-- This caused customers to be overcharged when partial group orders cancel.
-- =============================================================================
CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees(p_cart_group_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_missing_delivery NUMERIC := 0;
    v_missing_rider NUMERIC := 0;
    v_missing_surcharge NUMERIC := 0;
    v_missing_small NUMERIC := 0;
    v_missing_heavy NUMERIC := 0;
    v_missing_discount NUMERIC := 0;
    v_active_count INT := 0;
    v_split_delivery NUMERIC;
    v_split_rider NUMERIC;
    v_split_surcharge NUMERIC;
    v_split_small NUMERIC;
    v_split_heavy NUMERIC;
    v_split_discount NUMERIC;
    rec RECORD;
    v_net_delivery NUMERIC;
    v_new_gst_delivery NUMERIC;
BEGIN
    -- Explicitly lock ALL orders for this cart_group_id ordered by id to prevent deadlocks
    PERFORM id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE;

    -- Only run if there's an active awaiting_payment order
    SELECT COUNT(*) INTO v_active_count
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status = 'awaiting_payment';

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Sum up delivery fees from cancelled orders that haven't been zeroed yet
    SELECT
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(rider_earnings), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0),
        COALESCE(SUM(delivery_discount), 0)
    INTO
        v_missing_delivery, v_missing_rider, v_missing_surcharge, v_missing_small, v_missing_heavy, v_missing_discount
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('cancelled', 'seller_rejected')
      AND delivery_charges > 0;

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    -- Split evenly among active orders
    v_split_delivery  := v_missing_delivery  / v_active_count;
    v_split_rider     := v_missing_rider     / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small     := v_missing_small     / v_active_count;
    v_split_heavy     := v_missing_heavy     / v_active_count;
    v_split_discount  := v_missing_discount  / v_active_count;

    -- Zero out delivery on cancelled/rejected orders
    FOR rec IN
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected')
          AND delivery_charges > 0
    LOOP
        UPDATE orders
        SET delivery_charges       = 0,
            rider_earnings         = 0,
            multi_shop_surcharge   = 0,
            small_cart_fee         = 0,
            heavy_order_fee        = 0,
            delivery_discount      = 0,
            gst_delivery           = 0,
            grand_total            = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform,
            grand_total_collected  = 0
        WHERE id = rec.id;
    END LOOP;

    -- Add absorbed fees to active orders
    FOR rec IN
        SELECT id, delivery_charges, rider_earnings, multi_shop_surcharge, small_cart_fee,
               heavy_order_fee, delivery_discount,
               total_amount, gst_item_total, platform_fee, gst_platform,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders
        WHERE cart_group_id = p_cart_group_id
          AND status = 'awaiting_payment'
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery)
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy)
                        - (rec.delivery_discount + v_split_discount);

        -- Extract 18% embedded GST: net - (net / 1.18)
        v_new_gst_delivery := v_net_delivery - (v_net_delivery / 1.18);

        UPDATE orders
        SET delivery_charges      = rec.delivery_charges + v_split_delivery,
            rider_earnings        = rec.rider_earnings + v_split_rider,
            multi_shop_surcharge  = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee        = rec.small_cart_fee + v_split_small,
            heavy_order_fee       = rec.heavy_order_fee + v_split_heavy,
            delivery_discount     = rec.delivery_discount + v_split_discount,
            gst_delivery          = v_new_gst_delivery,
            -- BUG-5 FIX: grand_total_collected must subtract coupon_discount.
            -- Previously missing → customer was overcharged on partial-cancel orders.
            grand_total           = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount,
            grand_total_collected  = rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;


-- =============================================================================
-- FIX 3 (BUG-9): admin_cancel_order — Missing refund trigger for terminal states
-- =============================================================================
-- admin_cancel_order raised an exception for 'seller_rejected'/'verification_failed'
-- orders. Those are valid admin targets for cancellation. More importantly, it
-- did not set refund_status='processing' when payment had been captured.
-- =============================================================================
CREATE OR REPLACE FUNCTION admin_cancel_order(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  -- Only block if already in a fully terminal state
  IF v_status IN ('cancelled', 'delivered') THEN
    RAISE EXCEPTION 'Order is already %', v_status;
  END IF;

  UPDATE orders
  SET
    status           = 'cancelled',
    cancelled_reason = 'admin',
    -- BUG-9 FIX: Always trigger refund path if payment was captured,
    -- even for seller_rejected / verification_failed terminal states.
    refund_status    = CASE
                         WHEN v_payment_status = 'captured' THEN 'processing'
                         ELSE refund_status
                       END
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_cancel_order(UUID) TO authenticated;


-- =============================================================================
-- FIX 4 (BUG-9b): admin_issue_refund — Also handle seller_rejected state
-- =============================================================================
-- admin_issue_refund previously only set refund_status on non-delivered orders,
-- but 'seller_rejected' was not explicitly protected, potentially allowing
-- a double-cancel + refund on an already-terminal order.
-- =============================================================================
CREATE OR REPLACE FUNCTION admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  -- For already-cancelled or terminal states, only update refund_status
  IF v_status IN ('cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute') THEN
    IF v_payment_status != 'captured' THEN
      RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
    END IF;
    UPDATE orders
    SET refund_status = 'processing'
    WHERE id = p_order_id;
  ELSE
    -- Active order — cancel and refund
    UPDATE orders
    SET
      status           = 'cancelled',
      refund_status    = 'processing',
      cancelled_reason = 'admin_refund'
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_issue_refund(UUID) TO authenticated;


-- =============================================================================
-- Safety: Ensure current_uses column exists in coupons table
-- (guard against schema drift where the column might be named differently)
-- =============================================================================
DO $$
BEGIN
  -- Add current_uses if it doesn't exist (some schemas used 'used_count')
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'coupons'
      AND column_name  = 'current_uses'
  ) THEN
    ALTER TABLE public.coupons ADD COLUMN current_uses INT NOT NULL DEFAULT 0;
    -- Sync from used_count if that column exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name   = 'coupons'
        AND column_name  = 'used_count'
    ) THEN
      UPDATE public.coupons SET current_uses = used_count;
    END IF;
  END IF;
END;
$$;
