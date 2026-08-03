-- Migration 20260803105422_100x_cron_partial_rejection_fix.sql
-- 100x EXTREME EDGE CASE FIX: Fix Cron Jobs Status Discrepancy & Add Decision Timer

CREATE OR REPLACE FUNCTION public.safe_auto_cancel_expired_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_group RECORD;
BEGIN
  -- 1. Awaiting Acceptance Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    -- 100x FIX: Use 'cancelled' status to perfectly match track_order_page.dart UI mapping
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

  -- 2. Awaiting Payment Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    -- 100x FIX: Use 'cancelled' status to perfectly match track_order_page.dart UI mapping
    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'payment_failed',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 3. Ghosted Prep Orders Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status IN ('confirmed', 'preparing') 
      AND payment_deadline IS NOT NULL 
      AND payment_deadline < (NOW() - INTERVAL '1.5 hours')
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'Auto-cancelled: Seller ghosted preparation',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 4. 100x EXTREME EDGE CASE FIX: Partial Rejection Decision Timeout (5 minutes)
  -- If a group has a rejection, the customer has 5 minutes to decide. If they close the app,
  -- this cron job will catch it and cancel the remaining active sibling orders.
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM orders
    WHERE cart_group_id IS NOT NULL
    GROUP BY cart_group_id
    HAVING 
      COUNT(CASE WHEN status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN 1 END) > 0
      AND 
      COUNT(CASE WHEN status IN ('seller_rejected', 'cancelled') THEN 1 END) > 0
      AND
      MIN(CASE WHEN status IN ('seller_rejected', 'cancelled') THEN COALESCE(updated_at, created_at) END) + INTERVAL '5 minutes' < NOW()
    LIMIT 100
  LOOP
    PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE cart_group_id = v_group.cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
      
    PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
  END LOOP;
END;
$function$;
