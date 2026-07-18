-- =============================================================================
-- Migration: 100x Allow Seller Rejection After Payment
-- Description:
--   1. Fixes an issue where `prevent_reject_after_payment` trigger 
--      blocked `seller_rejected` from post-payment states, preventing the
--      refund logic from executing properly.
-- =============================================================================

CREATE OR REPLACE FUNCTION prevent_reject_after_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- We allow 'seller_rejected' because the reject_order_seller RPC now securely handles refund processing.
  IF NEW.status IN ('partner_rejected', 'cancelled')
     AND OLD.status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Cannot cancel order with id=% — payment is already confirmed (status was: %)',
      OLD.id, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
