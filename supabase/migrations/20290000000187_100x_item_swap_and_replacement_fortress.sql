-- ==============================================================================
-- 100x Forensic Migration: Item Swapped & Cross-Store Replacement Fortress
-- File: 20290000000187_100x_item_swap_and_replacement_fortress.sql
--
-- DIRECTIVES ENFORCED:
-- 1. 100% Prepaid Model (Zero COD Doorstep Collection)
-- 2. Soft-Delete Inviolability (is_deleted = false)
-- 3. 15.0 kg physical delivery ceiling & 3-order concurrent rider cap
-- 4. Idempotent refund calculations (GREATEST(0, (collected - grand) - total_refunded))
-- 5. Authoritative grand total recomputation in in-place swap (No double-deductions)
-- 6. Deferred refund states (pending_customer_decision) to block free merchandise exploit
-- 7. Unified transaction advisory locks (hashtext('cart_group_' || cart_group_id::text))
-- ==============================================================================

-- ── 1. Fortify customer_swap_order_item ───────────────────────────────────────
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
  v_group_total_weight_kg numeric;

  -- Statutory tax and commission variables
  v_shop_cat text;
  v_is_food boolean := false;
  v_gst_rate numeric := 0.0;
  v_comm_rate numeric := 5.0;
  v_comm_key text;
  v_comm_val numeric;

  v_new_s9_5 numeric := 0.0;
  v_new_non_food_gst numeric := 0.0;
  v_new_gst_item_total numeric := 0.0;
  v_new_enything_commission numeric := 0.0;
  v_new_tcs numeric := 0.0;
  v_new_tds numeric := 0.0;
  v_new_seller_payout numeric := 0.0;

  v_item_subtotal numeric;
  v_item_gst numeric;
  v_item_comm numeric;

  v_authoritative_grand_total numeric;
  v_pending_refund numeric := 0.0;
  oi_rec record;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  -- 1. Initial order lookup to fetch cart_group_id
  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Unified transaction-level advisory lock on cart group
  IF v_order.cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_order.cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_order.cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch order row post-lock
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;

  -- Strict customer authorization
  IF auth.uid() IS NULL OR (v_order.customer_id != auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_order.status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be modified at status %', v_order.status;
  END IF;

  -- Double-dip / Premature cash refund check:
  -- If cash refund was already processed to the customer bank, block in-place swap!
  IF v_order.payment_status = 'captured' AND (v_order.refund_status = 'processed' OR COALESCE(v_order.total_refunded, 0) > 0) THEN
    RAISE EXCEPTION 'ALREADY_REFUNDED: A cash refund has already been completed for this order. In-place item swap is disabled.';
  END IF;

  -- Verify declined item exists and belongs to this order
  SELECT * INTO v_declined_item FROM order_items WHERE id = p_declined_item_id AND order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Declined item not found';
  END IF;

  IF v_declined_item.status NOT IN ('declined', 'active') THEN
    RAISE EXCEPTION 'Item cannot be replaced in status %', v_declined_item.status;
  END IF;

  -- Verify replacement product belongs to the same shop, is available, and not soft-deleted
  SELECT * INTO v_prod FROM products 
  WHERE id = p_replacement_product_id 
    AND shop_id = v_order.shop_id 
    AND is_available = true 
    AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Replacement product is unavailable, deleted, or belongs to another shop';
  END IF;

  -- Stock check on replacement
  IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for replacement product';
  END IF;

  -- Inventory decrement on replacement product
  IF v_prod.total_quantity IS NOT NULL THEN
    UPDATE products 
    SET total_quantity = total_quantity - p_quantity,
        is_available = CASE WHEN total_quantity - p_quantity <= 0 THEN false ELSE is_available END
    WHERE id = p_replacement_product_id;
  END IF;

  -- Canonical Unit Weight Calculation (Comprehensive Indian Units)
  v_replacement_unit_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
  v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
  IF v_clean_unit != '' THEN
    IF v_clean_unit ~ '^\d+(\.\d+)?\s*(g|gm|gms|gram|grams)$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*(l|lt|ltr|ltrs|liter|liters|litre|litres)$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
    END IF;
  END IF;

  IF v_replacement_unit_weight_kg <= 0 THEN
    v_replacement_unit_weight_kg := 0.5;
  END IF;

  -- Price calculation
  v_replacement_price := v_prod.price;
  IF p_replacement_variant_name IS NOT NULL AND v_prod.variants IS NOT NULL THEN
    SELECT (elem->>'price')::numeric INTO v_variant_price
    FROM jsonb_array_elements(v_prod.variants) AS elem
    WHERE elem->>'name' = p_replacement_variant_name;
    IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
      v_replacement_price := v_variant_price;
    END IF;
  END IF;

  v_old_item_subtotal := v_declined_item.price * v_declined_item.quantity;
  v_new_item_subtotal := v_replacement_price * p_quantity;
  v_price_delta := v_new_item_subtotal - v_old_item_subtotal;

  -- If order is captured and replacement is more expensive, block direct swap (requires checkout for extra payment)
  IF v_order.payment_status = 'captured' AND v_price_delta > 0.01 THEN
    RAISE EXCEPTION 'REPLACEMENT_PRICE_EXCEEDS_ORIGINAL: Replacement item costs ₹% more than original item. Please select an item of equal or lower price.', v_price_delta;
  END IF;

  -- Insert new replacement order item
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

  -- 100x CROSS-SHOP 15.0 KG PAYLOAD CEILING GUARD
  IF v_order.cart_group_id IS NOT NULL THEN
    SELECT COALESCE(SUM(oi.quantity * COALESCE(oi.weight_kg, 0.5)), 0)
    INTO v_group_total_weight_kg
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.cart_group_id = v_order.cart_group_id
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
      AND oi.status = 'active';

    IF v_group_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Swapping this item brings delivery group weight to % kg, exceeding the 15.0 kg two-wheeler limit.', round(v_group_total_weight_kg::numeric, 2);
    END IF;
  ELSE
    SELECT COALESCE(SUM(quantity * COALESCE(weight_kg, 0.5)), 0)
    INTO v_order_total_weight_kg
    FROM order_items
    WHERE order_id = p_order_id AND status = 'active';

    IF v_order_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Swapping this item brings order weight to % kg, exceeding the 15.0 kg two-wheeler limit.', round(v_order_total_weight_kg::numeric, 2);
    END IF;
  END IF;

  -- Recalculate true active subtotal for this order
  SELECT COALESCE(SUM(price * quantity), 0)
  INTO v_new_active_subtotal
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- Statutory line-item tax and commission recomputation
  SELECT category INTO v_shop_cat FROM shops WHERE id = v_order.shop_id;

  FOR oi_rec IN
    SELECT oi.price, oi.quantity, p.is_food, p.gst_rate, p.category as prod_cat
    FROM order_items oi
    JOIN products p ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id AND oi.status = 'active'
  LOOP
    v_item_subtotal := oi_rec.price * oi_rec.quantity;
    v_is_food := COALESCE(oi_rec.is_food, (v_shop_cat = 'restaurant'));
    v_gst_rate := COALESCE(oi_rec.gst_rate, CASE WHEN v_is_food THEN 5.0 ELSE 18.0 END);

    IF v_is_food THEN
      v_item_gst := ROUND((v_item_subtotal * (v_gst_rate / 100.0))::numeric, 2);
      v_new_s9_5 := v_new_s9_5 + v_item_gst;
    ELSE
      v_item_gst := ROUND((v_item_subtotal - (v_item_subtotal / (1.0 + (v_gst_rate / 100.0))))::numeric, 2);
      v_new_non_food_gst := v_new_non_food_gst + v_item_gst;
    END IF;

    v_comm_key := 'commission_' || lower(COALESCE(oi_rec.prod_cat, 'grocery'));
    BEGIN
      SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
    EXCEPTION WHEN OTHERS THEN v_comm_val := NULL; END;
    IF v_comm_val IS NOT NULL THEN
      v_comm_rate := v_comm_val;
    ELSE
      v_comm_rate := 5.0;
    END IF;

    v_item_comm := ROUND((v_item_subtotal * (v_comm_rate / 100.0))::numeric, 2);
    v_new_enything_commission := v_new_enything_commission + v_item_comm;
    v_new_tcs := v_new_tcs + ROUND((v_item_subtotal * 0.005)::numeric, 2);
    v_new_tds := v_new_tds + ROUND((v_item_subtotal * 0.001)::numeric, 2);
  END LOOP;

  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  -- Authoritative Grand Total (No double-deduction!)
  v_authoritative_grand_total := GREATEST(0,
    v_new_active_subtotal
    + v_new_gst_item_total
    + COALESCE(v_order.platform_fee, 0)
    + COALESCE(v_order.delivery_charges, 0)
    + COALESCE(v_order.multi_shop_surcharge, 0)
    + COALESCE(v_order.small_cart_fee, 0)
    + COALESCE(v_order.heavy_order_fee, 0)
    - LEAST(COALESCE(v_order.coupon_discount, 0), v_new_active_subtotal)
  );

  IF v_order.payment_status = 'captured' THEN
    -- Strictly idempotent refund calculation:
    -- pending = max(0, (collected - authoritative_grand) - total_refunded)
    v_pending_refund := GREATEST(0.0, 
      (COALESCE(v_order.grand_total_collected, 0) - v_authoritative_grand_total) 
      - COALESCE(v_order.total_refunded, 0)
    );

    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      s9_5_gst_amount = v_new_s9_5,
      non_food_gst_amount = v_new_non_food_gst,
      gst_item_total = v_new_gst_item_total,
      enything_commission = v_new_enything_commission,
      tcs_amount = v_new_tcs,
      tds_amount = v_new_tds,
      seller_payout = v_new_seller_payout,
      grand_total = v_authoritative_grand_total,
      pending_refund_amount = v_pending_refund,
      refund_status = CASE 
        WHEN v_pending_refund <= 0.01 THEN 'none'
        WHEN COALESCE(refund_status, 'none') = 'none' THEN 'pending_customer_decision'
        ELSE refund_status
      END,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    -- PRE-PAYMENT: Synchronize grand_total and grand_total_collected exactly
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      s9_5_gst_amount = v_new_s9_5,
      non_food_gst_amount = v_new_non_food_gst,
      gst_item_total = v_new_gst_item_total,
      enything_commission = v_new_enything_commission,
      tcs_amount = v_new_tcs,
      tds_amount = v_new_tds,
      seller_payout = v_new_seller_payout,
      grand_total = v_authoritative_grand_total,
      grand_total_collected = v_authoritative_grand_total,
      pending_refund_amount = 0.0,
      refund_status = 'none',
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  -- Disarm 5-minute watchdog decision timer on cart group
  IF v_order.cart_group_id IS NOT NULL THEN
    PERFORM public.acknowledge_partial_rejection(v_order.cart_group_id, 'replaced');
    PERFORM public.rebalance_active_delivery_fees(v_order.cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_item_id', v_new_item_id,
    'price_delta', v_price_delta,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_authoritative_grand_total,
    'total_weight_kg', COALESCE(v_group_total_weight_kg, v_order_total_weight_kg)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO authenticated, service_role;


-- ── 2. Fortify decline_order_items_seller (Advisory Lock + Deferred Refund) ───
CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_order_item_ids UUID[],
  p_reason TEXT DEFAULT 'out_of_stock',
  p_message TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
  v_shop_id UUID;
  v_seller_id UUID;
  v_payment_status TEXT;
  v_refund_status TEXT;
  v_cart_group_id UUID;
  
  v_old_total_amount NUMERIC;
  v_old_grand_total NUMERIC;
  v_old_s9_5 NUMERIC;
  v_old_non_food_gst NUMERIC;
  v_old_enything_commission NUMERIC;
  v_old_tcs NUMERIC;
  v_old_tds NUMERIC;
  v_delivery_charges NUMERIC;
  v_platform_fee NUMERIC;
  v_multi_shop_surcharge NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_fee NUMERIC;
  v_coupon_discount NUMERIC;
  
  v_active_items_count INT;
  v_declined_target_count INT;
  v_pending_refund_amount NUMERIC := 0.0;
  v_new_heavy_order_fee NUMERIC := 0.0;
  v_refund_delta NUMERIC := 0.0;
  
  v_new_active_subtotal NUMERIC := 0.0;
  v_new_active_weight NUMERIC := 0.0;
  v_ratio NUMERIC := 1.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;
  v_new_grand_total NUMERIC := 0.0;
  v_new_refund_status TEXT;
  v_declined_prod_ids UUID[];
BEGIN
  IF p_order_item_ids IS NULL OR array_length(p_order_item_ids, 1) = 0 THEN
    RAISE EXCEPTION 'p_order_item_ids cannot be empty';
  END IF;

  SELECT 
    status, shop_id, payment_status, refund_status, cart_group_id,
    total_amount, grand_total, s9_5_gst_amount, non_food_gst_amount,
    enything_commission, tcs_amount, tds_amount,
    delivery_charges, platform_fee, multi_shop_surcharge, small_cart_fee,
    heavy_order_fee, coupon_discount, pending_refund_amount
  INTO 
    v_status, v_shop_id, v_payment_status, v_refund_status, v_cart_group_id,
    v_old_total_amount, v_old_grand_total, v_old_s9_5, v_old_non_food_gst,
    v_old_enything_commission, v_old_tcs, v_old_tds,
    v_delivery_charges, v_platform_fee, v_multi_shop_surcharge, v_small_cart_fee,
    v_heavy_order_fee, v_coupon_discount, v_pending_refund_amount
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Unified transaction advisory lock on cart group to eliminate deadlock with swap
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id IS NULL OR (v_seller_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner or admin can decline items';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot have items declined at status "%"', v_status;
  END IF;

  PERFORM id FROM order_items WHERE order_id = p_order_id ORDER BY id FOR UPDATE;

  SELECT COUNT(*) INTO v_active_items_count
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  SELECT COUNT(*), array_agg(DISTINCT product_id)
  INTO v_declined_target_count, v_declined_prod_ids
  FROM order_items
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  IF v_declined_target_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', false,
      'message', 'Items were already declined or not found',
      'active_items_count', v_active_items_count
    );
  END IF;

  -- CASE A: ALL active items declined -> Order becomes seller_rejected
  IF v_declined_target_count >= v_active_items_count THEN
    UPDATE order_items
    SET status = 'declined',
        declined_reason = p_reason,
        declined_at = NOW()
    WHERE order_id = p_order_id AND id = ANY(p_order_item_ids);

    IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
      UPDATE products
      SET is_available = false,
          total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
      WHERE id = ANY(v_declined_prod_ids)
        AND shop_id = v_shop_id
        AND is_deleted = false;
    END IF;

    UPDATE orders
    SET 
      status = CASE WHEN p_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
      seller_accepted = false,
      partner_accepted = false,
      delivery_partner_id = null,
      rejection_message = substring(p_message from 1 for 500),
      refund_status = CASE 
        WHEN v_payment_status = 'captured' AND COALESCE(v_refund_status, 'none') NOT IN ('completed', 'processed') 
        THEN 'processing' 
        ELSE v_refund_status 
      END,
      updated_at = NOW()
    WHERE id = p_order_id;

    IF v_cart_group_id IS NOT NULL THEN
      -- Extend acceptance deadline for surviving sibling shops to match customer decision timer
      UPDATE orders
      SET acceptance_deadline = GREATEST(acceptance_deadline, (now() AT TIME ZONE 'utc') + interval '5 minutes')
      WHERE cart_group_id = v_cart_group_id
        AND status IN ('awaiting_acceptance', 'pending');

      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_cart_group_id);

      -- Stranded sibling promotion
      IF EXISTS (
        SELECT 1 FROM orders
        WHERE cart_group_id = v_cart_group_id
          AND status IN ('awaiting_acceptance', 'pending')
          AND seller_accepted = true
          AND (partner_accepted = true OR delivery_partner_id IS NOT NULL)
      ) AND NOT EXISTS (
        SELECT 1 FROM orders
        WHERE cart_group_id = v_cart_group_id
          AND status NOT IN (
            'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
            'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
          )
          AND seller_accepted = false
      ) THEN
        UPDATE orders
        SET 
          status = 'awaiting_payment',
          payment_deadline = (now() AT TIME ZONE 'utc') + interval '10 minutes',
          updated_at = NOW()
        WHERE cart_group_id = v_cart_group_id
          AND status IN ('awaiting_acceptance', 'pending');
      END IF;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', true,
      'order_status', 'seller_rejected',
      'active_items_count', 0
    );
  END IF;

  -- CASE B: PARTIAL Item Decline
  UPDATE order_items
  SET status = 'declined',
      declined_reason = p_reason,
      declined_at = NOW()
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET is_available = false,
        total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
    WHERE id = ANY(v_declined_prod_ids)
      AND shop_id = v_shop_id
      AND is_deleted = false;
  END IF;

  -- Recalculate remaining active items
  SELECT 
    COUNT(*),
    COALESCE(SUM(price * quantity), 0),
    COALESCE(SUM(COALESCE(weight_kg, 0.5) * quantity), 0)
  INTO 
    v_active_items_count,
    v_new_active_subtotal,
    v_new_active_weight
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  IF COALESCE(v_old_total_amount, 0) > 0 THEN
    v_ratio := v_new_active_subtotal / v_old_total_amount;
  ELSE
    v_ratio := 1.0;
  END IF;

  v_new_s9_5 := ROUND((COALESCE(v_old_s9_5, 0) * v_ratio)::numeric, 2);
  v_new_non_food_gst := ROUND((COALESCE(v_old_non_food_gst, 0) * v_ratio)::numeric, 2);
  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;

  v_new_enything_commission := ROUND((COALESCE(v_old_enything_commission, 0) * v_ratio)::numeric, 2);
  v_new_tcs := ROUND((COALESCE(v_old_tcs, 0) * v_ratio)::numeric, 2);
  v_new_tds := ROUND((COALESCE(v_old_tds, 0) * v_ratio)::numeric, 2);
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  IF COALESCE(v_heavy_order_fee, 0) > 0 THEN
    IF v_new_active_weight <= 10.0 THEN
      v_new_heavy_order_fee := 0.0;
    ELSE
      v_new_heavy_order_fee := LEAST(v_heavy_order_fee, ROUND((20.0 * CEIL(v_new_active_weight - 10.0))::numeric, 2));
    END IF;
  ELSE
    v_new_heavy_order_fee := 0.0;
  END IF;

  IF v_cart_group_id IS NULL AND COALESCE(v_heavy_order_fee, 0) > v_new_heavy_order_fee THEN
    v_delivery_charges := GREATEST(0, v_delivery_charges - ((v_heavy_order_fee - v_new_heavy_order_fee) * (1.0 + 0.18)));
  END IF;

  v_new_grand_total := GREATEST(0, v_new_active_subtotal 
    + v_new_gst_item_total 
    + COALESCE(v_platform_fee, 0) 
    + COALESCE(v_delivery_charges, 0) 
    - LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal));

  -- 100x DEFERRED REFUND STATE MACHINE:
  -- When items are declined, transition to 'pending_customer_decision'
  -- rather than 'processing' so edge function doesn't refund bank before customer swaps!
  v_new_refund_status := v_refund_status;
  IF v_payment_status = 'captured' AND v_old_grand_total > v_new_grand_total THEN
    v_refund_delta := v_old_grand_total - v_new_grand_total;
    v_pending_refund_amount := COALESCE(v_pending_refund_amount, 0) + v_refund_delta;
    IF COALESCE(v_refund_status, 'none') NOT IN ('completed', 'processed') THEN
      v_new_refund_status := 'pending_customer_decision';
    END IF;
  END IF;

  UPDATE orders
  SET 
    total_amount = v_new_active_subtotal,
    s9_5_gst_amount = v_new_s9_5,
    non_food_gst_amount = v_new_non_food_gst,
    gst_item_total = v_new_gst_item_total,
    enything_commission = v_new_enything_commission,
    tcs_amount = v_new_tcs,
    tds_amount = v_new_tds,
    seller_payout = v_new_seller_payout,
    delivery_charges = v_delivery_charges,
    heavy_order_fee = v_new_heavy_order_fee,
    coupon_discount = LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal),
    grand_total = v_new_grand_total,
    grand_total_collected = CASE 
      WHEN v_payment_status = 'captured' THEN grand_total_collected
      ELSE v_new_grand_total 
    END,
    pending_refund_amount = v_pending_refund_amount,
    refund_status = v_new_refund_status,
    updated_at = NOW()
  WHERE id = p_order_id;

  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET acceptance_deadline = GREATEST(acceptance_deadline, (now() AT TIME ZONE 'utc') + interval '5 minutes')
    WHERE cart_group_id = v_cart_group_id
      AND status IN ('awaiting_acceptance', 'pending');

    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'all_items_declined', false,
    'declined_count', v_declined_target_count,
    'remaining_active_count', v_active_items_count,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_new_grand_total,
    'pending_refund_amount', v_pending_refund_amount
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated, service_role;


