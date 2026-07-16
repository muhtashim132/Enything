-- Migration: Update `get_order_reorder_data` RPC (V2)
-- Purpose: Adds `s.is_active = true` to prevent restoring products from banned/inactive shops.
-- Additive only. Overwrites the previous function signature safely.

CREATE OR REPLACE FUNCTION get_order_reorder_data(p_order_id UUID)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_result json;
BEGIN
  -- Verify ownership
  SELECT customer_id INTO v_customer_id FROM orders WHERE id = p_order_id;
  IF v_customer_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT json_agg(
    json_build_object(
      'quantity', oi.quantity,
      'variant_name', oi.variant_name,
      'product_id', oi.product_id,
      'product', row_to_json(p.*),
      'shop', row_to_json(s.*)
    )
  )
  INTO v_result
  FROM order_items oi
  JOIN products p ON p.id = oi.product_id
  JOIN shops s ON s.id = p.shop_id
  WHERE oi.order_id = p_order_id
    AND p.is_available = true
    AND s.is_active = true; -- [V2 FIX]: Ensure shop is not banned/inactive

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION get_order_reorder_data(UUID) TO authenticated;
