-- ============================================================================
-- Migration: 20260609000010_fix_order_lifecycle_bugs.sql
-- Description: Fixes all order lifecycle bugs identified in audit.
--
-- BUG-23: Add requires_prescription to order_items
-- BUG-7:  Add trigger to prevent customer cancel post-payment
-- BUG-6/9: Trigger also prevents overwriting seller_rejected with cancelled
-- PERF:   Add missing index on order_items(order_id)
-- CLEANUP: Remove auto_accept column (feature removed by design decision)
-- ============================================================================

-- ── BUG-23: Add requires_prescription to order_items ────────────────────────
-- Checkout page was inserting order_items without this column.
-- Sellers lose context on which items need a prescription.
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN NOT NULL DEFAULT false;

-- ── PERF: Index on order_items(order_id) ────────────────────────────────────
-- Used heavily in retry logic and order detail fetches.
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON public.order_items (order_id);

-- ── BUG-7 + BUG-6/9: Trigger to guard illegal status transitions ─────────────
--
-- Prevents:
--   a) Customer cancelling an order after payment is captured (confirmed/preparing/etc.)
--   b) A bulk cancel (cart_group_id sweep) from overwriting seller_rejected or
--      verification_failed orders with 'cancelled (customer)'.
--
-- This is a SECURITY DEFINER trigger so it runs with elevated privileges and
-- cannot be bypassed by the authenticated user's RLS policies.

CREATE OR REPLACE FUNCTION public.guard_order_status_transitions()
RETURNS TRIGGER AS $$
BEGIN
  -- Guard A: prevent customer from cancelling post-payment orders
  -- If the new status is 'cancelled' with reason 'customer', and the OLD status
  -- is already past the acceptance/payment stage, reject the transition.
  IF NEW.status = 'cancelled'
     AND NEW.cancelled_reason = 'customer'
     AND OLD.status NOT IN ('awaiting_acceptance', 'awaiting_payment')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed')
  THEN
    RAISE EXCEPTION
      'Order cannot be cancelled after payment has been confirmed. Status was: %', OLD.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Guard B: prevent any update from overwriting terminal rejection statuses
  -- seller_rejected and verification_failed are terminal — nothing should overwrite them.
  IF OLD.status IN ('seller_rejected', 'verification_failed')
     AND NEW.status NOT IN ('seller_rejected', 'verification_failed')
  THEN
    -- Silently keep the existing status rather than raising (to not break
    -- bulk cart_group_id sweeps — they just skip these rows gracefully).
    NEW.status := OLD.status;
    NEW.cancelled_reason := OLD.cancelled_reason;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate so migration is idempotent
DROP TRIGGER IF EXISTS tr_guard_order_status_transitions ON public.orders;

CREATE TRIGGER tr_guard_order_status_transitions
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_order_status_transitions();

-- ── CLEANUP: Remove auto_accept from delivery_partners ───────────────────────
-- Auto-accept feature has been removed by product decision (race condition risk).
-- We keep the column but disable it by setting all values to false and removing
-- the UI toggle. A future migration can DROP the column after confirming no
-- code reads it.
UPDATE public.delivery_partners
  SET auto_accept = false
  WHERE auto_accept = true;

-- ── Reload PostgREST schema cache ────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