-- ── 3. Fortify rebalance_active_delivery_fees (Idempotent Refund + Co-Location Floor)
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_original_items_total NUMERIC;

  v_admin_delivery_base NUMERIC := 20.0;
  v_delivery_rate_per_km NUMERIC := 20.0;
  v_new_base_delivery NUMERIC := 20.0;

  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  v_new_coupon NUMERIC;
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  v_new_gw_deduct NUMERIC;

  v_platform_gst_rate NUMERIC;
  v_delivery_gst_rate NUMERIC;
  v_rider_commission_percent NUMERIC;
  v_admin_platform_fee NUMERIC;
  v_small_cart_threshold NUMERIC;
  v_small_cart_fee_val NUMERIC;
  v_heavy_order_threshold_kg NUMERIC;
  v_heavy_order_fee_val NUMERIC;
  v_gateway_gst_rate CONSTANT NUMERIC := 0.18;

  v_group_coupon_id UUID;
  v_coupon_type TEXT;
  v_coupon_val NUMERIC;
  v_coupon_cap NUMERIC;
  v_coupon_min NUMERIC;
  v_recalculated_total_discount NUMERIC := 0;

  rec RECORD;
  v_active_idx INT := 0;

  v_act_shop_ids uuid[] := '{}';
  v_act_shop_lats double precision[] := '{}';
  v_act_shop_lngs double precision[] := '{}';
  v_act_dist_to_c double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharges numeric[] := '{}';
  v_total_act_surcharge numeric := 0.0;

  v_shop_lat double precision;
  v_shop_lng double precision;
  v_seen_shop_ids uuid[] := '{}';
  v_shop_leg_idx INT := 0;
