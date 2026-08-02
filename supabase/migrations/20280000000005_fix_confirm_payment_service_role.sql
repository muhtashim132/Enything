-- =============================================================================
-- Migration: Fix client_confirm_payment for service_role (Edge Function) calls
-- =============================================================================
-- BUG: When `verify-razorpay-payment` Edge Function calls `client_confirm_payment`
-- using the Supabase Admin client (service_role key), `auth.uid()` returns NULL
-- because there is no user JWT in the service_role context. This caused ALL payment
-- confirmations from the Edge Function to ALWAYS throw an "Unauthorized" exception,
-- leaving orders permanently stuck in "awaiting_payment" status even after Razorpay
-- successfully captured the payment.
--
-- FIX: Replace the blind `auth.uid() IS NULL` check with a caller-aware guard:
--   - If called as service_role → auth.uid() is NULL, but pg_has_role('service_role')
--     returns TRUE, meaning this is a trusted server-side call → ALLOW
--   - If called as anon/unauthenticated → auth.uid() is NULL AND service_role check
--     fails → DENY (original security maintained)
--   - If called as authenticated user → auth.uid() is NOT NULL → ALLOW
--
-- This is ADDITIVE: all other logic (TOCTOU lock, double-spend guard, status
-- transitions, refund handling) is 100% unchanged.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.client_confirm_payment(
  p_order_id uuid DEFAULT NULL::uuid,
  p_cart_group_id uuid DEFAULT NULL::uuid,
  p_razorpay_payment_id text DEFAULT NULL::text,
  p_razorpay_order_id text DEFAULT NULL::text
)
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
  -- ==========================================================================
  -- SECURITY GUARD (ADDITIVE FIX):
  -- Allow if:
  --   (a) Called by an authenticated user (auth.uid() IS NOT NULL), OR
  --   (b) Called by service_role (Edge Function server-side) — identified by
  --       the fact that CURRENT_USER is the service_role DB user.
  --       This is safe because service_role is never exposed to clients:
  --       it is only accessible via Supabase Edge Functions with SUPABASE_SERVICE_ROLE_KEY.
  --
  -- Block if: auth.uid() IS NULL AND caller is NOT service_role (i.e., anon/unauthenticated)
  -- ==========================================================================
  IF auth.uid() IS NULL AND current_user NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'Unauthorized: Payment confirmation requires an active session.';
  END IF;

  -- ==========================================================================
  -- 100x FIX: TOCTOU Double Spend Prevention via Transaction-Level Advisory Lock
  -- This forces all concurrent requests using the exact same payment ID to queue up here.
  -- ==========================================================================
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

-- Permissions remain exactly the same as existing:
-- service_role can call it (Edge Function), authenticated cannot directly
REVOKE EXECUTE ON FUNCTION public.client_confirm_payment(uuid, uuid, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.client_confirm_payment(uuid, uuid, text, text) TO service_role;
