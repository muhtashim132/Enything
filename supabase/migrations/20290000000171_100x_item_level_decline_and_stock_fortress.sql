-- =============================================================================
-- Migration: 20290000000164_100x_item_level_decline_and_stock_fortress.sql
-- =============================================================================
-- Description:
--   1. Adds item-level lifecycle status to `order_items` ('active', 'declined', 'cancelled')
--      with rejection reason, timestamp, and index for lightning-fast queries.
--   2. Introduces atomic `decline_order_items_seller` RPC:
--      - Validates seller authorization & permitted lifecycle stages.
--      - Marks specified item(s) as 'declined' in `order_items`.
--      - Instantly marks corresponding products in `products` table as out-of-stock
--        (`is_available = false`, respecting soft-deletes `is_deleted = false`).
--      - If ALL items are declined, automatically routes to full order rejection
--        (`seller_rejected`), freeing rider and reallocating delivery pool.
--      - If SOME items are declined, authoritatively recalculates active item total,
--        proportional GST (§9(5) and non-food), 0.5% TCS, 0.1% TDS, Enything commission,
--        seller payout, and grand total collected.
--      - Flags partial refund (`refund_status = 'processing'`) if payment was captured.
--      - Rebalances multi-shop cart group fees atomically via `rebalance_active_delivery_fees`.
-- =============================================================================

-- 1. Schema Additions to order_items and orders
ALTER TABLE public.order_items 
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS declined_reason TEXT,
  ADD COLUMN IF NOT EXISTS declined_at TIMESTAMPTZ;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS pending_refund_amount NUMERIC(10,2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS total_refunded NUMERIC(10,2) DEFAULT 0.00;

-- Add check constraint for valid order_items statuses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_order_items_status'
  ) THEN
    ALTER TABLE public.order_items
      ADD CONSTRAINT chk_order_items_status 
      CHECK (status IN ('active', 'declined', 'cancelled'));
  END IF;
END $$;

-- Index for instant lookup of active vs declined items per order
CREATE INDEX IF NOT EXISTS idx_order_items_order_status 
  ON public.order_items(order_id, status);

