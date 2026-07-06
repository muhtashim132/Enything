-- 13. RPC: Confirm Payment from Client
-- Note: In a fully secure production environment, this should only be called
-- by an Edge Function or Webhook. For now, it replaces the direct client updates.
CREATE OR REPLACE FUNCTION client_confirm_payment(
  p_order_id UUID DEFAULT NULL,
  p_cart_group_id UUID DEFAULT NULL,
  p_razorpay_payment_id text DEFAULT NULL,
  p_razorpay_order_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = 'confirmed',
      payment_status = 'captured',
      razorpay_payment_id = p_razorpay_payment_id,
      razorpay_order_id = p_razorpay_order_id
    WHERE cart_group_id = p_cart_group_id AND status = 'awaiting_payment';
  ELSE
    UPDATE orders
    SET 
      status = 'confirmed',
      payment_status = 'captured',
      razorpay_payment_id = p_razorpay_payment_id,
      razorpay_order_id = p_razorpay_order_id
    WHERE id = p_order_id AND status = 'awaiting_payment';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION client_confirm_payment(UUID, UUID, text, text) TO authenticated;
