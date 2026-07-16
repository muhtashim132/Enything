-- Migration: Add `get_order_reorder_data` RPC for atomic cart restoration
-- Purpose: Safely fetches order_items joined with products and shops in a single hit.
-- Additive only. No existing logic altered.

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
    AND p.is_available = true; -- Only return products that are still available

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION get_order_reorder_data(UUID) TO authenticated;
