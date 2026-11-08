-- =============================================================================
-- Migration 20290000000181: 100x Order Lifecycle Master Fortress
-- =============================================================================
-- Comprehensive hardening covering:
--   1. orders_status_check & validate_order_status_transition:
--      - Adds 'payment_failed', 'rider_rejected', and 'shop_dispute' to permitted check constraint.
--      - Allows riders to drop orders in 'confirmed', 'preparing', 'ready_for_pickup'
--        without violating transition triggers.
--   2. reject_order_rider:
--      - Preserves preparation state for kitchen ('confirmed'/'preparing'/'ready_for_pickup')
--        while unassigning rider (delivery_partner_id = NULL, partner_accepted = false).
--      - Emits pg_notify('rider_dropped_order') for realtime dispatcher & seller synchronization.
--   3. accept_order_seller & reject_order_seller:
--      - Enforces atomic cart group synchronization: orders only transition to
--        'awaiting_payment' once ALL active sibling shops and the assigned rider accept.
--      - Promotes surviving sibling orders to 'awaiting_payment' if all remaining active
--        shops are accepted and a rider is assigned when a sibling shop rejects or declines.
--   4. accept_order_rider:
--      - Prevents crashing on terminal/dead sibling sub-orders in cart groups.
--      - Unifies advisory locking across Dispatch Hub and Rider App.
--   5. place_orders_transaction:
--      - Step 0 strict authentication & authorization guard.
--      - Whitelists online prepaid payment methods (zero COD).
--      - Enforces uncompromised initial status ('awaiting_acceptance', 'pending').
--      - Verifies shop is_active, is_accepting_orders, and is_open.
--      - Prevents orphan item injection (all items must match a declared order).
--      - Prevents inventory cursor deadlocks via deterministic ORDER BY product_id.
--      - Verifies product is_available under FOR UPDATE lock.
--   6. decline_order_items_seller:
--      - Aligns grand total formula with checkout, preventing double-surcharges.
--      - Auto-deducts heavy delivery fee on single-shop orders when heavy items are dropped.
--      - Preserves Section 9(5) statutory tax exemptions by prorating TCS/TDS.
--      - Promotes surviving sibling orders when all items in a store are declined.
--   7. customer_swap_order_item:
--      - Atomic in-order same-shop item replacement with inventory reservation.
--      - Fixes double-refund inversion bug (deducts replacement price from pending_refund_amount).
--      - Recomputes exact active subtotal and validates item declined status.
--   8. rebalance_active_delivery_fees:
--      - Restricts weight calculations strictly to active order items (AND oi.status = 'active').
--   9. check_rider_has_stacked_orders:
--      - SECURITY DEFINER function enabling customer live map to detect multi-order riders
--        without leaking customer data across RLS boundaries.
-- =============================================================================

-- ── 1. Fortify orders_status_check constraint ─────────────────────────────────
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status = ANY (ARRAY[
    'awaiting_acceptance'::text,
    'awaiting_payment'::text,
    'pending'::text,
    'confirmed'::text,
    'preparing'::text,
    'ready_for_pickup'::text,
    'picked_up'::text,
    'out_for_delivery'::text,
    'delivered'::text,
    'cancelled'::text,
    'seller_rejected'::text,
    'partner_rejected'::text,
    'rider_rejected'::text,
    'verification_failed'::text,
    'bulk_pending'::text,
    'bulk_confirmed'::text,
    'bulk_preparing'::text,
    'bulk_ready'::text,
    'bulk_dispatched'::text,
    'modification_proposed'::text,
    'shop_dispute'::text,
    'shop_dispute_cancel'::text,
    'timeout'::text,
    'failed'::text,
    'returned'::text,
    'refunded'::text,
    'payment_failed'::text,
    'no_rider'::text
  ]));

