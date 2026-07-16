-- Migration: Additive RPC for fetching order item count to prevent pixel overload
-- Purpose: Safely determine the total original items in an order without transmitting full row payloads over network.
-- Zero side effects, does not alter existing logic.

CREATE OR REPLACE FUNCTION get_order_item_count_v1(p_order_id UUID)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT count(*)::integer FROM order_items WHERE order_id = p_order_id;
$$;

GRANT EXECUTE ON FUNCTION get_order_item_count_v1(UUID) TO authenticated;