-- 2. Atomic Core RPC: decline_order_items_seller
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
  v_delivery_charges NUMERIC;
  v_platform_fee NUMERIC;
  v_multi_shop_surcharge NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_fee NUMERIC;
  v_coupon_discount NUMERIC;
  v_gst_platform NUMERIC;
  v_gst_delivery NUMERIC;
  
  v_total_items_in_order INT;
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
  IF p_order_id IS NULL OR p_order_item_ids IS NULL OR array_length(p_order_item_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Invalid parameters: order_id and order_item_ids required';
  END IF;

  -- 1. Deterministic cart group locking
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  -- 2. Lock target order & extract financials
  SELECT 
    status, shop_id, payment_status, refund_status,
    total_amount, grand_total_collected,
    s9_5_gst_amount, non_food_gst_amount,
    enything_commission, delivery_charges, platform_fee,
    multi_shop_surcharge, small_cart_fee, heavy_order_fee,
    coupon_discount, gst_platform, gst_delivery,
    COALESCE(pending_refund_amount, 0)
  INTO 
    v_status, v_shop_id, v_payment_status, v_refund_status,
    v_old_total_amount, v_old_grand_total,
    v_old_s9_5, v_old_non_food_gst,
    v_old_enything_commission, v_delivery_charges, v_platform_fee,
    v_multi_shop_surcharge, v_small_cart_fee, v_heavy_order_fee,
    v_coupon_discount, v_gst_platform, v_gst_delivery,
    v_pending_refund_amount
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 3. Authorization Check
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id IS NULL OR (v_seller_id IS DISTINCT FROM auth.uid() AND NOT is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner or admin can decline items';
  END IF;

  -- 4. Lifecycle Stage Guard
  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot have items declined at status "%"', v_status;
  END IF;

  -- 5. Lock and verify targeted order items
  PERFORM id FROM order_items WHERE order_id = p_order_id ORDER BY id FOR UPDATE;

  -- Check how many items currently active in order
  SELECT COUNT(*) INTO v_active_items_count
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- Check how many of the requested decline items are currently active
  SELECT COUNT(*), array_agg(DISTINCT product_id)
  INTO v_declined_target_count, v_declined_prod_ids
  FROM order_items
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  -- If none of the requested items were active (already declined or invalid)
  IF v_declined_target_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', false,
      'message', 'Items were already declined or not found',
      'active_items_count', v_active_items_count
    );
  END IF;

  -- 6. CASE A: ALL active items are being declined -> Fall back to full order rejection
  IF v_declined_target_count >= v_active_items_count THEN
    -- Update all targeted items as declined
    UPDATE order_items
    SET status = 'declined',
        declined_reason = p_reason,
        declined_at = NOW()
    WHERE order_id = p_order_id AND id = ANY(p_order_item_ids);

    -- Mark products out of stock in shop inventory
    IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
      UPDATE products
      SET is_available = false,
          total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
      WHERE id = ANY(v_declined_prod_ids)
        AND shop_id = v_shop_id
        AND is_deleted = false;
    END IF;

    -- Update order to seller_rejected
    UPDATE orders
    SET 
      status = CASE WHEN p_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
      seller_accepted = false,
      partner_accepted = false,
      delivery_partner_id = null,
      rejection_message = substring(p_message from 1 for 500),
      refund_status = CASE 
        WHEN v_payment_status = 'captured' AND COALESCE(v_refund_status, 'none') NOT IN ('processing', 'completed') 
        THEN 'processing' 
        ELSE v_refund_status 
      END,
      updated_at = NOW()
    WHERE id = p_order_id;

    -- Rebalance delivery pool
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_cart_group_id);
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', true,
      'order_status', 'seller_rejected',
      'active_items_count', 0
    );
  END IF;

  -- 7. CASE B: PARTIAL Item Decline (Some items declined, remaining items stay active)
  -- Update specified items
  UPDATE order_items
  SET status = 'declined',
      declined_reason = p_reason,
      declined_at = NOW()
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  -- Mark products out of stock in shop inventory
  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET is_available = false,
        total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
    WHERE id = ANY(v_declined_prod_ids)
      AND shop_id = v_shop_id
      AND is_deleted = false;
  END IF;

  -- Compute new active subtotal & weight
  SELECT 
    COUNT(*),
    COALESCE(SUM(price * quantity), 0),
    COALESCE(SUM(weight_kg * quantity), 0)
  INTO 
    v_active_items_count,
    v_new_active_subtotal,
    v_new_active_weight
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- Calculate proportional financial scaling
  IF COALESCE(v_old_total_amount, 0) > 0 THEN
    v_ratio := v_new_active_subtotal / v_old_total_amount;
  ELSE
    v_ratio := 1.0;
  END IF;

  v_new_s9_5 := ROUND((COALESCE(v_old_s9_5, 0) * v_ratio)::numeric, 2);
  v_new_non_food_gst := ROUND((COALESCE(v_old_non_food_gst, 0) * v_ratio)::numeric, 2);
  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;

  v_new_enything_commission := ROUND((COALESCE(v_old_enything_commission, 0) * v_ratio)::numeric, 2);
  v_new_tcs := ROUND((v_new_active_subtotal * 0.005)::numeric, 2);
  v_new_tds := ROUND((v_new_active_subtotal * 0.001)::numeric, 2);
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  -- Recalculate heavy order fee if active weight decreased
  IF COALESCE(v_heavy_order_fee, 0) > 0 THEN
    IF v_new_active_weight <= 10.0 THEN
      v_new_heavy_order_fee := 0.0;
    ELSE
      v_new_heavy_order_fee := LEAST(v_heavy_order_fee, ROUND((20.0 * CEIL(v_new_active_weight - 10.0))::numeric, 2));
    END IF;
  ELSE
    v_new_heavy_order_fee := 0.0;
  END IF;

  v_new_grand_total := v_new_active_subtotal 
    + COALESCE(v_delivery_charges, 0) 
    + COALESCE(v_multi_shop_surcharge, 0) 
    + COALESCE(v_platform_fee, 0) 
    + COALESCE(v_gst_platform, 0) 
    + COALESCE(v_gst_delivery, 0) 
    + v_new_gst_item_total 
    + COALESCE(v_small_cart_fee, 0) 
    + v_new_heavy_order_fee 
    - LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal);

  -- Determine refund status for captured prepaid orders
  v_new_refund_status := v_refund_status;
  IF v_payment_status = 'captured' AND v_old_grand_total > v_new_grand_total THEN
    v_refund_delta := v_old_grand_total - v_new_grand_total;
    v_pending_refund_amount := COALESCE(v_pending_refund_amount, 0) + v_refund_delta;
    IF COALESCE(v_refund_status, 'none') NOT IN ('completed') THEN
      v_new_refund_status := 'processing';
    END IF;
  END IF;

  -- Update order record
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
    heavy_order_fee = v_new_heavy_order_fee,
    coupon_discount = LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal),
    grand_total = v_new_grand_total,
    grand_total_collected = v_new_grand_total,
    pending_refund_amount = v_pending_refund_amount,
    refund_status = v_new_refund_status,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Rebalance multi-shop cart group if applicable
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'all_items_declined', false,
    'active_items_count', v_active_items_count,
    'new_total_amount', v_new_active_subtotal,
    'new_grand_total', v_new_grand_total,
    'refund_status', v_new_refund_status,
    'refund_amount', GREATEST(0, COALESCE(v_old_grand_total, 0) - v_new_grand_total)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated, service_role;

