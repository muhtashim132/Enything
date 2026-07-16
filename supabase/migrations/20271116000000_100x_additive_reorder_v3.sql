-- Migration: Additive RPC for fetching order reorder data with strict bounds (V3)
-- Purpose: Safely fetch reorder data while strictly capping the payload at 100 items to prevent Pixel Overload / OOM attacks on massive orders.
-- Zero side effects, does not alter existing V1 or V2 logic.

CREATE OR REPLACE FUNCTION get_order_reorder_data_v3(p_order_id UUID)
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
  FROM (
    SELECT * FROM order_items WHERE order_id = p_order_id LIMIT 100
  ) oi
  JOIN products p ON p.id = oi.product_id
  JOIN shops s ON s.id = p.shop_id
  WHERE p.is_available = true
    AND s.is_active = true;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION get_order_reorder_data_v3(UUID) TO authenticated;
