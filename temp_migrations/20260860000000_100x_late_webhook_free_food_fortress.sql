-- =============================================================================
-- Migration: 100x Late Webhook Free Food Fortress (Phase 7)
-- Description:
--   1. Fixes a Catastrophic Free Food Exploit where a delayed Razorpay webhook
--      would auto-refund an order that had already progressed to 'delivered'
--      (or any other active state) via a manual admin override.
--   2. Implements a Strict State-Aware Refund Guard, ensuring refunds are ONLY
--      triggered if the order is in a terminal cancellation state AND hasn't 
--      already been refunded.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.client_confirm_payment(p_order_id uuid DEFAULT NULL::uuid, p_cart_group_id uuid DEFAULT NULL::uuid, p_razorpay_payment_id text DEFAULT NULL::text, p_razorpay_order_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_payment_status text;
  v_existing_payment_id text;
  v_order_id uuid;
  v_rec record;
BEGIN
  -- 100x FIX: TOCTOU Double Spend Prevention via Transaction-Level Advisory Lock
  -- This forces all concurrent requests using the exact same payment ID to queue up here.
  IF p_razorpay_payment_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('pay_' || p_razorpay_payment_id));
    
    IF EXISTS (
      SELECT 1 FROM orders 
      WHERE razorpay_payment_id = p_razorpay_payment_id 
      AND (
        (p_cart_group_id IS NOT NULL AND (cart_group_id IS NULL OR cart_group_id != p_cart_group_id))
        OR 
        (p_cart_group_id IS NULL AND id != p_order_id)
      )
    ) THEN
      RAISE EXCEPTION 'Double spend detected: Payment ID % is already used for another order or group.', p_razorpay_payment_id;
    END IF;
  END IF;

  IF p_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status, razorpay_payment_id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_rec.status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_rec.payment_status = 'captured' AND v_rec.razorpay_payment_id = p_razorpay_payment_id THEN
           CONTINUE;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          -- 100x STRESS TEST FIX (Phase 7): Prevent Late Webhook Free Food & Double-Refund Exploits
          refund_status = CASE 
            WHEN v_rec.status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel') 
                 AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') 
            THEN 'processing'
            ELSE refund_status
          END,
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    SELECT status, payment_status, razorpay_payment_id INTO v_status, v_payment_status, v_existing_payment_id FROM orders WHERE id = p_order_id FOR UPDATE;
    IF FOUND THEN
      IF v_status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_payment_status = 'captured' AND v_existing_payment_id = p_razorpay_payment_id THEN
           RETURN;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          -- 100x STRESS TEST FIX (Phase 7): Prevent Late Webhook Free Food & Double-Refund Exploits
          refund_status = CASE 
            WHEN v_status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel') 
                 AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') 
            THEN 'processing'
            ELSE refund_status
          END,
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      END IF;
    END IF;
  END IF;
END;
$function$;