BEGIN
    IF p_cart_group_id IS NULL THEN
        RETURN;
    END IF;

    -- Unified transaction advisory lock on cart group
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));

    -- Row-level locking
    PERFORM id FROM public.orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    -- Count active orders and current active subtotal
    SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
      INTO v_active_count, v_active_items_total
      FROM public.orders
     WHERE cart_group_id = p_cart_group_id
       AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider');

    IF v_active_count = 0 THEN
        RETURN;
    END IF;

    -- 100x SMALL CART FEE RETROACTIVE IMMUNITY:
    -- Sum original subtotal across all orders (including merchant rejections)
    SELECT COALESCE(SUM(total_amount), 0)
      INTO v_original_items_total
      FROM public.orders
     WHERE cart_group_id = p_cart_group_id
       AND (
         status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
         OR COALESCE(cancelled_reason, '') IN ('seller_rejected', 'out_of_stock', 'merchant_cancelled')
         OR status IN ('seller_rejected', 'verification_failed')
       );

    -- Platform Configurations
    BEGIN
        SELECT (value#>>'{}')::numeric INTO v_admin_delivery_base FROM public.platform_config WHERE key = 'delivery_base_fee';
        IF v_admin_delivery_base IS NULL THEN v_admin_delivery_base := 20.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM public.platform_config WHERE key = 'delivery_rate_per_km';
        IF v_delivery_rate_per_km IS NULL THEN v_delivery_rate_per_km := 20.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM public.platform_config WHERE key = 'platform_fee';
        IF v_admin_platform_fee IS NULL THEN v_admin_platform_fee := 2.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM public.platform_config WHERE key = 'platform_gst_rate';
        IF v_platform_gst_rate IS NULL THEN v_platform_gst_rate := 0.18; END IF;
        SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM public.platform_config WHERE key = 'delivery_gst_rate';
        IF v_delivery_gst_rate IS NULL THEN v_delivery_gst_rate := 0.18; END IF;
        SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM public.platform_config WHERE key = 'rider_commission_percent';
        IF v_rider_commission_percent IS NULL THEN v_rider_commission_percent := 80.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM public.platform_config WHERE key = 'small_cart_threshold';
        IF v_small_cart_threshold IS NULL THEN v_small_cart_threshold := 99.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_small_cart_fee_val FROM public.platform_config WHERE key = 'small_cart_fee';
        IF v_small_cart_fee_val IS NULL THEN v_small_cart_fee_val := 15.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM public.platform_config WHERE key = 'heavy_order_threshold_kg';
        IF v_heavy_order_threshold_kg IS NULL THEN v_heavy_order_threshold_kg := 10.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee_val FROM public.platform_config WHERE key = 'heavy_order_fee';
        IF v_heavy_order_fee_val IS NULL THEN v_heavy_order_fee_val := 20.0; END IF;
    EXCEPTION WHEN OTHERS THEN
        v_admin_delivery_base := 20.0;
        v_delivery_rate_per_km := 20.0;
        v_admin_platform_fee := 2.0;
        v_platform_gst_rate := 0.18;
        v_delivery_gst_rate := 0.18;
        v_rider_commission_percent := 80.0;
        v_small_cart_threshold := 99.0;
        v_small_cart_fee_val := 15.0;
        v_heavy_order_threshold_kg := 10.0;
        v_heavy_order_fee_val := 20.0;
    END;

    -- Active items weight
    SELECT COALESCE(SUM(oi.quantity * COALESCE(oi.weight_kg, 0.5)), 0)
      INTO v_active_weight_total
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
     WHERE o.cart_group_id = p_cart_group_id
       AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
       AND oi.status = 'active';

    -- Retrieve active shops and locations, sorted by first order creation sequence
    FOR rec IN
        SELECT o.shop_id, s.location, AVG(COALESCE(o.estimated_distance_km::double precision, 1.0)) as dist_to_c, MIN(o.coupon_id) as coupon_id
        FROM public.orders o
        JOIN public.shops s ON o.shop_id = s.id
        WHERE o.cart_group_id = p_cart_group_id
          AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
        GROUP BY o.shop_id, s.location
        ORDER BY MIN(o.created_at) ASC
    LOOP
        IF v_group_coupon_id IS NULL AND rec.coupon_id IS NOT NULL THEN
            v_group_coupon_id := rec.coupon_id;
        END IF;

        v_shop_lat := NULL;
        v_shop_lng := NULL;
        IF rec.location IS NOT NULL THEN
            v_shop_lat := ST_Y(rec.location::geometry);
            v_shop_lng := ST_X(rec.location::geometry);
        END IF;

        IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
            v_act_shop_ids := array_append(v_act_shop_ids, rec.shop_id);
            v_act_shop_lats := array_append(v_act_shop_lats, v_shop_lat);
            v_act_shop_lngs := array_append(v_act_shop_lngs, v_shop_lng);
        END IF;

        v_act_dist_to_c := array_append(v_act_dist_to_c, COALESCE(rec.dist_to_c, 1.0));
    END LOOP;

    -- Inter-shop distance and leg surcharges
    IF array_length(v_act_shop_lats, 1) >= 2 THEN
        FOR i IN 1..(array_length(v_act_shop_lats, 1) - 1) LOOP
            IF (v_act_shop_lats[i] = v_act_shop_lats[i+1] AND v_act_shop_lngs[i] = v_act_shop_lngs[i+1]) THEN
                -- Same physical location
                v_leg_surcharges := array_append(v_leg_surcharges, 15.0);
                v_total_act_surcharge := v_total_act_surcharge + 15.0;
            ELSE
                v_inter_dist := 6371.0 * acos(
                    LEAST(1.0, GREATEST(-1.0,
                        cos(radians(v_act_shop_lats[i])) * cos(radians(v_act_shop_lats[i+1])) *
                        cos(radians(v_act_shop_lngs[i+1]) - radians(v_act_shop_lngs[i])) +
                        sin(radians(v_act_shop_lats[i])) * sin(radians(v_act_shop_lats[i+1]))
                    ))
                );
                IF v_inter_dist < 0.05 THEN
                    -- Co-located distinct shops within 50m: Floor surcharge ₹15.00
                    -- Guarantees rider earns ₹15 * 80% = ₹12.00 commission for the extra pickup
                    v_leg_surcharges := array_append(v_leg_surcharges, 15.0);
                    v_total_act_surcharge := v_total_act_surcharge + 15.0;
                ELSE
                    v_leg_surcharges := array_append(v_leg_surcharges, GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km);
                    v_total_act_surcharge := v_total_act_surcharge + (GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km);
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- Base delivery fee
    IF array_length(v_act_dist_to_c, 1) >= 1 THEN
        v_new_base_delivery := GREATEST(v_admin_delivery_base, GREATEST(1, CEIL(v_act_dist_to_c[1])) * v_delivery_rate_per_km);
    ELSE
        v_new_base_delivery := v_admin_delivery_base;
    END IF;

    -- Re-evaluate group coupon
    IF v_group_coupon_id IS NOT NULL THEN
        SELECT discount_type, discount_value, max_discount_amount, min_order_amount
          INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min
          FROM public.coupons
         WHERE id = v_group_coupon_id;

        IF FOUND THEN
            IF v_coupon_min IS NULL OR v_active_items_total >= v_coupon_min THEN
                IF v_coupon_type = 'percentage' THEN
                    v_recalculated_total_discount := v_active_items_total * (v_coupon_val / 100.0);
                    IF v_coupon_cap IS NOT NULL THEN
                        v_recalculated_total_discount := LEAST(v_recalculated_total_discount, v_coupon_cap);
                    END IF;
                ELSE
                    v_recalculated_total_discount := LEAST(v_coupon_val, v_active_items_total);
                END IF;
            ELSE
                v_recalculated_total_discount := 0;
            END IF;
        END IF;
    END IF;

    -- Apply recalculations to active orders
    v_active_idx := 0;
    FOR rec IN
        SELECT o.id, o.shop_id, o.total_amount, o.gst_item_total, o.enything_commission, o.tcs_amount, o.tds_amount, o.payment_status, o.grand_total_collected, o.refund_status, o.total_refunded
        FROM public.orders o
        WHERE o.cart_group_id = p_cart_group_id
          AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
        ORDER BY o.created_at ASC
    LOOP
        v_active_idx := v_active_idx + 1;

        IF v_active_idx = 1 THEN
            v_new_plat := v_admin_platform_fee;
            -- Small cart fee immunity: Only charge if original cart was also below threshold
            IF v_active_items_total < v_small_cart_threshold AND v_original_items_total < v_small_cart_threshold THEN
                v_new_small := v_small_cart_fee_val;
            ELSE
                v_new_small := 0.0;
            END IF;

            v_new_heavy := CASE WHEN v_active_weight_total > v_heavy_order_threshold_kg THEN (v_active_weight_total - v_heavy_order_threshold_kg) * v_heavy_order_fee_val ELSE 0.0 END;
            v_new_surcharge := 0.0;
            v_new_del := (v_new_base_delivery + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);
            v_seen_shop_ids := array_append(v_seen_shop_ids, rec.shop_id);
        ELSE
            v_new_plat := 0.0;
            v_new_small := 0.0;
            v_new_heavy := 0.0;
            
            -- Same-shop surcharge elimination:
            -- If this order's shop was already processed in a prior order in this group, surcharge = ₹0!
            IF rec.shop_id = ANY(v_seen_shop_ids) THEN
                v_new_surcharge := 0.0;
            ELSE
                v_seen_shop_ids := array_append(v_seen_shop_ids, rec.shop_id);
                v_shop_leg_idx := v_shop_leg_idx + 1;
                IF array_length(v_leg_surcharges, 1) >= v_shop_leg_idx THEN
                    v_new_surcharge := v_leg_surcharges[v_shop_leg_idx];
                ELSE
                    v_new_surcharge := 20.0;
                END IF;
            END IF;

            v_new_del := v_new_surcharge * (1.0 + v_delivery_gst_rate);
        END IF;

        IF v_active_items_total > 0 THEN
            v_new_coupon := ROUND((v_recalculated_total_discount * (rec.total_amount / v_active_items_total))::numeric, 2);
        ELSE
            v_new_coupon := 0.0;
        END IF;

        v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
        v_new_gst_del := v_new_del - (v_new_del / (1.0 + v_delivery_gst_rate));
        v_new_rider := GREATEST(0, (v_new_del - v_new_gst_del - v_new_small) * (v_rider_commission_percent / 100.0));

        v_new_grand := GREATEST(0, rec.total_amount + rec.gst_item_total + v_new_plat + v_new_del - v_new_coupon);
        v_new_gw_deduct := GREATEST(0, (v_new_grand * 0.02) * (1.0 + v_gateway_gst_rate));

        -- 100x STRICTLY IDEMPOTENT REFUND ACCUMULATION:
        -- pending_refund_amount = GREATEST(0.0, (grand_total_collected - new_grand) - total_refunded)
        UPDATE public.orders
        SET
            platform_fee = v_new_plat,
            delivery_charges = v_new_del,
            multi_shop_surcharge = v_new_surcharge,
            small_cart_fee = v_new_small,
            heavy_order_fee = v_new_heavy,
            coupon_discount = v_new_coupon,
            gst_platform = v_new_gst_plat,
            gst_delivery = v_new_gst_del,
            rider_earnings = v_new_rider,
            gateway_deduction = v_new_gw_deduct,
            grand_total = v_new_grand,
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN rec.grand_total_collected
                ELSE v_new_grand 
            END,
            pending_refund_amount = CASE 
                WHEN rec.payment_status = 'captured' AND COALESCE(rec.grand_total_collected, 0) > v_new_grand
                THEN GREATEST(0.0, (rec.grand_total_collected - v_new_grand) - COALESCE(rec.total_refunded, 0))
                ELSE 0.0 
            END,
            refund_status = CASE
                WHEN rec.payment_status = 'captured' AND COALESCE(rec.grand_total_collected, 0) > v_new_grand AND COALESCE(rec.refund_status, 'none') NOT IN ('completed', 'processed')
                THEN CASE 
                  WHEN rec.refund_status = 'pending_customer_decision' THEN 'pending_customer_decision'
                  ELSE 'processing'
                END
                WHEN rec.payment_status = 'pending' THEN 'none'
                ELSE refund_status
            END,
            updated_at = NOW()
        WHERE id = rec.id;
    END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(UUID) TO authenticated, service_role;


-- ── 4. Fortify acknowledge_partial_rejection & admin_proxy ────────────────────
CREATE OR REPLACE FUNCTION public.acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded',
  p_resolution TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_effective_action TEXT;
BEGIN
  IF p_cart_group_id IS NULL THEN
    RETURN;
  END IF;

  v_effective_action := COALESCE(p_resolution, p_action, 'proceeded');

  -- Lock orders in group to prevent race conditions
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));
  PERFORM id FROM public.orders 
  WHERE cart_group_id = p_cart_group_id 
  ORDER BY id FOR UPDATE;

  -- Prepend 'customer_' to whatever reason was there
  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || v_effective_action || CASE WHEN cancelled_reason IS NOT NULL AND cancelled_reason != '' THEN '_' || cancelled_reason ELSE '' END,
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';

  -- Disarm Flutter timers by transitioning declined items to cancelled
  UPDATE public.order_items
  SET status = 'cancelled', 
      declined_reason = COALESCE(declined_reason, '') || ':customer_' || v_effective_action
  WHERE order_id IN (SELECT id FROM public.orders WHERE cart_group_id = p_cart_group_id)
    AND status = 'declined';

  -- If customer proceeds, release any pending customer decision refunds to processing!
  IF v_effective_action = 'proceeded' THEN
    UPDATE public.orders
    SET refund_status = 'processing',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND payment_status = 'captured'
      AND refund_status = 'pending_customer_decision';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_partial_rejection(UUID, TEXT, TEXT) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.admin_proxy_acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded',
  p_resolution TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_affected_count INT;
  v_effective_action TEXT;
