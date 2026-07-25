-- ============================================================================
-- Migration: 20271125000001_magic_auto_accept_rpc.sql
-- Description: ADDITIVE ONLY — adds a single new SECURITY DEFINER RPC for
--              the magic reviewer auto-accept flow.
--
-- Purpose: The 100x_rls_financial_fortress migration revokes direct UPDATE
--          on orders from all authenticated users. The reviewer auto-accept
--          (2-second animation on TrackOrderPage) needs to transition orders
--          from awaiting_acceptance → awaiting_payment.
--          This RPC is the secure, auditable path for that transition.
--
-- Security: Only callable by the 3 magic reviewer customer IDs.
--           Any other caller gets EXCEPTION 'Unauthorized'.
--           All other business logic is untouched.
-- ============================================================================

CREATE OR REPLACE FUNCTION magic_reviewer_auto_accept(
  p_order_ids UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_allowed boolean := false;
BEGIN
  -- Guard: Only the 3 magic reviewer customer UUIDs may call this.
  -- UUIDs are deterministic and set by the reviewer_accounts_final migration.
  IF v_caller_id IN (
      '00000000-0000-0000-0000-919999999996'::uuid,
      '00000000-0000-0000-0000-919999999997'::uuid,
      '00000000-0000-0000-0000-919999999998'::uuid
  ) THEN
    v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Unauthorized: magic_reviewer_auto_accept is restricted to reviewer accounts';
  END IF;

  -- Verify all provided order IDs belong to the calling reviewer customer
  -- (prevents a reviewer account from accepting another user's orders)
  IF EXISTS (
    SELECT 1 FROM orders
    WHERE id = ANY(p_order_ids)
      AND customer_id != v_caller_id
  ) THEN
    RAISE EXCEPTION 'Unauthorized: orders do not belong to the calling reviewer';
  END IF;

  -- Perform the acceptance: seller + rider both accepted, move to awaiting_payment
  UPDATE public.orders
  SET
    seller_accepted   = true,
    partner_accepted  = true,
    status            = 'awaiting_payment',
    payment_deadline  = (now() AT TIME ZONE 'utc') + interval '60 minutes',
    acceptance_deadline = NULL,
    updated_at        = (now() AT TIME ZONE 'utc')
  WHERE id = ANY(p_order_ids)
    AND status IN ('awaiting_acceptance', 'awaiting_payment');

END;
$$;

-- Grant to authenticated only — guard inside the function handles the rest
GRANT EXECUTE ON FUNCTION magic_reviewer_auto_accept(UUID[]) TO authenticated;

-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
