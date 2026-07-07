-- =============================================================================
-- Migration: Seller Dashboard Audit Fixes
-- Description: 
-- 1. Adds get_seller_balance RPC to prevent OOM/Pagination bugs on client side.
-- 2. Adds is_deleted column to products for soft-deletion.
-- =============================================================================

-- 1. Add is_deleted to products table
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Create get_seller_balance RPC
CREATE OR REPLACE FUNCTION get_seller_balance(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  -- Validate input
  IF p_seller_id IS NULL THEN
    RAISE EXCEPTION 'Seller ID is required';
  END IF;

  -- Calculate total earned across all shops owned by the seller
  SELECT COALESCE(SUM(seller_payout), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = p_seller_id);

  -- Calculate total paid (or pending)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_seller_balance(UUID) TO authenticated;

-- 3. Update reject_order_seller to handle post-payment cancellations
CREATE OR REPLACE FUNCTION reject_order_seller(p_order_id UUID, p_reject_reason text, p_message text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_payment_status text;
BEGIN
  SELECT status, shop_id, payment_status INTO v_status, v_shop_id, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Allow rejection even if confirmed or preparing
  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = p_message,
    -- Trigger refund if payment was already captured
    refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
  WHERE id = p_order_id;
END;
$$;
