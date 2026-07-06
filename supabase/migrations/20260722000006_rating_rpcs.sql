-- 12. RPCs for setting rating flags
CREATE OR REPLACE FUNCTION set_customer_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE orders SET has_customer_rated = true WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_customer_rated(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION set_seller_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE orders SET has_seller_rated = true WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_seller_rated(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION set_delivery_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE orders SET has_delivery_rated = true WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_delivery_rated(UUID) TO authenticated;
