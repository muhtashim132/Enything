-- Migration: 20260710000009_fix_cancelled_order_override.sql
-- Description: Purely additive. Fixes the issue where cancelled orders can be resurrected by sellers/riders.
-- Also ensures no missing SELECT grants.

-- Grant SELECT on core tables to all roles to prevent "Grant SELECT error"
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.orders TO anon;
GRANT SELECT ON public.order_items TO authenticated;
GRANT SELECT ON public.order_items TO anon;
GRANT SELECT ON public.delivery_partners TO authenticated;
GRANT SELECT ON public.delivery_partners TO anon;
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- Update the guard trigger to protect ALL terminal statuses, including 'cancelled'
CREATE OR REPLACE FUNCTION public.guard_order_status_transitions()
RETURNS TRIGGER AS $$
BEGIN
  -- Guard A: prevent customer from cancelling post-payment orders
  IF NEW.status = 'cancelled'
     AND NEW.cancelled_reason = 'customer'
     AND OLD.status NOT IN ('awaiting_acceptance', 'awaiting_payment')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed')
  THEN
    RAISE EXCEPTION
      'Order cannot be cancelled after payment has been confirmed. Status was: %', OLD.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Guard B: prevent any update from overwriting ANY terminal rejection/cancellation status.
  -- Once an order is cancelled, delivered, or rejected, it should NEVER be moved back to active statuses.
  IF OLD.status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'delivered')
     AND NEW.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'delivered')
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
