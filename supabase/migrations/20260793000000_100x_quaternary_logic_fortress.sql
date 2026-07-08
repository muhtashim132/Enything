-- =============================================================================
-- Migration: 100x Quaternary Logic Fortress (Cron Concurrency & Webhook Fixes)
-- Description:
--   1. Patches auto_cancel_expired_orders to group cancellations by cart_group_id
--      to prevent UI receipt corruption via sequential delivery fee reallocation.
--   2. Patches sweep_phantom_orders with the same grouping logic.
-- =============================================================================

-- 1. Patch auto_cancel_expired_orders
CREATE OR REPLACE FUNCTION auto_cancel_expired_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_group RECORD;
BEGIN
  -- Cancel orders that are awaiting acceptance and past their acceptance deadline
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    GROUP BY cart_group_id
  LOOP
    -- Deterministic lock
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- Cancel orders that are awaiting payment and past their payment deadline
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    GROUP BY cart_group_id
  LOOP
    -- Deterministic lock
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'payment_failed',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;
END;
$$;


-- 2. Patch sweep_phantom_orders
CREATE OR REPLACE FUNCTION sweep_phantom_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_group RECORD;
BEGIN
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status IN ('pending', 'awaiting_payment', 'awaiting_acceptance')
      AND created_at < NOW() - INTERVAL '24 hours'
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
        rejection_message = 'Automated system cleanup: Order stuck in phantom state',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;
END;
$$;
