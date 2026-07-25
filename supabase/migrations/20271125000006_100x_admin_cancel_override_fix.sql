-- =============================================================================
-- Migration: 100x Admin Cancel Override Fix
-- Description:
--   1. Fixes an issue where `prevent_reject_after_payment` trigger rigidly
--      blocked Super Admins from cancelling/refunding post-payment orders.
--   2. Injects a secure bypass strictly for `is_active_admin` when they
--      use the `admin_cancel_order` or `admin_issue_refund` RPCs (which set
--      `cancelled_reason = 'admin'`).
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
     
    -- 100x ADMIN FIX: Allow admins to forcefully cancel orders using admin_cancel_order (which sets cancelled_reason = 'admin')
    -- We verify the user is a true admin via auth.uid() check to prevent exploits.
    IF NEW.status = 'cancelled' AND NEW.cancelled_reason = 'admin' AND public.is_active_admin(auth.uid()) THEN
       -- Bypass allowed for Super Admins
       RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Cannot cancel order with id=% — payment is already confirmed (status was: %)',
      OLD.id, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
