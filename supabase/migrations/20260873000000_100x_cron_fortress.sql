-- Migration 20260873000000_100x_cron_fortress.sql
-- Fixes Phase 19: Cron Job Reallocation Bypass & Denial of Service

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
    LIMIT 100 -- 100x STRESS TEST FIX: Prevent Pixel Overload (Cron DOS)
  LOOP
    -- Deterministic lock
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'timeout',
        cancelled_reason = 'Auto-cancelled: Acceptance timeout exceeded',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    -- 100x STRESS TEST FIX: Prevent Cascading Math Failure via Explicit Reallocation
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

    UPDATE orders
    SET status = 'payment_failed',
        cancelled_reason = 'Auto-cancelled: Payment timeout exceeded',
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
END;
$function$;

-- Clean up dangerous old jobs
DO $DO$
BEGIN
  BEGIN PERFORM cron.unschedule('auto-cancel-unaccepted-orders'); EXCEPTION WHEN OTHERS THEN END;
  BEGIN PERFORM cron.unschedule('auto-cancel-unpaid-orders'); EXCEPTION WHEN OTHERS THEN END;
  BEGIN PERFORM cron.unschedule('auto_cancel_orders'); EXCEPTION WHEN OTHERS THEN END;
  BEGIN PERFORM cron.unschedule('auto_cancel_phantom_orders_job'); EXCEPTION WHEN OTHERS THEN END;
  BEGIN PERFORM cron.unschedule('auto_cancel_ghost_prep_orders_job'); EXCEPTION WHEN OTHERS THEN END;
  
  -- Schedule the new fortress-protected job
  PERFORM cron.schedule(
    'safe_auto_cancel_expired_orders_job',
    '* * * * *',
    'SELECT public.safe_auto_cancel_expired_orders()'
  );
END;
$DO$;

-- Drop deprecated functions to prevent accidental usage
DROP FUNCTION IF EXISTS public.auto_cancel_timed_out_orders();
DROP FUNCTION IF EXISTS public.auto_cancel_phantom_orders();
DROP FUNCTION IF EXISTS public.auto_cancel_ghost_prep_orders();
DROP FUNCTION IF EXISTS public.auto_cancel_expired_orders();

