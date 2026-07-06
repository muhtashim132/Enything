-- 7. RPC: Seller Rejects Order
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
BEGIN
  SELECT status, shop_id INTO v_status, v_shop_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = p_message
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_order_seller(UUID, text, text) TO authenticated;
