-- =============================================================================
-- Migration: 100x Restart Payment Timer
-- Description:
--   Restarts the payment_deadline and acceptance_deadline by bumping them 
--   to now() + 10 mins (and 3 mins) so that the order is not reaped by the 
--   cron job after a customer takes time during a partial rejection hold.
-- =============================================================================

CREATE OR REPLACE FUNCTION restart_payment_timer(p_cart_group_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Bump the payment deadline and acceptance deadline for all active orders in the group
  UPDATE orders
  SET 
    payment_deadline = now() + interval '10 minutes',
    acceptance_deadline = now() + interval '3 minutes'
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_payment', 'awaiting_acceptance');
END;
$$;

GRANT EXECUTE ON FUNCTION restart_payment_timer(UUID) TO authenticated;