-- ── 2. Fortify validate_order_status_transition ──────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Only validate if status is actually changing
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    CASE OLD.status
        WHEN 'awaiting_payment' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'cancelled', 'pending', 'confirmed', 'payment_failed', 'verification_failed', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'awaiting_acceptance' THEN
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'pending' THEN
            IF NEW.status NOT IN ('confirmed', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'awaiting_acceptance', 'awaiting_payment') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'confirmed' THEN
            -- Whitelist awaiting_acceptance for rider drop when unassigned
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'preparing' THEN
            -- Whitelist awaiting_acceptance for rider drop when unassigned
            IF NEW.status NOT IN ('ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'ready_for_pickup' THEN
            IF NEW.status NOT IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'awaiting_acceptance') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'shop_dispute' THEN
            IF NEW.status NOT IN ('cancelled', 'delivered', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_pending' THEN
            IF NEW.status NOT IN ('bulk_confirmed', 'bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_confirmed' THEN
            IF NEW.status NOT IN ('bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_preparing' THEN
            IF NEW.status NOT IN ('bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_ready' THEN
            IF NEW.status NOT IN ('bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_dispatched' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'returned') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'modification_proposed' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        -- Terminal states: strictly immutable
        WHEN 'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded', 'payment_failed', 'no_rider' THEN
            RAISE EXCEPTION 'Cannot change status from terminal state % to %', OLD.status, NEW.status;

        ELSE
            RETURN NEW;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── 3. Fortify reject_order_rider ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_order_rider(
  p_order_id UUID, 
  p_reason TEXT, 
  p_disputed BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_delivery_partner_id uuid;
  v_shop_id uuid;
  v_status text;
  v_cart_group_id uuid;
BEGIN
  -- First, fetch the cart_group_id without locking to determine lock scope
  SELECT delivery_partner_id, shop_id, status, cart_group_id 
  INTO v_delivery_partner_id, v_shop_id, v_status, v_cart_group_id
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Transaction-level Cart Group Advisory Lock
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch critical fields post-lock
  SELECT delivery_partner_id, status 
  INTO v_delivery_partner_id, v_status
  FROM orders 
  WHERE id = p_order_id;

  IF v_delivery_partner_id IS NULL OR (v_delivery_partner_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: You are not assigned to this order.';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment') THEN
    RAISE EXCEPTION 'CRITICAL: Cannot drop an order after it has been picked up or delivered (Status: %). Contact platform support.', v_status;
  END IF;

  -- Atomic Cart Group Drop: Preserve preparation status for kitchen, unassign rider cleanly
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE 'awaiting_acceptance'
      END,
      partner_accepted = false,
      delivery_partner_id = null,
      arrived_at_shop_time = null,
      wait_time_penalty = 0,
      wait_time_disputed = COALESCE(p_disputed, false),
      acceptance_deadline = now() + interval '3 minutes'
    WHERE cart_group_id = v_cart_group_id 
      AND delivery_partner_id = v_delivery_partner_id;
  ELSE
    UPDATE orders
    SET 
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE 'awaiting_acceptance'
      END,
      partner_accepted = false,
      delivery_partner_id = null,
      arrived_at_shop_time = null,
      wait_time_penalty = 0,
      wait_time_disputed = COALESCE(p_disputed, false),
      acceptance_deadline = now() + interval '3 minutes'
    WHERE id = p_order_id;
  END IF;

  -- Notify platform and seller channels of rider drop
  BEGIN
    PERFORM pg_notify('rider_dropped_order', json_build_object(
      'order_id', p_order_id,
      'cart_group_id', v_cart_group_id,
      'rider_id', auth.uid()
    )::text);
  EXCEPTION WHEN OTHERS THEN
  END;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_order_rider(UUID, TEXT, BOOLEAN) TO authenticated;

-- ── 4. Fortify accept_order_seller (Atomic Sibling Cart Synchronization) ───────
CREATE OR REPLACE FUNCTION public.accept_order_seller(p_order_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_partner_accepted boolean;
  v_delivery_partner_id uuid;
  v_cart_group_id uuid;
  v_all_siblings_accepted boolean := true;
BEGIN
  -- Fetch cart_group_id first
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;

  -- Acquire transaction lock
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  -- Verify order exists and lock row
  SELECT status, shop_id, partner_accepted, delivery_partner_id, cart_group_id
  INTO v_status, v_shop_id, v_partner_accepted, v_delivery_partner_id, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Authorization check
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner can accept this order';
  END IF;

  -- Shop active verification
  IF EXISTS (
    SELECT 1 FROM shops 
    WHERE id = v_shop_id 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'SHOP_SUSPENDED: This shop is suspended or unverified and cannot accept orders.';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status != 'awaiting_acceptance' AND v_status != 'pending' THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Mark this specific order as seller_accepted = true
  UPDATE orders
  SET seller_accepted = true, updated_at = NOW()
  WHERE id = p_order_id;

  -- In a multi-shop cart group, inspect all sibling active orders
  IF v_cart_group_id IS NOT NULL THEN
    -- Check if any sibling active shop has NOT accepted yet
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = v_cart_group_id
        AND id != p_order_id
        AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
          'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
        )
        AND seller_accepted = false
    ) INTO v_all_siblings_accepted;
    
    -- If any active sibling is unaccepted, v_all_siblings_accepted becomes false
    v_all_siblings_accepted := NOT v_all_siblings_accepted;

    -- If a rider is assigned AND ALL active shops have accepted:
    IF (v_partner_accepted = true OR v_delivery_partner_id IS NOT NULL) AND v_all_siblings_accepted THEN
      UPDATE orders
      SET 
        status = 'awaiting_payment',
        payment_deadline = (now() AT TIME ZONE 'utc') + interval '10 minutes',
        updated_at = NOW()
      WHERE cart_group_id = v_cart_group_id
        AND status IN ('awaiting_acceptance', 'pending');
      RETURN true;
    END IF;
  ELSE
    -- Single-shop order: advance if rider has accepted
    IF v_partner_accepted = true OR v_delivery_partner_id IS NOT NULL THEN
      UPDATE orders
      SET 
        status = 'awaiting_payment',
        payment_deadline = (now() AT TIME ZONE 'utc') + interval '10 minutes',
        updated_at = NOW()
      WHERE id = p_order_id;
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_seller(UUID) TO authenticated;

-- ── 5. Fortify reject_order_seller (Surviving Sibling Promotion) ───────────────
CREATE OR REPLACE FUNCTION public.reject_order_seller(
  p_order_id uuid,
  p_reject_reason text,
  p_message text DEFAULT NULL::text,
  p_out_of_stock_product_id uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Fetch cart_group_id first without locking to prevent out-of-order lock deadlocks
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  -- Lock all orders in the group deterministically by ID if it's a multi-shop order
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  -- Lock target order
  SELECT status, shop_id, payment_status INTO v_status, v_shop_id, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  
  -- Tenant isolation & authorization check
  IF v_seller_id IS NULL OR (v_seller_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  -- Precise Out of Stock item resolution
  IF p_reject_reason = 'out_of_stock' THEN
    IF p_out_of_stock_product_id IS NOT NULL THEN
      UPDATE products
      SET is_available = false
      WHERE id = p_out_of_stock_product_id
        AND shop_id = v_shop_id;
    ELSIF (SELECT COUNT(DISTINCT product_id) FROM order_items WHERE order_id = p_order_id) = 1 THEN
      PERFORM id FROM products 
      WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        AND shop_id = v_shop_id
      ORDER BY id FOR UPDATE;
      
      UPDATE products
      SET is_available = false
      WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        AND shop_id = v_shop_id;
    END IF;
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = substring(p_message from 1 for 500),
    refund_status = CASE 
      WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
      ELSE refund_status 
    END,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Reallocate delivery fees & rebalance active orders atomically
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);

    -- 100x STRANDED SIBLING PROMOTION:
    -- If all surviving active siblings are accepted and have a rider, advance them to awaiting_payment!
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
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_order_seller(UUID, text, text, UUID) TO authenticated;

-- ── 6. Fortify accept_order_rider (Advisory Lock Ordering & Multi-Shop Parity) ──
CREATE OR REPLACE FUNCTION public.accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_status text;
  v_payment_deadline timestamptz;
  v_order_ready_time timestamptz;
  v_new_status text;
  v_rows_affected INT;
  v_active_cart_groups_count INT;
  v_cart_group_id UUID;
  v_all_shops_accepted boolean := true;
BEGIN
  IF length(p_rider_phone) > 20 THEN
    RAISE EXCEPTION 'Rider phone string too long (Max 20 chars)';
  END IF;

  -- Delivery partner active check
  IF EXISTS (
    SELECT 1 FROM delivery_partners 
    WHERE id = auth.uid() 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'RIDER_SUSPENDED: Your delivery partner account is currently suspended or unverified.';
  END IF;

  -- 1. Acquire transaction advisory locks BEFORE row locks to eliminate deadlocks
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  -- Capacity ceiling check (max 3 distinct customer deliveries)
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
      'returned', 'refunded', 'failed', 'payment_failed', 'timeout', 
      'verification_failed', 'no_rider', 'shop_dispute_cancel'
    )
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- Verify whether all shops in cart group have accepted
  IF v_cart_group_id IS NOT NULL THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = v_cart_group_id
        AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
          'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
        )
        AND seller_accepted = false
    ) INTO v_all_shops_accepted;
  ELSE
    v_all_shops_accepted := v_seller_accepted;
  END IF;

  -- Determine target status
  IF v_payment_status = 'captured' THEN
    IF v_order_ready_time IS NOT NULL THEN
      v_new_status := 'ready_for_pickup';
    ELSE
      v_new_status := 'preparing';
    END IF;
  ELSIF v_all_shops_accepted = true THEN
    v_new_status := 'awaiting_payment';
  ELSE
    v_new_status := v_status;
  END IF;

  -- Update target orders atomically, strictly excluding terminal/dead sub-orders
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE v_new_status 
      END,
      payment_deadline = CASE 
        WHEN v_all_shops_accepted = true AND v_payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE payment_deadline 
      END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = COALESCE(p_shop_lat, shop_lat),
      shop_lng = COALESCE(p_shop_lng, shop_lng),
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id
      AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid())
      AND status NOT IN (
        'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
        'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded',
        'payment_failed', 'no_rider'
      );
  ELSE
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE v_new_status 
      END,
      payment_deadline = CASE 
        WHEN v_all_shops_accepted = true AND v_payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE v_payment_deadline 
      END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = COALESCE(p_shop_lat, shop_lat),
      shop_lng = COALESCE(p_shop_lng, shop_lng),
      updated_at = NOW()
    WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());
  END IF;

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_all_shops_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO authenticated;

-- ── 7. Fortify decline_order_items_seller (Exact Financial Recalculation) ──────
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
  IF p_order_id IS NULL OR p_order_item_ids IS NULL OR array_length(p_order_item_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Invalid parameters: order_id and order_item_ids required';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  SELECT 
    status, shop_id, payment_status, refund_status,
    total_amount, grand_total_collected,
    s9_5_gst_amount, non_food_gst_amount,
    enything_commission, tcs_amount, tds_amount,
    delivery_charges, platform_fee,
    multi_shop_surcharge, small_cart_fee, heavy_order_fee,
    coupon_discount, COALESCE(pending_refund_amount, 0)
  INTO 
    v_status, v_shop_id, v_payment_status, v_refund_status,
    v_old_total_amount, v_old_grand_total,
    v_old_s9_5, v_old_non_food_gst,
    v_old_enything_commission, v_old_tcs, v_old_tds,
    v_delivery_charges, v_platform_fee,
    v_multi_shop_surcharge, v_small_cart_fee, v_heavy_order_fee,
    v_coupon_discount, v_pending_refund_amount
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
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
        WHEN v_payment_status = 'captured' AND COALESCE(v_refund_status, 'none') NOT IN ('processing', 'completed') 
        THEN 'processing' 
        ELSE v_refund_status 
      END,
      updated_at = NOW()
    WHERE id = p_order_id;

    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_cart_group_id);

      -- 100x STRANDED SIBLING PROMOTION:
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

  -- Recalculate remaining active items financials
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

  IF COALESCE(v_old_total_amount, 0) > 0 THEN
    v_ratio := v_new_active_subtotal / v_old_total_amount;
  ELSE
    v_ratio := 1.0;
  END IF;

  v_new_s9_5 := ROUND((COALESCE(v_old_s9_5, 0) * v_ratio)::numeric, 2);
  v_new_non_food_gst := ROUND((COALESCE(v_old_non_food_gst, 0) * v_ratio)::numeric, 2);
  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;

  v_new_enything_commission := ROUND((COALESCE(v_old_enything_commission, 0) * v_ratio)::numeric, 2);
  -- 100x STATUTORY EXEMPTION PRESERVATION: Prorate existing TCS and TDS to avoid charging Section 9(5) items
  v_new_tcs := ROUND((COALESCE(v_old_tcs, 0) * v_ratio)::numeric, 2);
  v_new_tds := ROUND((COALESCE(v_old_tds, 0) * v_ratio)::numeric, 2);
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  -- Recalculate heavy order fee if applicable
  IF COALESCE(v_heavy_order_fee, 0) > 0 THEN
    IF v_new_active_weight <= 10.0 THEN
      v_new_heavy_order_fee := 0.0;
    ELSE
      v_new_heavy_order_fee := LEAST(v_heavy_order_fee, ROUND((20.0 * CEIL(v_new_active_weight - 10.0))::numeric, 2));
    END IF;
  ELSE
    v_new_heavy_order_fee := 0.0;
  END IF;

  -- 100x SINGLE SHOP HEAVY FEE DEDUCTION:
  -- If single-shop order and heavy fee was reduced, adjust delivery_charges downwards accordingly
  IF v_cart_group_id IS NULL AND COALESCE(v_heavy_order_fee, 0) > v_new_heavy_order_fee THEN
    v_delivery_charges := GREATEST(0, v_delivery_charges - ((v_heavy_order_fee - v_new_heavy_order_fee) * (1.0 + 0.18)));
  END IF;

  -- 100x ARCHITECTURAL FIX: Match exact grand_total formula from place_orders_transaction.
  v_new_grand_total := GREATEST(0, v_new_active_subtotal 
    + v_new_gst_item_total 
    + COALESCE(v_platform_fee, 0) 
    + COALESCE(v_delivery_charges, 0) 
    - LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal));

  v_new_refund_status := v_refund_status;
  IF v_payment_status = 'captured' AND v_old_grand_total > v_new_grand_total THEN
    v_refund_delta := v_old_grand_total - v_new_grand_total;
    v_pending_refund_amount := COALESCE(v_pending_refund_amount, 0) + v_refund_delta;
    IF COALESCE(v_refund_status, 'none') NOT IN ('completed') THEN
      v_new_refund_status := 'processing';
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
    grand_total_collected = v_new_grand_total,
    pending_refund_amount = v_pending_refund_amount,
    refund_status = v_new_refund_status,
    updated_at = NOW()
  WHERE id = p_order_id;

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

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated;

-- ── 8. Fortify customer_swap_order_item RPC ──────────────────────────────────
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
    p_quantity, v_replacement_price, v_replacement_price, v_new_item_subtotal, 'active', COALESCE(v_prod.weight_per_unit, 0.5), NOW()
  );

  -- Mark old item as swapped
  UPDATE order_items 
  SET status = 'swapped', declined_reason = 'customer_replaced'
  WHERE id = p_declined_item_id;

  -- Recalculate true active subtotal
  SELECT COALESCE(SUM(price * quantity), 0)
  INTO v_new_active_subtotal
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- 100x DOUBLE REFUND INVERSION FIX:
  -- The customer is now receiving the replacement item.
  -- Deduct the replacement cost from pending_refund_amount rather than adding!
  IF v_order.payment_status = 'captured' THEN
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = grand_total + v_price_delta,
      pending_refund_amount = GREATEST(0, COALESCE(pending_refund_amount, 0) - v_new_item_subtotal),
      refund_status = CASE 
        WHEN GREATEST(0, COALESCE(pending_refund_amount, 0) - v_new_item_subtotal) <= 0.01 THEN 'none'
        ELSE refund_status
      END,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = grand_total + v_price_delta,
      grand_total_collected = grand_total_collected + v_price_delta,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_item_id', v_new_item_id,
    'price_delta', v_price_delta,
    'old_subtotal', v_old_item_subtotal,
    'new_subtotal', v_new_item_subtotal,
    'new_active_subtotal', v_new_active_subtotal
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO authenticated;

