-- =============================================================================
-- Migration: Fix Acceptance TOCTOU Race Conditions
-- Description: Changes accept_order_seller and accept_order_rider to return a boolean
-- indicating if the other party had already accepted. This prevents race conditions
-- where both parties accept simultaneously and neither sends the customer the
-- 'Pay Now' push notification.
-- =============================================================================

-- 1. Modify accept_order_seller
DROP FUNCTION IF EXISTS accept_order_seller(UUID);
CREATE OR REPLACE FUNCTION accept_order_seller(p_order_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_partner_accepted boolean;
BEGIN
  -- Verify order exists and get status + shop WITH FOR UPDATE LOCK
  SELECT status, shop_id, partner_accepted INTO v_status, v_shop_id, v_partner_accepted 
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Ensure the caller is the seller for this shop
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner can accept this order';
  END IF;

  -- State machine check
  IF v_status != 'awaiting_acceptance' AND v_status != 'pending' THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Update order
  UPDATE orders
  SET 
    seller_accepted = true,
    status = CASE WHEN v_partner_accepted = true THEN 'awaiting_payment' ELSE status END,
    payment_deadline = CASE WHEN v_partner_accepted = true THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END
  WHERE id = p_order_id;

  -- Return true if the rider had already accepted, meaning it transitioned to awaiting_payment
  RETURN v_partner_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_seller(UUID) TO authenticated;


-- 2. Modify accept_order_rider
DROP FUNCTION IF EXISTS accept_order_rider(UUID, text, numeric, numeric);
CREATE OR REPLACE FUNCTION accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_deadline timestamptz;
BEGIN
  SELECT status, seller_accepted, payment_deadline INTO v_status, v_seller_accepted, v_payment_deadline 
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  UPDATE orders
  SET 
    partner_accepted = true,
    delivery_partner_id = auth.uid(),
    status = CASE WHEN v_seller_accepted = true THEN 'awaiting_payment' ELSE status END,
    payment_deadline = CASE WHEN v_seller_accepted = true THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_payment_deadline END,
    rider_phone = COALESCE(p_rider_phone, rider_phone),
    shop_lat = COALESCE(p_shop_lat, shop_lat),
    shop_lng = COALESCE(p_shop_lng, shop_lng)
  WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());

  -- Return true if the seller had already accepted, meaning it transitioned to awaiting_payment
  RETURN v_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