BEGIN
  IF v_admin_id IS NULL OR NOT public.is_active_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Unauthorized: Only platform administrators or dispatchers can invoke proxy rejection acknowledgement';
  END IF;

  IF p_cart_group_id IS NULL THEN
    RAISE EXCEPTION 'cart_group_id is required';
  END IF;

  v_effective_action := COALESCE(p_resolution, p_action, 'proceeded');

  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));
  PERFORM id FROM public.orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE;

  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || v_effective_action || '_by_admin',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';

  GET DIAGNOSTICS v_affected_count = ROW_COUNT;

  -- Disarm Flutter timers by transitioning declined items to cancelled
  UPDATE public.order_items
  SET status = 'cancelled', 
      declined_reason = COALESCE(declined_reason, '') || ':customer_' || v_effective_action || '_by_admin'
  WHERE order_id IN (SELECT id FROM public.orders WHERE cart_group_id = p_cart_group_id)
    AND status = 'declined';

  -- Release deferred refunds
  IF v_effective_action = 'proceeded' THEN
    UPDATE public.orders
    SET refund_status = 'processing',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND payment_status = 'captured'
      AND refund_status = 'pending_customer_decision';
  END IF;

  -- Disarm timer and extend active orders
  UPDATE public.orders
  SET 
    acceptance_deadline = NOW() + INTERVAL '3 minutes',
    payment_deadline = NOW() + INTERVAL '10 minutes',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'pending', 'awaiting_payment');

  RETURN jsonb_build_object(
    'success', true,
    'affected_orders_count', v_affected_count,
    'action', v_effective_action
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_acknowledge_partial_rejection(UUID, TEXT, TEXT) TO authenticated, service_role;


-- ── 5. Fortify place_orders_transaction (Replacement Platform Fee Harmony) ─────
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
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_inserted_ids uuid[] := '{}';
  v_order jsonb;
  v_item jsonb;
  v_prod record;
  v_order_id uuid;
  v_expected_total_amount numeric;
  v_client_total_amount numeric;
  v_expected_grand_total numeric;
  v_client_grand_total numeric;
  v_item_price numeric;
  v_variant_price numeric;
  v_expected_discount numeric := 0;
  v_num_orders int;
  v_order_seq int := 0;
  v_is_replacement boolean := false;
  v_acceptance_deadline timestamptz;

  v_platform_fee_config numeric := 2.0;
  v_platform_gst_rate numeric := 0.18;
  v_server_gst_platform numeric;
  v_delivery_gst_rate numeric := 0.18;
  v_server_gst_delivery numeric;
  v_rider_commission_percent numeric := 80.0;
  v_server_rider_earnings numeric;
  v_server_seller_payout numeric;
  v_server_enything_commission numeric;

  v_tcs_rate numeric := 0.005;
  v_tds_rate numeric := 0.001;
  v_tcs_amount numeric := 0.0;
  v_tds_amount numeric := 0.0;
  v_gw_deduct numeric := 0.0;
  v_seller_gw_share numeric := 0.0;
  v_item_weight_kg numeric;
  v_clean_unit text;
  v_order_total_weight_kg numeric;
  v_group_total_weight_kg numeric := 0.0;
  v_existing_group_weight numeric := 0.0;

  v_s9_5_gst numeric := 0.0;
  v_non_food_gst numeric := 0.0;
  v_pure_commission numeric := 0.0;
  v_item_subtotal numeric := 0.0;
  v_item_gst numeric := 0.0;
  v_item_commission numeric := 0.0;
  v_item_is_food boolean := false;
  v_item_gst_rate numeric := 0.0;
  v_item_comm_rate numeric := 5.0;

  v_shop_cat text;
  v_comm_key text;
  v_comm_val numeric;

  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;
  v_secure_order jsonb;
  v_active_cart_groups_count int;
  v_rider_cap int := 3;

  v_shop_lat double precision;
  v_shop_lng double precision;
BEGIN
  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place orders';
  END IF;

  IF p_cart_group_id IS NULL THEN
    RAISE EXCEPTION 'cart_group_id is strictly required';
  END IF;

  -- 100x BOLA IDOR SECURITY GUARD: Verify cancellation target belongs to caller
  IF p_order_id_to_cancel IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM orders 
      WHERE id = p_order_id_to_cancel 
        AND customer_id = v_customer_id 
        AND cart_group_id = p_cart_group_id
    ) THEN
      RAISE EXCEPTION 'Unauthorized: Cancellation target order does not belong to your cart group';
    END IF;
  END IF;

  -- 100x UNIFIED TRANSACTION ADVISORY LOCK
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));

  -- 1. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT array_agg(id) INTO v_inserted_ids
    FROM orders
    WHERE idempotency_key = p_idempotency_key;
    IF v_inserted_ids IS NOT NULL AND array_length(v_inserted_ids, 1) > 0 THEN
      RETURN jsonb_build_object(
        'success', true,
        'order_ids', to_jsonb(v_inserted_ids),
        'cart_group_id', p_cart_group_id,
        'message', 'Idempotent request; existing order returned.'
      );
    END IF;
  END IF;

  -- 2. Detect Replacement Mode
  IF p_order_id_to_cancel IS NOT NULL THEN
    v_is_replacement := true;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM orders 
      WHERE cart_group_id = p_cart_group_id 
        AND status IN ('seller_rejected', 'partner_rejected', 'cancelled', 'timeout', 'verification_failed')
    ) INTO v_is_replacement;
  END IF;

  -- 3. Calculate Existing Group Weight
  IF v_is_replacement THEN
    SELECT COALESCE(SUM(oi.quantity * COALESCE(oi.weight_kg, 0.5)), 0)
    INTO v_existing_group_weight
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.cart_group_id = p_cart_group_id
      AND o.id != COALESCE(p_order_id_to_cancel, '00000000-0000-0000-0000-000000000000'::uuid)
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed')
      AND oi.status = 'active';
  END IF;
  v_group_total_weight_kg := v_existing_group_weight;

  -- 4. Single-Rider Affinity Resolution with Capacity Check
  IF v_is_replacement THEN
    SELECT delivery_partner_id, rider_phone, partner_accepted
    INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
    LIMIT 1;

    IF v_existing_rider_id IS NOT NULL THEN
      SELECT (value#>>'{}')::int INTO v_rider_cap FROM platform_config WHERE key = 'rider_max_active_orders';
      IF v_rider_cap IS NULL THEN v_rider_cap := 3; END IF;

      SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
      FROM orders
      WHERE delivery_partner_id = v_existing_rider_id
        AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
        AND COALESCE(cart_group_id, id) != p_cart_group_id;

      IF v_active_cart_groups_count >= v_rider_cap THEN
        v_existing_rider_id := NULL;
        v_existing_rider_phone := NULL;
        v_existing_partner_accepted := false;
      END IF;
    END IF;
  END IF;

  -- 5. Platform Configuration
  BEGIN
    SELECT (value#>>'{}')::numeric INTO v_platform_fee_config FROM platform_config WHERE key = 'platform_fee';
    IF v_platform_fee_config IS NULL THEN v_platform_fee_config := 2.0; END IF;
    SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent';
    IF v_rider_commission_percent IS NULL THEN v_rider_commission_percent := 80.0; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_platform_fee_config := 2.0;
    v_rider_commission_percent := 80.0;
  END;

  v_num_orders := jsonb_array_length(p_orders);
  IF v_num_orders = 0 THEN
    RAISE EXCEPTION 'p_orders array cannot be empty';
  END IF;

  v_acceptance_deadline := (now() AT TIME ZONE 'utc') + interval '3 minutes';

  -- 6. Process Orders
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders)
  LOOP
    v_order_seq := v_order_seq + 1;
    v_order_id := gen_random_uuid();
    v_client_total_amount := (v_order->>'total_amount')::numeric;
    v_client_grand_total := (v_order->>'grand_total')::numeric;

    v_expected_total_amount := 0;
    v_order_total_weight_kg := 0.0;
    v_s9_5_gst := 0.0;
    v_non_food_gst := 0.0;
    v_pure_commission := 0.0;
    v_tcs_amount := 0.0;
    v_tds_amount := 0.0;

    SELECT category INTO v_shop_cat FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    -- Validate Items for this order
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      IF (v_item->>'shop_id')::uuid = (v_order->>'shop_id')::uuid THEN
        SELECT * INTO v_prod FROM products 
        WHERE id = (v_item->>'product_id')::uuid 
          AND is_available = true 
          AND is_deleted = false
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Product % is unavailable or deleted', (v_item->>'product_id');
        END IF;

        IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < (v_item->>'quantity')::int THEN
          RAISE EXCEPTION 'Insufficient stock for product % (Available: %, Requested: %)', 
            v_prod.name, v_prod.total_quantity, (v_item->>'quantity')::int;
        END IF;

        -- Unit Weight Calculation
        v_item_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
        v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
        IF v_clean_unit != '' THEN
          IF v_clean_unit ~ '^\d+(\.\d+)?\s*(g|gm|gms|gram|grams)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*(l|lt|ltr|ltrs|liter|liters|litre|litres)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          END IF;
        END IF;

        IF v_item_weight_kg <= 0 THEN v_item_weight_kg := 0.5; END IF;

        v_order_total_weight_kg := v_order_total_weight_kg + (v_item_weight_kg * (v_item->>'quantity')::int);

        -- Price verification
        v_item_price := v_prod.price;
        IF (v_item->>'variant_name') IS NOT NULL AND v_prod.variants IS NOT NULL THEN
          SELECT (elem->>'price')::numeric INTO v_variant_price
          FROM jsonb_array_elements(v_prod.variants) AS elem
          WHERE elem->>'name' = (v_item->>'variant_name');
          IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
            v_item_price := v_variant_price;
          END IF;
        END IF;

        v_item_subtotal := v_item_price * (v_item->>'quantity')::int;
        v_expected_total_amount := v_expected_total_amount + v_item_subtotal;

        -- Tax and commission calculations
        v_item_is_food := COALESCE(v_prod.is_food, (v_shop_cat = 'restaurant'));
        v_item_gst_rate := COALESCE(v_prod.gst_rate, CASE WHEN v_item_is_food THEN 5.0 ELSE 18.0 END);

        IF v_item_is_food THEN
          v_item_gst := ROUND((v_item_subtotal * (v_item_gst_rate / 100.0))::numeric, 2);
          v_s9_5_gst := v_s9_5_gst + v_item_gst;
        ELSE
          v_item_gst := ROUND((v_item_subtotal - (v_item_subtotal / (1.0 + (v_item_gst_rate / 100.0))))::numeric, 2);
          v_non_food_gst := v_non_food_gst + v_item_gst;
        END IF;

        v_comm_key := 'commission_' || lower(COALESCE(v_prod.category, 'grocery'));
        BEGIN
          SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
        EXCEPTION WHEN OTHERS THEN v_comm_val := NULL; END;
        IF v_comm_val IS NOT NULL THEN
          v_item_comm_rate := v_comm_val;
        ELSE
          v_item_comm_rate := 5.0;
        END IF;

        v_item_commission := ROUND((v_item_subtotal * (v_item_comm_rate / 100.0))::numeric, 2);
        v_pure_commission := v_pure_commission + v_item_commission;
        v_tcs_amount := v_tcs_amount + ROUND((v_item_subtotal * v_tcs_rate)::numeric, 2);
        v_tds_amount := v_tds_amount + ROUND((v_item_subtotal * v_tds_rate)::numeric, 2);

        -- Insert order item
        INSERT INTO order_items (
          id, order_id, product_id, product_name, variant_name,
          quantity, price, unit_price, total_price, status, weight_kg, created_at
        ) VALUES (
          gen_random_uuid(), v_order_id, (v_item->>'product_id')::uuid,
          v_prod.name, (v_item->>'variant_name'),
          (v_item->>'quantity')::int, v_item_price, v_item_price,
          v_item_subtotal, 'active', v_item_weight_kg, NOW()
        );

        IF v_prod.total_quantity IS NOT NULL THEN
          UPDATE products 
          SET total_quantity = total_quantity - (v_item->>'quantity')::int
          WHERE id = v_prod.id;
        END IF;
      END IF;
    END LOOP;

    -- Weight ceiling verification
    v_group_total_weight_kg := v_group_total_weight_kg + v_order_total_weight_kg;
    IF v_group_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Total delivery weight % kg exceeds the 15.0 kg two-wheeler limit.', 
        round(v_group_total_weight_kg::numeric, 2);
    END IF;

    -- Subtotal validation
    IF ABS(v_expected_total_amount - v_client_total_amount) > 0.05 THEN
      RAISE EXCEPTION 'Total amount mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_total_amount, v_client_total_amount;
    END IF;

    -- Grand total calculation (allowing optional client platform fee in replacement mode)
    IF v_is_replacement THEN
      v_expected_grand_total := v_expected_total_amount 
        + v_s9_5_gst 
        + COALESCE((v_order->>'delivery_charges')::numeric, 0)
        + COALESCE((v_order->>'platform_fee')::numeric, 0)
        + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
        - COALESCE((v_order->>'coupon_discount')::numeric, 0);
    ELSE
      v_expected_grand_total := v_expected_total_amount 
        + v_s9_5_gst 
        + COALESCE((v_order->>'delivery_charges')::numeric, 0)
        + COALESCE((v_order->>'platform_fee')::numeric, 0)
        + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
        + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
        + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)
        - COALESCE((v_order->>'coupon_discount')::numeric, 0);
    END IF;

    IF ABS(v_expected_grand_total - v_client_grand_total) > 0.05 THEN
      RAISE EXCEPTION 'Grand total mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_grand_total, v_client_grand_total;
    END IF;

    -- Statutory Deductions & Payouts
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_pure_commission - v_tcs_amount - v_tds_amount;
    v_gw_deduct := (v_expected_grand_total * 0.02) * (1.0 + 0.18);

    -- Prepare sanitized order payload
    v_secure_order := v_order || jsonb_build_object(
      'id', v_order_id,
      'customer_id', v_customer_id,
      'cart_group_id', p_cart_group_id,
      'status', 'awaiting_acceptance',
      'payment_status', 'pending',
      'total_amount', v_expected_total_amount,
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'enything_commission', v_pure_commission,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'seller_payout', v_server_seller_payout,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'rider_earnings', v_server_rider_earnings,
      'gateway_deduction', v_gw_deduct,
      'acceptance_deadline', v_acceptance_deadline,
      'created_at', NOW(),
      'updated_at', NOW()
    );

    IF v_existing_rider_id IS NOT NULL THEN
      v_secure_order := v_secure_order || jsonb_build_object(
        'delivery_partner_id', v_existing_rider_id,
        'rider_phone', v_existing_rider_phone,
        'partner_accepted', v_existing_partner_accepted
      );
    END IF;

    -- Dynamically resolve missing shop coordinates
    IF (v_secure_order->>'shop_lat' IS NULL OR (v_secure_order->>'shop_lat')::numeric = 0.0) THEN
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_shop_lat, v_shop_lng
      FROM shops WHERE id = (v_order->>'shop_id')::uuid;

      IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
        v_secure_order := v_secure_order || jsonb_build_object(
          'shop_lat', v_shop_lat,
          'shop_lng', v_shop_lng
        );
      END IF;
    END IF;

    -- Insert Order
    INSERT INTO orders SELECT * FROM jsonb_populate_record(null::orders, v_secure_order);
    v_inserted_ids := array_append(v_inserted_ids, v_order_id);
  END LOOP;

  -- 7. Cancel Previous Order if Replacement
  IF p_order_id_to_cancel IS NOT NULL THEN
    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'customer_replaced',
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel
      AND customer_id = v_customer_id;
  END IF;

  -- 8. Disarm Rejection Timers and Rebalance Delivery Fees
  IF v_is_replacement THEN
    PERFORM public.acknowledge_partial_rejection(p_cart_group_id, 'replaced');
    PERFORM public.rebalance_active_delivery_fees(p_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_inserted_ids),
    'cart_group_id', p_cart_group_id,
    'total_weight_kg', v_group_total_weight_kg,
    'is_replacement', v_is_replacement,
    'assigned_rider_id', v_existing_rider_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO authenticated, service_role;