-- ── 9. Fortify rebalance_active_delivery_fees (Active Items Filter Guard) ─────
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

  v_act_shop_lats double precision[] := '{}';
  v_act_shop_lngs double precision[] := '{}';
  v_act_dist_to_c double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharges numeric[] := '{}';
  v_total_act_surcharge numeric := 0.0;

  v_shop_lat double precision;
  v_shop_lng double precision;
BEGIN
    IF p_cart_group_id IS NULL THEN
        RETURN;
    END IF;

    -- Deterministic row-level locking
    PERFORM id FROM public.orders
    WHERE cart_group_id = p_cart_group_id
    ORDER BY id FOR UPDATE;

    -- Count active orders
    SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
      INTO v_active_count, v_active_items_total
      FROM public.orders
     WHERE cart_group_id = p_cart_group_id
       AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider');

    IF v_active_count = 0 THEN
        RETURN;
    END IF;

    -- Dynamic Platform Configurations
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_admin_delivery_base := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee_val FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee_val := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee_val FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee_val := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_admin_delivery_base := COALESCE(v_admin_delivery_base, 20.0);
    v_delivery_rate_per_km := COALESCE(v_delivery_rate_per_km, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee_val := COALESCE(v_small_cart_fee_val, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee_val := COALESCE(v_heavy_order_fee_val, 25.0);

    -- 100x ACTIVE ORDER ITEMS FILTER GUARD: Filter oi.status = 'active'
    SELECT COALESCE(SUM(
        oi.quantity * (
            CASE 
                WHEN oi.weight_kg IS NOT NULL AND oi.weight_kg > 0 AND oi.weight_kg <= 25.0 THEN
                    oi.weight_kg
                WHEN oi.weight_kg IS NOT NULL AND oi.weight_kg > 25.0 AND (p.category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') OR oi.weight_kg > 100.0) THEN
                    oi.weight_kg / 1000.0
                WHEN oi.weight_in_grams IS NOT NULL AND oi.weight_in_grams > 0 THEN
                    oi.weight_in_grams / 1000.0
                WHEN p.weight_per_unit IS NOT NULL AND p.weight_per_unit > 0 THEN
                    CASE 
                        WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres') THEN
                            p.weight_per_unit / 1000.0
                        WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('mg', 'milligram', 'milligrams') THEN
                            p.weight_per_unit / 1000000.0
                        WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres') THEN
                            p.weight_per_unit
                        WHEN LOWER(TRIM(COALESCE(p.unit_type, ''))) IN ('pieces', 'piece', 'pcs', 'pc') THEN
                            CASE WHEN p.weight_per_unit > 25.0 THEN p.weight_per_unit / 1000.0 ELSE p.weight_per_unit END
                        WHEN p.category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') AND p.weight_per_unit > 20.0 THEN
                            p.weight_per_unit / 1000.0
                        WHEN p.weight_per_unit > 25.0 THEN
                            p.weight_per_unit / 1000.0
                        ELSE
                            p.weight_per_unit
                    END
                ELSE 0.5
            END
        )
    ), 0)
      INTO v_active_weight_total
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      JOIN public.products p ON p.id = oi.product_id
     WHERE o.cart_group_id = p_cart_group_id
       AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
       AND oi.status = 'active'
       AND p.is_deleted = false;

    v_active_weight_total := LEAST(COALESCE(v_active_weight_total, 0.0), 100.0);

    -- Resolve coupon_id from group
    SELECT MAX(coupon_id::text)::uuid
      INTO v_group_coupon_id
      FROM public.orders
     WHERE cart_group_id = p_cart_group_id;

    -- Build sequential coordinates for active shops
    FOR rec IN
        SELECT o.id, o.estimated_distance_km, o.delivery_lat, o.delivery_lng, s.location
        FROM public.orders o
        JOIN public.shops s ON s.id = o.shop_id
        WHERE o.cart_group_id = p_cart_group_id
          AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
        ORDER BY o.created_at ASC
    LOOP
        v_shop_lat := NULL;
        v_shop_lng := NULL;
        IF rec.location IS NOT NULL THEN
            v_shop_lat := ST_Y(rec.location::geometry);
            v_shop_lng := ST_X(rec.location::geometry);
        END IF;

        IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
            v_act_shop_lats := array_append(v_act_shop_lats, v_shop_lat);
            v_act_shop_lngs := array_append(v_act_shop_lngs, v_shop_lng);
        END IF;

        v_act_dist_to_c := array_append(v_act_dist_to_c, COALESCE(rec.estimated_distance_km::double precision, 1.0));
    END LOOP;

    -- Calculate leg surcharges between active shops
    IF v_active_count > 1 AND array_length(v_act_shop_lats, 1) >= 2 THEN
        FOR i IN 1..(array_length(v_act_shop_lats, 1) - 1) LOOP
            v_inter_dist := 6371.0 * acos(
                LEAST(1.0, GREATEST(-1.0,
                    cos(radians(v_act_shop_lats[i])) * cos(radians(v_act_shop_lats[i+1])) *
                    cos(radians(v_act_shop_lngs[i+1]) - radians(v_act_shop_lngs[i])) +
                    sin(radians(v_act_shop_lats[i])) * sin(radians(v_act_shop_lats[i+1]))
                ))
            );
            v_leg_surcharges := array_append(v_leg_surcharges, GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km);
            v_total_act_surcharge := v_total_act_surcharge + (GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km);
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
        SELECT o.id, o.total_amount, o.gst_item_total, o.enything_commission, o.tcs_amount, o.tds_amount, o.payment_status, o.grand_total_collected, o.refund_status
        FROM public.orders o
        WHERE o.cart_group_id = p_cart_group_id
          AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider')
        ORDER BY o.created_at ASC
    LOOP
        v_active_idx := v_active_idx + 1;

        IF v_active_idx = 1 THEN
            v_new_plat := v_admin_platform_fee;
            v_new_small := CASE WHEN v_active_items_total < v_small_cart_threshold THEN v_small_cart_fee_val ELSE 0.0 END;
            v_new_heavy := CASE WHEN v_active_weight_total > v_heavy_order_threshold_kg THEN (v_active_weight_total - v_heavy_order_threshold_kg) * v_heavy_order_fee_val ELSE 0.0 END;
            v_new_surcharge := 0.0;
            v_new_del := (v_new_base_delivery + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);
        ELSE
            v_new_plat := 0.0;
            v_new_small := 0.0;
            v_new_heavy := 0.0;
            IF array_length(v_leg_surcharges, 1) >= (v_active_idx - 1) THEN
                v_new_surcharge := v_leg_surcharges[v_active_idx - 1];
            ELSE
                v_new_surcharge := 20.0;
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
            grand_total_collected = CASE WHEN rec.payment_status = 'captured' THEN v_new_grand ELSE grand_total_collected END,
            pending_refund_amount = CASE 
                WHEN rec.payment_status = 'captured' AND COALESCE(rec.grand_total_collected, 0) > v_new_grand
                THEN COALESCE(pending_refund_amount, 0) + (rec.grand_total_collected - v_new_grand)
                ELSE pending_refund_amount 
            END,
            refund_status = CASE
                WHEN rec.payment_status = 'captured' AND COALESCE(rec.grand_total_collected, 0) > v_new_grand AND COALESCE(rec.refund_status, 'none') NOT IN ('completed')
                THEN 'processing'
                ELSE refund_status
            END,
            updated_at = NOW()
        WHERE id = rec.id;
    END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(UUID) TO service_role;

-- ── 10. Fortify place_orders_transaction (Ghost Order, Deadlock, Auth Fortress) ──
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

    -- 100x SHOP STATUS & POSTGIS RESOLUTION
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

  -- 2. Items & Weight Validation
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

    IF v_unit_weight IS NOT NULL AND v_unit_weight > 0 THEN
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

      v_total_weight_kg := v_total_weight_kg + (v_item.quantity * v_resolved_unit_weight_kg);
    ELSE
      v_total_weight_kg := v_total_weight_kg + (v_item.quantity * COALESCE(v_item.weight_kg, 0.5));
    END IF;
  END LOOP;

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
  IF v_shop_count > 1 AND NOT v_is_replacement THEN
    IF ABS(v_sum_client_multi_shop_surcharge - v_expected_surcharge) > 2.0 THEN
       IF ABS(v_sum_client_multi_shop_surcharge - (20.0 * (v_shop_count - 1))) > 2.0 THEN
          RAISE EXCEPTION 'Multi shop surcharge mismatch. Expected: %, Got: %', v_expected_surcharge, v_sum_client_multi_shop_surcharge;
       END IF;
    END IF;
  END IF;

  -- 5. Handling / Platform Fee
  IF v_is_replacement THEN
    v_expected_platform_fee := 0.0;
  ELSE
    v_expected_platform_fee := v_global_platform_fee;
  END IF;

  IF ABS(v_sum_client_platform_fee - v_expected_platform_fee) > 1.0 THEN
     RAISE EXCEPTION 'Handling fee spoofing detected. Expected: %, Got: %', v_expected_platform_fee, v_sum_client_platform_fee;
  END IF;

  -- 6. Delivery Fee Validation
  IF v_is_replacement THEN
    v_expected_delivery_fee := (v_sum_client_multi_shop_surcharge + v_sum_client_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  ELSE
    v_calculated_delivery_base := GREATEST(
      v_global_delivery_base, 
      GREATEST(1, CEIL(v_first_shop_dist_km)) * v_delivery_rate_per_km
    );
    v_expected_delivery_fee := (v_calculated_delivery_base + v_expected_surcharge + v_expected_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  END IF;

  IF ABS(v_sum_client_delivery_charges - v_expected_delivery_fee) > 2.5 THEN
     RAISE EXCEPTION 'Delivery charges spoofing detected. Expected: %, Got: %', v_expected_delivery_fee, v_sum_client_delivery_charges;
  END IF;

  -- 7. Coupon Discount Validation
  IF p_coupon_id IS NOT NULL THEN
    SELECT * INTO v_coupon_record FROM coupons WHERE id = p_coupon_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid coupon.';
    END IF;
    IF NOT v_coupon_record.is_active THEN
      RAISE EXCEPTION 'Coupon is inactive.';
    END IF;
    IF v_coupon_record.valid_until < NOW() THEN
      RAISE EXCEPTION 'Coupon has expired.';
    END IF;
    IF v_coupon_record.min_order_amount IS NOT NULL AND v_sum_expected_total_amount < v_coupon_record.min_order_amount THEN
      RAISE EXCEPTION 'Order amount % does not meet minimum % for coupon.', v_sum_expected_total_amount, v_coupon_record.min_order_amount;
    END IF;
    
    v_customer_id := (p_orders->0->>'customer_id')::uuid;
    SELECT COUNT(*) INTO v_user_usage_count FROM user_coupon_usage WHERE user_id = v_customer_id AND coupon_id = p_coupon_id;
    IF v_coupon_record.usage_limit_per_user IS NOT NULL AND v_user_usage_count >= v_coupon_record.usage_limit_per_user THEN
      RAISE EXCEPTION 'Coupon usage limit per user reached.';
    END IF;
    
    SELECT COUNT(*) INTO v_total_usage_count FROM user_coupon_usage WHERE coupon_id = p_coupon_id;
    IF v_coupon_record.total_usage_limit IS NOT NULL AND v_total_usage_count >= v_coupon_record.total_usage_limit THEN
      RAISE EXCEPTION 'Coupon total usage limit reached.';
    END IF;
    
    IF v_coupon_record.discount_type = 'percentage' THEN
      v_calculated_discount := (v_sum_expected_total_amount * (v_coupon_record.discount_value / 100.0));
      IF v_coupon_record.max_discount_amount IS NOT NULL THEN
        v_calculated_discount := LEAST(v_calculated_discount, v_coupon_record.max_discount_amount);
      END IF;
    ELSE
      v_calculated_discount := v_coupon_record.discount_value;
    END IF;
    v_expected_discount := v_calculated_discount;
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_coupon_discount_sum := v_coupon_discount_sum + COALESCE((v_order->>'coupon_discount')::numeric, 0);
  END LOOP;

  IF p_coupon_id IS NOT NULL THEN
    IF ABS(v_coupon_discount_sum - v_expected_discount) > 1.0 THEN
      RAISE EXCEPTION 'Coupon discount spoofing detected: Claimed %, Expected %', v_coupon_discount_sum, v_expected_discount;
    END IF;
  ELSE
    IF v_coupon_discount_sum > 0 THEN
      RAISE EXCEPTION 'Unauthorized coupon discount without coupon_id.';
    END IF;
  END IF;

  -- 8. Sub-Orders Secure Processing & Insertion
  v_order_seq := 0;
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order_seq := v_order_seq + 1;
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    SELECT TRIM(category) INTO v_shop_category FROM shops WHERE id = (v_order->>'shop_id')::uuid;

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

    IF (v_order->>'grand_total_collected') IS NOT NULL AND ABS((v_order->>'grand_total_collected')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total_collected';
    ELSIF (v_order->>'grand_total') IS NOT NULL AND ABS((v_order->>'grand_total')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total';
    END IF;
    
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));

    v_gw_deduct := GREATEST(0, (v_expected_grand_total * 0.02) * (1.0 + v_gateway_gst_rate));
    v_seller_gw_share := GREATEST(0, (v_expected_total_amount - v_pure_commission + v_non_food_gst) * 0.0236);
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;
    
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));

    v_acceptance_deadline := (v_order->>'acceptance_deadline')::timestamptz;
    IF v_acceptance_deadline IS NULL THEN
      v_acceptance_deadline := NOW() + INTERVAL '3 minutes';
    END IF;

    -- 100x INJECTION BLOCK: Force status = 'awaiting_acceptance' and payment_status = 'pending'
    v_secure_order := jsonb_build_object(
      'id', v_order->>'id',
      'customer_id', v_order->>'customer_id',
      'shop_id', v_order->>'shop_id',
      'payment_method', v_order->>'payment_method',
      'payment_status', 'pending',
      'status', 'awaiting_acceptance',
      'seller_accepted', false,
      'partner_accepted', COALESCE(v_existing_partner_accepted, false),
      'delivery_partner_id', v_existing_rider_id,
      'rider_phone', COALESCE(v_existing_rider_phone, v_order->>'rider_phone'),
      'address', v_order->>'address',
      'address_label', v_order->>'address_label',
      'delivery_lat', v_order->>'delivery_lat',
      'delivery_lng', v_order->>'delivery_lng',
      'delivery_notes', v_order->>'delivery_notes',
      'estimated_distance_km', v_order->>'estimated_distance_km',
      'acceptance_deadline', v_acceptance_deadline,
      'cart_group_id', p_cart_group_id,
      'idempotency_key', p_idempotency_key,
      'created_at', (COALESCE((v_order->>'created_at')::timestamptz, clock_timestamp()) + ((v_order_seq * 10) || ' milliseconds')::interval)::text,
      'updated_at', (COALESCE((v_order->>'updated_at')::timestamptz, clock_timestamp()) + ((v_order_seq * 10) || ' milliseconds')::interval)::text,
      'total_amount', v_expected_total_amount,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'platform_fee', COALESCE((v_order->>'platform_fee')::numeric, 0),
      'delivery_charges', COALESCE((v_order->>'delivery_charges')::numeric, 0),
      'multi_shop_surcharge', COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0),
      'small_cart_fee', COALESCE((v_order->>'small_cart_fee')::numeric, 0),
      'heavy_order_fee', COALESCE((v_order->>'heavy_order_fee')::numeric, 0),
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'coupon_id', p_coupon_id,
      'coupon_discount', COALESCE((v_order->>'coupon_discount')::numeric, 0),
      'gst_rate_snapshot', COALESCE(v_order->'gst_rate_snapshot', '{}'::jsonb),
      'prescription_urls', COALESCE(v_order->'prescription_urls', '[]'::jsonb),
      'shop_prep_time_snapshot', (v_order->>'shop_prep_time_snapshot')::int
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

  -- Insert order items
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
      COALESCE(v_item.weight_kg, 0.0),
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

-- ── 11. Fortify check_rider_has_stacked_orders (RLS Safe Multi-Cart Radar) ────
CREATE OR REPLACE FUNCTION public.check_rider_has_stacked_orders(
  p_rider_id UUID,
  p_my_cart_group_id TEXT DEFAULT NULL,
  p_my_order_id UUID DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_stacked boolean := false;
BEGIN
  IF p_rider_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM orders
    WHERE delivery_partner_id = p_rider_id
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery')
      AND (
        (p_my_cart_group_id IS NOT NULL AND (cart_group_id IS NULL OR cart_group_id::text != p_my_cart_group_id))
        OR
        (p_my_cart_group_id IS NULL AND (p_my_order_id IS NULL OR id != p_my_order_id))
      )
  ) INTO v_has_stacked;

  RETURN v_has_stacked;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_rider_has_stacked_orders(UUID, TEXT, UUID) TO authenticated, anon;
