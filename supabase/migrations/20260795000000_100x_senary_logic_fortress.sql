-- =============================================================================
-- Migration: 100x Senary Logic Fortress (Ghost Cron Exploits)
-- Description:
--   1. Patches monitor_rider_heartbeat to group by cart_group_id, trigger 
--      refunds, and reallocate delivery fees correctly.
--   2. Patches auto_cancel_ghost_prep_orders with the same fixes.
-- =============================================================================

-- 1. Patch auto_cancel_ghost_prep_orders
CREATE OR REPLACE FUNCTION auto_cancel_ghost_prep_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
BEGIN
  -- Automatically cancel orders stuck in confirmed or preparing for > 1.5 hours
  -- after the payment deadline, indicating someone ghosted.
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status IN ('confirmed', 'preparing') 
      AND payment_deadline IS NOT NULL 
      AND payment_deadline < (NOW() - INTERVAL '1.5 hours')
    GROUP BY cart_group_id
  LOOP
    -- Deterministic lock
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;
END;
$$;

-- 2. Patch monitor_rider_heartbeat
CREATE OR REPLACE FUNCTION monitor_rider_heartbeat()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
BEGIN
  -- Unassign rider or cancel order if rider ghosted before picking up the food
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status IN ('confirmed', 'preparing', 'ready_for_pickup') 
      AND delivery_partner_id IS NOT NULL
      AND rider_location_updated_at IS NOT NULL
      AND rider_location_updated_at < (NOW() - INTERVAL '15 minutes')
    GROUP BY cart_group_id
  LOOP
    -- Deterministic lock
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET 
      status = CASE WHEN status IN ('preparing', 'ready_for_pickup') THEN 'cancelled' ELSE 'pending' END,
      cancelled_reason = CASE WHEN status IN ('preparing', 'ready_for_pickup') THEN 'no_rider' ELSE cancelled_reason END,
      refund_status = CASE WHEN status IN ('preparing', 'ready_for_pickup') AND payment_status = 'captured' THEN 'processing' ELSE refund_status END,
      delivery_partner_id = NULL,
      partner_accepted = false,
      updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;
END;
$$;
